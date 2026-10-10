// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
public import Observation

public struct SelectionSummary: Sendable, Equatable {
    public var files: Int
    public var directories: Int
    public var bytes: Int64

    public init(files: Int = 0, directories: Int = 0, bytes: Int64 = 0) {
        self.files = files
        self.directories = directories
        self.bytes = bytes
    }
}

/// State and behavior of one file panel: listing, cursor, selection, history.
@MainActor @Observable
public final class PanelModel {
    private enum NavMode { case record, back, forward }

    public static let historyLimit = 64

    // MARK: State

    public private(set) var location: URL
    /// Sorted and filtered; the parent row comes first unless at "/".
    public private(set) var items: [FileItem] = []
    public private(set) var cursor: Int = 0
    /// `rules.key(name)` of every selected item.
    public private(set) var selection: Set<String> = [] {
        didSet { if selection.isEmpty, !oldValue.isEmpty { previousSelection = oldValue } }
    }
    /// The last non-empty selection before it was cleared (by an operation, navigation or a refresh
    /// after the items moved away); ⌃W brings it back. Keys as in `selection`.
    public private(set) var previousSelection: Set<String> = []
    public private(set) var rules: NameRules = .apfsDefault
    public private(set) var isLoading = false
    public private(set) var lastError: (any Error)?
    public private(set) var directorySizes: [String: Int64] = [:]
    /// Set while the panel shows find results instead of a directory; `location` is then its root.
    public private(set) var results: ResultsListing?
    /// Set while the panel shows the branch view of `location`: the files of its subfolders too.
    public private(set) var branch: BranchListing?
    /// Subfolders of the shown branch that could not be read.
    public private(set) var unreadableFolders = 0
    /// Told how a branch scan goes (also when a refresh rescans it); nil when the scan has ended.
    @ObservationIgnored public var onBranchProgress: (@MainActor @Sendable (BranchProgress?) -> Void)?
    @ObservationIgnored private var branchScan: Task<BranchResult, any Error>?
    /// Whether a branch is being scanned (to show or to refresh it).
    public var isScanningBranch: Bool { branchScan != nil }
    /// Set while `location` is a folder inside an archive (`/x/a.zip/dir`).
    public private(set) var archive: ArchivePath?
    /// Set while `location` is a folder on a server (`sftp://…`, `ftp://…`).
    public var remote: RemoteLocation? { results == nil ? RemoteURL.parse(location) : nil }
    /// The panel shows the virtual Network folder (servers and network volumes, nothing on disk).
    public var isNetwork: Bool { NetworkPlaces.isNetwork(location) }

    public var sort: SortSpec = .default {
        didSet { if !isRestoring, sort != oldValue { rebuild() } }
    }
    public var showHidden = false {
        didSet {
            if !isRestoring, showHidden != oldValue { Task { await refresh() } }
        }
    }
    /// Never hides directories or the parent row; selection is untouched.
    public var filter: WildcardMask? {
        didSet { if !isRestoring, filter != oldValue { rebuild() } }
    }

    private var back: [PanelState.Place] = []
    private var forward: [PanelState.Place] = []

    @ObservationIgnored private let source: any FileSource
    @ObservationIgnored private var rawItems: [FileItem] = []
    @ObservationIgnored private var navToken = 0
    @ObservationIgnored private var inFlight = 0
    /// True while `restore` assigns sort/showHidden/filter, so their observers stay quiet.
    @ObservationIgnored private var isRestoring = false

    public init(location: URL, source: any FileSource = LocalFileSource()) {
        self.location = location
        self.source = source
    }

    public var cursorItem: FileItem? {
        items.indices.contains(cursor) ? items[cursor] : nil
    }
    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    // MARK: Loading

