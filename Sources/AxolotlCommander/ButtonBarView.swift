// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Stored buttons of the button bar (Settings → Button Bar, spec 018).
enum ButtonBarDefaults {
    static var items: [ButtonBarItem] {
        get { ButtonBarStore.decode(UserDefaults.standard.data(forKey: ButtonBarStore.key)) }
        set { UserDefaults.standard.set(try? ButtonBarStore.encode(newValue), forKey: ButtonBarStore.key) }
    }

    static var placement: ButtonBarPlacement {
        ButtonBarPlacement(storage: UserDefaults.standard.string(forKey: ButtonBarPlacement.key))
    }

    /// Show Button Bar: on at the last place used, or off (remembering where it was).
    static func toggle() {
        let defaults = UserDefaults.standard
        if placement == .off {
            let place = ButtonBarPlacement.shown(last: defaults.string(forKey: ButtonBarPlacement.lastKey))
            defaults.set(place.rawValue, forKey: ButtonBarPlacement.key)
        } else {
            defaults.set(placement.rawValue, forKey: ButtonBarPlacement.lastKey)
            defaults.set(ButtonBarPlacement.off.rawValue, forKey: ButtonBarPlacement.key)
        }
    }

    /// Settings → Button Bar opens with this button selected (set by Edit Button… and Add Button…).
    static let selectionKey = "buttonBar.editSelection"

    static func edit(_ id: UUID?) {
        UserDefaults.standard.set(id?.uuidString, forKey: selectionKey)
        (NSApp.delegate as? AppDelegate)?.showSettings(tab: .buttonBar)
    }

    /// Adds a command button after `id` (at the end for nil) and opens it for editing.
    static func add(after id: UUID?) {
        var all = items
        let item = ButtonBarItem.command(.refresh)
        let index = id.flatMap { id in all.firstIndex { $0.id == id } }.map { $0 + 1 } ?? all.count
        all.insert(item, at: index)
        items = all
        edit(item.id)
    }

    static func remove(_ id: UUID) {
        items = items.filter { $0.id != id }
    }

    // MARK: Looks

    /// The name of a button: the command's title, or the program's title (its file name without one).
    static func title(of item: ButtonBarItem) -> String {
        switch item.kind {
        case .separator: return String(localized: "Separator")
        case .command:
            guard let command = item.resolvedCommand else {
                return String(localized: "Unknown command “\(item.command)”")
            }
            return CommandRegistry.spec(command).localizedTitle.replacingOccurrences(of: "…", with: "")
        case .program:
            if !item.program.title.isEmpty { return item.program.title }
            let name = (item.program.program as NSString).lastPathComponent
            return name.isEmpty ? String(localized: "Untitled") : (name as NSString).deletingPathExtension
        }
    }

    /// The tooltip: the name and, for a command with a shortcut, the shortcut.
    static func toolTip(of item: ButtonBarItem) -> String {
        let name = title(of: item)
        if let command = item.resolvedCommand, let chord = KeyMaps.panel.chords(for: command).first {
            return "\(name) (\(chord.description))"
        }
        return name
    }

    static func image(for item: ButtonBarItem, pointSize: CGFloat = 14) -> NSImage? {
        switch ButtonBarIcon.resolve(item) {
        case .appIcon(let path):
            let icon = NSWorkspace.shared.icon(forFile: path)
            icon.size = NSSize(width: pointSize + 4, height: pointSize + 4)
            return icon
        case .symbol(let name):
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            let image = NSImage(systemSymbolName: name, accessibilityDescription: title(of: item))
                ?? NSImage(systemSymbolName: ButtonBarIcon.genericCommand, accessibilityDescription: title(of: item))
            return image?.withSymbolConfiguration(config)
        }
    }
}

/// A row of icon buttons. It only renders: the window controller says what is enabled and what a
/// click does. Buttons never take keyboard focus; what does not fit goes into a » menu.
final class ButtonBarView: NSView {
    var onCommand: ((Command) -> Void)?
    var onProgram: ((UserMenuItem) -> Void)?
    var onHide: (() -> Void)?

    /// Room at both ends (the bottom row gives none: the function key bar has its own).
    var edge: CGFloat = 5 { didSet { needsLayout = true } }

