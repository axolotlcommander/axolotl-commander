// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Darwin
import Foundation

/// Snapshot of one source item and its subtree, taken before any write.
/// Later steps (including deleting a moved source) only touch what is here.
struct PlanNode {
    enum Kind: Equatable {
        case file
        case symlink(toDirectory: Bool)
        case directory
        /// FIFO, socket, device, or an entry that could not be stat'ed.
        case unsupported
    }

    let path: String
    let name: String
    let targetName: String
    let kind: Kind
    let stat: FileStat?
    let children: [PlanNode]
    /// The directory listing itself could be read.
    let listingComplete: Bool

    // Subtree aggregates.
    let bytes: Int64
    let items: Int
    let fileCount: Int
    /// A directory symlink (or a link whose target cannot be checked) is in the subtree.
    let containsDirectoryLink: Bool
    /// Every directory was listed and every entry is supported.
    let traversalComplete: Bool

    var url: URL { FSPath.url(path) }
    var identity: FileIdentity? { stat?.identity }

    static func scan(_ path: String, mask: String) -> PlanNode {
        let name = FSPath.name(path)
        guard case .exists(let st) = FileProbe.probe(path, followingLinks: false) else {
            return leaf(path, name, name, .unsupported, nil)
        }
        if st.isDirectory {
            var children: [PlanNode] = []
            var listed = true
            if let names = try? FileManager.default.contentsOfDirectory(atPath: path) {
                children = names.sorted().map { scan(FSPath.join(path, $0), mask: mask) }
            } else {
                listed = false
            }
            return PlanNode(
                path: path, name: name, targetName: name, kind: .directory, stat: st,
                children: children, listingComplete: listed,
                bytes: children.reduce(0) { $0 + $1.bytes },
                items: children.reduce(1) { $0 + $1.items },
                fileCount: children.reduce(0) { $0 + $1.fileCount },
                containsDirectoryLink: children.contains { $0.containsDirectoryLink },
                traversalComplete: listed && children.allSatisfy(\.traversalComplete)
            )
        }
        let target = NameMask.apply(mask, to: name)
        if st.isSymlink {
            let toDirectory: Bool
            switch FileProbe.probe(path, followingLinks: true) {
            case .missing: toDirectory = false
            case .unknown: toDirectory = true
            case .exists(let resolved): toDirectory = resolved.isDirectory
            }
            return leaf(path, name, target, .symlink(toDirectory: toDirectory), st)
        }
        return leaf(path, name, target, st.isRegular ? .file : .unsupported, st)
    }

    private static func leaf(_ path: String, _ name: String, _ target: String, _ kind: Kind, _ st: FileStat?) -> PlanNode {
        let isLink: Bool
        if case .symlink(let toDir) = kind { isLink = toDir } else { isLink = false }
        return PlanNode(
            path: path, name: name, targetName: target, kind: kind, stat: st,
            children: [], listingComplete: true,
            bytes: kind == .file ? (st?.size ?? 0) : 0,
            items: 1,
            fileCount: kind == .unsupported ? 0 : 1,
            containsDirectoryLink: isLink,
            traversalComplete: kind != .unsupported
        )
    }
}

/// Finds an existing entry for a name the way the destination volume compares
/// names (NFC/NFD, case folding), not only by exact bytes.
final class DirectoryLookup {
    let rules: NameRules
    private var listings: [String: [String: String]] = [:]
    /// Directories created by this operation (known to hold only what we put there).
    var fresh: Set<String> = []

    init(rules: NameRules) {
        self.rules = rules
    }

    /// Path of the existing entry that has the same name as `name`, or nil.
    func existing(in dir: String, named name: String) throws(OperationError) -> String? {
        let direct = FSPath.join(dir, name)
        switch FileProbe.probe(direct, followingLinks: false) {
        case .exists: return direct
        case .unknown: throw .identityUnknown(FSPath.url(direct))
        case .missing: break
        }
        if fresh.contains(dir) { return nil }
        let listing = listings[dir] ?? load(dir)
        guard let actual = listing[rules.key(name)] else { return nil }
        let path = FSPath.join(dir, actual)
        if case .exists = FileProbe.probe(path, followingLinks: false) { return path }
        return nil
    }