    private func load(_ url: URL, results: ResultsListing? = nil, branch: BranchListing? = nil,
                      includeHidden: Bool? = nil) async throws
        -> (raw: [FileItem], rules: NameRules, archive: ArchivePath?, unreadable: Int) {
        inFlight += 1
        isLoading = true
        defer {
            inFlight -= 1
            isLoading = inFlight > 0
        }
        do {
            var unreadable = 0
            let raw: [FileItem]
            if let results {
                raw = try await results.load()
            } else if let branch {
                let report = onBranchProgress
                let (source, hidden) = (source, includeHidden ?? showHidden)
                let scan = Task {
                    try await BranchScanner.scan(
                        branch, source: source, includeHidden: hidden,
                        progress: { p in if let report { Task { @MainActor in report(p) } } })
                }
                branchScan?.cancel()
                branchScan = scan
                defer {
                    if branchScan == scan { branchScan = nil }
                    // Queued after the progress reports, so it is the last word.
                    if let report { Task { @MainActor in report(nil) } }
                }
                let scanned = try await withTaskCancellationHandler { try await scan.value } onCancel: { scan.cancel() }
                raw = scanned.items
                unreadable = scanned.unreadable
            } else {
                raw = try await source.list(url, includeHidden: includeHidden ?? showHidden).filter { !$0.isParent }
            }
            // Member names are case-sensitive: "A.txt" and "a.txt" are two members.
            let archive = results == nil ? ArchivePath.split(url) : nil
            let caseSensitive = archive != nil || RemoteURL.isRemote(url) || NetworkPlaces.isNetwork(url)
            return (raw, caseSensitive ? NameRules(caseSensitive: true) : NameRules.forVolume(containing: url), archive, unreadable)
        } catch {
            lastError = error
            throw error
        }
    }

    private func buildItems() -> [FileItem] {
        var visible = rawItems
        if let filter {
            let ownName = branch != nil
            visible = visible.filter { $0.isDirectory || filter.matches(ownName ? $0.fileName : $0.name, rules: rules) }
        }
        var result = sortItems(visible, by: sort, rules: rules, directorySizes: directorySizes, byFileName: branch != nil)
        if results != nil {
            // ".." leaves the results for their root folder.
            result.insert(FileItem(url: location, name: "..", isParent: true, isDirectory: true), at: 0)
        } else if location.path != "/" {
            result.insert(.parent(of: location), at: 0)
        }
        return result
    }

    private func index(ofName name: String) -> Int? {
        if let i = items.firstIndex(where: { $0.name == name }) { return i }
        let k = rules.key(name)
        return items.firstIndex { rules.key($0.name) == k }
    }

    /// Rebuilds `items`, keeping the cursor on the same item when it survives.
    private func rebuild() {
        let name = cursorItem?.name
        let old = cursor
        items = buildItems()
        if let name, let i = index(ofName: name) {
            cursor = i
        } else {
            cursor = max(0, min(old, items.count - 1))
        }
    }

    // MARK: Navigation

    public func go(to url: URL, focusing name: String? = nil) async throws {
        try await navigate(to: url, focusing: name, mode: .record)
    }

    /// Shows `listing` like a directory; Back returns to where the panel was.
    public func showResults(_ listing: ResultsListing, focusing name: String? = nil) async throws {
        try await navigate(to: listing.root, focusing: name, mode: .record, results: listing)
    }

    /// Shows the branch view of `listing.root`; Back returns to where the panel was. The panel stays
    /// as it was until the scan has finished, so cancelling the task changes nothing.
    public func showBranch(_ listing: BranchListing, focusing name: String? = nil) async throws {
        try await navigate(to: listing.root, focusing: name, mode: .record, branch: listing)
    }

    private func navigate(to url: URL, focusing name: String?, mode: NavMode, results: ResultsListing? = nil,
                          branch: BranchListing? = nil) async throws {
        navToken += 1
        let token = navToken
        let loaded = try await load(url, results: results, branch: branch)
        guard token == navToken else { throw CancellationError() }

        let leaving = PanelState.Place(url: location, cursorName: cursorItem?.name, results: self.results, branch: self.branch)
        switch mode {
        case .record:
            if leaving.url.standardizedFileURL.path != url.standardizedFileURL.path || leaving.results != results
                || leaving.branch != branch {
                back.append(leaving)
                if back.count > Self.historyLimit { back.removeFirst(back.count - Self.historyLimit) }
                forward.removeAll()
            }
        case .back:
            _ = back.popLast()
            forward.append(leaving)
            if forward.count > Self.historyLimit { forward.removeFirst(forward.count - Self.historyLimit) }
        case .forward:
            _ = forward.popLast()
            back.append(leaving)
            if back.count > Self.historyLimit { back.removeFirst(back.count - Self.historyLimit) }
        }

        location = url
        self.results = results
        self.branch = branch
        unreadableFolders = loaded.unreadable
        archive = loaded.archive
        rules = loaded.rules
        rawItems = loaded.raw
        selection = []
        directorySizes = [:]
        items = buildItems()
        cursor = name.flatMap { index(ofName: $0) } ?? 0
        lastError = nil
    }

