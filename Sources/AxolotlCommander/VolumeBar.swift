// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Row above a panel (the Windows drive bar): the mounted volumes, then Home, iCloud Drive,
/// Network and the open server connections as Settings → Appearance chooses. Clicking a volume
/// opens its root in that panel, a server its last folder there; the item of the current
/// location is shown pressed.
final class VolumeBar: NSView {
    /// A volume, Home, iCloud Drive or a network volume from the Network menu.
    var onChoose: ((URL) -> Void)?
    var onChooseServer: ((RemoteEndpoint) -> Void)?
    var onOpenServerInOtherPanel: ((RemoteEndpoint) -> Void)?
    var onCopyServerAddress: ((RemoteEndpoint) -> Void)?
    var onDisconnectServer: ((RemoteEndpoint) -> Void)?
    var onConnectToServer: (() -> Void)?

    private let stack = NSStackView()
    private var items: [VolumeBarModel.Item] = []
    private var settings = VolumeBar.savedSettings
    /// The shown location, its server and (for a local one) the mount point containing it.
    private var location: URL?
    private var remote: RemoteEndpoint?
    private var volumeRoot: URL?
    private var workspaceObservers: [any NSObjectProtocol] = []
    private var observers: [any NSObjectProtocol] = []

    /// The iCloud Drive folder when iCloud Drive is set up on this Mac.
    static var iCloudDrive: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static var savedSettings: VolumeBarSettings {
        VolumeBarSettings { UserDefaults.standard.object(forKey: $0) }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ServerConnectionsUI.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        })
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    isolated deinit {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Marks the item of `location` (a folder on disk or on a server).
    func show(location: URL) {
        guard location != self.location else { return }
        self.location = location
        remote = RemoteURL.parse(location)?.endpoint
        volumeRoot = remote == nil ? Volumes.root(of: location) : nil
        updateStates()
    }

    private func settingsChanged() {
        let saved = Self.savedSettings
        guard saved != settings else { return }
        settings = saved
        reload()
    }

    private func reload() {
        items = VolumeBarModel.items(volumes: Volumes.mounted(), home: FileManager.default.homeDirectoryForCurrentUser,
                                     iCloud: Self.iCloudDrive, servers: ServerConnectionsUI.shared.opened,
                                     settings: settings)
        // A volume mounted or unmounted may change which one holds the location.
        if let location, remote == nil { volumeRoot = Volumes.root(of: location) }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in items.enumerated() {
            let button = makeButton(for: item)
            button.tag = index
            stack.addArrangedSubview(button)
        }
        updateStates()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        fitItems()
    }

    /// A bar too narrow for every item hides items from the end, so volumes stay visible
    /// longest (each stays reachable through the volume menu); the first item only truncates.
    private func fitItems() {
        var used: CGFloat = 0
        for (index, view) in stack.arrangedSubviews.enumerated() {
            used += (index > 0 ? stack.spacing : 0) + view.fittingSize.width
            let hide = index > 0 && used > bounds.width
            if view.isHidden != hide { view.isHidden = hide }
        }
    }

    private func makeButton(for item: VolumeBarModel.Item) -> NSButton {
        switch item {
        case .volume(let volume):
            let icon = NSWorkspace.shared.icon(forFile: volume.url.path)
            icon.size = NSSize(width: 14, height: 14)
            let button = configured(BarButton(), title: volume.name, image: icon)
            button.toolTip = volume.availableCapacity.map { String(localized: "\(volume.url.path) — \(Format.bytes($0)) free") }
                ?? volume.url.path
            return button
        case .home(let url):
            let button = configured(BarButton(), title: String(localized: "Home"), image: Self.symbol("house"))
            button.toolTip = url.path
            return button
        case .iCloud(let url):
            let button = configured(BarButton(), title: String(localized: "iCloud Drive"), image: Self.symbol("icloud"))
            button.toolTip = url.path
            return button
        case .network:
            let button = configured(BarButton(), title: String(localized: "Network"), image: Self.symbol("network"))
            button.menuProvider = { [weak self] in self?.networkMenu() }
            return button
        case .server(let endpoint, let label):
            let button = ServerButton(label: label)
            configured(button, title: label, image: Self.symbol("network"))
            button.toolTip = ServerConnectionsUI.shared.address(of: endpoint)
            button.onEject = { [weak self] in self?.onDisconnectServer?(endpoint) }
            button.menuProvider = { [weak self] in self?.serverMenu(endpoint) }
            return button
        }
    }

    /// The look of the volume buttons: a small accessory bar button that stays pressed.
    @discardableResult
    private func configured(_ button: BarButton, title: String, image: NSImage?) -> BarButton {
        button.title = title
        button.target = self
        button.action = #selector(clicked(_:))
        button.bezelStyle = .accessoryBarAction
        button.setButtonType(.pushOnPushOff)
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.image = image
        button.imagePosition = .imageLeading
        button.refusesFirstResponder = true
        button.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
    }

    private func updateStates() {
        let pressed = VolumeBarModel.pressed(local: remote == nil ? location : nil, remote: remote,
                                             volumeRoot: volumeRoot, items: items)
        for case let button as NSButton in stack.arrangedSubviews {
            button.state = button.tag == pressed ? .on : .off
        }
    }

    @objc private func clicked(_ sender: NSButton) {
        updateStates()
        guard items.indices.contains(sender.tag) else { return }
        switch items[sender.tag] {
        case .volume(let volume): onChoose?(volume.url)
        case .home(let url), .iCloud(let url): onChoose?(url)
        case .network:
            guard let menu = networkMenu() else { return }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.height + 2 : -2), in: sender)
        case .server(let endpoint, _): onChooseServer?(endpoint)
        }
    }

    // MARK: Menus

    /// Network volumes mounted in macOS, the open connections, and Connect to Server…
    private func networkMenu() -> NSMenu? {
        let menu = NSMenu()
        for volume in Volumes.mounted() where volume.isNetwork {
            let item = actionItem(volume.name) { [weak self] in self?.onChoose?(volume.url) }
            let icon = NSWorkspace.shared.icon(forFile: volume.url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        let connections = ServerConnectionsUI.shared
        if !connections.opened.isEmpty, !menu.items.isEmpty { menu.addItem(.separator()) }
        for endpoint in connections.opened {
            let item = actionItem(connections.label(for: endpoint)) { [weak self] in self?.onChooseServer?(endpoint) }
            item.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
            item.toolTip = connections.address(of: endpoint)
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(actionItem(CommandRegistry.spec(.connectToServer).localizedTitle) { [weak self] in
            self?.onConnectToServer?()
        })
        return menu
    }

    private func serverMenu(_ endpoint: RemoteEndpoint) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(actionItem(String(localized: "Open in Other Panel")) { [weak self] in
            self?.onOpenServerInOtherPanel?(endpoint)
        })
        menu.addItem(actionItem(String(localized: "Copy Address")) { [weak self] in self?.onCopyServerAddress?(endpoint) })
        menu.addItem(.separator())
        menu.addItem(actionItem(String(localized: "Disconnect")) { [weak self] in self?.onDisconnectServer?(endpoint) })
        return menu
    }
}

/// A volume bar button; right-click or Control-click shows `menuProvider`'s menu.
private class BarButton: NSButton {
    var menuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu = menuProvider?() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.mouseDown(with: event)
    }
}

