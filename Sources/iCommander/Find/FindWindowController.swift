import AppKit
import CommanderCore
import Quartz
import SwiftUI

/// Esc in a field of the form reaches the window as cancelOperation.
private final class FindWindow: NSWindow {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Results table: Find keys that are not menu-safe (Enter, Space, ⌫, Esc), files to the pasteboard.
final class FindTableView: NSTableView, NSMenuItemValidation {
    var onKey: ((NSEvent) -> Bool)?
    var onCopy: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    @objc func copy(_ sender: Any?) { onCopy?() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(copy(_:)) { return !selectedRowIndexes.isEmpty }
        return true
    }
}

/// ⌃⌥F7: a find window per search, independent of the main window. Results arrive
/// while the search runs and act like a panel (F3, F4, Quick Look, Trash, drag out).
final class FindWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation,
    NSTableViewDataSource, NSTableViewDelegate {
    private static var open: [FindWindowController] = []

    static func show(from main: MainWindowController) {
        let panel = main.activePanel
        let controller = FindWindowController(main: main, directory: panel.diskFolder, showHidden: panel.showsHidden)
        open.append(controller)
        controller.showWindow(nil)
    }

    private enum Column: String, CaseIterable {
        case name, path, size, date
        var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }
        var title: String {
            switch self {
            case .name: String(localized: "Name")
            case .path: String(localized: "Folder")
            case .size: String(localized: "Size")
            case .date: String(localized: "Modified")
            }
        }
    }

    private enum Outcome {
        case finished(TimeInterval), stopped, failed(String)
    }

    private weak var main: MainWindowController?
    private let form: FindForm
    private let table = FindTableView()
    private let statusField = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let problemsButton = NSButton(title: "", target: nil, action: nil)

    private var items: [FileItem] = []
    /// Duplicate group of each result (duplicate searches only).
    private var groups: [URL: Int] = [:]
    private var problems: [(path: String, message: String)] = []
    private var progress = SearchProgress(currentDirectory: "", directories: 0, files: 0, matches: 0)
    private var searchTask: Task<Void, Never>?
    private var outcome: Outcome?
    private let preview = FindPreview()

    private var isSearching: Bool { searchTask != nil }