    /// Current state as a value, for tabs and persistence. The cursor name is nil on "..".
    public func snapshot() -> PanelState {
        PanelState(
            location: location,
            cursorName: cursorItem.flatMap { $0.isParent ? nil : $0.name },
            sort: sort,
            showHidden: showHidden,
            filterPattern: filter?.pattern,
            back: back,
            forward: forward,
            results: results,
            branch: branch,
            selectedNames: selectedItems.map(\.name)
        )
    }

    /// Brings the panel to `state`: loads its location with the cursor on `cursorName`, applies
    /// sort, hidden flag and filter, then installs its history as-is (the directory being left is
    /// not recorded). The selection is the state's selected names that still exist. If loading fails the error is thrown and nothing changes.
    public func restore(_ state: PanelState) async throws {
        navToken += 1
        let token = navToken
        let loaded = try await load(state.location, results: state.results, branch: state.branch, includeHidden: state.showHidden)
        guard token == navToken else { throw CancellationError() }

        isRestoring = true
        sort = state.sort
        showHidden = state.showHidden
        if let pattern = state.filterPattern, !pattern.isEmpty { filter = WildcardMask(pattern) } else { filter = nil }
        isRestoring = false

        back = Array(state.back.suffix(Self.historyLimit))
        forward = Array(state.forward.suffix(Self.historyLimit))
        location = state.location
        results = state.results
        branch = state.branch
        unreadableFolders = loaded.unreadable
        archive = loaded.archive
        rules = loaded.rules
        rawItems = loaded.raw
        let present = Set(rawItems.map { rules.key($0.name) })
        selection = Set(state.selectedNames.map { rules.key($0) }).intersection(present)
        directorySizes = [:]
        items = buildItems()
        cursor = state.cursorName.flatMap { index(ofName: $0) } ?? 0
        lastError = nil
    }

    /// Stops a running branch scan: a branch being opened is not shown; a branch being refreshed
    /// gives way to the folder's normal listing.
    public func cancelBranchScan() {
        branchScan?.cancel()
    }

    /// Find results: an item was renamed, so the listing follows it (call `refresh` afterwards).
    public func replaceResult(_ old: URL, with new: URL) {
        results = results?.replacing(old, with: new)
    }

    /// Reloads the current directory (scans a branch again), keeping cursor, selection and sizes
    /// where possible.
    public func refresh() async {
        let token = navToken
        let url = location
        let loaded: (raw: [FileItem], rules: NameRules, archive: ArchivePath?, unreadable: Int)
        do {
            loaded = try await load(url, results: results, branch: branch)
        } catch is CancellationError where branch != nil && token == navToken {
            try? await go(to: url)
            return
        } catch {
            return
        }
        guard token == navToken else { return }
        let name = cursorItem?.name
        let old = cursor
        rules = loaded.rules
        rawItems = loaded.raw
        unreadableFolders = loaded.unreadable
        let present = Set(rawItems.map { rules.key($0.name) })
        selection.formIntersection(present)
        directorySizes = directorySizes.filter { present.contains($0.key) }
        items = buildItems()
        if let name, let i = index(ofName: name) {
            cursor = i
        } else {
            cursor = max(0, min(old, items.count - 1))
        }
        lastError = nil
    }

