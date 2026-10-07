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
            let plan = try TransferPlanner.plan(request, lookup: lookup)
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

    /// Moves items to the Trash; returns their URLs in the Trash.
    public func trash(_ urls: [URL]) async throws -> [URL] {
        for url in urls { _ = try existingStat(url) }
        var result: [URL] = []
        for url in urls {
            if Task.isCancelled { throw OperationError.cancelled }
            var trashed: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            } catch {
                throw OperationError.io("Cannot move \(url.path) to Trash: \(error.localizedDescription)")
            }
            result.append((trashed as URL?) ?? url)
        }
        return result
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
