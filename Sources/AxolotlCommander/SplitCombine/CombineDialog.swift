// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The Combine Files dialog (spec 029): the parts, their total size, the target path with the file name
/// (and the destination menu), and whether the result is checked against a checksum file.
@MainActor
final class CombineDialog: NSObject {
    private let sheet = KeySheetWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
                                       styleMask: [.titled], backing: .buffered, defer: true)
    private let field = NSTextField()
    private lazy var menuButton = DestinationMenuPopup.button(target: self, action: #selector(showDestinations))
    private lazy var popup = DestinationMenuPopup { [weak self] folder in self?.choose(folder: folder) }
    private let entries: () -> [DestinationMenu.Entry]
    private var continuation: CheckedContinuation<String?, Never>?

    private init(set: PartSet, totalSize: Int64, text: String, entries: @escaping () -> [DestinationMenu.Entry]) {
        self.entries = entries
        super.init()
        field.stringValue = text
        build(set: set, totalSize: totalSize)
        sheet.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    }

    /// The "To:" text the user confirmed, or nil.
    static func run(set: PartSet, totalSize: Int64, text: String, entries: @escaping () -> [DestinationMenu.Entry],
                    in window: NSWindow) async -> String? {
        let dialog = CombineDialog(set: set, totalSize: totalSize, text: text, entries: entries)
        return await withCheckedContinuation { continuation in
            dialog.continuation = continuation
            dialog.sheet.owner = dialog
            window.beginSheet(dialog.sheet, completionHandler: nil)
            DispatchQueue.main.async { dialog.selectName() }
        }
    }

    private func build(set: PartSet, totalSize: Int64) {
        let first = set.parts.first?.lastPathComponent ?? ""
        let heading = NSTextField(labelWithString: set.parts.count == 1
            ? String(localized: "Combine “\(first)”")
            : String(localized: "Combine \(set.parts.count) parts starting with “\(first)”"))
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        heading.lineBreakMode = .byTruncatingMiddle
        let sizeLine = NSTextField(labelWithString: String(localized: "Total size: \(Format.bytes(totalSize)) (\(Format.grouped(totalSize)) bytes)"))
        sizeLine.textColor = .secondaryLabelColor
        let check: String
        if let file = set.checksumFile, let checksum = set.checksum, checksum.size != nil || checksum.crc32 != nil {
            check = String(localized: "The result will be checked against “\(file.lastPathComponent)”.")
        } else if let file = set.checksumFile {
            check = String(localized: "“\(file.lastPathComponent)” cannot be read; the result will not be checked.")
        } else {
            check = String(localized: "No checksum file: the result will not be checked.")
        }
        let checkLine = NSTextField(wrappingLabelWithString: check)
        checkLine.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        let toRow = NSStackView(views: [field, menuButton])
        toRow.spacing = 6
        let form = NSGridView(views: [[NSTextField(labelWithString: String(localized: "To:")), toRow]])
        form.column(at: 0).xPlacement = .trailing
        form.columnSpacing = 8
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: String(localized: "Combine"), target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, ok])
        buttons.spacing = 8
        let stack = NSStackView(views: [heading, sizeLine, form, checkLine, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(4, after: heading)
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
            checkLine.widthAnchor.constraint(equalToConstant: 520),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        sheet.contentView = content
        sheet.setContentSize(content.fittingSize)
    }

    /// Selects the file name part of "To:".
    private func selectName() {
        sheet.makeFirstResponder(field)
        guard let editor = field.currentEditor() as? NSTextView else { return }
        let text = field.stringValue as NSString
        let slash = text.range(of: "/", options: .backwards)
        let start = slash.location == NSNotFound ? 0 : slash.location + 1
        editor.selectedRange = NSRange(location: start, length: text.length - start)
    }

    /// The chosen folder replaces the folder part; the file name stays.
    private func choose(folder: String) {
        let text = field.stringValue
        let name = text.hasSuffix("/") ? "" : String(text.split(separator: "/", omittingEmptySubsequences: false).last ?? "")
        field.stringValue = TransferTarget.text(folder: folder, name: name)
        selectName()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch (event.keyCode, flags) {
        case (125, .option):  // ⌥↓
            showDestinations()
            return true
        case (2, .control):  // ⌃D
            popup.show(entries().filter { $0.section == .hotPaths }, under: menuButton)
            return true
        default:
            return false
        }
    }

    @objc private func showDestinations() {
        popup.show(entries(), under: menuButton)
    }

    @objc private func confirm() { finish(field.stringValue) }
    @objc private func cancel() { finish(nil) }

    private func finish(_ result: String?) {
        guard let continuation else { return }
        self.continuation = nil
        sheet.sheetParent?.endSheet(sheet)
        sheet.owner = nil
        continuation.resume(returning: result)
    }
}
