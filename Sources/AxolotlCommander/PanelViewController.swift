// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import Observation
import OSLog
import UniformTypeIdentifiers

/// Table that sends every key through the panel before default handling.
final class PanelTableView: NSTableView, NSServicesMenuRequestor {
    var onKey: ((NSEvent) -> Bool)?
    var onFocus: (() -> Void)?
    /// Right click: the menu for the row (nil = empty space).
    var onMenu: ((Int?) -> NSMenu?)?
    /// Files the Services menu works on.
    var serviceURLs: (() -> [URL])?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return onMenu?(row >= 0 ? row : nil)
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?,
                                 returnType: NSPasteboard.PasteboardType?) -> Any? {
        if sendType == .fileURL, returnType == nil, serviceURLs?().isEmpty == false { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let urls = serviceURLs?(), !urls.isEmpty else { return false }
        pboard.clearContents()
        return pboard.writeObjects(urls.map { $0 as NSURL })
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }
}

/// One commander panel: path bar, file table, info line. The cursor is the
/// table's single selected row; marked items (`model.selection`) are drawn in
/// the mark color, as in the Windows commander.
final class PanelViewController: NSViewController {
    let side: PanelSide
    weak var router: MainWindowController?
    let model: PanelModel
    let tableView = PanelTableView()
    let pathField = NSTextField()
    /// Breadcrumbs or the path field (hosted inside), by the "Path bar" setting.
    private(set) lazy var pathBar = PathBar(field: pathField)
    /// What the shown trail was built from (location, results, archive).
    private var trailSource: (URL, ResultsListing?, ArchivePath?)?
    let statusField = NSTextField(labelWithString: "")
    private let volumeBar = VolumeBar()
    let tabStrip = TabStrip()
    let briefView = BriefGridView()
    let briefScroll = NSScrollView()
    private let tableScroll = NSScrollView()
    /// Detailed table or brief grid; switched with ⌃⌥1 / ⌃⌥2 and saved with the layout.
    var viewMode: PanelViewMode = .detailed { didSet { if viewMode != oldValue { viewModeChanged() } } }
    /// The view that holds keyboard focus in the current mode.
    var listView: NSView { viewMode == .brief ? briefView : tableView }
    /// Saved states of this panel's tabs; the active one mirrors the model (see PanelTabs.swift).
    var tabs: TabList

    private var watcher: DirectoryWatcher?
    private var watchedURL: URL?
    private var syncingSelection = false
    private var sizeTask: Task<Void, Never>?

    /// Commander-style quick search buffer; nil when not searching.
    private var quickSearch: String?
    /// Mark state applied while Shift+movement drags the selection.
    private var shiftMarkState: Bool?
    /// Items shown by Quick Look (see QuickLook.swift).
    var previewURLs: [URL] = []
    // Brief grid reload bookkeeping: a cursor move only redraws the cursor.
    private var briefCount = -1
    private var briefLocation: URL?
    private var briefSelection: Set<String> = []
    private var briefSizes = 0
    /// True while a tab's saved state is being loaded; the model then does not mirror into `tabs`.
    var isRestoringTab = false

    var showsHidden: Bool { model.showHidden }
    var isActive = false { didSet { updateActiveAppearance() } }

    private var defaultsKey: String { "panel.\(side == .left ? "left" : "right")" }

