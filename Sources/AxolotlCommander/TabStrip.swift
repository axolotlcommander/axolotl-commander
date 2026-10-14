// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Tabs of one panel. Hidden while the panel has a single tab, like Finder and Safari.
/// Click switches, middle click or the × closes, the context menu offers more. The left end of a tab shows
/// the × while the pointer is over it, otherwise the lock of a locked tab, otherwise the × of the active tab
/// (spec 028).
final class TabStrip: NSView {
    struct Item: Equatable {
        var title: String
        var lock: TabLock.Mode?
        var toolTip: String
    }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onCloseOthers: ((Int) -> Void)?
    var onCloseToTheRight: ((Int) -> Void)?
    var onNew: (() -> Void)?
    var onDuplicate: ((Int) -> Void)?
    var onCopyToOtherPanel: ((Int) -> Void)?
    var onLock: ((Int, TabLock.Mode) -> Void)?
    var onReopen: (() -> Void)?

    private let stack = NSStackView()
    private var items: [Item] = []
    private var active = 0
    private var canReopen = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ items: [Item], active: Int, canReopen: Bool) {
        isHidden = items.count < 2
        guard items != self.items || active != self.active || canReopen != self.canReopen else { return }
        self.items = items
        self.active = active
        self.canReopen = canReopen
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in items.enumerated() {
            let tab = TabButton(item, isActive: index == active, canClose: items.count > 1)
            tab.onClick = { [weak self] in self?.onSelect?(index) }
            tab.onClose = { [weak self] in self?.onClose?(index) }
            tab.menu = contextMenu(for: index)
            stack.addArrangedSubview(tab)
        }
    }

    /// The menu of the tab at `index`; every item acts on that tab, not on the active one.
    private func contextMenu(for index: Int) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let count = items.count
        let lock = items[index].lock
        func add(_ title: String, _ action: Selector, enabled: Bool = true, on: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            item.isEnabled = enabled
            item.state = on ? .on : .off
            menu.addItem(item)
        }
        add(String(localized: "New Tab"), #selector(newTab(_:)))
        add(String(localized: "Duplicate Tab"), #selector(duplicateTab(_:)))
        add(String(localized: "Copy Tab to Other Panel"), #selector(copyTabToOtherPanel(_:)))
        menu.addItem(.separator())
        add(String(localized: "Lock Tab"), #selector(lockTab(_:)), on: lock == .locked)
        add(String(localized: "Lock Tab, Allow Folder Changes"), #selector(lockTabAllowingChanges(_:)),
            on: lock == .allowsChanges)
        menu.addItem(.separator())
        add(String(localized: "Close Tab"), #selector(closeTab(_:)), enabled: count > 1)
        add(String(localized: "Close Other Tabs"), #selector(closeOtherTabs(_:)), enabled: count > 1)
        add(String(localized: "Close Tabs to the Right"), #selector(closeTabsToRight(_:)), enabled: index < count - 1)
        add(String(localized: "Reopen Closed Tab"), #selector(reopenClosedTab(_:)), enabled: canReopen)
        return menu
    }

    @objc private func newTab(_ sender: NSMenuItem) { onNew?() }
    @objc private func duplicateTab(_ sender: NSMenuItem) { onDuplicate?(sender.tag) }
    @objc private func copyTabToOtherPanel(_ sender: NSMenuItem) { onCopyToOtherPanel?(sender.tag) }
    @objc private func lockTab(_ sender: NSMenuItem) { onLock?(sender.tag, .locked) }
    @objc private func lockTabAllowingChanges(_ sender: NSMenuItem) { onLock?(sender.tag, .allowsChanges) }
    @objc private func closeTab(_ sender: NSMenuItem) { onClose?(sender.tag) }
    @objc private func closeOtherTabs(_ sender: NSMenuItem) { onCloseOthers?(sender.tag) }
    @objc private func closeTabsToRight(_ sender: NSMenuItem) { onCloseToTheRight?(sender.tag) }
    @objc private func reopenClosedTab(_ sender: NSMenuItem) { onReopen?() }
}

private final class TabButton: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    private let isActive: Bool
    private let isLocked: Bool
    private let canClose: Bool
    private let close: NSButton
    private let lockMark: NSImageView
    private var isHovered = false {
        didSet { updateSlot() }
    }

    init(_ item: TabStrip.Item, isActive: Bool, canClose: Bool) {
        self.isActive = isActive
        self.isLocked = item.lock != nil
        self.canClose = canClose
        close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Close Tab"))!,
                         target: nil, action: nil)
        lockMark = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: String(localized: "Locked"))!)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        toolTip = item.toolTip
        let label = NSTextField(labelWithString: item.title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: isActive ? .semibold : .regular)
        label.textColor = isActive ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        close.target = self
        close.action = #selector(closeClicked)
        close.isBordered = false
        close.imageScaling = .scaleProportionallyDown
        close.refusesFirstResponder = true
        close.toolTip = String(localized: "Close Tab (⌃⇧W)")
        lockMark.imageScaling = .scaleProportionallyDown
        lockMark.contentTintColor = .secondaryLabelColor
        lockMark.setAccessibilityElement(false)
        // The name keeps its insets on both sides, so neither mark moves it.
        for view in [label, close, lockMark] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        var constraints = [
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ]
        for slot in [close, lockMark] as [NSView] {
            constraints += [
                slot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                slot.centerYAnchor.constraint(equalTo: centerYAnchor),
                slot.widthAnchor.constraint(equalToConstant: 12),
                slot.heightAnchor.constraint(equalToConstant: 12),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        updateSlot()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// One place at the left end: × while hovered, else the lock, else × on the active tab.
    private func updateSlot() {
        let showsClose = canClose && (isHovered || (isActive && !isLocked))
        close.isHidden = !showsClose
        lockMark.isHidden = showsClose || !isLocked
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func updateLayer() {
        layer?.backgroundColor = (isActive ? NSColor.controlAccentColor.withAlphaComponent(0.22)
                                           : NSColor.quaternarySystemFill).cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() } else { super.otherMouseDown(with: event) }
    }

    @objc private func closeClicked() { onClose?() }
}
