// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin
import Synchronization

/// Copies and moves between the disk and a server, between servers, and deletes on a server.
///
/// Files arrive under a temporary name and get their final name only when complete, so an
/// existing file is replaced only by a full copy. A move removes a source only after its copy
/// arrived with the expected size; folders go only when everything inside went. Symlinks to
/// folders are never followed (skipped and kept); symlinks to files are copied as files.
public struct RemoteTransfer: Sendable {
    public typealias Progress = @Sendable (OperationProgress) -> Void
    public typealias ConflictHandler = @Sendable (Conflict) async -> ConflictResolution

    let connections: RemoteConnections

    public init(connections: RemoteConnections = .shared) {
        self.connections = connections
    }

    // MARK: - Upload

    /// Local `sources` into the server folder `directory`; `nameMask` renames files (see `NameMask`).
    public func upload(
        _ sources: [URL],
        to directory: RemoteLocation,
        kind: TransferKind,
        nameMask: String = "*.*",
        progress: @escaping Progress,
        conflict: @escaping ConflictHandler
    ) async throws -> TransferReport {
        let nodes = try sources.map { try LocalNode.scan($0.standardizedFileURL.path) }
        let meter = Meter(totalBytes: nodes.reduce(0) { $0 + $1.bytes }, totalItems: nodes.reduce(0) { $0 + $1.count }, progress: progress)
        var run = Run(conflict: conflict)
        let endpoint = directory.endpoint
        let resolved = try await connections.resolve(directory)

        func existing(in dir: String) async throws -> [String: RemoteEntry] {
            if let cached = run.remoteListings[dir] { return cached }
            let entries = try await connections.perform(on: endpoint) { try await $0.list(dir) }
            let byName = Dictionary(entries.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            run.remoteListings[dir] = byName
            return byName
        }

        /// Returns true when the node and everything below it arrived.
        func send(_ node: LocalNode, into dir: String) async throws -> Bool {
            try Task.checkCancellation()
            let name = node.kind == .file ? NameMask.apply(nameMask, to: node.name) : node.name
            try NameCheck.validate(name)
            let target = RemotePath.join(dir, name)
            let present = try await existing(in: dir)[name]
            meter.current(node.name)

            switch node.kind {
            case .directoryLink, .unsupported:
                run.skip(URL(filePath: node.path))
                meter.skip(node)
                return false

            case .directory:
                if let present, !present.isDirectoryLike {
                    // A file is in the way; a folder can't replace it.
                    _ = try await run.resolve(Conflict(source: node.info, destination: present.info(at: target, endpoint)))
                    run.skip(URL(filePath: node.path))
                    meter.skip(node)
                    return false
                }
                if present == nil {
                    try await connections.perform(on: endpoint) { try await $0.makeDirectory(target) }
                    run.remoteListings[target] = [:]
                    run.remoteListings[dir]?[name] = RemoteEntry(name: name, kind: .directory)
                }
                meter.itemDone()
                var all = true
                for child in node.children {
                    if try await !send(child, into: target) { all = false }
                }
                if kind == .move, all {
                    if Darwin.rmdir(node.path) != 0 { run.keep(URL(filePath: node.path)); return false }
                }
                if !all { run.keep(URL(filePath: node.path)) }
                return all

            case .file:
                var finalName = name
                var replace = false
                if let present {
                    switch try await run.resolve(Conflict(source: node.info, destination: present.info(at: target, endpoint))) {
                    case .overwrite, .overwriteAll:
                        guard !present.isDirectoryLike else {
                            run.skip(URL(filePath: node.path))
                            meter.skip(node)
                            return false
                        }
                        replace = true
                    case .rename(let newName):
                        try NameCheck.validate(newName)
                        guard try await existing(in: dir)[newName] == nil else {
                            throw OperationError.alreadyExists(RemoteURL.make(endpoint, path: RemotePath.join(dir, newName)))
                        }
                        finalName = newName
                    case .skip, .skipAll:
                        run.skip(URL(filePath: node.path))
                        meter.skip(node)
                        return false
                    case .cancel:
                        throw OperationError.cancelled
                    }
                }
                let finalPath = RemotePath.join(dir, finalName)
                let temp = RemotePath.join(dir, ".\(finalName).icmd-\(UUID().uuidString.prefix(8))")
                let source = URL(filePath: node.path)
                let base = meter.done
                do {
                    try await connections.perform(on: endpoint) { fs in
                        try await fs.upload(source, to: temp) { meter.bytes(base + $0) }
                    }
                } catch {
                    // Outside this (possibly cancelled) task, so the cleanup still runs.
                    await Task { [connections] in
                        try? await connections.perform(on: endpoint) { fs in
                            if try await fs.info(temp) != nil { try await fs.removeFile(temp) }
                        }
                    }.value
                    throw error
                }
                do {
                    if replace {
                        try await placeReplacing(temp: temp, final: finalPath, endpoint: endpoint)
                    } else {
                        try await connections.perform(on: endpoint) { try await $0.rename(temp, to: finalPath) }
                    }
                } catch {
                    // replaceIncomplete: the new file stays under its temporary name; the error says where.
                    if case RemoteError.replaceIncomplete = error { throw error }
                    await Task { [connections] in
                        try? await connections.perform(on: endpoint) { fs in
                            if try await fs.info(temp) != nil { try await fs.removeFile(temp) }
                        }
                    }.value
                    throw error
                }
                run.remoteListings[dir]?[finalName] = RemoteEntry(name: finalName, kind: .file, size: node.size)
                meter.fileDone(base + node.size)
                run.copied += 1
                if kind == .move {
                    let arrived = try await connections.perform(on: endpoint) { try await $0.info(finalPath) }
                    guard let arrived, arrived.kind == .file, arrived.size == nil || arrived.size == node.size,
                          Darwin.unlink(node.path) == 0
                    else {
                        run.keep(source)
                        return false
                    }
                }
                return true
            }
        }

        for node in nodes {
            if try await !send(node, into: resolved.path), kind == .move { run.keep(URL(filePath: node.path)) }
        }
        return run.report
    }

    // MARK: - Download

    /// Server items (all on one endpoint) into the local folder `directory`.
    public func download(
        _ sources: [RemoteLocation],
        to directory: URL,
        kind: TransferKind,
        nameMask: String = "*.*",
        progress: @escaping Progress,
        conflict: @escaping ConflictHandler
    ) async throws -> TransferReport {
        guard let endpoint = sources.first?.endpoint else { return TransferReport(copied: 0, skipped: [], keptSources: []) }
        let nodes = try await scanSources(sources, endpoint: endpoint)
        return try await download(nodes, from: endpoint, to: directory, kind: kind, nameMask: nameMask,
                                  progress: progress, conflict: conflict)
    }

    /// The items to copy, scanned on the server; throws `.notFound` for a missing one.
    private func scanSources(_ sources: [RemoteLocation], endpoint: RemoteEndpoint) async throws -> [RemoteNode] {
        var nodes: [RemoteNode] = []
        for source in sources {
            try Task.checkCancellation()
            guard let entry = try await connections.perform(on: endpoint, { try await $0.walkInfo(source.path) }) else {
                throw RemoteError.notFound(source.path)
            }
            nodes.append(try await scanRemote(entry, at: source.path, endpoint: endpoint))
        }
        return nodes
    }

    private func download(
        _ nodes: [RemoteNode],
        from endpoint: RemoteEndpoint,
        to directory: URL,
        kind: TransferKind,
        nameMask: String,
        progress: @escaping Progress,
        conflict: @escaping ConflictHandler
    ) async throws -> TransferReport {
        let meter = Meter(totalBytes: nodes.reduce(0) { $0 + $1.bytes }, totalItems: nodes.reduce(0) { $0 + $1.count }, progress: progress)
        var run = Run(conflict: conflict)
        let root = directory.standardizedFileURL.path
        let lookup = DirectoryLookup(rules: NameRules.forVolume(containing: directory))

        func receive(_ node: RemoteNode, into dir: String) async throws -> Bool {
            try Task.checkCancellation()
            let sourceURL = RemoteURL.make(endpoint, path: node.path)
            let name = node.kind == .file ? NameMask.apply(nameMask, to: node.entry.name) : node.entry.name
            try NameCheck.validate(name)
            let target = FSPath.join(dir, name)
            try NameCheck.validate(path: target)
            let present = try lookup.existing(in: dir, named: name)
            meter.current(node.entry.name)

            switch node.kind {
            case .directoryLink, .unsupported:
                run.skip(sourceURL)
                meter.skip(node)
                return false

            case .directory:
                var into = target
                if let present {
                    let st = Self.localStat(present)
                    guard st?.isDirectory == true else {
                        _ = try await run.resolve(Conflict(source: node.info(endpoint), destination: Self.localInfo(present)))
                        run.skip(sourceURL)
                        meter.skip(node)
                        return false
                    }
                    into = present
                } else {
                    if mkdir(target, 0o777) != 0 && errno != EEXIST {
                        throw OperationError.io(FSPath.errorText(errno, "Cannot create folder", target))
                    }
                    lookup.noteCreated(name, in: dir)
                    lookup.fresh.insert(target)
                }
                meter.itemDone()
                var all = true
                for child in node.children {
                    if try await !receive(child, into: into) { all = false }
                }
                if kind == .move, all {
                    do {
                        try await connections.perform(on: endpoint) { try await $0.removeDirectory(node.path) }
                    } catch {
                        run.keep(sourceURL)
                        return false
                    }
                }
                if !all { run.keep(sourceURL) }
                return all

            case .file:
                var finalPath = target
                var replace = false
                if let present {
                    switch try await run.resolve(Conflict(source: node.info(endpoint), destination: Self.localInfo(present))) {
                    case .overwrite, .overwriteAll:
                        if Self.localStat(present)?.isDirectory == true {
                            run.skip(sourceURL)
                            meter.skip(node)
                            return false
                        }
                        finalPath = present
                        replace = true
                    case .rename(let newName):
                        try NameCheck.validate(newName)
                        finalPath = FSPath.join(dir, newName)
                        if try lookup.existing(in: dir, named: newName) != nil {
                            throw OperationError.alreadyExists(FSPath.url(finalPath))
                        }
                    case .skip, .skipAll:
                        run.skip(sourceURL)
                        meter.skip(node)
                        return false
                    case .cancel:
                        throw OperationError.cancelled
                    }
                }
                let temp = FSPath.join(dir, ".~icmd-\(UUID().uuidString)")
                let base = meter.done
                do {
                    try await connections.perform(on: endpoint) { fs in
                        try await fs.download(node.path, to: URL(filePath: temp)) { meter.bytes(base + $0) }
                    }
                } catch where node.entry.kind == .symlink && !(error is CancellationError) && (error as? RemoteError) != .cancelled {
                    // A link the server could not open as a file (e.g. to a folder on FTP).
                    unlink(temp)
                    run.skip(sourceURL)
                    meter.skip(node)
                    return false
                }
                let placed = replace
                    ? Darwin.rename(temp, finalPath) == 0
                    : renamex_np(temp, finalPath, UInt32(RENAME_EXCL)) == 0
                guard placed else {
                    let err = errno
                    unlink(temp)
                    if err == EEXIST { throw OperationError.alreadyExists(FSPath.url(finalPath)) }
                    throw OperationError.io(FSPath.errorText(err, "Cannot write", finalPath))
                }
                lookup.noteCreated(FSPath.name(finalPath), in: dir)
                meter.fileDone(base + node.bytes)
                run.copied += 1
                if kind == .move {
                    let size = Self.localStat(finalPath)?.size
                    guard node.entry.size == nil || size == node.entry.size else {
                        run.keep(sourceURL)
                        return false
                    }
                    do {
                        try await connections.perform(on: endpoint) { try await $0.removeFile(node.path) }
                    } catch {
                        run.keep(sourceURL)
                        return false
                    }
                }
                return true
            }
        }

        for node in nodes {
            if try await !receive(node, into: root), kind == .move {
                run.keep(RemoteURL.make(endpoint, path: node.path))
            }
        }
        return run.report
    }

    // MARK: - Server to server

    /// Server items into a folder on the same or another server. Same server + move = rename
    /// there; otherwise the items go through `scratch` (an empty local folder the caller removes).
    public func transfer(
        _ sources: [RemoteLocation],
        to directory: RemoteLocation,
        kind: TransferKind,
        scratch: URL,
        progress: @escaping Progress,
        conflict: @escaping ConflictHandler
    ) async throws -> TransferReport {
        guard let from = sources.first?.endpoint else { return TransferReport(copied: 0, skipped: [], keptSources: []) }
        let target = try await connections.resolve(directory)
        if from == directory.endpoint, kind == .move {
            return try await renameOnServer(sources, into: target, conflict: conflict)
        }
        let nodes = try await scanSources(sources, endpoint: from)
        let down = try await download(nodes, from: from, to: scratch, kind: .copy, nameMask: "*.*", progress: { p in
            progress(OperationProgress(totalBytes: p.totalBytes * 2, doneBytes: p.doneBytes, totalItems: p.totalItems,
                                       doneItems: p.doneItems, currentName: p.currentName))
        }, conflict: { _ in .skip })  // the scratch folder starts empty: a clash means names that differ
                                       // only in case; overwriting would lose one (and a move delete both)
        let local = sources.map { scratch.appending(path: RemotePath.name($0.path)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        let totalBytes = local.reduce(Int64(0)) { $0 + ((try? LocalNode.scan($1.path).bytes) ?? 0) }
        let up = try await upload(local, to: target, kind: .copy, progress: { p in
            progress(OperationProgress(totalBytes: totalBytes * 2, doneBytes: totalBytes + p.doneBytes, totalItems: p.totalItems,
                                       doneItems: p.doneItems, currentName: p.currentName))
        }, conflict: conflict)
        let skipped = down.skipped + up.skipped.map { url in
            RemoteURL.make(from, path: RemotePath.join(RemotePath.parent(sources[0].path), String(url.path.dropFirst(scratch.path.count + 1))))
        }
        var kept: [URL] = []
        if kind == .move {
            if skipped.isEmpty, down.keptSources.isEmpty {
                kept = try await removeCopied(nodes, endpoint: from)
            } else {
                kept = sources.map(\.url)
            }
        }
        return TransferReport(copied: up.copied, skipped: skipped, keptSources: kept)
    }

    /// After a move copied the scanned `nodes`, removes exactly them: a file only while the
    /// server still lists it as scanned (same kind, size and time), a folder only once empty, so
    /// anything added or changed meanwhile stays. Returns the items of which something remained.
    private func removeCopied(_ nodes: [RemoteNode], endpoint: RemoteEndpoint) async throws -> [URL] {
        func unchanged(_ now: RemoteEntry?, _ node: RemoteNode) -> Bool {
            guard let now, now.kind == node.entry.kind else { return false }
            return node.kind == .directory
                || (now.size == node.entry.size && now.modificationDate == node.entry.modificationDate)
        }
        /// True when the node and everything below it went.
        func remove(_ node: RemoteNode, now: RemoteEntry?) async throws -> Bool {
            try Task.checkCancellation()
            guard unchanged(now, node) else { return false }
            do {
                switch node.kind {
                case .directory:
                    let listing = try await connections.perform(on: endpoint) { try await $0.walkList(node.path) }
                    let byName = Dictionary(listing.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
                    var all = true
                    for child in node.children where try await !remove(child, now: byName[child.entry.name]) { all = false }
                    guard all else { return false }
                    try await connections.perform(on: endpoint) { try await $0.removeDirectory(node.path) }
                case .file:
                    try await connections.perform(on: endpoint) { try await $0.removeFile(node.path) }
                case .directoryLink, .unsupported:
                    return false
                }
            } catch {
                if error is CancellationError || (error as? RemoteError) == .cancelled { throw error }
                return false
            }
            return true
        }
        var kept: [URL] = []
        for node in nodes {
            let now = try await connections.perform(on: endpoint) { try await $0.walkInfo(node.path) }
            if try await !remove(node, now: now) { kept.append(RemoteURL.make(endpoint, path: node.path)) }
        }
        return kept
    }

    private func renameOnServer(_ sources: [RemoteLocation], into target: RemoteLocation, conflict: @escaping ConflictHandler)
        async throws -> TransferReport {
        let endpoint = target.endpoint
        var run = Run(conflict: conflict)
        for source in sources {
            try Task.checkCancellation()
            let name = RemotePath.name(source.path)
            let dest = RemotePath.join(target.path, name)
            if dest == source.path { run.skip(source.url); continue }
            if let present = try await connections.perform(on: endpoint, { try await $0.info(dest) }) {
                guard let entry = try await connections.perform(on: endpoint, { try await $0.info(source.path) }) else {
                    throw RemoteError.notFound(source.path)
                }
                let answer = try await run.resolve(Conflict(source: entry.info(at: source.path, endpoint),
                                                            destination: present.info(at: dest, endpoint)))
                guard answer == .overwrite || answer == .overwriteAll, !present.isDirectoryLike, !entry.isDirectoryLike else {
                    if answer == .cancel { throw OperationError.cancelled }
                    run.skip(source.url)
                    run.keep(source.url)
                    continue
                }
                try await placeReplacing(temp: source.path, final: dest, endpoint: endpoint)
            } else {
                try await connections.perform(on: endpoint) { try await $0.rename(source.path, to: dest) }
            }
            run.copied += 1
        }
        return run.report
    }

    // MARK: - Replacing

    /// Gives the complete file `temp` the name `final`, replacing the file there, so that a
    /// complete version always exists under a known name: an atomic swap when the server has
    /// one; otherwise the old file is renamed aside, the new one takes its name (on failure the
    /// old one is put back), and only then the old one is removed.
    ///
    /// Runs in its own task: cancelling the operation does not stop it half-way. Each step is
    /// a separate `perform`, so a reconnect never repeats a step that already happened; after
    /// a failed step the server state is checked before going on.
    ///
    /// Throws: any error before the swap (nothing changed, `temp` still there); the swap's
    /// error after the old file was restored; `.replaceIncomplete` when it couldn't be.
    func placeReplacing(temp: String, final: String, endpoint: RemoteEndpoint) async throws {
        try await Task { [connections] in
            func exists(_ path: String) async -> Bool? {
                do { return try await connections.perform(on: endpoint) { try await $0.info(path) } != nil } catch { return nil }
            }
            if try await connections.perform(on: endpoint, { try await $0.replace(temp, over: final) }) { return }

            let backup = RemotePath.join(RemotePath.parent(final),
                                         ".\(RemotePath.name(final)).axo-old-\(UUID().uuidString.prefix(8))")
            do {
                try await connections.perform(on: endpoint) { try await $0.rename(final, to: backup) }
            } catch {
                // A dropped reply may hide a rename that happened; go on only when it did.
                guard await exists(final) == false, await exists(backup) == true else { throw error }
            }
            do {
                try await connections.perform(on: endpoint) { try await $0.rename(temp, to: final) }
            } catch {
                if await exists(temp) == false, await exists(final) == true {
                    // It did happen.
                } else {
                    do {
                        try await connections.perform(on: endpoint) { try await $0.rename(backup, to: final) }
                    } catch {
                        throw RemoteError.replaceIncomplete(target: final, newAt: temp, oldAt: backup)
                    }
                    throw error
                }
            }
            // The new version is in place; a backup that can't be removed is only clutter.
            try? await connections.perform(on: endpoint) { try await $0.removeFile(backup) }
        }.value
    }

    // MARK: - Delete

    /// Removes files and folders (recursively) on a server; symlinks are removed, not followed.
    public func delete(_ items: [RemoteLocation], progress: @escaping Progress) async throws {
        guard let endpoint = items.first?.endpoint else { return }
        var nodes: [RemoteNode] = []
        for item in items {
            guard let entry = try await connections.perform(on: endpoint, { try await $0.walkInfo(item.path) }) else { continue }
            nodes.append(try await scanRemote(entry, at: item.path, endpoint: endpoint, followLinks: false))
        }
        let meter = Meter(totalBytes: 0, totalItems: nodes.reduce(0) { $0 + $1.count }, progress: progress)
        func remove(_ node: RemoteNode) async throws {
            try Task.checkCancellation()
            meter.current(node.entry.name)
            if node.kind == .directory {
                for child in node.children { try await remove(child) }
                try await connections.perform(on: endpoint) { try await $0.removeDirectory(node.path) }
            } else {
                try await connections.perform(on: endpoint) { try await $0.removeFile(node.path) }
            }
            meter.itemDone()
        }
        for node in nodes { try await remove(node) }
    }

    // MARK: - Scanning

    /// `ancestors`: `uniqueID`s of the folders above; a folder with one of them is a link back
    /// up that the server listed as a folder, and is treated as a link to a folder.
    private func scanRemote(_ entry: RemoteEntry, at path: String, endpoint: RemoteEndpoint, followLinks: Bool = true,
                            ancestors: Set<String> = []) async throws -> RemoteNode {
        var entry = entry
        if entry.kind == .directory, let id = entry.uniqueID, ancestors.contains(id) {
            entry.kind = .symlink
            entry.targetIsDirectory = true
        }
        switch entry.kind {
        case .directory:
            try Task.checkCancellation()
            let entries = try await connections.perform(on: endpoint) { try await $0.walkList(path) }
            var below = ancestors
            if let id = entry.uniqueID { below.insert(id) }
            var children: [RemoteNode] = []
            for child in entries.sorted(by: { $0.name < $1.name }) {
                children.append(try await scanRemote(child, at: RemotePath.join(path, child.name), endpoint: endpoint,
                                                     followLinks: followLinks, ancestors: below))
            }
            return RemoteNode(entry: entry, path: path, kind: .directory, children: children)
        case .symlink:
            return RemoteNode(entry: entry, path: path, kind: !followLinks ? .file : entry.targetIsDirectory ? .directoryLink : .file)
        case .file:
            return RemoteNode(entry: entry, path: path, kind: .file)
        case .other:
            return RemoteNode(entry: entry, path: path, kind: followLinks ? .unsupported : .file)
        }
    }

    private static func localStat(_ path: String) -> FileStat? {
        if case .exists(let st) = FileProbe.probe(path, followingLinks: false) { return st }
        return nil
    }

    private static func localInfo(_ path: String) -> FileItemInfo {
        if let st = localStat(path) { return FileItemInfo(path: path, stat: st) }
        return FileItemInfo(url: FSPath.url(path), isDirectory: false, size: nil, modificationDate: nil)
    }
}

// MARK: - Plan nodes

enum NodeKind { case file, directory, directoryLink, unsupported }

/// A local item to upload; symlinks to files count as files (their target's size).
struct LocalNode {
    var path: String
    var name: String
    var kind: NodeKind
    var size: Int64
    var modified: Date?
    var children: [LocalNode] = []

    var bytes: Int64 { kind == .file ? size : children.reduce(0) { $0 + $1.bytes } }
    var count: Int { 1 + children.reduce(0) { $0 + $1.count } }

    var info: FileItemInfo {
        FileItemInfo(url: FSPath.url(path), name: name, isDirectory: kind == .directory, size: kind == .file ? size : nil,
                     modificationDate: modified)
    }

    static func scan(_ path: String) throws -> LocalNode {
        let name = FSPath.name(path)
        var st = stat()
        guard lstat(path, &st) == 0 else { throw OperationError.path(.notFound) }
        let modified = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
        switch st.st_mode & S_IFMT {
        case S_IFDIR:
            let names = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
            return LocalNode(path: path, name: name, kind: .directory, size: 0, modified: modified,
                             children: try names.map { try scan(FSPath.join(path, $0)) })
        case S_IFREG:
            return LocalNode(path: path, name: name, kind: .file, size: Int64(st.st_size), modified: modified)
        case S_IFLNK:
            var target = stat()
            guard stat(path, &target) == 0 else { return LocalNode(path: path, name: name, kind: .unsupported, size: 0) }
            if target.st_mode & S_IFMT == S_IFDIR { return LocalNode(path: path, name: name, kind: .directoryLink, size: 0) }
            if target.st_mode & S_IFMT != S_IFREG { return LocalNode(path: path, name: name, kind: .unsupported, size: 0) }
            return LocalNode(path: path, name: name, kind: .file, size: Int64(target.st_size), modified: modified)
        default:
            return LocalNode(path: path, name: name, kind: .unsupported, size: 0)
        }
    }
}

struct RemoteNode {
    var entry: RemoteEntry
    var path: String
    var kind: NodeKind
    var children: [RemoteNode] = []

    var bytes: Int64 { kind == .file ? entry.size ?? 0 : children.reduce(0) { $0 + $1.bytes } }
    var count: Int { 1 + children.reduce(0) { $0 + $1.count } }

    func info(_ endpoint: RemoteEndpoint) -> FileItemInfo { entry.info(at: path, endpoint) }
}

extension RemoteEntry {
    func info(at path: String, _ endpoint: RemoteEndpoint) -> FileItemInfo {
        FileItemInfo(url: RemoteURL.make(endpoint, path: path), name: name, isDirectory: isDirectoryLike, size: size,
                     modificationDate: modificationDate)
    }
}

extension RemotePath {
    /// Last component; "/" for the root.
    public static func name(_ path: String) -> String {
        path == "/" ? "/" : String(path.split(separator: "/").last ?? "")
    }
}

/// Sticky conflict answers and the report being built.
private struct Run {
    let conflict: RemoteTransfer.ConflictHandler
    var sticky: ConflictResolution?
    var copied = 0
    var skipped: [URL] = []
    var kept: [URL] = []
    var remoteListings: [String: [String: RemoteEntry]] = [:]

    init(conflict: @escaping RemoteTransfer.ConflictHandler) {
        self.conflict = conflict
    }

    mutating func resolve(_ c: Conflict) async throws -> ConflictResolution {
        if let sticky { return sticky }
        let answer = await conflict(c)
        switch answer {
        case .overwriteAll, .skipAll: sticky = answer
        case .cancel: throw OperationError.cancelled
        default: break
        }
        return answer
    }

    mutating func skip(_ url: URL) { skipped.append(url) }
    mutating func keep(_ url: URL) { if !kept.contains(url) { kept.append(url) } }

    var report: TransferReport { TransferReport(copied: copied, skipped: skipped, keptSources: kept) }
}

/// Progress counters shared with transfer callbacks.
private final class Meter: Sendable {
    private struct State {
        var progress: OperationProgress
    }

    private let state: Mutex<State>
    private let report: RemoteTransfer.Progress

    init(totalBytes: Int64, totalItems: Int, progress: @escaping RemoteTransfer.Progress) {
        state = Mutex(State(progress: OperationProgress(totalBytes: totalBytes, doneBytes: 0, totalItems: totalItems,
                                                        doneItems: 0, currentName: "")))
        report = progress
    }

    var done: Int64 { state.withLock { $0.progress.doneBytes } }

    func current(_ name: String) { update { $0.currentName = name } }
    func bytes(_ total: Int64) { update { $0.doneBytes = max($0.doneBytes, total) } }
    func itemDone() { update { $0.doneItems += 1 } }

    /// A file arrived; `bytes` = done bytes including it.
    func fileDone(_ bytes: Int64) {
        update {
            $0.doneBytes = max($0.doneBytes, bytes)
            $0.doneItems += 1
        }
    }

    func skip(_ node: LocalNode) { skip(bytes: node.bytes, items: node.count) }
    func skip(_ node: RemoteNode) { skip(bytes: node.bytes, items: node.count) }

    private func skip(bytes: Int64, items: Int) {
        update {
            $0.doneBytes += bytes
            $0.doneItems += items
        }
    }

    private func update(_ change: (inout OperationProgress) -> Void) {
        let p = state.withLock { s -> OperationProgress in
            change(&s.progress)
            return s.progress
        }
        report(p)
    }
}
