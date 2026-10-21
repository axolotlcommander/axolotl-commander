// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Tabs of one panel. Hidden while the panel has a single tab, like Finder and Safari, unless Settings →
/// Panels keeps it shown. Click switches, middle click or the × closes, the context menu offers more. The left
/// end of a tab shows the × while the pointer is over it, otherwise the lock of a locked tab, otherwise the ×
/// of the active tab. "+" opens a tab; tabs that do not fit are in the "»" menu (spec 028). A tab is dragged
/// to another place in the strip, Esc cancels the drag; Settings → Panels → Tab look picks how they are drawn
/// (spec 036).
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
    /// The tab at the first index moves to the second (indices of the items shown).
    var onMove: ((Int, Int) -> Void)?
    /// The panel of the strip is the active one; the prominent look marks its active tab.
    var panelIsActive = false { didSet { if panelIsActive != oldValue { rebuild() } } }

    private static let minimumTabWidth: CGFloat = 90
    private static let buttonWidth: CGFloat = 22
    private static let spacing: CGFloat = 1
    private static let prominentSpacing: CGFloat = 3
    private var look = PanelBehavior(defaults: .standard).tabLook

    private let stack = NSStackView()
    private lazy var height = heightAnchor.constraint(equalToConstant: Self.height)
    private static var height: CGFloat { 22 + PanelFont.windowGrowth }
    private let newButton = TabStrip.button("plus", String(localized: "New Tab"))
    private let moreButton = TabStrip.button("chevron.right.2", String(localized: "Hidden Tabs"))
    private var items: [Item] = []
    private var active = 0
    private var canReopen = false
    /// The tabs shown now (indices into `items`).
    private var shown: [Int] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = Self.spacing
        stack.distribution = .fillEqually
        newButton.target = self
        newButton.action = #selector(newTab(_:))
        moreButton.target = self
        moreButton.action = #selector(showHiddenTabs(_:))
        moreButton.isHidden = true
        let buttons = NSStackView(views: [newButton, moreButton])
        buttons.spacing = Self.spacing
        // The tabs take the width; the buttons only what they need.
        buttons.setHuggingPriority(.required, for: .horizontal)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        for view in [stack, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: buttons.leadingAnchor, constant: -Self.spacing),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttons.centerYAnchor.constraint(equalTo: centerYAnchor),
            height,
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func button(_ symbol: String, _ toolTip: String) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)!,
                              target: nil, action: nil)
        button.isBordered = false
        button.refusesFirstResponder = true
        button.toolTip = toolTip
        button.contentTintColor = .secondaryLabelColor
        button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
        return button
    }

    func show(_ items: [Item], active: Int, canReopen: Bool) {
        updateVisibility(count: items.count)
        guard items != self.items || active != self.active || canReopen != self.canReopen else { return }
        self.items = items
        self.active = active
        self.canReopen = canReopen
        rebuild()
    }

    private func updateVisibility(count: Int) {
        isHidden = count < 2 && !PanelBehavior(defaults: .standard).alwaysShowTabs
    }

    /// Takes the main window font chosen in Settings.
    func applyFont() {
        height.constant = Self.height
        rebuild()
    }

    @objc private func defaultsChanged() {
        updateVisibility(count: items.count)
        let look = PanelBehavior(defaults: .standard).tabLook
        if look != self.look {
            self.look = look
            rebuild()
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if visibleTabs() != shown { rebuild() }
    }

    private func visibleTabs() -> [Int] {
        let capacity = TabStripLayout.capacity(width: bounds.width, count: items.count, tabWidth: Self.minimumTabWidth,
                                               spacing: Self.spacing, button: Self.buttonWidth)
        return TabStripLayout.visible(count: items.count, active: active, capacity: capacity)
    }

    private func rebuild() {
        shown = visibleTabs()
        stack.spacing = look == .prominent ? Self.prominentSpacing : Self.spacing
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for index in shown {
            let tab = TabButton(items[index], isActive: index == active, canClose: items.count > 1, look: look,
                                panelIsActive: panelIsActive)
            tab.onPress = { [weak self, weak tab] event in
                guard let self, let tab else { return }
                track(event, of: tab, index: index)
            }
            tab.onClose = { [weak self] in self?.onClose?(index) }
            tab.menu = contextMenu(for: index)
            stack.addArrangedSubview(tab)
        }
        moreButton.isHidden = shown.count == items.count
    }

    /// "»": the tabs left out of the strip, in order.
    @objc private func showHiddenTabs(_ sender: NSButton) {
        let menu = NSMenu()
        for index in items.indices where !shown.contains(index) {
            let item = NSMenuItem(title: items[index].title, action: #selector(hiddenTabChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.toolTip = items[index].toolTip
            if items[index].lock != nil {
                item.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: String(localized: "Locked"))
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.height + 2 : -2), in: sender)
    }

    @objc private func hiddenTabChosen(_ sender: NSMenuItem) { onSelect?(sender.tag) }

    // MARK: Dragging (spec 036)

    /// A press on a tab: a release without moving is a click; moving more than 3 points drags the tab among
    /// the visible tabs. A picture of the tab follows the pointer while its own place stays empty and the
    /// others make room; Esc puts them back, a release anywhere keeps the order shown.
    private func track(_ event: NSEvent, of tab: TabButton, index: Int) {
        guard let window, let slot = stack.arrangedSubviews.firstIndex(of: tab) else {
            onSelect?(index)
            return
        }
        let start = convert(event.locationInWindow, from: nil)
        let grab = start.x - tab.frame.minX
        let original = stack.arrangedSubviews
        var picture: NSImageView?
        var target = slot
        var cancelled = false
        defer {
            picture?.removeFromSuperview()
            tab.alphaValue = 1
        }
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown], timeout: .infinity,
                           mode: .eventTracking) { next, stop in
            guard let next else { return }
            switch next.type {
            case .leftMouseUp:
                stop.pointee = true
            case .keyDown:
                if next.keyCode == 53 {
                    cancelled = true
                    stop.pointee = true
                }
            default:
                let x = convert(next.locationInWindow, from: nil).x
                if picture == nil {
                    guard abs(x - start.x) > MouseTracking.dragThreshold else { return }
                    picture = Self.picture(of: tab)
                    picture.map(addSubview)
                    tab.alphaValue = 0
                }
                let width = tab.frame.width
                let left = min(max(x - grab, stack.frame.minX), stack.frame.maxX - width)
                picture?.frame = NSRect(x: left, y: tab.frame.minY + stack.frame.minY, width: width,
                                        height: tab.frame.height)
                // The slot whose middle the picture's middle passed.
                let pitch = width + stack.spacing
                let slotNow = max(0, min(original.count - 1, Int(((left - stack.frame.minX) + width / 2) / pitch)))
                if slotNow != target {
                    target = slotNow
                    arrange(moving: tab, to: target, from: original)
                }
            }
        }
        guard picture != nil else {
            onSelect?(index)
            return
        }
        if cancelled || target == slot {
            arrange(moving: tab, to: slot, from: original)
            return
        }
        onMove?(index, shown[target])
    }

    /// Puts `tab` at `slot` among `views` (the order when the drag began); the others slide aside.
    private func arrange(moving tab: NSView, to slot: Int, from views: [NSView]) {
        var order = views.filter { $0 !== tab }
        order.insert(tab, at: slot)
        for view in order { stack.removeArrangedSubview(view) }
        for view in order { stack.addArrangedSubview(view) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            stack.layoutSubtreeIfNeeded()
        }
    }

    private static func picture(of view: NSView) -> NSImageView {
        let image = NSImage(size: view.bounds.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            image.addRepresentation(rep)
        }
        let picture = NSImageView(image: image)
        picture.imageScaling = .scaleNone
        picture.alphaValue = 0.85
        return picture
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
        add(String(localized: "Move Tab Left"), #selector(moveTabLeft(_:)), enabled: index > 0)
        add(String(localized: "Move Tab Right"), #selector(moveTabRight(_:)), enabled: index < count - 1)
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

    @objc private func newTab(_ sender: Any?) { onNew?() }
    @objc private func duplicateTab(_ sender: NSMenuItem) { onDuplicate?(sender.tag) }
    @objc private func copyTabToOtherPanel(_ sender: NSMenuItem) { onCopyToOtherPanel?(sender.tag) }
    @objc private func moveTabLeft(_ sender: NSMenuItem) { onMove?(sender.tag, sender.tag - 1) }
    @objc private func moveTabRight(_ sender: NSMenuItem) { onMove?(sender.tag, sender.tag + 1) }
    @objc private func lockTab(_ sender: NSMenuItem) { onLock?(sender.tag, .locked) }
    @objc private func lockTabAllowingChanges(_ sender: NSMenuItem) { onLock?(sender.tag, .allowsChanges) }
    @objc private func closeTab(_ sender: NSMenuItem) { onClose?(sender.tag) }
    @objc private func closeOtherTabs(_ sender: NSMenuItem) { onCloseOthers?(sender.tag) }
    @objc private func closeTabsToRight(_ sender: NSMenuItem) { onCloseToTheRight?(sender.tag) }
    @objc private func reopenClosedTab(_ sender: NSMenuItem) { onReopen?() }
}

private final class TabButton: NSView {
    /// A left press; the strip tells a click from a drag.
    var onPress: ((NSEvent) -> Void)?
    var onClose: (() -> Void)?
    private let isActive: Bool
    private let isLocked: Bool
    private let canClose: Bool
    private let look: TabLook
    private let panelIsActive: Bool
    private let close: NSButton
    private let lockMark: NSImageView
    private var isHovered = false {
        didSet {
            updateSlot()
            needsDisplay = true
        }
    }

    /// The prominent look's active tab of the active panel: the accent fill with white text and marks.
    private var isAccented: Bool { look == .prominent && isActive && panelIsActive }

    init(_ item: TabStrip.Item, isActive: Bool, canClose: Bool, look: TabLook, panelIsActive: Bool) {
        self.isActive = isActive
        self.isLocked = item.lock != nil
        self.canClose = canClose
        self.look = look
        self.panelIsActive = panelIsActive
        close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: String(localized: "Close Tab"))!,
                         target: nil, action: nil)
        lockMark = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: String(localized: "Locked"))!)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = look == .prominent ? 5 : 4
        toolTip = item.toolTip
        let label = NSTextField(labelWithString: item.title)
        label.font = PanelFont.window(weight: isActive ? .semibold : .regular)
        label.textColor = isAccented ? .white : isActive || look == .prominent ? .labelColor : .secondaryLabelColor
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
        lockMark.contentTintColor = isAccented ? .white : .secondaryLabelColor
        if isAccented { close.contentTintColor = .white }
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
        guard let layer else { return }
        switch look {
        case .standard:
            layer.backgroundColor = (isActive ? NSColor.controlAccentColor.withAlphaComponent(0.22)
                                              : NSColor.quaternarySystemFill).cgColor
            layer.borderWidth = 0
        case .prominent:
            let fill: NSColor = isAccented ? .controlAccentColor
                : isActive ? .systemGray.withAlphaComponent(0.5)
                : isHovered ? .secondarySystemFill : .tertiarySystemFill
            layer.backgroundColor = fill.cgColor
            layer.borderWidth = isActive ? 0 : 1
            layer.borderColor = NSColor.separatorColor.cgColor
        }
    }

    override var wantsUpdateLayer: Bool { true }

    override func mouseDown(with event: NSEvent) { onPress?(event) }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { onClose?() } else { super.otherMouseDown(with: event) }
    }

    @objc private func closeClicked() { onClose?() }
}
