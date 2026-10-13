// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Synchronization

/// What a run did, and the items it left alone.
public struct SyncRunReport: Sendable {
    public enum Reason: Hashable, Sendable {
        /// The item no longer looks as compared, or a target the plan did not expect is in the way.
        case changed
        /// Its volume has no Trash; nothing is ever deleted permanently.
        case noTrash
        case failed(String)
    }

    public struct Problem: Hashable, Sendable {
        /// Relative to the compared folders.
        public var path: String
        public var reason: Reason

        public init(path: String, reason: Reason) {
            self.path = path
            self.reason = reason
        }
    }

    /// Files and links placed on the targets.
    public var copied: Int
    /// Items moved to the Trash (deletions and replaced targets).
    public var trashed: Int
    public var problems: [Problem]

    public init(copied: Int = 0, trashed: Int = 0, problems: [Problem] = []) {
        self.copied = copied
        self.trashed = trashed
        self.problems = problems
    }
}

/// Carries out a confirmed plan: replacements, then copies grouped by destination folder, then
/// deletions to the Trash. Every item is checked against the compared state first.
public enum SyncRunner {
    /// Cancelling the task throws `OperationError.cancelled`; deletions never start after it.
    public static func run(_ plan: SyncPlan, of comparison: SyncComparison, operations: FileOperations,
                           progress: @escaping @Sendable (OperationProgress) -> Void) async throws -> SyncRunReport {
        try await run(plan, of: comparison, operations: operations, progress: progress,
                      trashAvailable: TrashSupport.isAvailable, trash: TrashSupport.moveToTrash)
    }

    static func run(_ plan: SyncPlan, of comparison: SyncComparison, operations: FileOperations,
                    progress: @escaping @Sendable (OperationProgress) -> Void,
                    trashAvailable: @escaping @Sendable (URL) -> Bool,
                    trash: @escaping @Sendable (URL) throws -> URL) async throws -> SyncRunReport {
        let run = SyncRun(plan: plan, comparison: comparison, operations: operations, progress: progress,
                          trashAvailable: trashAvailable, trash: trash)
        return try await run.execute()
    }
}

private struct SyncRun {
    let plan: SyncPlan
    let comparison: SyncComparison
    let operations: FileOperations
    let progress: @Sendable (OperationProgress) -> Void
    let trashAvailable: @Sendable (URL) -> Bool
    let trash: @Sendable (URL) throws -> URL
    let log = SyncRunLog()

    init(plan: SyncPlan, comparison: SyncComparison, operations: FileOperations,
         progress: @escaping @Sendable (OperationProgress) -> Void,
         trashAvailable: @escaping @Sendable (URL) -> Bool, trash: @escaping @Sendable (URL) throws -> URL) {
        self.plan = plan
        self.comparison = comparison
        self.operations = operations
        self.progress = progress
        self.trashAvailable = trashAvailable
        self.trash = trash
        log.setTotals(bytes: plan.bytes(to: .left) + plan.bytes(to: .right),
                      items: plan.files(to: .left) + plan.files(to: .right) + plan.deletionCount)
    }

    typealias Step = SyncPlan.Step

    func execute() async throws -> SyncRunReport {
        let replacements = plan.steps.filter { $0.effect == .replace }
        let copies = plan.steps.filter { $0.effect == .copy || $0.effect == .overwrite }
        let deletions = plan.steps.filter { $0.effect == .delete }

        var replaced: [Step] = []
        for step in replacements {
            try checkCancel()
            guard check(step) else { continue }
            if moveToTrash(step) { replaced.append(step) }
        }
        try await copyGroups(replaced, checking: false)
        try await copyGroups(copies, checking: true)
        for step in deletions {
            try checkCancel()
            guard check(step) else { continue }
            _ = moveToTrash(step)
        }
        progress(log.finished())
        return log.report()
    }

    private func checkCancel() throws {
        if Task.isCancelled { throw OperationError.cancelled }
    }

    /// Records the item as changed unless it still looks as compared.
    private func check(_ step: Step) -> Bool {
        if SyncCheck.unchanged(step.item, in: comparison) { return true }
        log.problem(step.item.path, .changed)
        return false
    }