    init(side: PanelSide, tabs: TabList) {
        self.side = side
        self.tabs = tabs
        model = PanelModel(location: tabs.current.location)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: View

    override func loadView() {
        let root = NSView()

        pathField.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        pathField.isBordered = false
        pathField.drawsBackground = true
        pathField.focusRingType = .none
        pathField.lineBreakMode = .byTruncatingHead
        pathField.cell?.isScrollable = true
        pathField.target = self
        pathField.action = #selector(pathFieldCommitted)
        pathField.delegate = self
        // Leaving the field never navigates; only Enter does.
        pathField.cell?.sendsActionOnEndEditing = false
        configurePathBar()

        for column in Column.allCases {
            let tc = NSTableColumn(identifier: column.identifier)
            tc.title = column.title
            tc.width = column.width
            tc.minWidth = 40
            tc.resizingMask = column == .name ? [.autoresizingMask, .userResizingMask] : .userResizingMask
            if column.isNumeric { tc.headerCell.alignment = .right }
            tableView.addTableColumn(tc)
        }
        tableView.style = .plain
        tableView.rowHeight = 18
        tableView.intercellSpacing = NSSize(width: 6, height: 0)
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.autosaveName = "PanelColumns.\(defaultsKey)"
        tableView.autosaveTableColumns = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
        tableView.registerForDraggedTypes([.fileURL, Self.itemsType])
        tableView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        tableView.draggingDestinationFeedbackStyle = .regular
        tableView.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        tableView.onMenu = { [weak self] row in self?.contextMenu(at: row) }
        tableView.serviceURLs = { [weak self] in self?.serviceURLs() ?? [] }
        tableView.onFocus = { [weak self] in
            guard let self else { return }
            router?.panelDidBecomeFirstResponder(self)
        }

        let scroll = tableScroll
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        statusField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingMiddle

        volumeBar.onChoose = { [weak self] url in
            guard let self else { return }
            router?.activate(side)
            go(to: url)
        }

        configureTabStrip()

        configureBriefView()
        // Both modes share one frame, so the hidden table keeps its column widths.
        let lists = NSView()
        for list in [scroll, briefScroll] {
            list.translatesAutoresizingMaskIntoConstraints = false
            lists.addSubview(list)
            NSLayoutConstraint.activate([
                list.leadingAnchor.constraint(equalTo: lists.leadingAnchor),
                list.trailingAnchor.constraint(equalTo: lists.trailingAnchor),
                list.topAnchor.constraint(equalTo: lists.topAnchor),
                list.bottomAnchor.constraint(equalTo: lists.bottomAnchor),
            ])
        }
        lists.setContentHuggingPriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [volumeBar, tabStrip, pathBar, lists, statusField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            volumeBar.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8),
            tabStrip.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8),
            pathBar.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8),
            lists.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8),
            statusField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8),
        ])
        view = root
        briefScroll.isHidden = viewMode != .brief
        tableScroll.isHidden = viewMode == .brief
        updateActiveAppearance()
        updateSortIndicator()
        observeModel()
        observeAppearance()
        Task { await restoreTab(tabs.current) }
    }

    private func updateActiveAppearance() {
        pathBar.isActive = isActive
        tableView.enumerateAvailableRowViews { rowView, _ in
            (rowView as? PanelRowView)?.panelIsActive = isActive
            rowView.needsDisplay = true
        }
        if viewMode == .brief { updateBriefCursor() }
    }

    private func viewModeChanged() {
        guard isViewLoaded else { return }
        let focused = view.window?.firstResponder === tableView || view.window?.firstResponder === briefView
        briefScroll.isHidden = viewMode != .brief
        tableScroll.isHidden = viewMode == .brief
        if viewMode == .brief { reloadBrief() } else { modelChanged() }
        if focused { view.window?.makeFirstResponder(listView) }
        router?.layoutChanged()
    }

    // MARK: Model observation

    private func observeModel() {
        withObservationTracking {
            _ = model.items
            _ = model.selection
            _ = model.cursor
            _ = model.location
            _ = model.directorySizes
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.modelChanged()
                self?.observeModel()
            }
        }
    }

    func modelChanged() {
        // A reload would end in-place rename editing; the rename refreshes afterwards.
        guard renaming == nil else { return }
        if viewMode == .brief {
            if briefCount != model.items.count || briefLocation != model.location || briefSelection != model.selection
                || briefSizes != model.directorySizes.count {
                briefCount = model.items.count
                briefLocation = model.location
                briefSelection = model.selection
                briefSizes = model.directorySizes.count
                reloadBrief()
            } else {
                updateBriefCursor()
                scrollBriefToCursor()
            }
        } else {
            syncingSelection = true
            tableView.reloadData()
            if !model.items.isEmpty {
                tableView.selectRowIndexes([model.cursor], byExtendingSelection: false)
                tableView.scrollRowToVisible(model.cursor)
            }
            syncingSelection = false
        }
        if pathField.currentEditor() == nil { pathField.stringValue = locationText }
        updatePathBar()
        volumeBar.show(location: model.location)
        router?.panelLocationChanged(self)
        ArchivePasswords.panel(self, showsArchive: model.archive?.archive)
        updateQuickLook()
        updateStatus()
        watchLocation()
        tabsChanged()
    }

    /// Inside an archive the folder holding the archive is watched: rewriting it replaces the file.
    private func watchLocation() {
        // Servers are not watched; ⌘R refreshes.
        if model.remote != nil {
            watcher?.cancel()
            watcher = nil
            watchedURL = nil
            return
        }
        guard watchedURL != diskFolder else { return }
        watcher?.cancel()
        watchedURL = diskFolder
        watcher = DirectoryWatcher(url: diskFolder) { [weak self] in
            Task { @MainActor in await self?.model.refresh() }
        }
    }

    private func updateStatus() {
        if let sizingProgress {
            statusField.stringValue = sizingProgress
            return
        }
        if let quickSearch {
            statusField.stringValue = String(localized: "Quick search: \(quickSearch)")
            return
        }
        let s = model.summary
        if s.files + s.directories > 0 {
            statusField.stringValue = String(localized: "Selected \(s.files) files, \(s.directories) folders — \(Format.bytes(s.bytes))")
        } else if let item = model.cursorItem, !item.isParent {
            let size = item.isDirectory ? (model.directorySizes[model.rules.key(item.name)].map(Format.bytes) ?? String(localized: "folder")) : Format.bytes(item.size ?? 0)
            statusField.stringValue = "\(item.name)   \(size)   \(item.modificationDate.map(Format.date) ?? "")"
        } else {
            let t = model.totals
            statusField.stringValue = String(localized: "\(t.files) files, \(t.directories) folders — \(Format.bytes(t.bytes))")
        }
    }

    /// Runs a navigation, reporting failure without moving the panel.
    func navigate(_ action: () async throws -> Void) async {
        do { try await action() } catch {
            NSSound.beep()
            statusField.stringValue = Format.error(error)
        }
    }

    // MARK: Keys

    func handleKey(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord(event: event) else { return false }
        if chord.key == .escape, chord.modifiers.isEmpty, quickSearch == nil, isSizing {
            sizeTask?.cancel()
            return true
        }
        if handleQuickSearch(chord, event: event) { return true }
        if handleMovement(chord) { return true }
        if let item = UserMenuDefaults.command(for: chord) {
            UserMenuPresenter.run(item, from: self)
            return true
        }
        if let command = KeyMaps.panel.command(for: chord) {
            router?.perform(command)
            return true
        }
        return false
    }

    private func handleQuickSearch(_ chord: KeyChord, event: NSEvent) -> Bool {
        let typing = chord.modifiers.isDisjoint(with: [.control, .command, .option])
        if case .character = chord.key, typing, let text = event.characters, !text.isEmpty {
            let candidate = (quickSearch ?? "") + text
            if model.quickSearch(candidate) { quickSearch = candidate } else { NSSound.beep() }
            updateStatus()
            return true
        }
        guard quickSearch != nil else { return false }
        switch chord.key {
        case .space where chord.modifiers.isEmpty:
            // Names with spaces: while searching, Space types instead of marking.
            let candidate = quickSearch! + " "
            if model.quickSearch(candidate) { quickSearch = candidate } else { NSSound.beep() }
        case .backspace:
            quickSearch?.removeLast()
            if quickSearch?.isEmpty == true { quickSearch = nil } else { model.quickSearch(quickSearch!) }
        case .escape:
            quickSearch = nil
        case .down where chord.modifiers == .control, .up where chord.modifiers == .control:
            model.quickSearchNext(quickSearch!, forward: chord.key == .down)
        default:
            quickSearch = nil
            updateStatus()
            return false
        }
        updateStatus()
        return true
    }

    private func handleMovement(_ chord: KeyChord) -> Bool {
        let rows = model.items.count
        guard rows > 0 else { return false }
        let brief = viewMode == .brief
        let page = brief ? briefRows * briefVisibleColumns
                         : max(1, Int(tableView.visibleRect.height / tableView.rowHeight) - 1)
        let from = model.cursor
        if chord.modifiers == .option {
            // ⌥↑ ⌥↓ previous / next marked item, ⌥Home ⌥End first / last one.
            let found: Int? = switch chord.key {
            case .up: model.selectedIndex(after: from, forward: false)
            case .down: model.selectedIndex(after: from, forward: true)
            case .home: model.selectedIndex(after: -1, forward: true)
            case .end: model.selectedIndex(after: rows, forward: false)
            default: nil
            }
            guard [.up, .down, .home, .end].contains(chord.key) else { return false }
            if let found { model.moveCursor(to: found) } else { NSSound.beep() }
            return true
        }
        let target: Int
        switch chord.key {
        case .up: target = from - 1
        case .down: target = from + 1
        case .pageUp: target = from - page
        case .pageDown: target = from + page
        case .home: target = 0
        case .end: target = rows - 1
        case .left where brief: target = from - briefRows
        case .right where brief: target = from + briefRows
        default: return false
        }
        let extra = chord.modifiers.subtracting(.shift)
        guard extra.isEmpty else { return false }
        let to = min(max(target, 0), rows - 1)
        if chord.modifiers.contains(.shift) {
            // Mark every row passed over; the boundary row too when the move hits it.
            let state = shiftMarkState ?? !(model.cursorItem.map(model.isSelected) ?? false)
            shiftMarkState = state
            if to != from {
                let passed = to > from ? from...(to == rows - 1 && target >= to ? to : to - 1)
                                       : (to == 0 && target <= 0 ? to : to + 1)...from
                model.setSelected(state, range: passed)
            } else {
                model.setSelected(state, range: from...from)
            }
        } else {
            shiftMarkState = nil
        }
        model.moveCursor(to: to)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        if !event.modifierFlags.contains(.shift) { shiftMarkState = nil }
        super.flagsChanged(with: event)
    }

    // MARK: Commands

    /// ⌃⇧F5 remembers the names of the marked items, ⌃⇧F6 marks them in any panel (for this session).
    private static var rememberedSelection: [String] = []

    private static let handled: Set<Command> = [
        .open, .goParent, .goRoot, .goHome, .goBack, .goForward, .changeDirectory, .editPath, .refresh,
        .sortByName, .sortByExtension, .sortByDate, .sortBySize, .toggleHidden, .filter,
        .leftVolumeMenu, .rightVolumeMenu,
        .toggleSelection, .toggleSelectionAndSize, .selectByMask, .deselectByMask, .invertByMask,
        .selectAll, .deselectAll, .selectSameExtension, .deselectSameExtension,
        .copyFullPath, .copyName, .calculateSizes,
        .copy, .move, .delete, .deletePermanently, .makeDirectory, .rename, .copyFiles, .pasteFiles,
        .view, .quickLook, .edit, .viewWith, .editWith, .newFile, .properties, .openTerminal, .revealInFinder,
        .newTab, .closeTab, .nextTab, .previousTab, .hotPaths, .viewModeDetailed, .viewModeBrief,
        .find, .pack, .unpack, .connectToServer, .disconnect, .compareFiles,
        .changeCase, .batchRename, .calculateChecksums, .verifyChecksums, .occupiedSpace, .userMenu,
        .contextMenu, .moveFilesHere, .invertAll, .restoreSelection, .saveSelection, .loadSelection, .volumeInfo,
    ]

    private static let needTargets: Set<Command> = [
        .copy, .move, .delete, .deletePermanently, .rename, .copyFiles, .view, .quickLook, .viewWith, .editWith,
        .changeCase, .batchRename, .calculateChecksums,
    ]

    /// Work on files on disk only: not inside archives, not on servers.
    private static let diskOnly: Set<Command> = [
        .changeCase, .batchRename, .calculateChecksums, .verifyChecksums, .occupiedSpace, .moveFilesHere, .volumeInfo,
        .viewWith, .editWith,
    ]

    func canPerform(_ command: Command) -> Bool {
        if command.hotPathSlot != nil { return true }
        guard Self.handled.contains(command) else { return false }
        if Self.needTargets.contains(command), targets().isEmpty { return false }
        if Self.diskOnly.contains(command), model.archive != nil || model.remote != nil { return false }
        if let archive = model.archive, let allowed = canPerform(command, inArchive: archive) { return allowed }
        if model.remote != nil, let allowed = canPerformOnServer(command) { return allowed }
        switch command {
        case .goBack: return model.canGoBack
        case .goForward: return model.canGoForward
        case .closeTab, .nextTab, .previousTab: return tabs.tabs.count > 1
        // Find results have no folder of their own to create or paste into.
        case .makeDirectory, .newFile: return model.results == nil
        case .pasteFiles: return model.results == nil && Self.pasteboardHasFilesOrPath
        case .moveFilesHere: return model.results == nil && Self.pasteboardHasFiles
        case .restoreSelection: return !model.previousSelection.isEmpty
        case .saveSelection: return !model.selectedItems.isEmpty
        case .loadSelection: return !Self.rememberedSelection.isEmpty
        case .edit: return model.cursorItem.map { !$0.isParent && (!$0.isDirectory || $0.isPackage) } ?? false
        case .viewWith, .editWith: return targets().allSatisfy { !$0.isDirectory || $0.isPackage }
        case .selectSameExtension, .deselectSameExtension:
            return model.cursorItem.map { !$0.isDirectory && !$0.fileExtension.isEmpty } ?? false
        case .pack: return !targets().isEmpty
        case .unpack: return !archiveTargets().isEmpty
        default: return true
        }
    }

    /// Inside an archive: members are not files on disk, so whatever needs one is off,
    /// and changes need a writable format. nil leaves the decision to the general rules.
    private func canPerform(_ command: Command, inArchive archive: ArchivePath) -> Bool? {
        let writable = archive.format.isWritable
        switch command {
        case .newFile, .pasteFiles, .copyFiles, .quickLook, .properties, .pack, .unpack: return false
        case .makeDirectory: return writable
        case .rename: return writable && !targets().isEmpty
        case .move, .delete, .deletePermanently: return writable && !targets().isEmpty
        case .edit, .view: return model.cursorItem.map { !$0.isParent && !$0.isDirectory } ?? false
        default: return nil
        }
    }

    /// On a server: no files on disk (Quick Look, Terminal, Finder, pasteboard, packing),
    /// no new empty file yet. nil leaves the decision to the general rules.
    private func canPerformOnServer(_ command: Command) -> Bool? {
        switch command {
        case .newFile, .pasteFiles, .copyFiles, .quickLook, .properties, .pack, .unpack,
             .openTerminal, .revealInFinder, .find:
            return false
        case .edit, .view: return model.cursorItem.map { !$0.isParent && !$0.isDirectory } ?? false
        default: return nil
        }
    }

    /// Selected archives (or the one under the cursor) on disk.
    private func archiveTargets() -> [URL] {
        guard model.archive == nil else { return [] }
        return targets().filter { !$0.isDirectory && ArchiveFormat.detect(fileName: $0.name) != nil }.map(\.url)
    }

    func perform(_ command: Command) {
        quickSearch = nil
        switch command {
        case .open: Task { await openCursor() }
        case .goParent: Task { await navigate { try await model.goParent() } }
        case .goRoot: Task { await navigate { try await model.goRoot() } }
        case .goHome: go(to: FileManager.default.homeDirectoryForCurrentUser)
        case .goBack: Task { await navigate { try await model.goBack() } }
        case .goForward: Task { await navigate { try await model.goForward() } }
        case .changeDirectory: Task { await askGoToFolder() }
        case .editPath: beginEditingPath()
        case .newTab: newTab()
        case .viewModeDetailed: viewMode = .detailed
        case .viewModeBrief: viewMode = .brief
        case .closeTab: closeTab(at: tabs.active)
        case .nextTab: switchTab { $0.next() }
        case .previousTab: switchTab { $0.previous() }
        case .hotPaths: showHotPathsMenu()
        case .refresh: Task { await model.refresh() }
        case .sortByName: resort(.name)
        case .sortByExtension: resort(.ext)
        case .sortByDate: resort(.date)
        case .sortBySize: resort(.size)
        case .toggleHidden: model.showHidden.toggle()
        case .filter: Task { await askFilter() }
        case .leftVolumeMenu, .rightVolumeMenu: showVolumeMenu()
        case .toggleSelection:
            model.toggleSelection(at: model.cursor)
            model.moveCursor(by: 1)
        case .toggleSelectionAndSize:
            if let item = model.cursorItem, item.isDirectory, !item.isParent, !model.isSelected(item) {
                startSizing([item])
            }
            model.toggleSelection(at: model.cursor)
            model.moveCursor(by: 1)
        case .selectByMask: Task { await askMask(title: String(localized: "Select"), action: { self.model.select(mask: $0, true) }) }
        case .deselectByMask: Task { await askMask(title: String(localized: "Deselect"), action: { self.model.select(mask: $0, false) }) }
        case .invertByMask: Task { await askMask(title: String(localized: "Invert Selection"), action: { self.model.invertSelection(mask: $0) }) }
        case .selectAll: model.selectAll()
        case .deselectAll: model.deselectAll()
        case .invertAll: model.invertSelection(includeDirectories: true)
        case .restoreSelection: model.restorePreviousSelection()
        case .saveSelection: Self.rememberedSelection = model.selectedItems.map(\.name)
        case .loadSelection: model.setSelection(names: Self.rememberedSelection + model.selectedItems.map(\.name))
        case .volumeInfo: VolumeInfoSheet.show(for: diskFolder, in: view.window)
        case .selectSameExtension: model.selectSameExtension(true)
        case .deselectSameExtension: model.selectSameExtension(false)
        case .copyFullPath: copyText(targets().map { $0.url.path(percentEncoded: false) })
        case .copyName: copyText(targets().map(\.name))
        case .copy, .move:
            router?.operations.transfer(command == .copy ? .copy : .move, sources: targets().map(\.url), from: self)
        case .delete, .deletePermanently:
            router?.operations.delete(targets().map(\.url), permanently: command == .deletePermanently)
        case .makeDirectory: router?.operations.makeDirectory(in: self)
        case .rename: if viewMode == .detailed { beginRename() } else { Task { await askRename() } }
        case .copyFiles: copyFilesToPasteboard()
        case .pasteFiles: pasteFromPasteboard()
        case .moveFilesHere: pasteFromPasteboard(move: true)
        case .contextMenu: showContextMenu()
        case .view: openViewer()
        case .find: if let router { FindWindowController.show(from: router) }
        case .compareFiles: Task { await CompareFiles.ask(from: self) }
        case .changeCase: ChangeCaseSheet.show(for: self)
        case .batchRename: BatchRenameSheet.show(for: self)
        case .calculateChecksums: ChecksumWindowController.calculate(targets().map(\.url), base: model.location)
        case .verifyChecksums:
            if let item = model.cursorItem, !item.isDirectory, ChecksumAlgorithm.forListFile(named: item.name) != nil {
                ChecksumWindowController.verify(item.url)
            } else {
                ChecksumWindowController.chooseAndVerify(in: model.location, window: view.window)
            }
        case .occupiedSpace:
            if let router { DiskMapWindowController.show(model.location, from: router) }
        case .userMenu: UserMenuPresenter.show(for: self)
        case .connectToServer: ConnectSheet.show(for: self)
        case .disconnect: DisconnectSheet.show(for: self)
        case .pack: router?.operations.pack(targets(), from: self)
        case .unpack: router?.operations.unpack(archiveTargets(), from: self)
        case .quickLook: toggleQuickLook()
        case .viewWith: showOpenWithMenu(viewing: true)
        case .editWith: showOpenWithMenu(viewing: false)
        case .edit:
            if let item = model.cursorItem {
                if let archive = model.archive {
                    editMember(item.name, in: archive)
                } else if let remote = RemoteURL.parse(item.url) {
                    Task {
                        do { try await ArchiveEdits.shared.edit(remote) } catch { router?.operations.report(error) }
                    }
                } else {
                    edit(item.url)
                }
            }
        case .newFile: router?.operations.makeFile(in: self) { [weak self] in self?.edit($0) }
        case .properties:
            let urls = targets().map(\.url)
            PropertiesSheet.show(urls.isEmpty ? [model.location] : urls, in: view.window) { [weak self] in
                Task { await self?.model.refresh() }
            }
        case .openTerminal:
            Task {
                do { try await Launcher.openTerminal(at: diskFolder) } catch { router?.operations.report(error) }
            }
        case .revealInFinder:
            if let archive = model.archive {
                Launcher.revealInFinder([archive.archive], directory: diskFolder)
            } else {
                Launcher.revealInFinder(targets().map(\.url), directory: model.location)
            }
        case .calculateSizes:
            // Every folder in the panel, regardless of the selection; Esc stops it.
            startSizing(model.items.filter { $0.isDirectory && !$0.isParent && !$0.isSymlink })
        default:
            if let slot = command.hotPathSlot {
                if Command.goHotPaths.contains(command) { goToHotPath(slot) } else { setHotPath(slot) }
            }
        }
    }

    /// The folder on disk: the location, the folder holding the archive the panel is in,
    /// or the home folder while the panel shows a server.
    var diskFolder: URL {
        if model.remote != nil { return FileManager.default.homeDirectoryForCurrentUser }
        return model.archive?.archive.deletingLastPathComponent() ?? model.location
    }

    /// F3: the internal viewer for the file under the cursor; folders and media go to Quick Look.
    private func openViewer() {
        if let (left, right) = CompareFiles.selectedPair(in: self) {
            Task { await CompareFiles.open(left, right, from: self) }
            return
        }
        guard let item = model.cursorItem, !item.isParent else { return }
        if let remote = RemoteURL.parse(item.url) {
            Task {
                do {
                    let copy = try await ArchiveScratch.download(remote)
                    if let sequence = FileSequence(entries: [.init(url: copy, isSelected: false)], current: copy) {
                        ViewerWindowController.show(sequence)
                    }
                } catch {
                    router?.operations.report(error)
                }
            }
            return
        }
        if let archive = model.archive {
            // Members are viewed from a temporary copy.
            Task {
                do {
                    let copy = try await ArchiveScratch.extract(item.name, from: archive, in: self.view.window)
                    if let sequence = FileSequence(entries: [.init(url: copy, isSelected: false)], current: copy) {
                        ViewerWindowController.show(sequence)
                    }
                } catch {
                    router?.operations.report(error)
                }
            }
            return
        }
        if item.isDirectory || ViewerDefaults.prefersQuickLook(item.url) {
            toggleQuickLook()
            return
        }
        let entries = model.items.filter { !$0.isParent && !$0.isDirectory }
            .map { FileSequence.Entry(url: $0.url, isSelected: model.isSelected($0)) }
        guard let sequence = FileSequence(entries: entries, current: item.url) else { return }
        ViewerWindowController.show(sequence)
    }

    private func editMember(_ name: String, in archive: ArchivePath) {
        Task {
            do { try await ArchiveEdits.shared.edit(name, in: archive) } catch { router?.operations.report(error) }
        }
    }

    private func edit(_ url: URL) {
        Task {
            do { try await Launcher.edit(url) } catch { router?.operations.report(error) }
        }
    }

    /// Selected items, or the item under the cursor when nothing is selected.
    func targets() -> [FileItem] {
        let selected = model.selectedItems
        if !selected.isEmpty { return selected }
        return model.cursorItem.flatMap { $0.isParent ? nil : [$0] } ?? []
    }

    /// Puts the cursor on the item with this name (volume name rules).
    func focus(name: String) {
        if let index = model.items.firstIndex(where: { !$0.isParent && model.rules.same($0.name, name) }) {
            model.moveCursor(to: index)
        }
    }

    func go(to url: URL, focusing name: String? = nil) {
        if let remote = RemoteURL.parse(url), remote.path.isEmpty { return connect(to: remote) }
        Task { await navigate { try await model.go(to: url, focusing: name) } }
    }

    /// Connects (asking for a password when needed) and shows `location`; "" path = the login folder.
    func connect(to location: RemoteLocation, password: String? = nil, options: ConnectOptions? = nil,
                 then done: ((URL) -> Void)? = nil) {
        statusField.stringValue = String(localized: "Connecting to \(RemoteURL.displayName(location.endpoint))…")
        Task {
            do {
                _ = try await RemoteConnections.shared.session(for: location.endpoint, password: password, options: options)
                let resolved = try await RemoteConnections.shared.resolve(location)
                try await model.go(to: resolved.url)
                done?(resolved.url)
            } catch RemoteError.cancelled {
                updateStatus()
            } catch {
                NSSound.beep()
                updateStatus()
                router?.operations.report(error)
            }
        }
    }

    func showResults(_ listing: ResultsListing, focusing name: String? = nil) {
        Task { await navigate { try await model.showResults(listing, focusing: name) } }
    }

    /// Path field text: the folder, or the results title and their root folder.
    private var locationText: String {
        guard let results = model.results else { return model.location.displayPath }
        return "\(results.title) — \(model.location.displayPath)"
    }

    private func resort(_ field: SortField) {
        model.sort = model.sort.toggled(field)
        updateSortIndicator()
    }

    func updateSortIndicator() {
        for column in Column.allCases {
            guard let tc = tableView.tableColumn(withIdentifier: column.identifier) else { continue }
            let image = column.sortField == model.sort.field
                ? NSImage(named: model.sort.ascending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator")
                : nil
            tableView.setIndicatorImage(image, in: tc)
        }
    }

    private func openCursor() async {
        guard let item = model.cursorItem else { return }
        if item.isPackage {
            NSWorkspace.shared.open(item.url)
            return
        }
        do {
            guard let file = try await model.enterCursor() else { return }
            if let archive = model.archive {
                NSWorkspace.shared.open(try await ArchiveScratch.extract(file.name, from: archive, in: view.window))
            } else if let remote = RemoteURL.parse(file.url) {
                // FTP listings do not say what a link points to: try it as a folder first.
                if file.isSymlink, (try? await model.go(to: file.url)) != nil { return }
                NSWorkspace.shared.open(try await ArchiveScratch.download(remote))
            } else {
                NSWorkspace.shared.open(file.url)
            }
        } catch RemoteError.cancelled {
        } catch ArchiveError.cancelled {
        } catch {
            NSSound.beep()
            statusField.stringValue = Format.error(error)
        }
    }

    @objc private func doubleClicked() {
        guard tableView.clickedRow >= 0 else { return }
        model.moveCursor(to: tableView.clickedRow)
        Task { await openCursor() }
    }

    private var isSizing: Bool { sizingProgress != nil }
    /// Status text while ⌃⇧F10 calculates folder sizes.
    private var sizingProgress: String?

    private func startSizing(_ items: [FileItem]) {
        sizeTask?.cancel()
        sizeTask = Task {
            defer { sizingProgress = nil; updateStatus() }
            for (index, item) in items.enumerated() {
                if Task.isCancelled { break }
                if items.count > 1 {
                    sizingProgress = String(localized: "Calculating folder sizes: \(index + 1) of \(items.count) — Esc stops")
                    updateStatus()
                }
                await model.calculateSize(of: item)
            }
        }
    }

    private func copyText(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    // MARK: Rename in place (F2)

    private var renaming: (row: Int, item: FileItem)?

    /// Brief view has no editable cells: F2 asks for the name in a sheet.
    private func askRename() async {
        guard let item = model.cursorItem, !item.isParent else { return }
        let name = model.results == nil ? item.name : item.url.lastPathComponent
        guard let newName = await TextPrompt.ask(title: String(localized: "Rename"), message: String(localized: "New name:"),
                                                 initial: name, in: view.window) else { return }
        router?.operations.rename(item.url, to: newName, in: self)
    }

    private func beginRename() {
        guard let item = model.cursorItem, !item.isParent,
              let column = tableView.tableColumn(withIdentifier: Column.name.identifier) else { return }
        let row = model.cursor
        let columnIndex = tableView.column(withIdentifier: column.identifier)
        guard let cell = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        renaming = (row, item)
        // Find results show the path below their root; only the last part is renamed.
        let name = model.results == nil ? item.name : item.url.lastPathComponent
        field.stringValue = name
        field.isEditable = true
        field.delegate = self
        tableView.editColumn(columnIndex, row: row, with: nil, select: false)
        if field.currentEditor() == nil { view.window?.makeFirstResponder(field) }
        // Finder selects the base name only, so typing keeps the extension.
        let base = item.isDirectory && !item.isPackage ? name
            : model.results == nil ? item.baseName : (name as NSString).deletingPathExtension
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
    }

    private func endRename(commit: Bool, newName: String) {
        guard let (_, item) = renaming else { return }
        renaming = nil
        view.window?.makeFirstResponder(tableView)
        modelChanged()
        if commit { router?.operations.rename(item.url, to: newName, in: self) }
    }

    // MARK: Pasteboard

    private static var pasteboardHasFiles: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
    }

    private static var pasteboardHasFilesOrPath: Bool {
        pasteboardHasFiles || NSPasteboard.general.string(forType: .string)?.hasPrefix("/") == true
    }

    private func copyFilesToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(targets().map { $0.url as NSURL })
    }

    /// Files on the pasteboard are copied here (moved with ⌘⌥V, as in Finder); a path as text navigates there.
    private func pasteFromPasteboard(move: Bool = false) {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            router?.operations.transfer(move ? .move : .copy, sources: urls, from: self, to: model.location)
        } else if let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = try? PathInput.resolve(text, relativeTo: model.location, absoluteIsLocal: true) {
            go(to: url)
        }
    }

    // MARK: Prompts

    private func askMask(title: String, action: @escaping (WildcardMask) -> Void) async {
        guard let text = await TextPrompt.ask(title: title, message: String(localized: "Mask (e.g. *.txt;*.md):"),
                                              initial: "*.*", in: view.window) else { return }
        action(WildcardMask(text))
    }

    private func askFilter() async {
        guard let text = await TextPrompt.ask(title: String(localized: "Filter"),
                                              message: String(localized: "Show only names matching (empty shows all):"),
                                              initial: model.filter?.pattern ?? "*.*", in: view.window) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        model.filter = trimmed.isEmpty || trimmed == "*.*" || trimmed == "*" ? nil : WildcardMask(trimmed)
    }

    // MARK: Volume menu

    private func showVolumeMenu() {
        let menu = NSMenu()
        for volume in Volumes.mounted() {
            let title = volume.availableCapacity.map { String(localized: "\(volume.name)  —  \(Format.bytes($0)) free") } ?? volume.name
            menu.addItem(placeItem(title, volume.url, icon: NSWorkspace.shared.icon(forFile: volume.url.path)))
        }
        menu.addItem(.separator())
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        menu.addItem(placeItem(String(localized: "Home"), home, icon: NSImage(systemSymbolName: "house", accessibilityDescription: nil)))
        for (dir, symbol) in [(FileManager.SearchPathDirectory.desktopDirectory, "menubar.dock.rectangle"),
                              (.documentDirectory, "doc"), (.downloadsDirectory, "arrow.down.circle"),
                              (.applicationDirectory, "square.grid.2x2")] {
            if let url = fm.urls(for: dir, in: dir == .applicationDirectory ? .localDomainMask : .userDomainMask).first {
                menu.addItem(placeItem(url.lastPathComponent, url, icon: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)))
            }
        }
        let iCloud = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        if fm.fileExists(atPath: iCloud.path) {
            menu.addItem(placeItem(String(localized: "iCloud Drive"), iCloud, icon: NSImage(systemSymbolName: "icloud", accessibilityDescription: nil)))
        }
        menu.addItem(placeItem(String(localized: "Network Volumes"), URL(filePath: "/Volumes", directoryHint: .isDirectory),
                               icon: NSImage(systemSymbolName: "network", accessibilityDescription: nil)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: pathBar.bounds.height + 2), in: pathBar)
    }

    private func placeItem(_ title: String, _ url: URL, icon: NSImage?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(volumeChosen(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        icon?.size = NSSize(width: 16, height: 16)
        item.image = icon
        return item
    }

    @objc private func volumeChosen(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        go(to: url)
    }

    // MARK: Path field

    @objc private func pathFieldCommitted() {
        // With breadcrumbs the bar comes back at once; the panel then shows the new folder, or the
        // status line the error.
        let returnFocus = pathBar.style == .breadcrumbs
        defer { if returnFocus { view.window?.makeFirstResponder(listView) } }
        let input = pathField.stringValue
        if model.results != nil, input == locationText {
            view.window?.makeFirstResponder(tableView)
            return
        }
        // "sftp://user:password@host/path" connects; the password is used once and never stored in history.
        if let typed = RemoteURL.parse(typed: input) {
            connect(to: typed.location, password: typed.password) { [weak self] url in
                AppSettings.shared.recentPaths.add(url.displayPath)
                if let self { view.window?.makeFirstResponder(tableView) }
            }
            return
        }
        do {
            let url = try PathInput.resolve(input, relativeTo: model.location)
            Task {
                do {
                    try await model.go(to: url)
                    AppSettings.shared.recentPaths.add(url.displayPath)
                    view.window?.makeFirstResponder(tableView)
                } catch {
                    NSSound.beep()
                    statusField.stringValue = Format.error(error)
                }
            }
        } catch {
            NSSound.beep()
            statusField.stringValue = Format.error(error)
        }
    }
}

extension PanelViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        if (obj.object as? NSTextField) === pathField { pathBar.endEditing() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control !== pathField, renaming != nil {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                (control as? NSTextField)?.isEditable = false
                endRename(commit: false, newName: "")
                return true
            }
            if selector == #selector(NSResponder.insertNewline(_:)) {
                let name = control.stringValue
                (control as? NSTextField)?.isEditable = false
                endRename(commit: true, newName: name)
                return true
            }
            return false
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            pathField.stringValue = locationText
            view.window?.makeFirstResponder(tableView)
            return true
        }
        return false
    }
}

