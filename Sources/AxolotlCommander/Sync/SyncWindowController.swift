// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Synchronize Folders (spec 023): compares two folder trees and lists what differs, with the
/// action for each item; the user changes the actions, then one confirmed run copies (and, when
/// asked for, moves to the Trash). Nothing on disk changes before that confirmation.
@MainActor
final class SyncWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
    /// One window per main window.
    private static var open: [ObjectIdentifier: SyncWindowController] = [:]

    /// ⌥⇧F10: brings this main window's sync window to the front, or asks for the options and compares.
    static func start(from main: MainWindowController) {
        if let existing = open[ObjectIdentifier(main)] {
            existing.showWindow(nil)
            return
        }
        guard let window = main.window else { return }
        let left = main.left.model.location, right = main.right.model.location
        SyncSheet.show(in: window, left: left, right: right) {
            if let refusal = SyncGuard.check(left: left, right: right) {
                let alert = NSAlert()
                switch refusal {
                case .same:
                    alert.messageText = String(localized: "Both panels show the same folder")
                    alert.informativeText = String(localized: "There is nothing to synchronize.")
                case .nested:
                    alert.messageText = String(localized: "One folder is inside the other")
                    alert.informativeText = String(localized: "Folders inside each other cannot be synchronized: copying would go on into the copy.")
                }
                alert.beginSheetModal(for: window)
                return
            }
            let controller = SyncWindowController(left: left, right: right, main: main)
            open[ObjectIdentifier(main)] = controller
            controller.showWindow(nil)
            controller.window?.makeFirstResponder(controller.table)
            controller.compare()
        }
    }

    private enum Column: String, CaseIterable {
        case name, leftSize, leftDate, action, rightSize, rightDate
    }

    private let left: URL
    private let right: URL
    private weak var main: MainWindowController?
    private let mainID: ObjectIdentifier
    private var comparison: SyncComparison?
    /// Indices into `comparison.items` that the filters show.
    private var rows: [Int] = []
    private var showEqual = false, showDifferent = true, showLeftOnly = true, showRightOnly = true
    private var compareTask: Task<Void, Never>?
    private var isRunning = false
    /// The rows selected before comparing again, selected again afterwards.
    private var keptSelection: Set<String> = []

    private let table = SyncTableView()
    private let headerField = NSTextField(wrappingLabelWithString: "")
    private let optionsField = NSTextField(labelWithString: "")
    private let summaryField = NSTextField(labelWithString: "")
    private let statusField = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let stopButton = NSButton()
    private let againButton = NSButton()
    private let syncButton = NSButton()
    private var filterButtons: [NSButton] = []

    /// Comparing reads both folders (spec 022: an eject waits for it). The run is an operation of
    /// the main window and is listed there.
    var volumeUser: VolumeUser? {
        compareTask == nil ? nil : VolumeUser(title: String(localized: "Synchronize Folders"), urls: [left, right])
    }

    private init(left: URL, right: URL, main: MainWindowController) {
        self.left = left
        self.right = right
        self.main = main
        mainID = ObjectIdentifier(main)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Synchronize – \(Self.short(left)) ↔ \(Self.short(right))")
        window.minSize = NSSize(width: 640, height: 360)
        window.setFrameAutosaveName("SyncFolders")
        super.init(window: window)
        window.delegate = self
        build()
        if !window.setFrameUsingName("SyncFolders") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func short(_ url: URL) -> String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    // MARK: Layout

    private func build() {
        headerField.stringValue = String(localized: "Left: \(left.displayPath)") + "\n" + String(localized: "Right: \(right.displayPath)")
        headerField.lineBreakMode = .byTruncatingMiddle
        headerField.font = .systemFont(ofSize: NSFont.systemFontSize)
        optionsField.textColor = .secondaryLabelColor
        optionsField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        optionsField.lineBreakMode = .byTruncatingTail

        let filters: [(String, Bool, Selector)] = [
            (String(localized: "Equal"), showEqual, #selector(toggleEqual(_:))),
            (String(localized: "Different"), showDifferent, #selector(toggleDifferent(_:))),
            (String(localized: "Left Only"), showLeftOnly, #selector(toggleLeftOnly(_:))),
            (String(localized: "Right Only"), showRightOnly, #selector(toggleRightOnly(_:))),
        ]
        filterButtons = filters.map { title, on, action in
            let button = NSButton(checkboxWithTitle: title, target: self, action: action)
            button.state = on ? .on : .off
            button.refusesFirstResponder = true
            return button
        }
        let filterLabel = NSTextField(labelWithString: String(localized: "Show:"))
        filterLabel.textColor = .secondaryLabelColor
        let filterRow = NSStackView(views: [filterLabel] + filterButtons)
        filterRow.spacing = 12

        for column in Column.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            switch column {
            case .name:
                tableColumn.title = String(localized: "Name")
                tableColumn.width = 360
                tableColumn.minWidth = 160
            case .leftSize, .rightSize:
                tableColumn.title = String(localized: "Size")
                tableColumn.width = 80
                tableColumn.minWidth = 50
            case .leftDate, .rightDate:
                tableColumn.title = String(localized: "Modified")
                tableColumn.width = 130
                tableColumn.minWidth = 70
            case .action:
                tableColumn.title = ""
                tableColumn.width = 36
                tableColumn.minWidth = 36
                tableColumn.maxWidth = 36
            }
            table.addTableColumn(tableColumn)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .fullWidth
        table.rowHeight = 20
        table.target = self
        table.action = #selector(clicked)
        table.doubleAction = #selector(compareFiles)
        table.owner = self
        let menu = NSMenu()
        menu.delegate = self
        table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusField.textColor = .secondaryLabelColor
        statusField.lineBreakMode = .byTruncatingMiddle
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stopButton.title = String(localized: "Stop")
        stopButton.bezelStyle = .push
        stopButton.target = self
        stopButton.action = #selector(stop)
        againButton.title = String(localized: "Compare Again")
        againButton.bezelStyle = .push
        againButton.target = self
        againButton.action = #selector(compareAgain)
        againButton.toolTip = "⌘R"
        syncButton.title = String(localized: "Synchronize…")
        syncButton.bezelStyle = .push
        syncButton.target = self
        syncButton.action = #selector(synchronize)
        syncButton.keyEquivalent = "\r"
        summaryField.lineBreakMode = .byTruncatingTail
        summaryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let status = NSStackView(views: [spinner, statusField, stopButton])
        status.spacing = 8
        let bottom = NSStackView(views: [summaryField, NSView(), againButton, syncButton])
        bottom.spacing = 8
        let stack = NSStackView(views: [headerField, optionsField, filterRow, scroll, status, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            headerField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            optionsField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        window?.contentView = content
        showStatus(nil)
    }

    private func describe(_ options: SyncOptions) -> String {
        var parts: [String] = []
        parts.append(options.includeSubfolders ? String(localized: "with subfolders") : String(localized: "this level only"))
        var by: [String] = []
        if options.compareDate { by.append(String(localized: "date")) }
        if options.compareSize { by.append(String(localized: "size")) }
        if options.compareContent { by.append(String(localized: "content")) }
        if !by.isEmpty { parts.append(String(localized: "by \(by.formatted(.list(type: .and)))")) }
        switch options.direction {
        case .bothWays: parts.append(String(localized: "both ways"))
        case .leftToRight: parts.append(String(localized: "left to right"))
        case .rightToLeft: parts.append(String(localized: "right to left"))
        }
        if options.deletionSide != nil { parts.append(String(localized: "deleting extra items")) }
        return parts.joined(separator: " · ")
    }

    /// While comparing: the spinner, the progress text and Stop; otherwise only a message, if any.
    private func showStatus(_ text: String?, busy: Bool = false) {
        statusField.stringValue = text ?? ""
        statusField.isHidden = text == nil
        stopButton.isHidden = !busy
        if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        againButton.isEnabled = !busy
        syncButton.isEnabled = !busy && !(comparison.map { SyncPlan($0).isEmpty } ?? true)
        for button in filterButtons { button.isEnabled = !busy }
    }

    // MARK: Comparing

    private func compare() {
        compareTask?.cancel()
        let options = AppSettings.shared.sync
        let includeHidden = main?.activePanel.showsHidden ?? false
        optionsField.stringValue = describe(options)
        if let comparison { keptSelection = Set(selectedItems.map { comparison.items[$0].path }) }
        comparison = nil
        rows = []
        table.reloadData()
        summaryField.stringValue = ""
        showStatus(String(localized: "Comparing…"), busy: true)
        let (left, right) = (self.left, self.right)
        compareTask = Task { [weak self] in
            do {
                let result = try await SyncScanner.compare(left: left, right: right, options: options, includeHidden: includeHidden) { progress in
                    Task { @MainActor in self?.showProgress(progress) }
                }
                guard let self, !Task.isCancelled else { return }
                self.compareTask = nil
                self.show(result)
            } catch {
                guard let self else { return }
                self.compareTask = nil
                if error is CancellationError || Task.isCancelled {
                    self.showStatus(String(localized: "Comparing was stopped."))
                } else {
                    self.showStatus(Format.error(error))
                }
            }
        }
    }

    private func showProgress(_ progress: SyncProgress) {
        guard compareTask != nil else { return }
        let count = Format.grouped(Int64(progress.scanned))
        let folder = progress.folder.isEmpty ? "/" : progress.folder
        showStatus(String(localized: "Comparing… \(count) items – \(folder)"), busy: true)
    }

    private func show(_ result: SyncComparison) {
        comparison = result
        applyFilters()
        let reselect = IndexSet(rows.indices.filter { keptSelection.contains(result.items[rows[$0]].path) })
        keptSelection = []
        table.selectRowIndexes(reselect.isEmpty && !rows.isEmpty ? [0] : reselect, byExtendingSelection: false)
        let differences = result.items.contains { $0.state != .equal }
        showStatus(differences ? nil : String(localized: "The folders are in sync."))
        updateSummary()
    }

    @objc private func stop() { compareTask?.cancel() }

    @objc private func compareAgain() {
        guard !isRunning else { return NSSound.beep() }
        compare()
    }

    // MARK: Filters and summary

    @objc private func toggleEqual(_ sender: NSButton) { showEqual = sender.state == .on; refilter() }
    @objc private func toggleDifferent(_ sender: NSButton) { showDifferent = sender.state == .on; refilter() }
    @objc private func toggleLeftOnly(_ sender: NSButton) { showLeftOnly = sender.state == .on; refilter() }
    @objc private func toggleRightOnly(_ sender: NSButton) { showRightOnly = sender.state == .on; refilter() }

    private func refilter() {
        let selected = Set(selectedItems)
        applyFilters()
        table.selectRowIndexes(IndexSet(rows.indices.filter { selected.contains(rows[$0]) }), byExtendingSelection: false)
    }

    private func applyFilters() {
        guard let comparison else { rows = []; table.reloadData(); return }
        rows = comparison.items.indices.filter { index in
            switch comparison.items[index].state {
            case .equal: showEqual
            case .onlyLeft: showLeftOnly
            case .onlyRight: showRightOnly
            case .leftNewer, .rightNewer, .different, .error: showDifferent
            }
        }
        table.reloadData()
    }

    private func updateSummary() {
        guard let comparison else { summaryField.stringValue = ""; return }
        let plan = SyncPlan(comparison)
        summaryField.stringValue = plan.summary
        syncButton.isEnabled = compareTask == nil && !isRunning && !plan.isEmpty
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let comparison, let id = tableColumn?.identifier, let column = Column(rawValue: id.rawValue) else { return nil }
        let item = comparison.items[rows[row]]
        let reuse = NSUserInterfaceItemIdentifier("sync." + column.rawValue)
        let cell = tableView.makeView(withIdentifier: reuse, owner: nil) as? NSTableCellView ?? makeCell(reuse, column)
        let text = cell.textField
        text?.textColor = item.excluded ? .tertiaryLabelColor : .labelColor
        switch column {
        case .name:
            cell.imageView?.image = icon(item)
            let parent = (item.path as NSString).deletingLastPathComponent
            let shown = NSMutableAttributedString()
            if !parent.isEmpty {
                shown.append(NSAttributedString(string: parent + "/", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
            }
            shown.append(NSAttributedString(string: item.name, attributes: [.foregroundColor: item.excluded ? NSColor.tertiaryLabelColor : NSColor.labelColor]))
            text?.attributedStringValue = shown
            if case .error(let reason) = item.state { text?.toolTip = reason } else { text?.toolTip = item.path }
        case .leftSize: text?.stringValue = sizeText(item.left)
        case .rightSize: text?.stringValue = sizeText(item.right)
        case .leftDate: text?.stringValue = item.left?.modified.map(Format.date) ?? ""
        case .rightDate: text?.stringValue = item.right?.modified.map(Format.date) ?? ""
        case .action:
            let (symbol, color, tip) = actionLook(item)
            text?.stringValue = symbol
            text?.textColor = color
            text?.toolTip = tip
        }
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier, _ column: Column) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = column == .name ? .byTruncatingMiddle : .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        var constraints = [text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                           text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2)]
        switch column {
        case .name:
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            constraints += [image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                            image.widthAnchor.constraint(equalToConstant: 16),
                            image.heightAnchor.constraint(equalToConstant: 16),
                            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 4)]
        case .action:
            text.alignment = .center
            text.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
            constraints.append(text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
        case .leftSize, .rightSize:
            text.alignment = .right
            text.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            constraints.append(text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
        case .leftDate, .rightDate:
            text.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            constraints.append(text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4))
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }

    private func icon(_ item: SyncItem) -> NSImage? {
        if case .error = item.state { return NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) }
        let side = item.left ?? item.right
        let name = switch side?.kind {
        case .folder?: "folder"
        case .link?: "arrow.turn.up.right"
        default: "doc"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func sizeText(_ side: SyncSide?) -> String {
        guard let side else { return "" }
        switch side.kind {
        case .file: return Format.bytes(side.size)
        case .folder: return side.fileCount > 0 || side.size > 0 ? Format.bytes(side.size) : ""
        case .link: return ""
        }
    }

    /// The symbol in the action column, its color and a tooltip that says it in words.
    private func actionLook(_ item: SyncItem) -> (String, NSColor, String) {
        if item.excluded { return ("–", .tertiaryLabelColor, String(localized: "Excluded")) }
        let (effect, target) = SyncRules.effect(of: item)
        let toRight = target == .right
        switch effect {
        case .copy, .overwrite:
            return (toRight ? "→" : "←", .controlAccentColor,
                    toRight ? String(localized: "Copy to the right") : String(localized: "Copy to the left"))
        case .replace:
            return (toRight ? "→" : "←", .systemOrange,
                    toRight ? String(localized: "Replace the item on the right (it goes to the Trash)")
                        : String(localized: "Replace the item on the left (it goes to the Trash)"))
        case .delete:
            return ("✕", .systemRed,
                    toRight ? String(localized: "Move to the Trash on the right") : String(localized: "Move to the Trash on the left"))
        case .nothing:
            switch item.state {
            case .equal: return ("=", .secondaryLabelColor, String(localized: "Equal"))
            case .onlyLeft, .onlyRight: return ("", .secondaryLabelColor, String(localized: "Nothing to do"))
            case .error(let reason): return ("!", .systemRed, reason)
            case .leftNewer, .rightNewer, .different: return ("≠", .systemOrange, String(localized: "Differs; choose a direction with ← or →"))
            }
        }
    }

    // MARK: Changing actions

    /// The comparison indices of the selected rows.
    private var selectedItems: [Int] {
        table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
    }

    fileprivate func setAction(_ action: SyncAction) {
        guard var comparison, !isRunning, !selectedItems.isEmpty else { return NSSound.beep() }
        let refused = SyncRules.set(action, at: selectedItems, in: &comparison.items, options: comparison.options)
        self.comparison = comparison
        if !refused.isEmpty { NSSound.beep() }
        reloadSelection()
    }

    fileprivate func toggleExcluded() {
        guard var comparison, !isRunning, !selectedItems.isEmpty else { return NSSound.beep() }
        SyncRules.toggleExcluded(at: selectedItems, in: &comparison.items)
        self.comparison = comparison
        reloadSelection()
    }

    private func reloadSelection() {
        table.reloadData(forRowIndexes: table.selectedRowIndexes, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        updateSummary()
    }

    /// A click on the action cell moves to the next action possible for that row.
    @objc private func clicked() {
        let row = table.clickedRow, column = table.clickedColumn
        guard row >= 0, column >= 0, table.tableColumns[column].identifier.rawValue == Column.action.rawValue,
              var comparison, !isRunning else { return }
        let index = rows[row]
        let item = comparison.items[index]
        let possible = SyncRules.possible(item, options: comparison.options)
        guard possible.count > 1 else { return NSSound.beep() }
        if item.excluded { SyncRules.toggleExcluded(at: [index], in: &comparison.items) }
        let next = possible[((possible.firstIndex(of: item.action) ?? -1) + 1) % possible.count]
        SyncRules.set(next, at: [index], in: &comparison.items, options: comparison.options)
        self.comparison = comparison
        table.reloadData(forRowIndexes: [row], columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        updateSummary()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clicked = table.clickedRow
        if clicked >= 0, !table.selectedRowIndexes.contains(clicked) {
            table.selectRowIndexes([clicked], byExtendingSelection: false)
        }
        guard let comparison, !selectedItems.isEmpty, !isRunning else { return }
        let items = selectedItems.map { comparison.items[$0] }
        func add(_ title: String, _ action: Selector, enabled: Bool) {
            let item = menu.addItem(withTitle: title, action: enabled ? action : nil, keyEquivalent: "")
            item.target = self
        }
        let possible = items.map { Set(SyncRules.possible($0, options: comparison.options)) }
        add(String(localized: "Copy to the Right"), #selector(menuToRight), enabled: possible.contains { $0.contains(.toRight) })
        add(String(localized: "Copy to the Left"), #selector(menuToLeft), enabled: possible.contains { $0.contains(.toLeft) })
        add(String(localized: "Do Nothing"), #selector(menuNone), enabled: true)
        add(items.allSatisfy(\.excluded) ? String(localized: "Include") : String(localized: "Exclude"), #selector(menuExclude), enabled: true)
        menu.addItem(.separator())
        add(String(localized: "Compare Files"), #selector(compareFiles), enabled: items.count == 1 && isFilePair(items[0]))
    }

    @objc private func menuToRight() { setAction(.toRight) }
    @objc private func menuToLeft() { setAction(.toLeft) }
    @objc private func menuNone() { setAction(.none) }
    @objc private func menuExclude() { toggleExcluded() }

    private func isFilePair(_ item: SyncItem) -> Bool {
        item.left?.kind == .file && item.right?.kind == .file
    }

    /// F3: the two files of the row side by side.
    @objc fileprivate func compareFiles() {
        guard let comparison, selectedItems.count == 1 else { return NSSound.beep() }
        let item = comparison.items[selectedItems[0]]
        guard isFilePair(item) else { return NSSound.beep() }
        let leftURL = comparison.url(of: item, on: .left), rightURL = comparison.url(of: item, on: .right)
        CompareWindowController.show(left: leftURL, right: rightURL,
                                     leftTitle: leftURL.displayPath, rightTitle: rightURL.displayPath)
    }

    // MARK: Running

    @objc fileprivate func synchronize() {
        guard let comparison, compareTask == nil, !isRunning, let window else { return NSSound.beep() }
        let plan = SyncPlan(comparison)
        guard !plan.isEmpty else { return NSSound.beep() }
        guard let main else { return NSSound.beep() }
        let alert = NSAlert()
        alert.messageText = String(localized: "Synchronize the folders?")
        alert.informativeText = Self.confirmation(plan)
        if plan.deletionCount > 0 { alert.alertStyle = .warning }
        alert.addButton(withTitle: String(localized: "Synchronize"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.run(plan, comparison, main: main) }
        }
    }

    /// What will be copied, and the items going to the Trash on a line of their own.
    private static func confirmation(_ plan: SyncPlan) -> String {
        var lines: [String] = []
        if let copy = plan.copyLine { lines.append(copy) }
        if let trash = plan.trashLine { lines += ["", trash] }
        lines += ["", String(localized: "Items that change before they are copied are skipped.")]
        return lines.joined(separator: "\n")
    }

    private func run(_ plan: SyncPlan, _ comparison: SyncComparison, main: MainWindowController) {
        isRunning = true
        showStatus(nil)
        let state = OperationState(title: String(localized: "Synchronizing Folders"), urls: [left, right])
        let operations = main.operations.operations
        main.operations.perform(state, in: window) { [weak self] in
            do {
                let report = try await SyncRunner.run(plan, of: comparison, operations: operations) { progress in
                    Task { @MainActor in state.progress = progress }
                }
                await self?.finish(report)
            } catch {
                await self?.finish(nil)
                throw error
            }
        }
    }

    private func finish(_ report: SyncRunReport?) async {
        isRunning = false
        compare()
        guard let report, !report.problems.isEmpty, let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Some items were not synchronized")
        let shown = report.problems.prefix(20).map { problem in
            let reason = switch problem.reason {
            case .changed: String(localized: "changed since comparing")
            case .noTrash: String(localized: "the volume has no Trash, so it was not deleted")
            case .failed(let message): message
            }
            return "\(problem.path): \(reason)"
        }
        var text = shown.joined(separator: "\n")
        if report.problems.count > shown.count {
            text += "\n" + String(localized: "and \(report.problems.count - shown.count) more")
        }
        alert.informativeText = text
        await alert.beginSheetModal(for: window)
    }

    // MARK: Window

    /// Esc stops comparing, otherwise closes the window.
    @objc fileprivate func cancel() {
        if compareTask != nil { stop() } else if !isRunning { window?.performClose(nil) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { !isRunning }

    func windowWillClose(_ notification: Notification) {
        compareTask?.cancel()
        compareTask = nil
        Self.open[mainID] = nil
    }

    fileprivate func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers == "r" {
            compareAgain()
            return true
        }
        return false
    }
}

/// The result list: keys change the actions of the selected rows (spec 023 FR-014).
@MainActor
final class SyncTableView: NSTableView {
    fileprivate weak var owner: SyncWindowController?

    override func keyDown(with event: NSEvent) {
        guard let owner else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        guard flags.isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 49: owner.toggleExcluded()                 // Space
        case 123: owner.setAction(.toLeft)              // ←
        case 124: owner.setAction(.toRight)             // →
        case 51, 117: owner.setAction(.none)            // Delete, forward delete: only clears the action
        case 99: owner.compareFiles()                   // F3
        case 36, 76: owner.synchronize()                // Return, Enter
        default:
            if event.charactersIgnoringModifiers == "=" { owner.setAction(.none) } else { super.keyDown(with: event) }
        }
    }

    override func cancelOperation(_ sender: Any?) { owner?.cancel() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        owner?.handleKeyEquivalent(event) == true || super.performKeyEquivalent(with: event)
    }
}