    /// Moves the target of a deletion or replacement to the Trash; false when it stayed.
    private func moveToTrash(_ step: Step) -> Bool {
        let url = comparison.url(of: step.item, on: step.target)
        progress(log.advance(name: step.item.name))
        guard trashAvailable(url) else {
            log.problem(step.item.path, .noTrash)
            return false
        }
        do {
            _ = try trash(url)
            log.trashed()
            return true
        } catch {
            log.problem(step.item.path, .failed(error.localizedDescription))
            return false
        }
    }

    // MARK: Copying

    /// One copy per destination folder; with `checking`, each group's items are checked right before it.
    private func copyGroups(_ steps: [Step], checking: Bool) async throws {
        var order: [String] = []
        var groups: [String: [Step]] = [:]
        for step in steps {
            let dir = comparison.url(of: step.item, on: step.target).deletingLastPathComponent()
            let key = "\(step.target.rawValue):\(dir.standardizedFileURL.path)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(step)
        }
        for key in order {
            try checkCancel()
            guard let group = groups[key]?.filter({ !checking || check($0) }), let first = group.first else { continue }
            try await copyGroup(group, source: first.source,
                                into: comparison.url(of: first.item, on: first.target).deletingLastPathComponent())
        }
    }

    private func copyGroup(_ group: [Step], source: Side, into directory: URL) async throws {
        let filter = SyncFilter(options: comparison.options, includeHidden: comparison.includeHidden, rules: comparison.rules)
        let expected = Set(group.filter { $0.effect == .overwrite }.map { key(comparison.url(of: $0.item, on: $0.target)) })
        let names = Dictionary(group.map { ($0.item.path(on: source), $0.item.path) }, uniquingKeysWith: { a, _ in a })
        let context = CopyContext(sourceRoot: comparison.root(source).standardizedFileURL.path, names: names,
                                  expected: expected, rules: comparison.rules)
        let nodes = group.map { step in
            CopyNode.make(comparison.url(of: step.item, on: source), isFolder: step.item.side(source)?.isFolder == true,
                          filter: filter)
        }
        do {
            try await copy(nodes, into: directory, context: context)
        } catch let error as OperationError where error == .cancelled {
            throw error
        } catch is CancellationError {
            throw OperationError.cancelled
        } catch {
            let reason = SyncRunReport.Reason.failed(Self.describe(error))
            for step in group where !SyncCheck.matches(step.item.side(source), comparison.url(of: step.item, on: step.target)) {
                log.problem(step.item.path, reason)
            }
        }
    }

    /// Copies whole what the filter leaves complete; a folder with left-out items is created and
    /// filled item by item.
    private func copy(_ nodes: [CopyNode], into directory: URL, context: CopyContext) async throws {
        let whole = nodes.filter(\.complete).map(\.url)
        if !whole.isEmpty {
            try await transfer(whole, into: directory, context: context)
        }
        for node in nodes where !node.complete {
            try checkCancel()
            let folder = try await operations.makeDirectory(named: node.url.lastPathComponent, in: directory)
            try await copy(node.children, into: folder, context: context)
        }
    }

    private func transfer(_ sources: [URL], into directory: URL, context: CopyContext) async throws {
        let log = log
        log.startTransfer()
        let report = try await operations.transfer(
            TransferRequest(kind: .copy, sources: sources, destinationDirectory: directory),
            progress: { [progress] p in progress(log.transferProgress(p)) },
            conflict: { conflict in
                if context.expected.contains(context.key(conflict.destination.url)) { return .overwrite }
                log.problem(context.itemPath(conflict.source.url), .changed)
                return .skip
            }
        )
        log.finishTransfer(copied: report.copied)
        for url in report.skipped {
            log.problem(context.itemPath(url), .failed(String(localized: "Could not be copied")), ifNew: true)
        }
    }

    private func key(_ url: URL) -> String {
        comparison.rules.key(url.standardizedFileURL.path)
    }

    static func describe(_ error: any Error) -> String {
        if case .io(let text)? = error as? OperationError { return text }
        if let error = error as? OperationError { return String(describing: error) }
        return error.localizedDescription
    }
}

/// What the conflict closure of one copy group needs.
private struct CopyContext: Sendable {
    let sourceRoot: String
    /// Source-side relative paths of the planned items → their item paths.
    let names: [String: String]
    /// Targets the plan overwrites (by `key`).
    let expected: Set<String>
    let rules: NameRules