/// A server connection: while the pointer is over it, an eject symbol at the trailing edge
/// disconnects (as Finder shows for ejectable volumes).
private final class ServerButton: BarButton {
    var onEject: (() -> Void)?
    private let eject = NSButton()
    private var hoverArea: NSTrackingArea?

    override class var cellClass: AnyClass? {
        get { ServerButtonCell.self }
        set {}
    }

    init(label: String) {
        super.init(frame: .zero)
        let image = NSImage(systemSymbolName: "eject.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .regular))
        eject.image = image
        eject.imagePosition = .imageOnly
        eject.isBordered = false
        eject.setButtonType(.momentaryChange)
        eject.contentTintColor = .secondaryLabelColor
        eject.refusesFirstResponder = true
        eject.target = self
        eject.action = #selector(ejectClicked)
        let title = String(localized: "Disconnect \(label)")
        eject.setAccessibilityLabel(title)
        eject.toolTip = title
        eject.isHidden = true
        eject.translatesAutoresizingMaskIntoConstraints = false
        addSubview(eject)
        NSLayoutConstraint.activate([
            eject.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            eject.centerYAnchor.constraint(equalTo: centerYAnchor),
            eject.widthAnchor.constraint(equalToConstant: ServerButtonCell.ejectWidth - 2),
            eject.heightAnchor.constraint(equalToConstant: ServerButtonCell.ejectWidth - 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if hoverArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                      owner: self)
            addTrackingArea(area)
            hoverArea = area
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if event.trackingArea === hoverArea { eject.isHidden = false }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if event.trackingArea === hoverArea { eject.isHidden = true }
    }

    // The accessory bar bezel sizes the button without asking the cell's `cellSize`, so the
    // room for the eject symbol is added here.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += ServerButtonCell.ejectWidth
        return size
    }

    @objc private func ejectClicked() { onEject?() }

    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + (eject.isHidden ? [] : [eject])
    }
}

/// Leaves room at the trailing edge for the eject symbol, so it never covers the name.
private final class ServerButtonCell: NSButtonCell {
    static let ejectWidth: CGFloat = 14

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var frame = cellFrame
        frame.size.width -= Self.ejectWidth
        super.drawInterior(withFrame: frame, in: controlView)
    }
}
