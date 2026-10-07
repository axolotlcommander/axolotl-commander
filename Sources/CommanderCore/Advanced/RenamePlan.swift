public import Foundation
import Darwin

/// One object to rename in place.
public struct RenameItem: Sendable, Hashable {
    public var url: URL
    public var isDirectory: Bool
    public var newName: String

    public init(url: URL, isDirectory: Bool, newName: String) {
        self.url = url
        self.isDirectory = isDirectory
        self.newName = newName
    }
}

public enum RenameSkip: Sendable, Hashable {
    /// Empty, ".", "..", contains "/" or NUL, or longer than 255 UTF-8 bytes.
    case invalidName
    /// The new name contains `*` or `?` that the original name did not contain.
    case wildcardIntroduced
    /// Another existing file in the folder has this name (for the volume); carries the existing name.
    case existsOnVolume(String)
    /// Two items would get the same name (for the volume) in the same folder; carries the name.
    case duplicateInBatch(String)
}

public enum RenameStatus: Sendable, Hashable {
    case rename
    case unchanged
    case skipped(RenameSkip)
}

public struct RenamePlanEntry: Sendable, Hashable {
    public var item: RenameItem
    public var status: RenameStatus

    public init(item: RenameItem, status: RenameStatus) {
        self.item = item
        self.status = status
    }
}

public enum RenamePlanner {
    /// Current names in a folder.
    public static func defaultListing(_ directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }

    /// Decides per item whether it can be renamed. Pure respellings (same key on the volume, e.g. a case
    /// change on a case-insensitive volume) are valid; swaps and chains inside the batch are allowed.
    /// A folder that cannot be listed counts as empty (the executor never overwrites anyway).
    public static func plan(
        _ items: [RenameItem],
        rules: (URL) -> NameRules = NameRules.forVolume(containing:),
        listing: (URL) throws -> [String] = RenamePlanner.defaultListing
    ) -> [RenamePlanEntry] {
        var status = [RenameStatus](repeating: .rename, count: items.count)
        var groups: [String: (dir: URL, indices: [Int])] = [:]

        for (i, item) in items.enumerated() {
            let old = item.url.lastPathComponent
            if item.newName.unicodeScalars.elementsEqual(old.unicodeScalars) {
                status[i] = .unchanged
            } else if !isValid(item.newName) {
                status[i] = .skipped(.invalidName)
            } else if introducesWildcard(old: old, new: item.newName) {
                status[i] = .skipped(.wildcardIntroduced)
            }
            let dir = item.url.deletingLastPathComponent()
            groups[dir.path, default: (dir, [])].indices.append(i)
        }

        for (_, group) in groups {
            let nameRules = rules(group.dir)
            let existing = (try? listing(group.dir)) ?? []
            let candidates = group.indices.filter { status[$0] == .rename }

            // Same target in the same folder: none of the colliding items is renamed.
            var byKey: [String: [Int]] = [:]
            for i in candidates { byKey[nameRules.key(items[i].newName), default: []].append(i) }
            for (_, colliding) in byKey where colliding.count > 1 {
                for i in colliding { status[i] = .skipped(.duplicateInBatch(items[i].newName)) }
            }

            // Names occupied in the folder: the listing plus every batch item (listing may be injected).
            var occupied: [String: String] = [:]
            for name in existing { occupied[nameRules.key(name)] = name }
            for i in group.indices {
                let name = items[i].url.lastPathComponent
                occupied[nameRules.key(name)] = name
            }

            // A name is free when its holder is renamed away in this batch. A skipped item keeps its name,
            // which can block others, so iterate until stable (skipping only ever grows).
            var alive = Set(candidates.filter { status[$0] == .rename })
            var changed = true
            while changed {
                changed = false
                let moving = Set(alive.map { nameRules.key(items[$0].url.lastPathComponent) })
                for i in alive.sorted() {
                    let key = nameRules.key(items[i].newName)
                    if moving.contains(key) { continue }
                    if let holder = occupied[key] {
                        status[i] = .skipped(.existsOnVolume(holder))
                        alive.remove(i)
                        changed = true
                    }
                }
            }
        }
        return zip(items, status).map { RenamePlanEntry(item: $0, status: $1) }
    }