// MARK: - Table

private enum Column: String, CaseIterable {
    case name, ext, size, date

    var identifier: NSUserInterfaceItemIdentifier { .init(rawValue) }
    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .ext: String(localized: "Ext")
        case .size: String(localized: "Size")
        case .date: String(localized: "Date")
        }
    }
    var width: CGFloat {
        switch self {
        case .name: 140
        case .ext: 50
        case .size: 90
        case .date: 130
        }
    }
    var isNumeric: Bool { self == .size || self == .date }
    var sortField: SortField {
        switch self {
        case .name: .name
        case .ext: .ext
        case .size: .size
        case .date: .date
        }
    }
}

extension PanelViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { model.items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let column = Column(rawValue: tableColumn.identifier.rawValue),
              row < model.items.count else { return nil }
        let item = model.items[row]
        let cell = tableView.makeView(withIdentifier: tableColumn.identifier, owner: nil) as? FileCellView
            ?? FileCellView(identifier: tableColumn.identifier, withIcon: column == .name)
        let marked = model.isSelected(item)
        cell.textField?.alignment = column.isNumeric ? .right : .left
        cell.textField?.stringValue = text(for: column, item: item)
        cell.textField?.textColor = textColor(for: item, marked: marked)
        cell.textField?.font = marked ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
        if column == .name { cell.imageView?.image = IconCache.icon(for: item) }
        return cell
    }

    private func text(for column: Column, item: FileItem) -> String {
        switch column {
        case .name: return item.isParent ? ".." : item.baseName
        case .ext: return item.fileExtension
        case .size:
            if item.isParent { return "" }
            if item.isDirectory {
                // A package is a file to the user: no <DIR>, its size once calculated (Space).
                return model.directorySizes[model.rules.key(item.name)].map(Format.grouped) ?? (item.isPackage ? "—" : "<DIR>")
            }
            return Format.grouped(item.size ?? 0)
        case .date: return item.isParent ? "" : item.modificationDate.map(Format.date) ?? ""
        }
    }

    // MARK: Drag & drop (shared rules in PanelDragDrop.swift)

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row < model.items.count, !model.items[row].isParent else { return nil }
        // Dragging a marked row drags the whole selection (written when the session begins).
        if model.isSelected(model.items[row]) { return nil }
        return dragItem(for: model.items[row])
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        guard let row = rowIndexes.first, row < model.items.count, model.isSelected(model.items[row]) else { return }
        session.draggingPasteboard.clearContents()
        session.draggingPasteboard.writeObjects(model.selectedItems.map(dragItem(for:)))
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let target = dropTarget(row: dropOperation == .on ? row : nil) else { return [] }
        // Highlight the folder row, or the whole panel when dropping into the current folder.
        tableView.setDropRow(target == model.location ? -1 : row, dropOperation: .on)
        return dragOperation(info, target: target)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let target = dropTarget(row: dropOperation == .on ? row : nil) else { return false }
        return performDrop(info, target: target)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncingSelection, tableView.selectedRow >= 0 else { return }
        model.moveCursor(to: tableView.selectedRow)
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let column = Column(rawValue: tableColumn.identifier.rawValue) else { return }
        resort(column.sortField)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = PanelRowView()
        rowView.panelIsActive = isActive
        return rowView
    }
}