    private(set) var items: [ButtonBarItem] = []
    private var views: [NSView] = []
    private var shown = 0
    private let overflow = NSButton()
    private let emptyHint = NSTextField(labelWithString: String(localized: "Right-click to add buttons"))
    static let height: CGFloat = 28

    override init(frame: NSRect) {
        super.init(frame: frame)
        overflow.bezelStyle = .recessed
        overflow.showsBorderOnlyWhileMouseInside = true
        overflow.image = NSImage(systemSymbolName: "chevron.right.2", accessibilityDescription: String(localized: "More Buttons"))
        overflow.imagePosition = .imageOnly
        overflow.refusesFirstResponder = true
        overflow.target = self
        overflow.action = #selector(showOverflow(_:))
        overflow.toolTip = String(localized: "More Buttons")
        addSubview(overflow)
        emptyHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        emptyHint.textColor = .tertiaryLabelColor
        addSubview(emptyHint)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Button Bar"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }

    /// The width every button takes side by side (the bottom row gives the bar this much when it can).
    var naturalWidth: CGFloat { items.isEmpty ? emptyHint.intrinsicContentSize.width : CGFloat(ButtonBarLayout.naturalWidth(items)) }

    func update(_ items: [ButtonBarItem]) {
        guard items != self.items else { return }
        self.items = items
        views.forEach { $0.removeFromSuperview() }
        views = items.map(makeView)
        views.forEach { addSubview($0) }
        emptyHint.isHidden = !items.isEmpty
        needsLayout = true
    }

    /// Re-reads titles and icons, e.g. after the key map changed.
    func reload() {
        let current = items
        items = []
        update(current)
    }

    func validate(_ isEnabled: (Command) -> Bool) {
        for (item, view) in zip(items, views) {
            guard let button = view as? NSButton else { continue }
            let enabled: Bool = switch item.kind {
            case .command: item.resolvedCommand.map(isEnabled) ?? false
            case .program: true
            case .separator: false
            }
            if button.isEnabled != enabled { button.isEnabled = enabled }
        }
    }

    private func makeView(_ item: ButtonBarItem) -> NSView {
        if item.kind == .separator {
            let line = NSBox()
            line.boxType = .separator
            return line
        }
        let button = NSButton()
        button.bezelStyle = .recessed
        button.showsBorderOnlyWhileMouseInside = true
        button.setButtonType(.momentaryPushIn)
        button.image = ButtonBarDefaults.image(for: item)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.refusesFirstResponder = true
        button.toolTip = ButtonBarDefaults.toolTip(of: item)
        button.setAccessibilityLabel(ButtonBarDefaults.title(of: item))
        button.target = self
        button.action = #selector(click(_:))
        return button
    }

    override func layout() {
        super.layout()
        let available = Double(bounds.width - 2 * edge)
        shown = ButtonBarLayout.visibleCount(items, in: available)
        var x = edge
        let height = bounds.height - 4
        for (index, (item, view)) in zip(items, views).enumerated() {
            view.isHidden = index >= shown
            guard index < shown else { continue }
            let width = CGFloat(ButtonBarLayout.width(of: item))
            if item.kind == .separator {
                view.frame = NSRect(x: x + (width - 1) / 2, y: 5, width: 1, height: bounds.height - 10)
            } else {
                view.frame = NSRect(x: x, y: 2, width: width, height: height)
            }
            x += width + CGFloat(ButtonBarLayout.gap)
        }
        overflow.isHidden = shown == items.count
        overflow.frame = NSRect(x: bounds.width - edge - CGFloat(ButtonBarLayout.overflowWidth), y: 2,
                                width: CGFloat(ButtonBarLayout.overflowWidth), height: height)
        let hint = emptyHint.intrinsicContentSize
        emptyHint.frame = NSRect(x: edge + 4, y: ((bounds.height - hint.height) / 2).rounded(), width: hint.width, height: hint.height)
    }

    // MARK: Clicks

    @objc private func click(_ sender: NSButton) {
        guard sender.isEnabled, let index = views.firstIndex(of: sender) else { return }
        run(items[index])
    }

    private func run(_ item: ButtonBarItem) {
        switch item.kind {
        case .command: if let command = item.resolvedCommand { onCommand?(command) }
        case .program: onProgram?(item.program)
        case .separator: break
        }
    }

    @objc private func showOverflow(_ sender: NSButton) {
        let menu = NSMenu()
        for (index, item) in items.enumerated() where index >= shown {
            if item.kind == .separator {
                if menu.items.last.map({ !$0.isSeparatorItem }) ?? false { menu.addItem(.separator()) }
                continue
            }
            let entry = NSMenuItem(title: ButtonBarDefaults.title(of: item), action: #selector(runFromMenu(_:)), keyEquivalent: "")
            entry.image = ButtonBarDefaults.image(for: item, pointSize: 13)
            entry.representedObject = item.id
            entry.target = self
            let button = views[index] as? NSButton
            entry.isEnabled = button?.isEnabled ?? true
            menu.addItem(entry)
        }
        menu.autoenablesItems = false
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func runFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let item = items.first(where: { $0.id == id }) else { return }
        run(item)
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard event.type == .rightMouseDown else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let index = views.indices.first { !views[$0].isHidden && views[$0].frame.insetBy(dx: -1, dy: -4).contains(point) }
        let id = index.map { items[$0].id }
        let menu = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) {
            let handler = MenuHandler(action)
            let entry = NSMenuItem(title: title, action: #selector(MenuHandler.run(_:)), keyEquivalent: "")
            entry.target = handler
            entry.representedObject = handler
            menu.addItem(entry)
        }
        if let id {
            add(String(localized: "Edit Button…")) { ButtonBarDefaults.edit(id) }
            add(String(localized: "Remove Button")) { ButtonBarDefaults.remove(id) }
            menu.addItem(.separator())
        }
        add(String(localized: "Add Button…")) { ButtonBarDefaults.add(after: id) }
        add(String(localized: "Customize Button Bar…")) { ButtonBarDefaults.edit(nil) }
        add(String(localized: "Hide Button Bar")) { [weak self] in self?.onHide?() }
        return menu
    }
}

/// The target of a context menu item: runs a closure (the item keeps it alive).
private final class MenuHandler: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) { self.handler = handler }