    static func isValid(_ name: String) -> Bool {
        !(name.isEmpty || name == "." || name == ".." || name.contains("/") || name.utf8.contains(0)
            || name.utf8.count > PathRules.maxNameBytes)
    }

    static func introducesWildcard(old: String, new: String) -> Bool {
        (new.contains("*") && !old.contains("*")) || (new.contains("?") && !old.contains("?"))
    }
}

public struct RenamedItem: Sendable, Equatable {
    public var from: URL
    /// The new location at the time of the rename (a parent folder renamed later is not reflected).
    public var to: URL

    public init(from: URL, to: URL) {
        self.from = from
        self.to = to
    }
}

public struct RenameFailure: Sendable, Equatable {
    public var url: URL
    public var message: String
}

public struct RenameOutcome: Sendable, Equatable {
    public var renamed: [RenamedItem] = []
    public var failures: [RenameFailure] = []
    /// The run was cancelled; the items not reached were left untouched.
    public var cancelled = false

    public init() {}
}

public enum RenameExecutor {
    /// Executes the `.rename` entries. Deeper paths go first so that renaming a folder never invalidates
    /// the URLs of its children. Within one depth, items whose target name is currently held by another
    /// item of the batch (swaps, chains) first move to a temporary name `.~icmd-ren-<uuid>`, then to the
    /// final name; nothing is ever overwritten. A failed final rename puts the item back (best effort).
    /// Cancellation is checked between items: pending temporary names are restored and the outcome so far
    /// is returned with `cancelled == true` (no CancellationError is thrown).
    public static func run(
        _ plan: [RenamePlanEntry],
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> RenameOutcome {
        let items = plan.compactMap { $0.status == .rename ? $0.item : nil }
        let total = items.count
        var outcome = RenameOutcome()
        var done = 0
        let operations = FileOperations()
        var rulesCache: [String: NameRules] = [:]

        let byDepth = Dictionary(grouping: items) { $0.url.pathComponents.count }
        for depth in byDepth.keys.sorted(by: >) {
            let level = byDepth[depth] ?? []
            var current = level.map(\.url)
            var temporary = [Bool](repeating: false, count: level.count)
            var failed = [Bool](repeating: false, count: level.count)

            // i needs a temporary name when its target is another item's current name (or vice versa).
            var byDir: [String: [Int]] = [:]
            for (i, item) in level.enumerated() {
                byDir[item.url.deletingLastPathComponent().path, default: []].append(i)
            }
            var needsTemp = Set<Int>()
            for (dirPath, indices) in byDir {
                let rules: NameRules
                if let cached = rulesCache[dirPath] {
                    rules = cached
                } else {
                    rules = NameRules.forVolume(containing: URL(fileURLWithPath: dirPath, isDirectory: true))
                    rulesCache[dirPath] = rules
                }
                var holder: [String: Int] = [:]
                for i in indices { holder[rules.key(level[i].url.lastPathComponent)] = i }
                for i in indices {
                    if let j = holder[rules.key(level[i].newName)], j != i {
                        needsTemp.insert(i)
                        needsTemp.insert(j)
                    }
                }
            }

            func restore(_ i: Int) -> String? {
                guard temporary[i] else { return nil }
                if renamex_np(current[i].path, level[i].url.path, UInt32(RENAME_EXCL)) == 0 {
                    current[i] = level[i].url
                    temporary[i] = false
                    return nil
                }
                return " (could not restore the original name, left as \(current[i].lastPathComponent))"
            }
            func restoreAll() {
                for i in level.indices where temporary[i] && !failed[i] {
                    if let note = restore(i) {
                        outcome.failures.append(RenameFailure(url: level[i].url, message: "Cancelled" + note))
                    }
                }
            }

            // Phase 1: temporary names.
            for i in needsTemp.sorted() {
                if Task.isCancelled { restoreAll(); outcome.cancelled = true; return outcome }
                let tempName = ".~icmd-ren-\(UUID().uuidString)"
                let target = level[i].url.deletingLastPathComponent().appendingPathComponent(tempName)
                if renamex_np(level[i].url.path, target.path, UInt32(RENAME_EXCL)) == 0 {
                    current[i] = target
                    temporary[i] = true
                } else {
                    let err = errno
                    failed[i] = true
                    outcome.failures.append(RenameFailure(
                        url: level[i].url, message: FSPath.errorText(err, "Cannot rename", level[i].url.path)))
                    done += 1
                    progress(done, total)
                }
            }

            // Phase 2: final names.
            for i in level.indices where !failed[i] {
                if Task.isCancelled { restoreAll(); outcome.cancelled = true; return outcome }
                do {
                    _ = try await operations.rename(current[i], to: level[i].newName)
                    let target = level[i].url.deletingLastPathComponent().appendingPathComponent(level[i].newName)
                    outcome.renamed.append(RenamedItem(from: level[i].url, to: target))
                    temporary[i] = false
                } catch {
                    let note = restore(i) ?? ""
                    outcome.failures.append(RenameFailure(url: level[i].url, message: message(for: error) + note))
                }
                done += 1
                progress(done, total)
            }
        }
        return outcome
    }

    /// The plan that puts back the names of a finished run (`renamed` in execution order, as `run` reports
    /// it). Each item is located where it is now, i.e. with the folders renamed after it in the same run
    /// applied. Swaps and chains are undone through temporary names like any batch; an original name that
    /// something else holds now makes the entry `.skipped(.existsOnVolume)`, so nothing is overwritten.
    public static func undoPlan(
        _ renamed: [RenamedItem],
        rules: (URL) -> NameRules = NameRules.forVolume(containing:),
        listing: (URL) throws -> [String] = RenamePlanner.defaultListing
    ) -> [RenamePlanEntry] {
        let items = renamed.indices.map { i -> RenameItem in
            var components = renamed[i].to.standardizedFileURL.pathComponents
            // Later renames of an enclosing folder move this item along with it.
            for later in renamed[(i + 1)...] {
                let from = later.from.standardizedFileURL.pathComponents
                if from.count < components.count, Array(components[..<from.count]) == from {
                    components = later.to.standardizedFileURL.pathComponents + components[from.count...]
                }
            }
            let current = URL(fileURLWithPath: NSString.path(withComponents: components))
            return RenameItem(url: current, isDirectory: isRealDirectory(current),
                              newName: renamed[i].from.lastPathComponent)
        }
        return RenamePlanner.plan(items, rules: rules, listing: listing)
    }

    /// Puts back the names of a finished run (see `undoPlan`). Entries that cannot be planned, e.g. because
    /// the original name is taken now, are reported as failures. Undoing the returned outcome redoes it.
    public static func undo(
        _ renamed: [RenamedItem],
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> RenameOutcome {
        let plan = undoPlan(renamed)
        var outcome = try await run(plan, progress: progress)
        for entry in plan {
            guard case .skipped(let reason) = entry.status else { continue }
            let text = switch reason {
            case .existsOnVolume(let name), .duplicateInBatch(let name): "Already exists: \(name)"
            case .invalidName, .wildcardIntroduced: "Cannot rename to \(entry.item.newName)"
            }
            outcome.failures.append(RenameFailure(url: entry.item.url, message: text))
        }
        return outcome
    }

    /// The items plus, when `recursive`, everything inside the selected folders (packages included,
    /// symbolic links to folders not followed). Parents precede their children.
    public static func expand(_ urls: [URL], recursive: Bool) -> [(url: URL, isDirectory: Bool)] {
        var result: [(url: URL, isDirectory: Bool)] = []
        func visit(_ url: URL) {
            let isDir = isRealDirectory(url)
            result.append((url, isDir))
            guard recursive, isDir,
                  let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return }
            for name in names.sorted() { visit(url.appendingPathComponent(name)) }
        }
        for url in urls { visit(url) }
        return result
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }

    private static func message(for error: any Error) -> String {
        if let e = error as? OperationError {
            switch e {
            case .io(let text): return text
            case .alreadyExists(let url): return "Already exists: \(url.path)"
            default: return String(describing: e)
            }
        }
        return String(describing: error)
    }
}
