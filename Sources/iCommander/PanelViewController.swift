import AppKit
import CommanderCore
import Observation
import OSLog
import UniformTypeIdentifiers

/// Table that sends every key through the panel before default handling.
final class PanelTableView: NSTableView {
    var onKey: ((NSEvent) -> Bool)?
    var onFocus: (() -> Void)?

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
    private let pathField = NSTextField()
    private let statusField = NSTextField(labelWithString: "")

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

    var showsHidden: Bool { model.showHidden }
    var isActive = false { didSet { updateActiveAppearance() } }

    private var defaultsKey: String { "panel.\(side == .left ? "left" : "right")" }

    init(side: PanelSide) {
        self.side = side
        let saved = UserDefaults.standard.string(forKey: "panel.\(side == .left ? "left" : "right").path")
        let start = saved.map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        model = PanelModel(location: start)
        if let raw = UserDefaults.standard.data(forKey: "panel.\(side == .left ? "left" : "right").sort"),
           let sort = try? JSONDecoder().decode(SortSpec.self, from: raw) {
            model.sort = sort
        }
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
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)
        tableView.draggingDestinationFeedbackStyle = .regular
        tableView.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        tableView.onFocus = { [weak self] in
            guard let self else { return }
            router?.panelDidBecomeFirstResponder(self)
        }

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        statusField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingMiddle

        let stack = NSStackView(views: [pathField, scroll, statusField])
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
            pathField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8),
            statusField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8),
        ])
        view = root
        updateActiveAppearance()
        updateSortIndicator()
        observeModel()
        Task { await self.navigate { try await self.model.go(to: self.model.location) } }
    }

    private func updateActiveAppearance() {
        pathField.backgroundColor = isActive ? .controlAccentColor.withAlphaComponent(0.28) : .quaternarySystemFill
        tableView.enumerateAvailableRowViews { rowView, _ in
            (rowView as? PanelRowView)?.panelIsActive = isActive
            rowView.needsDisplay = true
        }
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

    private func modelChanged() {
        // A reload would end in-place rename editing; the rename refreshes afterwards.
        guard renaming == nil else { return }
        syncingSelection = true
        tableView.reloadData()
        if !model.items.isEmpty {
            tableView.selectRowIndexes([model.cursor], byExtendingSelection: false)
            tableView.scrollRowToVisible(model.cursor)
        }
        syncingSelection = false
        if pathField.currentEditor() == nil { pathField.stringValue = model.location.path(percentEncoded: false) }
        router?.panelLocationChanged(self)
        updateQuickLook()
        updateStatus()
        watchLocation()
        UserDefaults.standard.set(model.location.path(percentEncoded: false), forKey: "\(defaultsKey).path")
    }

    private func watchLocation() {
        guard watchedURL != model.location else { return }
        watcher?.cancel()
        watchedURL = model.location
        watcher = DirectoryWatcher(url: model.location) { [weak self] in
            Task { @MainActor in await self?.model.refresh() }
        }
    }

    private func updateStatus() {
        if let quickSearch {
            statusField.stringValue = "Quick search: \(quickSearch)"
            return
        }
        let s = model.summary
        if s.files + s.directories > 0 {
            statusField.stringValue = "Selected \(s.files) files, \(s.directories) folders — \(Format.bytes(s.bytes))"
        } else if let item = model.cursorItem, !item.isParent {
            let size = item.isDirectory ? (model.directorySizes[model.rules.key(item.name)].map(Format.bytes) ?? "folder") : Format.bytes(item.size ?? 0)
            statusField.stringValue = "\(item.name)   \(size)   \(item.modificationDate.map(Format.date) ?? "")"
        } else {
            let t = model.totals
            statusField.stringValue = "\(t.files) files, \(t.directories) folders — \(Format.bytes(t.bytes))"
        }
    }

    /// Runs a navigation, reporting failure without moving the panel.
    private func navigate(_ action: () async throws -> Void) async {
        do { try await action() } catch {
            NSSound.beep()
            statusField.stringValue = Format.error(error)
        }
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord(event: event) else {
            log.debug("unmapped key code \(event.keyCode)")
            return false
        }
        log.debug("key \(chord.description, privacy: .public)")
        if handleQuickSearch(chord, event: event) { return true }
        if handleMovement(chord) { return true }
        if let command = KeyMap.standard.command(for: chord) {
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
        let page = max(1, Int(tableView.visibleRect.height / tableView.rowHeight) - 1)
        let from = model.cursor
        let target: Int
        switch chord.key {
        case .up: target = from - 1
        case .down: target = from + 1
        case .pageUp: target = from - page
        case .pageDown: target = from + page
        case .home: target = 0
        case .end: target = rows - 1
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

    private static let handled: Set<Command> = [
        .open, .goParent, .goRoot, .goHome, .goBack, .goForward, .changeDirectory, .refresh,
        .sortByName, .sortByExtension, .sortByDate, .sortBySize, .toggleHidden, .filter,
        .leftVolumeMenu, .rightVolumeMenu,
        .toggleSelection, .toggleSelectionAndSize, .selectByMask, .deselectByMask, .invertByMask,
        .selectAll, .deselectAll, .selectSameExtension, .deselectSameExtension,
        .copyFullPath, .copyName, .calculateSizes,
        .copy, .move, .delete, .deletePermanently, .makeDirectory, .rename, .copyFiles, .pasteFiles,
        .view, .quickLook, .properties, .openTerminal, .revealInFinder,
    ]

    private static let needTargets: Set<Command> = [
        .copy, .move, .delete, .deletePermanently, .rename, .copyFiles, .view, .quickLook,
    ]

    func canPerform(_ command: Command) -> Bool {
        guard Self.handled.contains(command) else { return false }
        if Self.needTargets.contains(command), targets().isEmpty { return false }
        switch command {
        case .pasteFiles: return Self.pasteboardHasFilesOrPath
        case .goBack: return model.canGoBack
        case .goForward: return model.canGoForward
        case .selectSameExtension, .deselectSameExtension:
            return model.cursorItem.map { !$0.isDirectory && !$0.fileExtension.isEmpty } ?? false
        default: return true
        }
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
        case .changeDirectory: beginPathEditing()
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
        case .selectByMask: Task { await askMask(title: "Select", action: { self.model.select(mask: $0, true) }) }
        case .deselectByMask: Task { await askMask(title: "Deselect", action: { self.model.select(mask: $0, false) }) }
        case .invertByMask: Task { await askMask(title: "Invert Selection", action: { self.model.invertSelection(mask: $0) }) }
        case .selectAll: model.selectAll()
        case .deselectAll: model.deselectAll()
        case .selectSameExtension: model.selectSameExtension(true)
        case .deselectSameExtension: model.selectSameExtension(false)
        case .copyFullPath: copyText(targets().map { $0.url.path(percentEncoded: false) })
        case .copyName: copyText(targets().map(\.name))
        case .copy, .move:
            router?.operations.transfer(command == .copy ? .copy : .move, sources: targets().map(\.url), from: self)
        case .delete, .deletePermanently:
            router?.operations.delete(targets().map(\.url), permanently: command == .deletePermanently)
        case .makeDirectory: router?.operations.makeDirectory(in: self)
        case .rename: beginRename()
        case .copyFiles: copyFilesToPasteboard()
        case .pasteFiles: pasteFromPasteboard()
        case .view, .quickLook: toggleQuickLook()
        case .properties:
            let urls = targets().map(\.url)
            PropertiesSheet.show(urls.isEmpty ? [model.location] : urls, in: view.window)
        case .openTerminal:
            Task {
                do { try await Launcher.openTerminal(at: model.location) } catch { router?.operations.report(error) }
            }
        case .revealInFinder: Launcher.revealInFinder(targets().map(\.url), directory: model.location)
        case .calculateSizes:
            let dirs = model.selectedItems.filter(\.isDirectory)
            startSizing(dirs.isEmpty ? model.items.filter { $0.isDirectory && !$0.isParent } : dirs)
        default: break
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
        Task { await navigate { try await model.go(to: url, focusing: name) } }
    }

    private func resort(_ field: SortField) {
        model.sort = model.sort.toggled(field)
        if let data = try? JSONEncoder().encode(model.sort) {
            UserDefaults.standard.set(data, forKey: "\(defaultsKey).sort")
        }
        updateSortIndicator()
    }

    private func updateSortIndicator() {
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
            if let file = try await model.enterCursor() { NSWorkspace.shared.open(file.url) }
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

    private func startSizing(_ items: [FileItem]) {
        sizeTask?.cancel()
        sizeTask = Task {
            for item in items {
                if Task.isCancelled { break }
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

    private func beginRename() {
        guard let item = model.cursorItem, !item.isParent,
              let column = tableView.tableColumn(withIdentifier: Column.name.identifier) else { return }
        let row = model.cursor
        let columnIndex = tableView.column(withIdentifier: column.identifier)
        guard let cell = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        renaming = (row, item)
        field.stringValue = item.name
        field.isEditable = true
        field.delegate = self
        tableView.editColumn(columnIndex, row: row, with: nil, select: false)
        if field.currentEditor() == nil { view.window?.makeFirstResponder(field) }
        log.debug("rename begin editor=\(field.currentEditor() != nil)")
        // Finder selects the base name only, so typing keeps the extension.
        let base = item.isDirectory ? item.name : item.baseName
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

    private static var pasteboardHasFilesOrPath: Bool {
        let pb = NSPasteboard.general
        if pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) { return true }
        return pb.string(forType: .string)?.hasPrefix("/") == true
    }

    private func copyFilesToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(targets().map { $0.url as NSURL })
    }

    /// Files on the pasteboard are copied here; a path as text navigates there.
    private func pasteFromPasteboard() {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            router?.operations.transfer(.copy, sources: urls, from: self, to: model.location)
        } else if let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let url = try? PathRules.resolve(text, relativeTo: model.location) {
            go(to: url)
        }
    }

    // MARK: Prompts

    private func askMask(title: String, action: @escaping (WildcardMask) -> Void) async {
        guard let text = await TextPrompt.ask(title: title, message: "Mask (e.g. *.txt;*.md):",
                                              initial: "*.*", in: view.window) else { return }
        action(WildcardMask(text))
    }

    private func askFilter() async {
        guard let text = await TextPrompt.ask(title: "Filter", message: "Show only names matching (empty shows all):",
                                              initial: model.filter?.pattern ?? "*.*", in: view.window) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        model.filter = trimmed.isEmpty || trimmed == "*.*" || trimmed == "*" ? nil : WildcardMask(trimmed)
    }

    // MARK: Volume menu

    private func showVolumeMenu() {
        let menu = NSMenu()
        for volume in Volumes.mounted() {
            let title = volume.availableCapacity.map { "\(volume.name)  —  \(Format.bytes($0)) free" } ?? volume.name
            menu.addItem(placeItem(title, volume.url, icon: NSWorkspace.shared.icon(forFile: volume.url.path)))
        }
        menu.addItem(.separator())
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        menu.addItem(placeItem("Home", home, icon: NSImage(systemSymbolName: "house", accessibilityDescription: nil)))
        for (dir, symbol) in [(FileManager.SearchPathDirectory.desktopDirectory, "menubar.dock.rectangle"),
                              (.documentDirectory, "doc"), (.downloadsDirectory, "arrow.down.circle"),
                              (.applicationDirectory, "square.grid.2x2")] {
            if let url = fm.urls(for: dir, in: dir == .applicationDirectory ? .localDomainMask : .userDomainMask).first {
                menu.addItem(placeItem(url.lastPathComponent, url, icon: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)))
            }
        }
        let iCloud = home.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        if fm.fileExists(atPath: iCloud.path) {
            menu.addItem(placeItem("iCloud Drive", iCloud, icon: NSImage(systemSymbolName: "icloud", accessibilityDescription: nil)))
        }
        menu.addItem(placeItem("Network Volumes", URL(filePath: "/Volumes", directoryHint: .isDirectory),
                               icon: NSImage(systemSymbolName: "network", accessibilityDescription: nil)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: pathField.bounds.height + 2), in: pathField)
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

    private func beginPathEditing() {
        view.window?.makeFirstResponder(pathField)
        pathField.currentEditor()?.selectAll(nil)
    }

    @objc private func pathFieldCommitted() {
        let input = pathField.stringValue
        do {
            let url = try PathRules.resolve(input, relativeTo: model.location)
            Task {
                do {
                    try await model.go(to: url)
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
            pathField.stringValue = model.location.path(percentEncoded: false)
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
        case .name: "Name"
        case .ext: "Ext"
        case .size: "Size"
        case .date: "Date"
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
        cell.textField?.textColor = marked ? .systemRed : (item.isHidden ? .secondaryLabelColor : .labelColor)
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
                return model.directorySizes[model.rules.key(item.name)].map(Format.grouped) ?? "<DIR>"
            }
            return Format.grouped(item.size ?? 0)
        case .date: return item.isParent ? "" : item.modificationDate.map(Format.date) ?? ""
        }
    }

    // MARK: Drag & drop — same rules as F5/F6: Option copies, Command moves,
    // otherwise move within a volume and copy across volumes (Finder convention).

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row < model.items.count, !model.items[row].isParent else { return nil }
        let item = model.items[row]
        // Dragging a marked row drags the whole selection.
        if model.isSelected(item) { return nil }
        return item.url as NSURL
    }

    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                   willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        guard let row = rowIndexes.first, row < model.items.count, model.isSelected(model.items[row]) else { return }
        session.draggingPasteboard.clearContents()
        session.draggingPasteboard.writeObjects(model.selectedItems.map { $0.url as NSURL })
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let target = dropTarget(row: row, operation: dropOperation) else { return [] }
        // Highlight the folder row, or the whole panel when dropping into the current folder.
        tableView.setDropRow(target == model.location ? -1 : row, dropOperation: .on)
        guard let urls = Self.fileURLs(info), !urls.isEmpty else { return [] }
        if urls.contains(where: { $0.deletingLastPathComponent().standardizedFileURL == target.standardizedFileURL }) { return [] }
        return dragOperation(info, sources: urls, target: target)
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = Self.fileURLs(info), !urls.isEmpty,
              let target = dropTarget(row: row, operation: dropOperation) else { return false }
        let op = dragOperation(info, sources: urls, target: target)
        router?.operations.transfer(op == .move ? .move : .copy, sources: urls, from: self, to: target)
        return true
    }

    private func dropTarget(row: Int, operation: NSTableView.DropOperation) -> URL? {
        if operation == .on, row >= 0, row < model.items.count {
            let item = model.items[row]
            if item.isParent { return model.location.deletingLastPathComponent() }
            if item.isDirectory && !item.isPackage { return item.url }
        }
        return model.location
    }

    private func dragOperation(_ info: any NSDraggingInfo, sources: [URL], target: URL) -> NSDragOperation {
        let mask = info.draggingSourceOperationMask
        if mask == .copy { return .copy }                 // Option held
        if mask == .generic || mask == .move { return .move } // Command held
        let sameVolume = sources.allSatisfy { Volumes.root(of: $0) == Volumes.root(of: target) }
        return sameVolume ? .move : .copy
    }

    private static func fileURLs(_ info: any NSDraggingInfo) -> [URL]? {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
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