    @objc func run(_ sender: Any?) { handler() }
}

/// The bottom row: the function key bar and, when the button bar is placed there, the buttons after a
/// thin line. The function keys shrink before buttons go into ».
final class BottomRowView: NSView {
    let keys: FunctionKeyBarView
    private(set) var buttons: ButtonBarView?
    private let divider = NSBox()
    private static let dividerWidth: CGFloat = 9

    init(keys: FunctionKeyBarView) {
        self.keys = keys
        super.init(frame: .zero)
        divider.boxType = .separator
        addSubview(keys)
        addSubview(divider)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 24) }

    /// Puts `bar` into the row (nil takes it out).
    func setButtons(_ bar: ButtonBarView?) {
        guard bar !== buttons else { return }
        if let buttons, buttons.superview === self { buttons.removeFromSuperview() }
        buttons = bar
        if let bar {
            bar.removeFromSuperview()
            bar.edge = 0
            addSubview(bar)
        }
        needsLayout = true
    }

    /// Shown when either part has something to show.
    var hasContent: Bool { !keys.isHidden || buttons != nil }

    override func layout() {
        super.layout()
        let keyCount = keys.isHidden ? 0 : keys.choice.visible.count
        let split = ButtonBarLayout.bottomRow(width: Double(bounds.width), keyCount: keyCount,
                                              buttons: Double(buttons?.naturalWidth ?? 0), edge: Double(FunctionKeyBarView.edge),
                                              keyGap: Double(FunctionKeyBarView.gap), divider: Double(Self.dividerWidth),
                                              minKeyWidth: Double(FunctionKeyBarView.minimumButtonWidth))
        keys.frame = NSRect(x: 0, y: 0, width: CGFloat(split.keys), height: bounds.height)
        divider.isHidden = buttons == nil || keyCount == 0
        divider.frame = NSRect(x: CGFloat(split.keys) + (Self.dividerWidth - 1) / 2, y: 4, width: 1, height: bounds.height - 8)
        let start = keyCount == 0 ? FunctionKeyBarView.edge : CGFloat(split.keys) + Self.dividerWidth
        buttons?.frame = NSRect(x: start, y: 0, width: CGFloat(split.buttons), height: bounds.height)
    }
}