    init(main: MainWindowController, directory: URL, showHidden: Bool) {
        self.main = main
        form = FindForm(directory: directory, showHidden: showHidden)
        let window = FindWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                backing: .buffered, defer: true)
        window.title = String(localized: "Find Files")
        window.minSize = NSSize(width: 720, height: 420)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.onCancel = { [weak self] in self?.perform(.findClose) }
        form.onFind = { [weak self] in self?.startSearch() }
        form.onStop = { [weak self] in self?.stopSearch() }
        form.onChooseFolder = { [weak self] in self?.chooseFolder() }
        buildContent(in: window)
        if let last = Self.open.last?.window {
            window.setFrame(last.frame, display: false)
            window.setFrameTopLeftPoint(window.cascadeTopLeft(from: NSPoint(x: last.frame.minX, y: last.frame.maxY)))
        } else if !window.setFrameUsingName("Find") {
            window.center()
        }
        window.setFrameAutosaveName("Find")
        // Quick Look looks for its controller along the responder chain.
        window.nextResponder = self
        updateStatus()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    private func buildContent(in window: NSWindow) {
        let formView = NSHostingView(rootView: FindFormView(form: form))
        formView.sizingOptions = [.intrinsicContentSize]

        for column in Column.allCases {
            let tc = NSTableColumn(identifier: column.identifier)
            tc.title = column.title
            tc.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            switch column {
            case .name: tc.width = 260
            case .path: tc.width = 360
            case .size:
                tc.width = 90
                tc.headerCell.alignment = .right
            case .date: tc.width = 140
            }
            table.addTableColumn(tc)
        }
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.onKey = { [weak self] in self?.handleKey($0) ?? false }
        table.onCopy = { [weak self] in self?.perform(.findCopyFiles) }
        table.menu = contextMenu()
        preview.table = table
        table.setDraggingSourceOperationMask([.copy, .move, .link], forLocal: false)
        table.autosaveName = "FindResults"
        table.autosaveTableColumns = true

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusField.lineBreakMode = .byTruncatingMiddle
        statusField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        problemsButton.bezelStyle = .accessoryBarAction
        problemsButton.controlSize = .small
        problemsButton.target = self
        problemsButton.action = #selector(showProblems)
        problemsButton.isHidden = true
        let status = NSStackView(views: [spinner, statusField, problemsButton])
        status.spacing = 6
        status.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)

        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [formView, separator, scroll, status])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        for view in [formView, separator, scroll, status] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        formView.setContentHuggingPriority(.required, for: .vertical)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        window.contentView = stack
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let commands: [Command?] = [.findOpen, .findShowInPanel, nil, .findView, .findEdit, .findQuickLook,
                                    .findProperties, nil, .findCopyFiles, .findCopyPaths, .findCopyNames,
                                    nil, .findRemove, .findTrash]
        for command in commands {
            guard let command else { menu.addItem(.separator()); continue }
            let spec = CommandRegistry.spec(command)
            let action = MainMenuBuilder.standardSelectors[command] ?? #selector(performCommand(_:))
            let item = NSMenuItem(title: spec.localizedTitle, action: action, keyEquivalent: "")
            item.representedObject = command.rawValue
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Search

    private func startSearch() {
        guard !isSearching, let window else { return }
        let criteria: SearchCriteria
        do {
            criteria = try form.criteria()
        } catch {
            if case .message(let text) = error { alert(text) }
            return
        }
        form.commit()
        let duplicates = form.duplicateCriteria
        items = []
        groups = [:]
        problems = []
        outcome = nil
        progress = SearchProgress(currentDirectory: "", directories: 0, files: 0, matches: 0)
        table.usesAlternatingRowBackgroundColors = duplicates == nil
        table.reloadData()
        window.title = Self.title(for: criteria)
        window.makeFirstResponder(table)
        let started = Date()
        let encoding = ViewerDefaults.encoding
        searchTask = Task { [weak self] in
            var found: [FileItem] = []
            do {
                for try await event in FileSearch.run(criteria, legacyEncoding: encoding) {
                    guard let self else { return }
                    switch event {
                    case .found(let batch):
                        if duplicates == nil { self.append(batch) } else { found += batch }
                    case .progress(let value):
                        self.progress = value
                        self.updateStatus()
                    case .problem(let path, let message):
                        self.problems.append((path, message))
                    }
                }
                if let duplicates, !Task.isCancelled {
                    self?.statusField.stringValue = String(localized: "Comparing \(found.count) files…")
                    let result = try await DuplicateFinder.groups(found, by: duplicates)
                    self?.show(groups: result)
                }
                self?.finish(Task.isCancelled ? .stopped : .finished(Date().timeIntervalSince(started)))
            } catch is CancellationError {
                self?.finish(.stopped)
            } catch {
                self?.finish(.failed(Self.describe(error)))
            }
        }
        form.isSearching = true
        updateStatus()
    }

    private func stopSearch() {
        searchTask?.cancel()
    }

    private func finish(_ result: Outcome) {
        searchTask = nil
        form.isSearching = false
        outcome = result
        if case .failed(let message) = result { alert(message) }
        sortItems()
        updateStatus()
    }

    private func append(_ batch: [FileItem]) {
        let wasEmpty = items.isEmpty
        items += batch
        table.noteNumberOfRowsChanged()
        if wasEmpty, !items.isEmpty, table.selectedRowIndexes.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    private func show(groups result: [[FileItem]]) {
        items = result.flatMap { $0 }
        groups = [:]
        for (index, group) in result.enumerated() {
            for item in group { groups[item.url] = index }
        }
        table.reloadData()
        if !items.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    private static func title(for criteria: SearchCriteria) -> String {
        let name = criteria.namePattern.isEmpty ? "*" : criteria.namePattern
        let place = criteria.roots.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: "; ")
        return String(localized: "Find “\(name)” in \(place)")
    }

    private static func describe(_ error: any Error) -> String {
        if let error = error as? SearchError {
            switch error {
            case .invalidPattern(let text): return String(localized: "Invalid search text: \(text)")
            default: break
            }
        }
        return error.localizedDescription
    }

    private func updateStatus() {
        spinner.isHidden = !isSearching
        if isSearching { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        let count = groups.isEmpty ? String(localized: "\(items.count) found")
                                   : String(localized: "\(Set(groups.values).count) groups, \(items.count) files")
        switch outcome {
        case nil where isSearching:
            let place = (progress.currentDirectory as NSString).abbreviatingWithTildeInPath
            statusField.stringValue = String(localized: "\(count) — searching \(place)")
        case nil:
            statusField.stringValue = String(localized: "Enter what to find and press Return.")
        case .finished(let seconds)?:
            let time = seconds.formatted(.number.precision(.fractionLength(1)))
            statusField.stringValue = String(localized: "\(count) in \(progress.files) files and \(progress.directories) folders (\(time) s)")
        case .stopped?:
            statusField.stringValue = String(localized: "\(count) — stopped")
        case .failed(let message)?:
            statusField.stringValue = message
        }
        problemsButton.isHidden = problems.isEmpty
        problemsButton.title = String(localized: "\(problems.count) not readable…")
    }

    @objc private func showProblems() {
        let lines = problems.prefix(200).map { "\(($0.path as NSString).abbreviatingWithTildeInPath): \($0.message)" }
        let more = problems.count > 200 ? "\n…" : ""
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 240))
        text.string = lines.joined(separator: "\n") + more
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let scroll = NSScrollView(frame: text.frame)
        scroll.documentView = text
        scroll.hasVerticalScroller = true
        let alert = NSAlert()
        alert.messageText = String(localized: "Items that could not be read")
        alert.accessoryView = scroll
        if let window { alert.beginSheetModal(for: window) }
    }

    private func alert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        if let window { alert.beginSheetModal(for: window) }
    }

    private func chooseFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Choose")
        if let first = SearchCriteria.parseRoots(form.lookIn).first {
            panel.directoryURL = URL(fileURLWithPath: first, isDirectory: true)
        }
        panel.beginSheetModal(for: window) { [form] response in
            guard response == .OK else { return }
            form.lookIn = panel.urls.map(\.displayPath).joined(separator: "; ")
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, let column = Column(rawValue: id.rawValue) else { return nil }
        let item = items[row]
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id, icon: column == .name)
        switch column {
        case .name:
            cell.textField?.stringValue = item.name
            cell.imageView?.image = IconCache.icon(for: item)
        case .path:
            cell.textField?.stringValue = (item.url.deletingLastPathComponent().displayPath as NSString).abbreviatingWithTildeInPath
        case .size:
            cell.textField?.stringValue = item.size.map(Format.grouped) ?? String(localized: "Folder")
            cell.textField?.alignment = .right
        case .date:
            cell.textField?.stringValue = item.modificationDate.map(Format.date) ?? ""
        }
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier, icon: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        var constraints = [
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ]
        if icon {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            constraints += [
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4),
            ]
        } else {
            constraints.append(text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }

    /// Duplicate groups alternate their background so each set reads as one block.
    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        guard let group = groups[items[row].url] else { return }
        rowView.backgroundColor = group.isMultiple(of: 2) ? .clear : NSColor.controlAccentColor.withAlphaComponent(0.1)
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        sortItems()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateQuickLook()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        items[row].url as NSURL
    }

    /// Sorts by the header; duplicate groups stay together and sort inside.
    private func sortItems() {
        guard !isSearching, let descriptor = table.sortDescriptors.first, let key = descriptor.key,
              let column = Column(rawValue: key) else { return }
        let selected = Set(table.selectedRowIndexes.map { items[$0].url })
        let ascending = descriptor.ascending
        func less(_ a: FileItem, _ b: FileItem) -> Bool {
            let order: ComparisonResult = switch column {
            case .name: a.name.localizedStandardCompare(b.name)
            case .path: a.url.deletingLastPathComponent().path.localizedStandardCompare(b.url.deletingLastPathComponent().path)
            case .size: compare(a.size ?? -1, b.size ?? -1)
            case .date: compare(a.modificationDate ?? .distantPast, b.modificationDate ?? .distantPast)
            }
            if order == .orderedSame { return a.url.path < b.url.path }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
        items.sort { a, b in
            let ga = groups[a.url] ?? 0, gb = groups[b.url] ?? 0
            return ga != gb ? ga < gb : less(a, b)
        }
        table.reloadData()
        let rows = IndexSet(items.indices.filter { selected.contains(items[$0].url) })
        table.selectRowIndexes(rows, byExtendingSelection: false)
    }

    private func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }

    @objc private func doubleClicked() {
        guard table.clickedRow >= 0 else { return }
        perform(.findOpen)
    }

    // MARK: Targets

    /// Selected results; the clicked row when the context menu opened outside the selection.
    private var targets: [FileItem] {
        let clicked = table.clickedRow
        if clicked >= 0, !table.selectedRowIndexes.contains(clicked) { return [items[clicked]] }
        return table.selectedRowIndexes.map { items[$0] }
    }

    private var cursorItem: FileItem? {
        let clicked = table.clickedRow
        if clicked >= 0 { return items[clicked] }
        let row = table.selectedRow
        return row >= 0 ? items[row] : nil
    }

    private var tableHasFocus: Bool { window?.firstResponder === table }

    // MARK: Commands

    @objc func performCommand(_ sender: Any?) {
        guard let command = (sender as? NSMenuItem)?.command else { return }
        perform(command)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord(event: event), !chord.isMenuSafe,
              let command = KeyMap.find.command(for: chord), CommandRegistry.spec(command).scope == .find,
              canPerform(command) else { return false }
        perform(command)
        return true
    }

    func canPerform(_ command: Command) -> Bool {
        switch command {
        case .findStart: return !isSearching
        case .findStop: return isSearching
        case .findClose: return true
        case .findToPanel: return !items.isEmpty && main != nil
        case .findOpen, .findShowInPanel, .findView, .findEdit, .findQuickLook, .findProperties,
             .findCopyFiles, .findCopyPaths, .findCopyNames, .findRemove:
            return !targets.isEmpty
        case .findTrash: return !targets.isEmpty && tableHasFocus
        case .findSelectAll: return !items.isEmpty
        default:
            return CommandRegistry.spec(command).scope == .app && ((NSApp.delegate as? AppDelegate)?.canPerform(command) ?? false)
        }
    }

    func perform(_ command: Command) {
        switch command {
        case .findStart: startSearch()
        case .findStop: stopSearch()
        case .findClose:
            if isSearching { stopSearch() } else { window?.performClose(nil) }
        case .findOpen: openTargets()
        case .findShowInPanel: if let item = cursorItem { showInPanel(item) }
        case .findView: view()
        case .findEdit:
            guard let item = cursorItem, !item.isDirectory || item.isPackage else { NSSound.beep(); return }
            Task { do { try await Launcher.edit(item.url) } catch { alert(OperationsController.describe(error)) } }
        case .findQuickLook: toggleQuickLook()
        case .findProperties: PropertiesSheet.show(targets.map(\.url), in: window)
        case .findTrash: Task { await trash() }
        case .findRemove: remove(targets)
        case .findCopyFiles:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(targets.map { $0.url as NSURL })
        case .findCopyPaths: copyText(targets.map(\.url.displayPath))
        case .findCopyNames: copyText(targets.map(\.name))
        case .findSelectAll: table.selectAll(nil)
        case .findToPanel: showResultsInPanel()
        default:
            if CommandRegistry.spec(command).scope == .app { (NSApp.delegate as? AppDelegate)?.perform(command) }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.command else { return true }
        return canPerform(command)
    }

    private func copyText(_ lines: [String]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines.joined(separator: "\n"), forType: .string)
    }

    /// Files open in their app; folders open in the active panel.
    private func openTargets() {
        let chosen = targets
        if chosen.count == 1, let item = chosen.first, item.isDirectory, !item.isPackage {
            guard let main else { return }
            main.activePanel.go(to: item.url)
            main.window?.makeKeyAndOrderFront(nil)
            return
        }
        for item in chosen { NSWorkspace.shared.open(item.url) }
    }

    /// The active panel goes to the item's folder with the cursor on it.
    /// The active panel lists every result like a folder; Back returns.
    private func showResultsInPanel() {
        guard let main else { return }
        let query = [form.name, form.containing].filter { !$0.isEmpty }.joined(separator: " · ")
        let title = query.isEmpty ? String(localized: "Find Results") : String(localized: "Find Results: \(query)")
        let listing = ResultsListing(title: title, urls: items.map(\.url))
        main.activePanel.showResults(listing, focusing: cursorItem.map { listing.relativeName(of: $0.url) })
        main.window?.makeKeyAndOrderFront(nil)
    }

    private func showInPanel(_ item: FileItem) {
        guard let main else { return }
        main.activePanel.go(to: item.url.deletingLastPathComponent(), focusing: item.name)
        main.window?.makeKeyAndOrderFront(nil)
    }

    /// F3: the viewer walks through the found files; media goes to Quick Look.
    private func view() {
        guard let item = cursorItem else { return }
        if item.isDirectory || ViewerDefaults.prefersQuickLook(item.url) {
            toggleQuickLook()
            return
        }
        let selected = Set(table.selectedRowIndexes.count > 1 ? table.selectedRowIndexes.map { items[$0].url } : [])
        let entries = items.filter { !$0.isDirectory }.map { FileSequence.Entry(url: $0.url, isSelected: selected.contains($0.url)) }
        guard let sequence = FileSequence(entries: entries, current: item.url) else { return }
        ViewerWindowController.show(sequence)
    }

    private func remove(_ removed: [FileItem]) {
        let urls = Set(removed.map(\.url))
        guard !urls.isEmpty else { return }
        let first = table.selectedRowIndexes.first ?? 0
        items.removeAll { urls.contains($0.url) }
        for url in urls { groups[url] = nil }
        table.reloadData()
        if !items.isEmpty { table.selectRowIndexes([min(first, items.count - 1)], byExtendingSelection: false) }
        updateStatus()
    }

    /// F8: to the Trash after confirmation; trashed items leave the list.
    private func trash() async {
        let chosen = targets
        guard let window, !chosen.isEmpty else { return }
        let names = chosen.count == 1 ? "“\(chosen[0].name)”" : String(localized: "\(chosen.count) items")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Move \(names) to the Trash?")
        alert.informativeText = String(localized: "You can put them back from the Trash.")
        alert.addButton(withTitle: String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
        do {
            _ = try await FileOperations().trash(chosen.map(\.url))
            remove(chosen)
        } catch {
            self.alert(OperationsController.describe(error))
        }
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        searchTask?.cancel()
        if isQuickLooking { QLPreviewPanel.shared()?.orderOut(nil) }
        Self.open.removeAll { $0 === self }
    }
}

// MARK: Quick Look

extension FindWindowController {
    private var isQuickLooking: Bool {
        guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible else { return false }
        return (panel.currentController as AnyObject?) === self
    }

    fileprivate func toggleQuickLook() {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
            return
        }
        preview.urls = targets.map(\.url)
        guard !preview.urls.isEmpty else { NSSound.beep(); return }
        QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
    }

    fileprivate func updateQuickLook() {
        guard isQuickLooking else { return }
        let urls = targets.map(\.url)
        guard urls != preview.urls else { return }
        preview.urls = urls
        QLPreviewPanel.shared()?.reloadData()
    }

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = preview
            panel.delegate = preview
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

/// Quick Look data for the find window (a separate object: the window controller is
/// already the window's delegate). Arrows move in the results and the preview follows;
/// Esc, F3 and ⌘Y close it.
private final class FindPreview: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    var urls: [URL] = []
    weak var table: NSTableView?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        urls[index] as NSURL
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        if let chord = KeyChord(event: event) {
            let command = KeyMap.find.command(for: chord)
            if chord.key == .escape || command == .findView || command == .findQuickLook {
                panel.orderOut(nil)
                return true
            }
        }
        table?.keyDown(with: event)
        return true
    }
}
