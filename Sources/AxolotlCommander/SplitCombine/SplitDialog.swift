// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

enum SplitDefaults {
    static let partSizeKey = "split.partSize"
    static let writeChecksumKey = "split.writeChecksum"

    static var partSize: Int64 {
        get {
            let stored = (UserDefaults.standard.object(forKey: partSizeKey) as? NSNumber)?.int64Value ?? 0
            return stored > 0 ? stored : PartSize.defaultSize
        }
        set { UserDefaults.standard.set(NSNumber(value: newValue), forKey: partSizeKey) }
    }

    static var writeChecksum: Bool {
        get { UserDefaults.standard.object(forKey: writeChecksumKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: writeChecksumKey) }
    }
}

/// The Split File dialog (spec 029): target folder with the destination menu, part size (presets or a
/// typed size), the number of parts that will be made, and the checksum file checkbox.
@MainActor
final class SplitDialog: NSObject, NSTextFieldDelegate {
    struct Result {
        var target: String
        var partSize: Int64
        var writeChecksum: Bool
    }

    private static let customTag = -1

    private let sheet = KeySheetWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 220),
                                       styleMask: [.titled], backing: .buffered, defer: true)
    private let field = NSTextField()
    private lazy var menuButton = DestinationMenuPopup.button(target: self, action: #selector(showDestinations))
    private lazy var popup = DestinationMenuPopup { [weak self] folder in
        self?.field.stringValue = folder
        self?.sheet.makeFirstResponder(self?.field)
    }
    private let sizePopup = NSPopUpButton()
    private let customField = NSTextField()
    private let countLabel = NSTextField(labelWithString: "")
    private let checksumBox = NSButton(checkboxWithTitle: String(localized: "Create checksum file"), target: nil, action: nil)
    private let okButton = NSButton()
    private let fileSize: Int64
    private let entries: () -> [DestinationMenu.Entry]
    private var continuation: CheckedContinuation<Result?, Never>?

    private init(name: String, size: Int64, folder: String, entries: @escaping () -> [DestinationMenu.Entry]) {
        fileSize = size
        self.entries = entries
        super.init()
        field.stringValue = folder
        build(name: name)
        choose(size: SplitDefaults.partSize)
        checksumBox.state = SplitDefaults.writeChecksum ? .on : .off
        update()
        sheet.onKey = { [weak self] event in self?.handleKey(event) ?? false }
    }

    static func run(name: String, size: Int64, folder: String, entries: @escaping () -> [DestinationMenu.Entry],
                    in window: NSWindow) async -> Result? {
        let dialog = SplitDialog(name: name, size: size, folder: folder, entries: entries)
        return await withCheckedContinuation { continuation in
            dialog.continuation = continuation
            dialog.sheet.owner = dialog
            window.beginSheet(dialog.sheet, completionHandler: nil)
            DispatchQueue.main.async { dialog.sheet.makeFirstResponder(dialog.field) }
        }
    }

    // MARK: Layout

    static func title(of preset: PartSize.Preset) -> String {
        switch preset {
        case .email: String(localized: "25 MB (e-mail)")
        case .hundred: String(localized: "100 MB")
        case .cd: String(localized: "700 MB (CD)")
        case .dvd: String(localized: "4.7 GB (DVD)")
        case .fat32: String(localized: "4 GB − 1 byte (FAT32)")
        }
    }

    private func build(name: String) {
        let heading = NSTextField(labelWithString: String(localized: "Split “\(name)” into parts"))
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        heading.lineBreakMode = .byTruncatingMiddle
        let sizeLine = NSTextField(labelWithString: String(localized: "Size: \(Format.bytes(fileSize)) (\(Format.grouped(fileSize)) bytes)"))
        sizeLine.textColor = .secondaryLabelColor
        field.lineBreakMode = .byTruncatingHead
        field.cell?.isScrollable = true
        let toRow = NSStackView(views: [field, menuButton])
        toRow.spacing = 6

        for (index, preset) in PartSize.Preset.allCases.enumerated() {
            sizePopup.addItem(withTitle: Self.title(of: preset))
            sizePopup.lastItem?.tag = index
        }
        sizePopup.menu?.addItem(.separator())
        sizePopup.addItem(withTitle: String(localized: "Custom…"))
        sizePopup.lastItem?.tag = Self.customTag
        sizePopup.target = self
        sizePopup.action = #selector(sizeChosen)
        customField.placeholderString = String(localized: "e.g. 10M, 1,5G, 500k")
        customField.delegate = self
        customField.toolTip = String(localized: "A number with an optional unit k, M or G (1024-based); bytes without a unit.")
        let sizeRow = NSStackView(views: [sizePopup, customField])
        sizeRow.spacing = 8
        checksumBox.toolTip = String(localized: "Writes a small file with the original name, size and CRC32, so Combine Files can check the result.")

        let form = NSGridView(views: [
            [NSTextField(labelWithString: String(localized: "To:")), toRow],
            [NSTextField(labelWithString: String(localized: "Part size:")), sizeRow],
            [NSGridCell.emptyContentView, countLabel],
            [NSGridCell.emptyContentView, checksumBox],
        ])
        form.column(at: 0).xPlacement = .trailing
        form.rowSpacing = 8
        form.columnSpacing = 8
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        okButton.title = String(localized: "Split")
        okButton.bezelStyle = .push
        okButton.target = self
        okButton.action = #selector(confirm)
        okButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, okButton])
        buttons.spacing = 8
        let stack = NSStackView(views: [heading, sizeLine, form, buttons])
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
            customField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            heading.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
            countLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        sheet.contentView = content
        sheet.setContentSize(content.fittingSize)
    }

    // MARK: Size

    /// Selects the preset of `size`, or Custom with the size written in the largest exact unit.
    private func choose(size: Int64) {
        if let preset = PartSize.Preset.matching(size), let index = PartSize.Preset.allCases.firstIndex(of: preset) {
            sizePopup.selectItem(withTag: index)
            customField.stringValue = ""
        } else {
            sizePopup.selectItem(withTag: Self.customTag)
            customField.stringValue = Self.text(of: size)
        }
        customField.isEnabled = sizePopup.selectedTag() == Self.customTag
    }

    static func text(of size: Int64) -> String {
        for (unit, factor) in [("G", Int64(1) << 30), ("M", Int64(1) << 20), ("k", Int64(1) << 10)] where size % factor == 0 {
            return "\(size / factor)\(unit)"
        }
        return String(size)
    }

    private var partSize: Int64? {
        let tag = sizePopup.selectedTag()
        if tag == Self.customTag { return PartSize.parse(customField.stringValue) }
        return PartSize.Preset.allCases[tag].bytes
    }

    @objc private func sizeChosen() {
        let custom = sizePopup.selectedTag() == Self.customTag
        customField.isEnabled = custom
        if custom {
            if customField.stringValue.isEmpty { customField.stringValue = Self.text(of: SplitDefaults.partSize) }
            sheet.makeFirstResponder(customField)
        } else {
            customField.stringValue = ""
        }
        update()
    }

    func controlTextDidChange(_ obj: Notification) { update() }

    private func update() {
        let size = partSize
        switch PartSize.problem(fileSize: fileSize, partSize: size) {
        case .invalid?:
            countLabel.stringValue = String(localized: "Enter a part size, e.g. 10M.")
            countLabel.textColor = .systemRed
        case .notLarger?:
            countLabel.stringValue = String(localized: "The file is not larger than one part.")
            countLabel.textColor = .systemRed
        case .tooManyParts?:
            countLabel.stringValue = String(localized: "More than \(PartSize.maximumParts) parts would be needed; choose a larger size.")
            countLabel.textColor = .systemRed
        case nil:
            let count = PartSize.count(fileSize: fileSize, partSize: size ?? 1)
            countLabel.stringValue = String(localized: "Creates \(count) parts")
            countLabel.textColor = .secondaryLabelColor
        }
        okButton.isEnabled = PartSize.problem(fileSize: fileSize, partSize: size) == nil
    }

    // MARK: Keys

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

    // MARK: Ending

    @objc private func confirm() {
        guard let size = partSize, PartSize.problem(fileSize: fileSize, partSize: size) == nil else {
            NSSound.beep()
            return
        }
        SplitDefaults.partSize = size
        SplitDefaults.writeChecksum = checksumBox.state == .on
        finish(Result(target: field.stringValue, partSize: size, writeChecksum: checksumBox.state == .on))
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