    func noteCreated(_ name: String, in dir: String) {
        listings[dir]?[rules.key(name)] = name
    }

    private func load(_ dir: String) -> [String: String] {
        var map: [String: String] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
            map[rules.key(name)] = name
        }
        listings[dir] = map
        return map
    }
}

/// Whole-request validation. Runs before the first write and throws the first problem.
enum TransferPlanner {
    struct Plan {
        let destination: String
        let destinationStat: FileStat
        let nodes: [PlanNode]
    }

    static func plan(_ request: TransferRequest, lookup: DirectoryLookup) throws(OperationError) -> Plan {
        let destURL = request.destinationDirectory
        let dest = destURL.path
        let destStat: FileStat
        switch FileProbe.probe(dest, followingLinks: true) {
        case .missing: throw .path(.notFound)
        case .unknown: throw .identityUnknown(destURL)
        case .exists(let st): destStat = st
        }
        if !destStat.isDirectory { throw .path(.notADirectory) }
        try NameCheck.validate(path: dest)

        let ancestors = ancestorIdentities(of: dest)
        var nodes: [PlanNode] = []
        for source in request.sources {
            let path = source.path
            switch FileProbe.probe(path, followingLinks: false) {
            case .missing: throw .path(.notFound)
            case .unknown: throw .identityUnknown(source)
            case .exists: break
            }
            let node = PlanNode.scan(path, mask: request.nameMask)
            try NameCheck.validate(node.targetName)
            let target = FSPath.join(dest, node.targetName)
            try NameCheck.validate(path: target)

            if node.kind == .directory {
                guard let id = node.identity, !ancestors.unknown else { throw .identityUnknown(source) }
                if ancestors.ids.contains(id) { throw .intoItself(source) }
            }
            if request.kind == .move && node.identity == nil { throw .identityUnknown(source) }

            if let existing = try lookup.existing(in: dest, named: node.targetName) {
                guard case .exists(let est) = FileProbe.probe(existing, followingLinks: false),
                      let existingID = est.identity, let sourceID = node.identity
                else { throw .identityUnknown(FSPath.url(existing)) }
                if existingID == sourceID { throw .sameFile(source) }
                let merge = node.kind == .directory && est.isDirectory
                try validateNested(node, target: merge ? existing : target, targetExists: merge)
            } else {
                try validateNested(node, target: target, targetExists: false)
            }
            nodes.append(node)
        }
        return Plan(destination: dest, destinationStat: destStat, nodes: nodes)
    }

    /// Path lengths of every target, and identity of targets inside a merged directory.
    private static func validateNested(_ node: PlanNode, target: String, targetExists: Bool) throws(OperationError) {
        for child in node.children {
            let childTarget = FSPath.join(target, child.targetName)
            try NameCheck.validate(path: childTarget)
            var childExists = false
            if targetExists {
                switch FileProbe.probe(childTarget, followingLinks: false) {
                case .missing: break
                case .unknown: throw .identityUnknown(FSPath.url(childTarget))
                case .exists(let est):
                    guard let a = est.identity, let b = child.identity else {
                        throw .identityUnknown(FSPath.url(childTarget))
                    }
                    if a == b { throw .sameFile(child.url) }
                    childExists = est.isDirectory && child.kind == .directory
                }
            }
            try validateNested(child, target: childTarget, targetExists: childExists)
        }
    }

    /// Identities of the destination and all its ancestors, along the literal
    /// path (links followed per component) and along its realpath.
    static func ancestorIdentities(of path: String) -> (ids: Set<FileIdentity>, unknown: Bool) {
        var ids = Set<FileIdentity>()
        var unknown = false
        var chains = [path]
        if let resolved = realpath(path, nil) {
            chains.append(String(cString: resolved))
            free(resolved)
        } else {
            unknown = true
        }
        for start in chains {
            var current = start
            while true {
                switch FileProbe.probe(current, followingLinks: true) {
                case .exists(let st):
                    if let id = st.identity { ids.insert(id) } else { unknown = true }
                case .unknown: unknown = true
                case .missing: break
                }
                if current == "/" || current.isEmpty { break }
                let up = FSPath.parent(current)
                if up == current { break }
                current = up
            }
        }
        return (ids, unknown)
    }
}
