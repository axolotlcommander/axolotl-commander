// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The Encode File and Decode File dialog (spec 030): what is processed, the target folder with the
/// destination menu and, for Encode, the format (remembered).
@MainActor
final class CodecDialog: NSObject {
    enum Mode { case encode, decode }

    struct Result {
        var target: String
        var format: EncodeFormat
    }

    static var lastFormat: EncodeFormat {
        get { UserDefaults.standard.string(forKey: EncodeFormat.key).flatMap(EncodeFormat.init(rawValue:)) ?? .base64 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: EncodeFormat.key) }
    }

    private let sheet = KeySheetWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
                                       styleMask: [.titled], backing: .buffered, defer: true)
    private let field = NSTextField()
    private lazy var menuButton = DestinationMenuPopup.button(target: self, action: #selector(showDestinations))
    private lazy var popup = DestinationMenuPopup { [weak self] folder in
        self?.field.stringValue = folder
        self?.sheet.makeFirstResponder(self?.field)
    }
    private let formatPopup = NSPopUpButton()
    private let mode: Mode
    private let entries: () -> [DestinationMenu.Entry]
    private var continuation: CheckedContinuation<Result?, Never>?

    private init(mode: Mode, heading: String, details: [String], folder: String,
                 entries: @escaping () -> [DestinationMenu.Entry]) {
        self.mode = mode
        self.entries = entries
        super.init()
        field.stringValue = folder
        build(heading: heading, details: details)
        sheet.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    }

    static func run(mode: Mode, heading: String, details: [String], folder: String,
                    entries: @escaping () -> [DestinationMenu.Entry], in window: NSWindow) async -> Result? {
        let dialog = CodecDialog(mode: mode, heading: heading, details: details, folder: folder, entries: entries)
        return await withCheckedContinuation { continuation in
            dialog.continuation = continuation
            dialog.sheet.owner = dialog
            window.beginSheet(dialog.sheet, completionHandler: nil)
            DispatchQueue.main.async { dialog.sheet.makeFirstResponder(dialog.field) }
        }
    }

    static func title(of format: EncodeFormat) -> String {
        switch format {
        case .base64: String(localized: "Base64 (MIME, .b64)")
        case .uue: String(localized: "UUE (.uue)")
        }
    }

    private func build(heading: String, details: [String]) {
        let headingLabel = NSTextField(labelWithString: heading)
        headingLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        headingLabel.lineBreakMode = .byTruncatingMiddle
        var views: [NSView] = [headingLabel]
        for detail in details {
            let label = NSTextField(wrappingLabelWithString: detail)
            label.textColor = .secondaryLabelColor
            label.widthAnchor.constraint(equalToConstant: 520).isActive = true
            views.append(label)
        }
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        let toRow = NSStackView(views: [field, menuButton])
        toRow.spacing = 6
        var rows: [[NSView]] = [[NSTextField(labelWithString: String(localized: "To:")), toRow]]
        if mode == .encode {
            for format in EncodeFormat.allCases {
                formatPopup.addItem(withTitle: Self.title(of: format))
                formatPopup.lastItem?.representedObject = format.rawValue
            }
            formatPopup.selectItem(at: EncodeFormat.allCases.firstIndex(of: Self.lastFormat) ?? 0)
            formatPopup.toolTip = String(localized: "Base64 keeps the file name in a small MIME header; UUE is the older format read by uudecode.")
            rows.append([NSTextField(labelWithString: String(localized: "Format:")), formatPopup])
        }
        let form = NSGridView(views: rows)
        form.column(at: 0).xPlacement = .trailing
        form.rowSpacing = 8
        form.columnSpacing = 8
        views.append(form)

        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: mode == .encode ? String(localized: "Encode") : String(localized: "Decode"),
                          target: self, action: #selector(confirm))
        ok.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, ok])
        buttons.spacing = 8
        views.append(buttons)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.setCustomSpacing(6, after: headingLabel)
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
            headingLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        sheet.contentView = content
        sheet.setContentSize(content.fittingSize)
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

    @objc private func confirm() {
        let raw = formatPopup.selectedItem?.representedObject as? String
        let format = raw.flatMap(EncodeFormat.init(rawValue:)) ?? Self.lastFormat
        if mode == .encode { Self.lastFormat = format }
        finish(Result(target: field.stringValue, format: format))
    }

    @objc private func cancel() { finish(nil) }

    private func finish(_ result: Result?) {
        guard let continuation else { return }
        self.continuation = nil
        sheet.sheetParent?.endSheet(sheet)
        sheet.owner = nil
        continuation.resume(returning: result)
    }
}
