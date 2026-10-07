import AppKit

/// Tabs of one panel. Hidden while the panel has a single tab, like Finder and Safari.
/// Click switches, middle click or the × on the active tab closes, the context menu offers more.
final class TabStrip: NSView {
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onCloseOthers: ((Int) -> Void)?
    var onNew: (() -> Void)?

    private let stack = NSStackView()
    private var titles: [String] = []
    private var active = 0

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

    func show(titles: [String], active: Int) {
        isHidden = titles.count < 2
        guard titles != self.titles || active != self.active else { return }
        self.titles = titles
        self.active = active
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, title) in titles.enumerated() {
            let tab = TabButton(title: title, isActive: index == active, canClose: titles.count > 1)
            tab.onClick = { [weak self] in self?.onSelect?(index) }
            tab.onClose = { [weak self] in self?.onClose?(index) }
            tab.menu = contextMenu(for: index)
            stack.addArrangedSubview(tab)
        }
    }

    private func contextMenu(for index: Int) -> NSMenu {
        let menu = NSMenu()
        for (title, action) in [("New Tab", #selector(newTab(_:))), ("Close Tab", #selector(closeTab(_:))),
                                ("Close Other Tabs", #selector(closeOtherTabs(_:)))] {
            if action == #selector(closeTab(_:)) { menu.addItem(.separator()) }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        return menu
    }

    @objc private func newTab(_ sender: NSMenuItem) { onNew?() }
    @objc private func closeTab(_ sender: NSMenuItem) { onClose?(sender.tag) }
    @objc private func closeOtherTabs(_ sender: NSMenuItem) { onCloseOthers?(sender.tag) }
}

private final class TabButton: NSView {
    var onClick: (() -> Void)?
    var onClose: (() -> Void)?
    private let isActive: Bool

    init(title: String, isActive: Bool, canClose: Bool) {
        self.isActive = isActive
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        toolTip = title
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: isActive ? .semibold : .regular)
        label.textColor = isActive ? .labelColor : .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        var constraints = [
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ]
        if isActive && canClose {
            let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")!,
                                 target: self, action: #selector(closeClicked))
            close.isBordered = false
            close.imageScaling = .scaleProportionallyDown
            close.refusesFirstResponder = true
            close.toolTip = "Close Tab (⌃⇧W)"
            close.translatesAutoresizingMaskIntoConstraints = false
            addSubview(close)
            constraints += [
                close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                close.centerYAnchor.constraint(equalTo: centerYAnchor),
                close.widthAnchor.constraint(equalToConstant: 12),
                close.heightAnchor.constraint(equalToConstant: 12),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
