// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The F5/F6 target dialog (spec 021): "To:" with a destination menu (the button, ⌥↓; ⌃D for the hot
/// paths). For one item "To:" also holds its name, and F5 / F6 again move the selection through the
/// name, the extension, the folder and the whole text; several items keep the name mask.
@MainActor
final class TransferDialog: NSObject {
    struct Result {
        var text: String
        var mask: String
    }

    /// The item when the dialog works on one.
    struct Single {
        var name: String
        var isDirectory: Bool
    }

    private let sheet = KeySheetWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 160),
                                       styleMask: [.titled], backing: .buffered, defer: true)
    private let field = NSTextField()
    private let maskField = NSTextField(string: "*.*")
    private lazy var menuButton = DestinationMenuPopup.button(target: self, action: #selector(showDestinations))
    private lazy var popup = DestinationMenuPopup { [weak self] folder in self?.choose(folder: folder) }
    private let single: Single?
    /// F5 for copy, F6 for move: the key that opened the dialog.
    private let cycleKey: UInt16
    private let entries: () -> [DestinationMenu.Entry]
    private var part: TransferTarget.Part = .name
    private var continuation: CheckedContinuation<Result?, Never>?

    private init(title: String, text: String, single: Single?, cycleKey: UInt16,
                 entries: @escaping () -> [DestinationMenu.Entry]) {
        self.single = single
        self.cycleKey = cycleKey
        self.entries = entries
        super.init()
        field.stringValue = text
        build(title: title)
        sheet.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    }

    static func run(title: String, text: String, single: Single?, cycleKey: UInt16,
                    entries: @escaping () -> [DestinationMenu.Entry], in window: NSWindow) async -> Result? {
        let dialog = TransferDialog(title: title, text: text, single: single, cycleKey: cycleKey, entries: entries)
        return await withCheckedContinuation { continuation in
            dialog.continuation = continuation
            dialog.sheet.owner = dialog
            window.beginSheet(dialog.sheet, completionHandler: nil)
            // The field editor exists once the sheet is key.
            DispatchQueue.main.async { dialog.select(dialog.single == nil ? .all : .name) }
        }
    }

    // MARK: Layout

    private func build(title: String) {
        let heading = NSTextField(labelWithString: title)
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        heading.lineBreakMode = .byTruncatingMiddle
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        let toRow = NSStackView(views: [field, menuButton])
        toRow.spacing = 6
        var grid: [[NSView]] = [[Self.label(String(localized: "To:")), toRow]]
        if single == nil { grid.append([Self.label(String(localized: "Name mask:")), maskField]) }
        let form = NSGridView(views: grid)
        form.column(at: 0).xPlacement = .trailing
        form.rowSpacing = 8
        form.columnSpacing = 8
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: String(localized: "OK"), target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, ok])
        buttons.spacing = 8
        let stack = NSStackView(views: [heading, form, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 560),
            field.widthAnchor.constraint(equalToConstant: 420),
            heading.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        // The mask field is in the window only for several items.
        if single == nil { maskField.widthAnchor.constraint(equalTo: field.widthAnchor).isActive = true }
        sheet.contentView = content
        sheet.setContentSize(content.fittingSize)
    }

    private static func label(_ text: String) -> NSTextField {
        NSTextField(labelWithString: text)
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch (event.keyCode, flags) {
        case (cycleKey, []) where single != nil:
            select(TransferTarget.next(after: part, in: field.stringValue, isDirectory: single!.isDirectory))
            return true
        case (125, .option):  // ⌥↓
            showDestinations()
            return true
        case (2, .control):  // ⌃D
            showMenu(entries().filter { $0.section == .hotPaths })
            return true
        default:
            return false
        }
    }

    private func select(_ part: TransferTarget.Part) {
        self.part = part
        let text = field.stringValue
        let range = single.flatMap { TransferTarget.range(of: part, in: text, isDirectory: $0.isDirectory) }
            ?? NSRange(location: 0, length: (text as NSString).length)
        if sheet.firstResponder !== field.currentEditor() { sheet.makeFirstResponder(field) }
        guard let editor = field.currentEditor() as? NSTextView else { return }
        editor.selectedRange = range
        editor.scrollRangeToVisible(range)
    }

    // MARK: Destinations

    @objc private func showDestinations() {
        showMenu(entries())
    }

    private func showMenu(_ entries: [DestinationMenu.Entry]) {
        popup.show(entries, under: menuButton)
    }

    /// The chosen folder replaces the folder part; the item's name stays.
    private func choose(folder: String) {
        if single != nil {
            let text = field.stringValue
            let name = text.hasSuffix("/") ? "" : String(text.split(separator: "/", omittingEmptySubsequences: false).last ?? "")
            field.stringValue = TransferTarget.text(folder: folder, name: name)
            select(.name)
        } else {
            field.stringValue = folder
            select(.all)
        }
    }

    // MARK: Ending

    @objc private func confirm() { finish(Result(text: field.stringValue, mask: maskField.stringValue)) }
    @objc private func cancel() { finish(nil) }

    private func finish(_ result: Result?) {
        guard let continuation else { return }
        self.continuation = nil
        sheet.sheetParent?.endSheet(sheet)
        sheet.owner = nil
        continuation.resume(returning: result)
    }
}
