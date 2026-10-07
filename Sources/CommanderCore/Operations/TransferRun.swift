import Darwin
import Foundation

/// Executes a validated plan. One instance per `transfer` call.
final class TransferRun {
    private enum Placement {
        case skip
        /// Write to a new name (exclusive placement).
        case create(String)
        /// Replace this existing non-directory entry.
        case replace(String)
        /// Existing directory: merge the source directory's content into it.
        case merge(String)
    }

    private let kind: TransferKind
    private let plan: TransferPlanner.Plan
    private let lookup: DirectoryLookup
    private let options: FileOperations.Options
    private let progressHandler: @Sendable (OperationProgress) -> Void
    private let conflictHandler: @Sendable (Conflict) async -> ConflictResolution

    private var progress: OperationProgress
    private var overwriteAll = false
    private var skipAll = false
    private var copied = 0
    private var skipped: [URL] = []
    private var kept: [URL] = []

    init(
        kind: TransferKind,
        plan: TransferPlanner.Plan,
        lookup: DirectoryLookup,
        options: FileOperations.Options,
        progress: @escaping @Sendable (OperationProgress) -> Void,
        conflict: @escaping @Sendable (Conflict) async -> ConflictResolution
    ) {
        self.kind = kind
        self.plan = plan
        self.lookup = lookup
        self.options = options
        self.progressHandler = progress
        self.conflictHandler = conflict
        self.progress = OperationProgress(
            totalBytes: plan.nodes.reduce(0) { $0 + $1.bytes },
            doneBytes: 0,
            totalItems: plan.nodes.reduce(0) { $0 + $1.items },
            doneItems: 0,
            currentName: ""
        )
    }

    func execute() async throws -> TransferReport {
        emit()
        for node in plan.nodes {
            try checkCancel()
            switch kind {
            case .copy:
                _ = try await copy(node, into: plan.destination)
            case .move:
                let sameVolume = node.stat?.device == plan.destinationStat.device
                if sameVolume && !options.forceCopyMove {
                    try await renameMove(node, into: plan.destination)
                } else {
                    try await copyThenDelete(node, into: plan.destination)
                }
            }
        }
        return TransferReport(copied: copied, skipped: skipped, keptSources: kept)
    }

    // MARK: Copy

    /// Returns true when the whole subtree was placed (nothing skipped or unreadable).
    private func copy(_ node: PlanNode, into dir: String) async throws -> Bool {
        try checkCancel()
        progress.currentName = node.name
        if node.kind == .unsupported {
            markSkipped(node)
            return false
        }
        while true {
            let target: String
            let replace: Bool
            switch try await resolve(node, in: dir) {
            case .skip:
                markSkipped(node)
                return false
            case .merge(let existing):
                return try await copyChildren(of: node, into: existing)
            case .create(let path):
                target = path
                replace = false
            case .replace(let path):
                target = path
                replace = true
            }

            let outcome: FileCopy.Outcome
            switch node.kind {
            case .file:
                let base = progress.doneBytes
                outcome = try FileCopy.copyFile(
                    from: node.path, to: target, replace: replace, clone: options.cloneAllowed
                ) { [self] bytes in
                    progress.doneBytes = base + min(bytes, node.bytes)
                    emit()
                }
                progress.doneBytes = base + (outcome == .placed ? node.bytes : 0)
            case .symlink:
                outcome = try FileCopy.copySymlink(from: node.path, to: target, replace: replace)
            case .directory:
                outcome = try FileCopy.makeDirectory(target)
                if outcome == .placed {
                    lookup.fresh.insert(target)
                    lookup.noteCreated(FSPath.name(target), in: dir)
                    let complete = try await copyChildren(of: node, into: target)
                    FileCopy.copyDirectoryMetadata(from: node.path, to: target)
                    return complete
                }
            case .unsupported:
                outcome = .placed // handled above
            }
            if outcome == .targetAppeared { continue }
            lookup.noteCreated(FSPath.name(target), in: dir)
            copied += 1
            progress.doneItems += 1
            emit()
            return true
        }
    }

    private func copyChildren(of node: PlanNode, into target: String) async throws -> Bool {
        progress.doneItems += 1
        emit()
        var complete = node.listingComplete
        for child in node.children {
            if !(try await copy(child, into: target)) { complete = false }
        }
        return complete
    }

    // MARK: Move

