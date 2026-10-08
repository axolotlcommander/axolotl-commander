// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The row of F1–F12 buttons below the command line. It only renders: the window controller
/// gives it the commands for the held modifiers and decides what is enabled and what a click does.
/// Buttons never take keyboard focus.
final class FunctionKeyBarView: NSView {
    var onClick: ((Command) -> Void)?
    var onHide: (() -> Void)?

    private var buttons: [FunctionKeyButton] = []
    private(set) var slots: [Command?] = Array(repeating: nil, count: FunctionKeyBar.count)
    private(set) var modifiers: KeyChord.Modifiers = []
    private static let height: CGFloat = 24
    private static let gap: CGFloat = 1

    override init(frame: NSRect) {
        super.init(frame: frame)
        for number in 1...FunctionKeyBar.count {
            let button = FunctionKeyButton(number: number)
            button.target = self
            button.action = #selector(click(_:))
            addSubview(button)
            buttons.append(button)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Function Key Bar"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    /// Shows `slots` (F1…F12) for `modifiers`; unchanged buttons are left alone.
    func update(slots: [Command?], modifiers: KeyChord.Modifiers) {
        guard slots != self.slots || modifiers != self.modifiers else { return }
        self.slots = slots
        self.modifiers = modifiers
        for (button, command) in zip(buttons, slots) { button.show(command, modifiers: modifiers) }
        needsLayout = true
    }

    /// Re-reads everything (titles, icons, tooltips), e.g. after the key map changed.
    func reload() {
        for (button, command) in zip(buttons, slots) { button.show(command, modifiers: modifiers) }
        needsLayout = true
    }

    func validate(_ isEnabled: (Command) -> Bool) {
        for button in buttons {
            let enabled = button.command.map(isEnabled) ?? false
            if button.isEnabled != enabled { button.setAvailable(enabled) }
        }
    }

    override func layout() {
        super.layout()
        let count = CGFloat(buttons.count)
        let width = ((bounds.width - Self.gap * (count + 1)) / count).rounded(.down)
        var x = Self.gap
        for (index, button) in buttons.enumerated() {
            // The last button takes the rounding remainder so the row ends at the edge.
            let w = index == buttons.count - 1 ? bounds.width - Self.gap - x : width
            button.frame = NSRect(x: x, y: 1, width: max(w, 0), height: bounds.height - 2)
            button.fitTitle()
            x += width + Self.gap
        }
    }

    @objc private func click(_ sender: FunctionKeyButton) {
        guard let command = sender.command, sender.isEnabled else { return }
        onClick?(command)
    }

    // MARK: Context menu

    private lazy var contextMenu: NSMenu = {
        let menu = NSMenu()
        let hide = NSMenuItem(title: String(localized: "Hide Function Key Bar"), action: #selector(hide(_:)),
                              keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        return menu
    }()

    @objc private func hide(_ sender: Any?) { onHide?() }

    /// Only a real right click opens the menu: a ⌃-click is an ordinary click, so the ⌃ set of
    /// commands can be clicked too.
    override func menu(for event: NSEvent) -> NSMenu? {
        event.type == .rightMouseDown ? contextMenu : nil
    }

    fileprivate func menuForButton(_ event: NSEvent) -> NSMenu? { menu(for: event) }
}

/// One F-key button: key number and command name (no icon, as in the reference), shortened to fit.
private final class FunctionKeyButton: NSButton {
    let number: Int
    private(set) var command: Command?
    private var modifiers: KeyChord.Modifiers = []
    private var fitted: (width: CGFloat, enabled: Bool)?

    override class var cellClass: AnyClass? {
        get { FunctionKeyButtonCell.self }
        set {}
    }

    init(number: Int) {
        self.number = number
        super.init(frame: .zero)
        bezelStyle = .recessed
        showsBorderOnlyWhileMouseInside = true
        controlSize = .small
        font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        imagePosition = .noImage
        refusesFirstResponder = true
        lineBreakMode = .byTruncatingTail
        cell?.usesSingleLineMode = true
        cell?.truncatesLastVisibleLine = true
        setButtonType(.momentaryPushIn)
        show(nil, modifiers: [])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { false }

    override func menu(for event: NSEvent) -> NSMenu? {
        (superview as? FunctionKeyBarView)?.menuForButton(event)
    }

    func show(_ command: Command?, modifiers: KeyChord.Modifiers) {
        self.command = command
        self.modifiers = modifiers
        let key = "F\(number)"
        if let command {
            let spec = CommandRegistry.spec(command)
            let chord = KeyChord(.function(number), modifiers)
            let name = CommandRegistry.barTitle(command) == nil ? spec.localizedTitle : spec.barTitle
            toolTip = "\(name) (\(chord.description))"
            setAccessibilityLabel("\(key), \(name)")
        } else {
            toolTip = nil
            setAccessibilityLabel(key)
        }
        isEnabled = command != nil && isEnabled
        fitted = nil
        fitTitle()
    }

    func setAvailable(_ enabled: Bool) {
        isEnabled = enabled
        fitted = nil
        fitTitle()
    }

    /// Picks the longest label that fits: full name, short name, short name truncated, key only.
    func fitTitle() {
        let width = bounds.width
        if let fitted, fitted.width == width, fitted.enabled == isEnabled { return }
        fitted = (width, isEnabled)
        guard let command else {
            attributedTitle = label(name: nil)
            return
        }
        let spec = CommandRegistry.spec(command)
        let full = label(name: spec.barTitle)
        let short = label(name: spec.localizedShortTitle)
        let keyOnly = label(name: nil)
        attributedTitle = full
        if fits() { return }
        attributedTitle = short
        if fits() { return }
        attributedTitle = keyOnly
        let keyWidth = cell?.cellSize.width ?? 0
        // Room for at least a couple of letters and "…": the short name, truncated.
        if width >= keyWidth + 28 { attributedTitle = short }
    }

    private func fits() -> Bool { (cell?.cellSize.width ?? .infinity) <= bounds.width }

    private func label(name: String?) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let keyColor: NSColor = command == nil || !isEnabled ? .tertiaryLabelColor : .secondaryLabelColor
        let nameColor: NSColor = isEnabled ? .labelColor : .tertiaryLabelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: "F\(number)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium),
            .foregroundColor: keyColor, .paragraphStyle: paragraph,
        ])
        if let name {
            text.append(NSAttributedString(string: " " + name, attributes: [
                .font: font, .foregroundColor: nameColor, .paragraphStyle: paragraph,
            ]))
        }
        return text
    }
}

/// The recessed bezel with narrower side margins than the system's, so longer names fit.
private final class FunctionKeyButtonCell: NSButtonCell {
    private static let margin: CGFloat = 4

    override var cellSize: NSSize {
        NSSize(width: attributedTitle.size().width.rounded(.up) + 2 * Self.margin, height: super.cellSize.height)
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        let bounds = controlView.bounds
        let wide = NSRect(x: bounds.minX + Self.margin, y: frame.minY,
                          width: max(bounds.width - 2 * Self.margin, 0), height: frame.height)
        return super.drawTitle(title, withFrame: wide, in: controlView)
    }
}
