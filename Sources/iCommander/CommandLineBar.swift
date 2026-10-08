// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import AppKit
import CommanderCore

/// Bottom command line: the active panel's folder as prompt and a text field.
/// While it edits, panel chords (⌃Tab, ⌃Enter…) are routed by `MainWindowController`.
final class CommandLineBar: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    private let prompt = NSTextField(labelWithString: "")
    private var history: CommandHistory
    private var browser: HistoryBrowser?

    var onExecute: ((String) -> Void)?
    /// Esc on an empty line: give focus back to the panel.
    var onLeave: (() -> Void)?

    private static let historyKey = "commandLine.history"

    override init(frame: NSRect) {
        history = CommandHistory(entries: UserDefaults.standard.stringArray(forKey: Self.historyKey) ?? [])
        super.init(frame: frame)

        let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular)
        prompt.font = font
        prompt.textColor = .secondaryLabelColor
        prompt.lineBreakMode = .byTruncatingHead
        prompt.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        prompt.setContentHuggingPriority(.required, for: .horizontal)

        field.font = font
        field.placeholderString = String(localized: "Command")
        field.bezelStyle = .roundedBezel
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self

        let stack = NSStackView(views: [prompt, field])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 6, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            prompt.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.45),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// True while the field has keyboard focus.
    var isEditing: Bool {
        guard let editor = window?.firstResponder as? NSTextView else { return false }
        return editor.delegate === field
    }

    func setDirectory(_ url: URL) {
        prompt.stringValue = Self.abbreviated(url) + " ›"
        prompt.toolTip = url.path(percentEncoded: false)
    }

    /// Path with the home folder shown as `~`, without a trailing slash.
    static func abbreviated(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        var home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        if home.hasSuffix("/") { home.removeLast() }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    func focus() {
        window?.makeFirstResponder(field)
        moveCaretToEnd()
    }

    /// Inserts at the caret while editing, otherwise appends; keeps focus where it is.
    func insert(_ text: String) {
        if isEditing, let editor = field.currentEditor() as? NSTextView {
            editor.insertText(text, replacementRange: editor.selectedRange())
        } else {
            var line = field.stringValue
            if !line.isEmpty, !line.hasSuffix(" ") { line += " " }
            field.stringValue = line + text
        }
        browser = nil
    }

    /// Stores the executed line in the history (without passwords) and clears the field.
    func commit(_ line: String) {
        history.add(line)
        UserDefaults.standard.set(history.entries, forKey: Self.historyKey)
        field.stringValue = ""
        browser = nil
    }

    func showOlder() {
        if browser == nil { browser = HistoryBrowser(history) }
        if let line = browser?.older(current: field.stringValue) { setLine(line) } else { NSSound.beep() }
    }

    func showNewer() {
        if let line = browser?.newer() { setLine(line) }
    }

    private func setLine(_ line: String) {
        field.stringValue = line
        moveCaretToEnd()
    }

    private func moveCaretToEnd() {
        field.currentEditor()?.selectedRange = NSRange(location: (field.stringValue as NSString).length, length: 0)
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) { browser = nil }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            onExecute?(field.stringValue)
        case #selector(NSResponder.cancelOperation(_:)):
            browser = nil
            if field.stringValue.isEmpty { onLeave?() } else { field.stringValue = "" }
        case #selector(NSResponder.moveUp(_:)):
            showOlder()
        case #selector(NSResponder.moveDown(_:)):
            showNewer()
        default:
            return false
        }
        return true
    }
}
