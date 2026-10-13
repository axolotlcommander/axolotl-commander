// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// A sheet with a search field over a list (Folder History, Command Line History). Typing filters
/// the list (`HistoryFilter`); the arrows, Page Up/Down, Home and End move the selection while the
/// field keeps the focus; Return chooses, ⌘Return and ⌥Return choose another way; Esc closes.
@MainActor
final class HistoryListSheet: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    struct Row {
        var text: String
        var symbol: String
        var isCurrent = false
    }

    /// How the entry was chosen: Return, ⌘Return or ⌥Return.
    enum Choice { case plain, command, option }

    private let rows: [Row]
    private var shown: [Int]
    private let onChoose: (Int, Choice) -> Void
    private let allowsModifiers: Bool
    private let sheet: KeyPanel
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    /// The sheet that is open; it keeps itself alive until it ends.
    private static var open: HistoryListSheet?

    /// Shows the sheet on `window`; `onChoose` gets the index into `rows`.
    static func present(on window: NSWindow, title: String, rows: [Row], selection: Int?, hint: String,
                        chooseTitle: String = String(localized: "Open"), allowsModifiers: Bool,
                        onChoose: @escaping (Int, Choice) -> Void) {
        guard open == nil, window.attachedSheet == nil else { NSSound.beep(); return }
        let list = HistoryListSheet(title: title, rows: rows, hint: hint, chooseTitle: chooseTitle,
                                    allowsModifiers: allowsModifiers, onChoose: onChoose)
        open = list
        list.select(selection ?? 0)
        window.beginSheet(list.sheet) { _ in open = nil }
        list.sheet.makeFirstResponder(list.searchField)
    }

    private init(title: String, rows: [Row], hint: String, chooseTitle: String, allowsModifiers: Bool,
                 onChoose: @escaping (Int, Choice) -> Void) {
        self.rows = rows
        self.shown = Array(rows.indices)
        self.onChoose = onChoose
        self.allowsModifiers = allowsModifiers
        sheet = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 400),
                         styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        super.init()
        sheet.title = title
        sheet.minSize = NSSize(width: 380, height: 240)
        sheet.onKey = { [weak self] in self?.handleKey($0) ?? false }

        let heading = NSTextField(labelWithString: title)
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        searchField.placeholderString = String(localized: "Filter")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("text"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
        tableView.refusesFirstResponder = true
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let hintLabel = NSTextField(wrappingLabelWithString: hint)
        hintLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hintLabel.textColor = .secondaryLabelColor
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let openButton = NSButton(title: chooseTitle, target: self, action: #selector(openClicked))
        openButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [hintLabel, cancel, openButton])
        buttons.orientation = .horizontal
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [heading, searchField, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        sheet.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case 36, 76: // Return, keypad Enter
            switch mods {
            case []: choose(.plain)
            case .command where allowsModifiers: choose(.command)
            case .option where allowsModifiers: choose(.option)
            default: NSSound.beep()
            }
            return true
        case 53 where mods.isEmpty: // Esc
            cancel()
            return true
        case 126 where mods.isEmpty: move(by: -1); return true
        case 125 where mods.isEmpty: move(by: 1); return true
        case 116 where mods.isEmpty: move(by: -page); return true
        case 121 where mods.isEmpty: move(by: page); return true
        case 115 where mods.isEmpty: select(0); return true
        case 119 where mods.isEmpty: select(shown.count - 1); return true
        default: return false
        }
    }

    private var page: Int { max(1, Int(tableView.visibleRect.height / tableView.rowHeight) - 1) }

    private func move(by delta: Int) {
        guard !shown.isEmpty else { NSSound.beep(); return }
        select(min(max(tableView.selectedRow + delta, 0), shown.count - 1))
    }

    private func select(_ row: Int) {
        guard shown.indices.contains(row) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func choose(_ choice: Choice) {
        let row = tableView.selectedRow
        guard shown.indices.contains(row) else { NSSound.beep(); return }
        let index = shown[row]
        end()
        onChoose(index, choice)
    }

    @objc private func doubleClicked() {
        guard tableView.clickedRow >= 0 else { return }
        select(tableView.clickedRow)
        choose(.plain)
    }

    @objc private func openClicked() { choose(.plain) }
    @objc private func cancel() { end() }

    private func end() {
        sheet.sheetParent?.endSheet(sheet)
    }

    // MARK: Filtering

    func controlTextDidChange(_ obj: Notification) {
        let query = searchField.stringValue
        shown = rows.indices.filter { HistoryFilter.matches(rows[$0].text, query: query) }
        tableView.reloadData()
        select(0)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("HistoryCell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
        let entry = rows[shown[row]]
        cell.textField?.stringValue = entry.text
        cell.textField?.font = entry.isCurrent ? .boldSystemFont(ofSize: NSFont.systemFontSize)
                                               : .systemFont(ofSize: NSFont.systemFontSize)
        cell.textField?.toolTip = entry.text
        cell.imageView?.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        for view in [image, text] {
            view.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(view)
        }
        cell.imageView = image
        cell.textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// A panel that offers its key presses to a handler before the field editor sees them.
private final class KeyPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}