    /// Parent row goes up, directories and archives are entered, files are returned untouched.
    public func enterCursor() async throws -> FileItem? {
        guard let item = cursorItem else { return nil }
        if item.isParent {
            try await goParent()
            return nil
        }
        if item.isDirectory {
            try await go(to: item.url)
            return nil
        }
        // Archives open like folders; an archive inside an archive or on a server is just a file.
        if archive == nil, remote == nil, ArchiveFormat.detect(fileName: item.name) != nil {
            try await go(to: item.url)
            return nil
        }
        return item
    }

    /// Where the other panel goes for the cursor item (⌃⇧← / ⌃⇧→): into a folder or an archive
    /// on disk, otherwise to the folder holding the item with the item focused. nil on "..".
    public var otherPanelTarget: (url: URL, focus: String?)? {
        guard let item = cursorItem, !item.isParent else { return nil }
        if item.isDirectory, !item.isPackage { return (item.url, nil) }
        if !item.isDirectory, archive == nil, remote == nil, ArchiveFormat.detect(fileName: item.name) != nil {
            return (item.url, nil)
        }
        return (item.url.deletingLastPathComponent(), item.url.lastPathComponent)
    }

    public func goParent() async throws {
        if results != nil { return try await go(to: location) }
        // The Network folder has no parent: back where the panel came from.
        if isNetwork {
            if canGoBack { return try await goBack() }
            return try await go(to: FileManager.default.homeDirectoryForCurrentUser)
        }
        guard location.path != "/" else { return }
        try await go(to: location.deletingLastPathComponent(), focusing: location.lastPathComponent)
    }

    public func goRoot() async throws {
        if isNetwork { return }
        if let remote { return try await go(to: RemoteURL.make(remote.endpoint, path: "/")) }
        try await go(to: Volumes.root(of: location))
    }

    public func goBack() async throws {
        guard let entry = back.last else { return }
        try await navigate(to: entry.url, focusing: entry.cursorName, mode: .back, results: entry.results, branch: entry.branch)
    }

    public func goForward() async throws {
        guard let entry = forward.last else { return }
        try await navigate(to: entry.url, focusing: entry.cursorName, mode: .forward, results: entry.results, branch: entry.branch)
    }

    // MARK: Cursor

    public func moveCursor(to index: Int) {
        cursor = max(0, min(index, items.count - 1))
    }

    public func moveCursor(by delta: Int) {
        moveCursor(to: cursor + delta)
    }

    // MARK: Quick search

    @discardableResult
    public func quickSearch(_ prefix: String) -> Bool {
        guard let i = items.indices.first(where: { matches(items[$0], prefix: prefix) }) else { return false }
        cursor = i
        return true
    }

    /// Cycles to the next (or previous) match; wraps around.
    @discardableResult
    public func quickSearchNext(_ prefix: String, forward: Bool) -> Bool {
        let n = items.count
        guard n > 0 else { return false }
        for step in 1...n {
            let i = ((forward ? cursor + step : cursor - step) % n + n) % n
            if matches(items[i], prefix: prefix) {
                cursor = i
                return true
            }
        }
        return false
    }

    private func matches(_ item: FileItem, prefix: String) -> Bool {
        guard !item.isParent, !prefix.isEmpty else { return false }
        // In branch view the shown name is the file's own, without its folder.
        return rules.key(branch != nil ? item.fileName : item.name).hasPrefix(rules.key(prefix))
    }

    // MARK: Selection

    private func selectable(_ item: FileItem) -> Bool { !item.isParent }

    public func isSelected(_ item: FileItem) -> Bool {
        selectable(item) && selection.contains(rules.key(item.name))
    }

    private func set(_ item: FileItem, _ on: Bool) {
        guard selectable(item) else { return }
        let k = rules.key(item.name)
        if on { selection.insert(k) } else { selection.remove(k) }
    }

    public func toggleSelection(at index: Int) {
        guard items.indices.contains(index) else { return }
        set(items[index], !isSelected(items[index]))
    }

    public func setSelected(_ on: Bool, range: ClosedRange<Int>) {
        guard !items.isEmpty else { return }
        let lo = max(range.lowerBound, 0), hi = min(range.upperBound, items.count - 1)
        guard lo <= hi else { return }
        for i in lo...hi { set(items[i], on) }
    }