    func key(_ url: URL) -> String { rules.key(url.standardizedFileURL.path) }

    func itemPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let relative = path.hasPrefix(sourceRoot + "/") ? String(path.dropFirst(sourceRoot.count + 1)) : path
        return names[relative] ?? relative
    }
}

/// A source of a copy and whether the filter leaves it whole.
private struct CopyNode {
    var url: URL
    var complete: Bool
    var children: [CopyNode]

    static func make(_ url: URL, isFolder: Bool, filter: SyncFilter) -> CopyNode {
        guard isFolder else { return CopyNode(url: url, complete: true, children: []) }
        // An unreadable folder is left to the copy, which reports it.
        guard let raw = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: SyncEntry.keys)
        else { return CopyNode(url: url, complete: true, children: []) }
        let entries = raw.map(SyncEntry.entry)
        let kept = entries.filter(filter.keeps)
        let children = kept.map { make($0.url, isFolder: $0.side.isFolder, filter: filter) }
        let complete = kept.count == entries.count && children.allSatisfy(\.complete)
        return CopyNode(url: url, complete: complete, children: complete ? [] : children)
    }
}

/// Problems and progress shared with the copy callbacks.
private final class SyncRunLog: Sendable {
    private struct State {
        var problems: [SyncRunReport.Problem] = []
        var paths: Set<String> = []
        var copied = 0
        var trashed = 0
        var totalBytes: Int64 = 0
        var totalItems = 0
        var doneBytes: Int64 = 0
        var doneItems = 0
        var current: OperationProgress?
    }

    private let state = Mutex(State())

    func setTotals(bytes: Int64, items: Int) {
        state.withLock {
            $0.totalBytes = bytes
            $0.totalItems = items
        }
    }

    /// Records one problem per path; `ifNew` keeps an earlier reason.
    func problem(_ path: String, _ reason: SyncRunReport.Reason, ifNew: Bool = false) {
        state.withLock {
            if $0.paths.insert(path).inserted {
                $0.problems.append(.init(path: path, reason: reason))
            } else if !ifNew, let i = $0.problems.firstIndex(where: { $0.path == path }) {
                $0.problems[i].reason = reason
            }
        }
    }

    func trashed() {
        state.withLock { $0.trashed += 1 }
    }

    /// One more item done outside a copy (a move to the Trash).
    func advance(name: String) -> OperationProgress {
        state.withLock { $0.doneItems += 1 }
        return progress(name: name)
    }

    func startTransfer() {
        state.withLock { $0.current = nil }
    }

    func transferProgress(_ p: OperationProgress) -> OperationProgress {
        state.withLock {
            $0.current = p
            // A copy counts folders as items too, and the plan may grow while the copy measures it.
            $0.totalBytes = max($0.totalBytes, $0.doneBytes + p.totalBytes)
            $0.totalItems = max($0.totalItems, $0.doneItems + p.totalItems)
            return OperationProgress(totalBytes: $0.totalBytes, doneBytes: $0.doneBytes + p.doneBytes,
                                     totalItems: $0.totalItems, doneItems: $0.doneItems + p.doneItems,
                                     currentName: p.currentName)
        }
    }

    func finishTransfer(copied: Int) {
        state.withLock {
            $0.copied += copied
            if let p = $0.current {
                $0.doneBytes += p.doneBytes
                $0.doneItems += p.doneItems
            }
            $0.current = nil
        }
    }

    /// The end of the run: everything counted as done (skipped items included).
    func finished() -> OperationProgress {
        state.withLock {
            OperationProgress(totalBytes: $0.totalBytes, doneBytes: $0.totalBytes, totalItems: $0.totalItems,
                              doneItems: $0.totalItems, currentName: "")
        }
    }

    func progress(name: String) -> OperationProgress {
        state.withLock {
            OperationProgress(totalBytes: $0.totalBytes, doneBytes: $0.doneBytes, totalItems: $0.totalItems,
                              doneItems: $0.doneItems, currentName: name)
        }
    }

    func report() -> SyncRunReport {
        state.withLock { SyncRunReport(copied: $0.copied, trashed: $0.trashed, problems: $0.problems) }
    }
}
