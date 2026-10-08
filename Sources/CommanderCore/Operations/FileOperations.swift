// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin

/// File operations on local volumes. Every request is validated as a whole
/// before the first write; cancellation is cooperative (Task cancellation)
/// and never leaves a half-written file behind.
public actor FileOperations {
    /// Internal knobs for tests.
    struct Options: Sendable {
        /// Allow APFS clones (clones finish without progress callbacks).
        var cloneAllowed = true
        /// Treat every move as cross-volume (copy, then delete).
        var forceCopyMove = false
        /// Does the volume of this item have a Trash? nil = ask the system (once per volume);
        /// tests answer per item without asking it.
        var trashAvailable: (@Sendable (URL) -> Bool)?
        /// What a volume promises about file ids. nil = ask the system (`VolumeTraits.of`);
        /// tests pretend a volume is FAT/SMB-like.
        var volumeTraits: (@Sendable (URL) -> VolumeTraits)?
        /// Moves one item to the Trash; tests move it into their sandbox instead.
        var trashItem: @Sendable (URL) throws -> URL = TrashSupport.moveToTrash
    }

    let options: Options

    public init() {
        options = Options()
    }

    init(options: Options) {
        self.options = options
    }

    // MARK: Transfer

    /// Validates first (all errors before any write), then runs. Progress via callback on any thread.
    public func transfer(
        _ request: TransferRequest,
        progress: @escaping @Sendable (OperationProgress) -> Void,
        conflict: @escaping @Sendable (Conflict) async -> ConflictResolution
    ) async throws -> TransferReport {
        do {
            let lookup = DirectoryLookup(rules: NameRules.forVolume(containing: request.destinationDirectory))
            let plan = try TransferPlanner.plan(request, lookup: lookup, traits: options.volumeTraits ?? VolumeTraits.of)
            let run = TransferRun(
                kind: request.kind, plan: plan, lookup: lookup, options: options,
                progress: progress, conflict: conflict
            )
            return try await run.execute()
        } catch {
            throw OperationError.wrap(error)
        }
    }

    // MARK: Delete

    /// Splits items into those that can go to the Trash and those on volumes without one.
    /// Changes nothing; each volume is asked once.
    public func planDelete(_ urls: [URL]) -> DeletePlan {
        var plan = DeletePlan(toTrash: [], permanent: [])
        var known: [Int64: Bool] = [:]
        for url in urls {
            let device: Int64? = if case .exists(let st) = FileProbe.probe(url.path, followingLinks: false) { st.device } else { nil }
            let available: Bool
            if let custom = options.trashAvailable {
                available = custom(url)
            } else if let device, let cached = known[device] {
                available = cached
            } else {
                available = TrashSupport.isAvailable(url)
                if let device { known[device] = available }
            }
            if available {
                plan.toTrash.append(url)
            } else if access(FSPath.parent(url.path), W_OK | X_OK) != 0 {
                plan.unremovable.append(url)
            } else {
                plan.permanent.append(url)
            }
        }
        return plan
    }

    /// Moves items to the Trash one by one; never throws half-way: the report says what went,
    /// which item failed and why, and what was not attempted after it.
    public func trash(_ urls: [URL]) async -> TrashReport {
        var report = TrashReport()
        for (i, url) in urls.enumerated() {
            if Task.isCancelled {
                report.notAttempted = Array(urls[i...])
                return report
            }
            do {
                _ = try existingStat(url)
                report.trashed.append((url, try options.trashItem(url)))
            } catch {
                report.failed = (url, error)
                report.notAttempted = Array(urls[(i + 1)...])
                return report
            }
        }
        return report
    }

    /// Deletes items recursively without following symlinks.
    public func deletePermanently(
        _ urls: [URL],
        progress: @escaping @Sendable (OperationProgress) -> Void = { _ in }
    ) async throws {
        var nodes: [PlanNode] = []
        for url in urls {
            _ = try existingStat(url)
            let path = url.path
            if path == "/" || path.isEmpty { throw OperationError.invalidName(path) }
            nodes.append(PlanNode.scan(path, mask: "*"))
        }
        var state = OperationProgress(
            totalBytes: nodes.reduce(0) { $0 + $1.bytes }, doneBytes: 0,
            totalItems: nodes.reduce(0) { $0 + $1.items }, doneItems: 0, currentName: ""
        )
        progress(state)
        func remove(_ node: PlanNode) throws {
            if Task.isCancelled { throw OperationError.cancelled }
            for child in node.children { try remove(child) }
            state.currentName = node.name
            let rc = node.kind == .directory ? rmdir(node.path) : unlink(node.path)
            if rc != 0 && errno != ENOENT {
                throw OperationError.io(FSPath.errorText(errno, "Cannot delete", node.path))
            }
            state.doneItems += 1
            state.doneBytes += node.kind == .file ? node.bytes : 0
            progress(state)
        }
        for node in nodes { try remove(node) }
    }

    // MARK: Create / rename

    public func makeDirectory(named name: String, in directory: URL) throws -> URL {
        try NameCheck.validate(name)
        let parent = directory.path
        let path = FSPath.join(parent, name)
        try NameCheck.validate(path: path)
        let lookup = DirectoryLookup(rules: NameRules.forVolume(containing: directory))
        if let existing = try lookup.existing(in: parent, named: name) {
            throw OperationError.alreadyExists(FSPath.url(existing))
        }
        if mkdir(path, 0o777) != 0 {
            let err = errno
            if err == EEXIST { throw OperationError.alreadyExists(FSPath.url(path)) }
            if err == ENOENT { throw OperationError.path(.notFound) }
            throw OperationError.io(FSPath.errorText(err, "Cannot create folder", path))
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Creates an empty file for "edit new file". An existing file of that name
    /// (volume name rules) is returned untouched, with `created == false`.
    public func makeFile(named name: String, in directory: URL) throws -> (url: URL, created: Bool) {
        try NameCheck.validate(name)
        let parent = directory.path
        let path = FSPath.join(parent, name)
        try NameCheck.validate(path: path)
        let rules = NameRules.forVolume(containing: directory)
        if try DirectoryLookup(rules: rules).existing(in: parent, named: name) != nil {
            // The spelling on disk, so the panel cursor lands on the real entry.
            let actual = (try? FileManager.default.contentsOfDirectory(atPath: parent))?
                .first { rules.same($0, name) } ?? name
            let existing = FSPath.join(parent, actual)
            var info = stat()
            if stat(existing, &info) == 0, info.st_mode & S_IFMT == S_IFDIR {
                throw OperationError.alreadyExists(FSPath.url(existing))
            }
            return (FSPath.url(existing), false)
        }
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o666)
        if fd < 0 {
            let err = errno
            if err == EEXIST { throw OperationError.alreadyExists(FSPath.url(path)) }
            if err == ENOENT { throw OperationError.path(.notFound) }
            throw OperationError.io(FSPath.errorText(err, "Cannot create file", path))
        }
        close(fd)
        return (URL(fileURLWithPath: path, isDirectory: false), true)
    }

    /// Renames in place. A change of case or Unicode normalization only (same
    /// identity on a case-insensitive volume) is allowed.
    public func rename(_ url: URL, to newName: String) throws -> URL {
        try NameCheck.validate(newName)
        let source = url.path
        let sourceStat = try existingStat(url)
        let parent = FSPath.parent(source)
        let target = FSPath.join(parent, newName)
        try NameCheck.validate(path: target)
        if FSPath.name(source).unicodeScalars.elementsEqual(newName.unicodeScalars) { return url }

        let lookup = DirectoryLookup(rules: NameRules.forVolume(containing: url))
        if let existing = try lookup.existing(in: parent, named: newName) {
            guard case .exists(let est) = FileProbe.probe(existing, followingLinks: false),
                  let a = est.identity, let b = sourceStat.identity
            else { throw OperationError.identityUnknown(FSPath.url(existing)) }
            guard a == b else { throw OperationError.alreadyExists(FSPath.url(existing)) }
            // Same object under another spelling: plain rename(2) changes the stored name.
            if Darwin.rename(source, target) != 0 {
                throw OperationError.io(FSPath.errorText(errno, "Cannot rename", source))
            }
        } else if renamex_np(source, target, UInt32(RENAME_EXCL)) != 0 {
            let err = errno
            if err == EEXIST { throw OperationError.alreadyExists(FSPath.url(target)) }
            throw OperationError.io(FSPath.errorText(err, "Cannot rename", source))
        }
        return URL(fileURLWithPath: target, isDirectory: sourceStat.isDirectory)
    }

    // MARK: Helpers

    private func existingStat(_ url: URL) throws -> FileStat {
        switch FileProbe.probe(url.path, followingLinks: false) {
        case .missing: throw OperationError.path(.notFound)
        case .unknown: throw OperationError.identityUnknown(url)
        case .exists(let st): return st
        }
    }
}