/// Inactive panel shows the cursor as an outline, like the Windows commander.
final class PanelRowView: NSTableRowView {
    var panelIsActive = true {
        didSet {
            guard panelIsActive != oldValue else { return }
            for case let cell as NSTableCellView in subviews { cell.backgroundStyle = interiorBackgroundStyle }
            needsDisplay = true
        }
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected && panelIsActive ? .emphasized : .normal
    }

    override var isEmphasized: Bool {
        get { panelIsActive }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        if panelIsActive {
            super.drawSelection(in: dirtyRect)
        } else {
            NSColor.secondaryLabelColor.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            path.lineWidth = 1
            path.stroke()
        }
    }
}

final class FileCellView: NSTableCellView {
    convenience init(identifier: NSUserInterfaceItemIdentifier, withIcon: Bool) {
        self.init(frame: .zero)
        self.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        textField = label
        var constraints = [
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
        ]
        if withIcon {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            addSubview(image)
            imageView = image
            constraints += [
                image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            ]
        } else {
            constraints.append(label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2))
        }
        NSLayoutConstraint.activate(constraints)
    }
}

// MARK: - Path bar

extension PanelViewController {
    fileprivate func configurePathBar() {
        pathBar.onClick = { [weak self] index, flags in self?.pathSegmentClicked(index, flags: flags) }
        pathBar.menuForSegment = { [weak self] index in self?.pathSegmentMenu(index) }
        pathBar.onEmptyClick = { [weak self] in
            guard let self else { return }
            router?.activate(side)
            beginEditingPath()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(pathBarSettingsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    /// The trail follows the location; cursor moves and selection changes leave it alone.
    fileprivate func updatePathBar() {
        // The archive counts too: a restored tab learns that its location is an archive only after loading.
        if let source = trailSource, source == (model.location, model.results, model.archive) { return }
        trailSource = (model.location, model.results, model.archive)
        pathBar.show(trail: Breadcrumbs.trail(
            location: model.location, results: model.results, archive: model.archive, remote: model.remote,
            volume: Self.volume(containing: model.location),
            home: FileManager.default.homeDirectoryForCurrentUser))
    }

    /// The volume a local location is on, named as the volume bar names it. A mount point that is
    /// not part of the shown path (firmlinked system folders) counts as the boot volume.
    private static func volume(containing url: URL) -> (root: URL, name: String) {
        var root = URL(filePath: "/", directoryHint: .isDirectory)
        if !RemoteURL.isRemote(url) {
            let mount = Volumes.root(of: url)
            let path = url.path(percentEncoded: false), mountPath = mount.path(percentEncoded: false)
            let prefix = mountPath.hasSuffix("/") ? mountPath : mountPath + "/"
            if mountPath != "/", path == mountPath || (path + "/").hasPrefix(prefix) { root = mount }
        }
        let name = (try? root.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
            ?? FileManager.default.displayName(atPath: root.path(percentEncoded: false))
        return (root, name)
    }

    @objc private func pathBarSettingsChanged() {
        let style = PathBar.savedStyle, icons = PathBar.savedShowsIcons
        guard style != pathBar.style || icons != pathBar.showsIcons else { return }
        if style != pathBar.style, pathField.currentEditor() != nil { view.window?.makeFirstResponder(listView) }
        pathBar.apply(style: style, showsIcons: icons)
    }

    /// ⌘L: the path field of this panel, all text selected (breadcrumbs make way for it).
    func beginEditingPath() {
        pathField.stringValue = locationText
        pathBar.beginEditing()
        view.window?.makeFirstResponder(pathField)
        pathField.currentEditor()?.selectAll(nil)
    }

    private func pathSegmentClicked(_ index: Int, flags: NSEvent.ModifierFlags) {
        let trail = pathBar.trail
        guard trail.indices.contains(index), trail[index].isClickable else { return }
        router?.activate(side)
        let url = trail[index].url
        let focus = Breadcrumbs.focusName(after: index, in: trail)
        if flags.contains(.command) { return openInNewTab(url, focusing: focus) }
        // The current folder; with results, its root leaves the results.
        if index == trail.count - 1, model.results == nil { return }
        go(to: url, focusing: focus)
    }

    private func openInNewTab(_ url: URL, focusing name: String?) {
        newTab()
        go(to: url, focusing: name)
    }

    /// The child of `segment` on the current trail, for the cursor wherever the segment is opened.
    private func focusName(after segment: PathSegment) -> String? {
        pathBar.trail.firstIndex(of: segment).flatMap { Breadcrumbs.focusName(after: $0, in: pathBar.trail) }
    }

    private func pathSegmentMenu(_ index: Int) -> NSMenu? {
        let trail = pathBar.trail
        guard trail.indices.contains(index), trail[index].isClickable else { return nil }
        let segment = trail[index]
        let menu = NSMenu()
        menu.autoenablesItems = false
        @discardableResult
        func add(_ title: String, _ action: Selector, to menu: NSMenu, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.representedObject = segment
            menu.addItem(item)
            return item
        }
        add(String(localized: "Open in Other Panel"), #selector(segmentOpenInOtherPanel(_:)), to: menu)
        add(String(localized: "Open in New Tab"), #selector(segmentOpenInNewTab(_:)), to: menu)
        menu.addItem(.separator())
        add(String(localized: "Copy Path"), #selector(segmentCopyPath(_:)), to: menu)
        let slots = NSMenu()
        for slot in 0..<HotPaths.shortcutSlots {
            let title = "\(slot + 1)" + (AppSettings.shared.hotPaths[slot].map { "  —  \($0.name)" } ?? "")
            add(title, #selector(segmentSetHotPath(_:)), to: slots, tag: slot)
        }
        let hotPath = NSMenuItem(title: String(localized: "Set as Hot Path"), action: nil, keyEquivalent: "")
        hotPath.submenu = slots
        menu.addItem(hotPath)
        menu.addItem(.separator())
        let finder = add(String(localized: "Show in Finder"), #selector(segmentShowInFinder(_:)), to: menu)
        finder.isEnabled = [.volume, .home, .folder, .archive].contains(segment.kind)
        return menu
    }

    private static func segment(of sender: NSMenuItem) -> PathSegment? { sender.representedObject as? PathSegment }

    @objc private func segmentOpenInOtherPanel(_ sender: NSMenuItem) {
        guard let segment = Self.segment(of: sender) else { return }
        router?.otherPanel(than: self).go(to: segment.url, focusing: focusName(after: segment))
    }

    @objc private func segmentOpenInNewTab(_ sender: NSMenuItem) {
        guard let segment = Self.segment(of: sender) else { return }
        router?.activate(side)
        openInNewTab(segment.url, focusing: focusName(after: segment))
    }

    @objc private func segmentCopyPath(_ sender: NSMenuItem) {
        guard let segment = Self.segment(of: sender) else { return }
        copyText([segment.url.displayPath])
    }

    @objc private func segmentSetHotPath(_ sender: NSMenuItem) {
        guard let segment = Self.segment(of: sender) else { return }
        setHotPath(sender.tag, path: segment.url.displayPath)
    }

    @objc private func segmentShowInFinder(_ sender: NSMenuItem) {
        guard let segment = Self.segment(of: sender) else { return }
        if segment.kind == .archive {
            Launcher.revealInFinder([segment.url], directory: segment.url.deletingLastPathComponent())
        } else {
            Launcher.revealInFinder([], directory: segment.url)
        }
    }
}