    /// Per Open Salamander, masks apply to files and optionally directories.
    public func select(mask: WildcardMask, _ on: Bool, includeDirectories: Bool = false) {
        for item in items where includeDirectories || !item.isDirectory {
            if mask.matches(item.name, rules: rules) { set(item, on) }
        }
    }

    public func invertSelection(mask: WildcardMask = WildcardMask("*"), includeDirectories: Bool = false) {
        for item in items where includeDirectories || !item.isDirectory {
            if mask.matches(item.name, rules: rules) { set(item, !isSelected(item)) }
        }
    }

    /// ⌃W: marks again the items of the last cleared selection that are listed here.
    public func restorePreviousSelection() {
        let present = Set(items.filter(selectable).map { rules.key($0.name) })
        selection.formUnion(previousSelection.intersection(present))
    }

    /// Index of the next (or previous) marked item after `index`; nil when there is none.
    public func selectedIndex(after index: Int, forward: Bool) -> Int? {
        let range = forward ? Array(items.indices.dropFirst(max(index + 1, 0)))
                            : Array(items.indices.prefix(max(index, 0)).reversed())
        return range.first { isSelected(items[$0]) }
    }

    public func selectAll() {
        for item in items { set(item, true) }
    }

    /// Replaces the selection with the items named in `names` (matched through `rules`);
    /// unknown names and ".." are ignored.
    public func setSelection(names: some Sequence<String>) {
        let rules = self.rules
        let wanted = Set(names.map { rules.key($0) })
        selection = Set(items.filter { !$0.isParent }.map { rules.key($0.name) }.filter { wanted.contains($0) })
    }

    public func deselectAll() {
        selection = []
    }

    /// Selects or deselects files sharing the cursor file's extension.
    public func selectSameExtension(_ on: Bool) {
        guard let current = cursorItem, !current.isDirectory, !current.isParent else { return }
        let ext = rules.key(current.fileExtension)
        for item in items where !item.isDirectory && rules.key(item.fileExtension) == ext { set(item, on) }
    }

    public var selectedItems: [FileItem] {
        items.filter { isSelected($0) }
    }

    public var summary: SelectionSummary { summarize(selectedItems) }
    public var totals: SelectionSummary { summarize(items.filter(selectable)) }

    private func summarize(_ list: [FileItem]) -> SelectionSummary {
        var s = SelectionSummary()
        for item in list {
            if item.isPackage {
                // Apps and bundles count as files (Finder), with their size once calculated.
                s.files += 1
                s.bytes += directorySizes[rules.key(item.name)] ?? 0
            } else if item.isDirectory {
                s.directories += 1
                s.bytes += directorySizes[rules.key(item.name)] ?? 0
            } else {
                s.files += 1
                s.bytes += item.size ?? 0
            }
        }
        return s
    }

    // MARK: Sizes

    /// Recursive size of a directory, computed off the main actor.
    public func calculateSize(of item: FileItem) async {
        guard item.isDirectory, !item.isParent, !item.isSymlink else { return }
        let url = location
        let key = rules.key(item.name)
        let size: Int64? = if let archive {
            try? await ArchiveCatalog.shared.index(of: archive.archive).totalSize(under: [archive.member(item.name)])
        } else if let folder = RemoteURL.parse(item.url) {
            try? await RemoteConnections.shared.totalSize(of: folder)
        } else {
            await Self.recursiveSize(of: item.url)
        }
        guard let size else { return }
        guard url == location else { return }
        directorySizes[key] = size
        if sort.field == .size { rebuild() }
    }

    @concurrent
    public static func recursiveSize(of directory: URL) async -> Int64? {
        let keys: [URLResourceKey] = [.fileSizeKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }
        ) else { return nil }
        var total: Int64 = 0
        while let url = walker.nextObject() as? URL {
            if Task.isCancelled { return nil }
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true || v.isDirectory == true { continue }
            total += Int64(v.fileSize ?? 0)
        }
        return total
    }
}