    /// Same volume: rename(2), merging into existing directories.
    private func renameMove(_ node: PlanNode, into dir: String) async throws {
        try checkCancel()
        progress.currentName = node.name
        while true {
            let target: String
            let rc: Int32
            switch try await resolve(node, in: dir) {
            case .skip:
                markSkipped(node)
                return
            case .merge(let existing):
                progress.doneItems += 1
                emit()
                for child in node.children {
                    try await renameMove(child, into: existing)
                }
                if rmdir(node.path) != 0 { kept.append(node.url) }
                return
            case .create(let path):
                target = path
                rc = renamex_np(node.path, path, UInt32(RENAME_EXCL))
            case .replace(let path):
                target = path
                rc = rename(node.path, path)
            }
            if rc != 0 {
                let err = errno
                if err == EEXIST { continue }
                if err == EXDEV {
                    try await copyThenDelete(node, into: dir)
                    return
                }
                throw OperationError.io(FSPath.errorText(err, "Cannot move", node.path))
            }
            lookup.noteCreated(FSPath.name(target), in: dir)
            copied += node.fileCount
            progress.doneItems += node.items
            progress.doneBytes += node.bytes
            emit()
            return
        }
    }

    /// Other volume (or forced): copy, then delete the source only when the
    /// whole subtree was placed, nothing was skipped, the traversal was complete
    /// and no directory symlink was found.
    private func copyThenDelete(_ node: PlanNode, into dir: String) async throws {
        let complete = try await copy(node, into: dir)
        guard complete, node.traversalComplete, !node.containsDirectoryLink, node.identity != nil else {
            kept.append(node.url)
            return
        }
        if !deleteSource(node) { kept.append(node.url) }
    }

    /// Deletes exactly the planned entries (never follows links). False if anything remained.
    private func deleteSource(_ node: PlanNode) -> Bool {
        switch node.kind {
        case .directory:
            var ok = true
            for child in node.children where !deleteSource(child) { ok = false }
            return rmdir(node.path) == 0 && ok
        case .file, .symlink:
            // Identity must still match the planned entry before deleting.
            guard case .exists(let st) = FileProbe.probe(node.path, followingLinks: false),
                  let id = st.identity, id == node.identity
            else { return false }
            return unlink(node.path) == 0
        case .unsupported:
            return false
        }
    }

    // MARK: Conflicts

    private func resolve(_ node: PlanNode, in dir: String) async throws -> Placement {
        var name = node.targetName
        while true {
            try NameCheck.validate(name)
            let candidate = FSPath.join(dir, name)
            try NameCheck.validate(path: candidate)
            guard let existing = try lookup.existing(in: dir, named: name) else { return .create(candidate) }
            let existingStat: FileStat
            switch FileProbe.probe(existing, followingLinks: false) {
            case .missing: continue
            case .unknown: throw OperationError.identityUnknown(FSPath.url(existing))
            case .exists(let st): existingStat = st
            }
            guard let sourceID = node.identity, let targetID = existingStat.identity else {
                throw OperationError.identityUnknown(FSPath.url(existing))
            }
            if sourceID == targetID { throw OperationError.sameFile(node.url) }
            if node.kind == .directory && existingStat.isDirectory { return .merge(existing) }

            let decision: ConflictResolution
            if skipAll {
                decision = .skip
            } else if overwriteAll {
                decision = .overwrite
            } else {
                let source = node.stat.map { FileItemInfo(path: node.path, stat: $0) }
                    ?? FileItemInfo(url: node.url, isDirectory: false, size: nil, modificationDate: nil)
                decision = await conflictHandler(Conflict(
                    source: source,
                    destination: FileItemInfo(path: existing, stat: existingStat)
                ))
                try checkCancel()
            }
            switch decision {
            case .overwrite: break
            case .overwriteAll: overwriteAll = true
            case .skip: return .skip
            case .skipAll:
                skipAll = true
                return .skip
            case .rename(let newName):
                name = newName
                continue
            case .cancel:
                throw OperationError.cancelled
            }
            // A directory is never replaced by a file or vice versa.
            if node.kind == .directory || existingStat.isDirectory { return .skip }
            return .replace(existing)
        }
    }

    // MARK: Helpers

    private func emit() {
        progressHandler(progress)
    }

    private func checkCancel() throws {
        if Task.isCancelled { throw OperationError.cancelled }
    }

    private func markSkipped(_ node: PlanNode) {
        skipped.append(node.url)
        progress.doneBytes += node.bytes
        progress.doneItems += node.items
        emit()
    }
}
