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
    /// A mounted volume (a volume button, a network volume from the Network menu); `onChoose` when nil.
    var onChooseVolume: ((URL) -> Void)?
    var onChooseServer: ((RemoteEndpoint) -> Void)?
    /// The Network button: the panel shows the Network folder (its right-click keeps the quick menu).
    var onChooseNetwork: (() -> Void)?
    var onOpenServerInOtherPanel: ((RemoteEndpoint) -> Void)?
    var onCopyServerAddress: ((RemoteEndpoint) -> Void)?
    var onDisconnectServer: ((RemoteEndpoint) -> Void)?
    /// The ⏏ of an ejectable volume, or Eject in its menu (spec 022).
    var onEjectVolume: ((VolumeInfo) -> Void)?
    /// Volume Information… in a volume button's menu.
    var onVolumeInfo: ((URL) -> Void)?
    var onConnectToServer: (() -> Void)?
    /// The pressed item changed (the drive row shows it).
    var onPressedChange: (() -> Void)?
    /// The free space at the right end, when the drive row is hidden (spec 020).
    let freeSpace = FreeSpaceLabel()
    var showsFreeSpace = false {
        didSet { if showsFreeSpace != oldValue { needsLayout = true } }
    }
    /// The item shown pressed, if any.
    private(set) var pressedItem: VolumeBarModel.Item?

    private let stack = NSStackView()
    private var items: [VolumeBarModel.Item] = []
    private var settings = VolumeBar.savedSettings
    /// The shown location, its server and (for a local one) the mount point containing it.
    private var location: URL?
    private var remote: RemoteEndpoint?
    /// The panel shows the Network folder.
    private var network = false
    private var volumeRoot: URL?
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
        addSubview(freeSpace)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: VolumeList.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(center.addObserver(forName: FileIcons.didLoadNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(center.addObserver(forName: VolumeRoots.didResolveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locationVolumeKnown() }
        })
        observers.append(center.addObserver(forName: ServerConnectionsUI.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        })
        observers.append(center.addObserver(forName: VolumeEjector.busyChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateBusy() }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        })
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Marks the item of `location` (a folder on disk or on a server).
    func show(location: URL) {
        guard location != self.location else { return }
        self.location = location
        remote = RemoteURL.parse(location)?.endpoint
        network = NetworkPlaces.isNetwork(location)
        volumeRoot = remote == nil && !network ? VolumeRoots.shared.root(of: location) : nil
        updateStates()
    }

    private func locationVolumeKnown() {
        guard let location, remote == nil, !network else { return }
        let root = VolumeRoots.shared.root(of: location)
        guard root != volumeRoot else { return }
        volumeRoot = root
        updateStates()
    }

    private func settingsChanged() {
        let saved = Self.savedSettings
        guard saved != settings else { return }
        settings = saved
        reload()
    }

    /// Takes the volume button font chosen in Settings.
    func applyFont() {
        freeSpace.applyFont()
        reload()
    }

    private func reload() {
        items = VolumeBarModel.items(volumes: VolumeList.shared.current, home: FileManager.default.homeDirectoryForCurrentUser,
                                     iCloud: Self.iCloudDrive, servers: ServerConnectionsUI.shared.opened,
                                     settings: settings)
        // A volume mounted or unmounted may change which one holds the location.
        if let location, remote == nil, !network { volumeRoot = VolumeRoots.shared.root(of: location) }
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
    /// The free space takes what the items leave, so it shortens and hides first.
    private func fitItems() {
        let gap: CGFloat = 8
        let views = stack.arrangedSubviews
        let natural = views.enumerated().reduce(CGFloat(0)) { $0 + ($1.offset > 0 ? stack.spacing : 0) + $1.element.fittingSize.width }
        let spaceWidth = showsFreeSpace ? freeSpace.width(fitting: bounds.width - natural - gap) : 0
        freeSpace.isHidden = spaceWidth == 0
        freeSpace.frame = NSRect(x: bounds.width - spaceWidth, y: 0, width: spaceWidth, height: bounds.height)
        let room = bounds.width - (spaceWidth > 0 ? spaceWidth + gap : 0)
        var used: CGFloat = 0
        for (index, view) in views.enumerated() {
            used += (index > 0 ? stack.spacing : 0) + view.fittingSize.width
            let hide = index > 0 && used > room
            if view.isHidden != hide { view.isHidden = hide }
        }
    }

    private func makeButton(for item: VolumeBarModel.Item) -> NSButton {
        switch item {
        case .volume(let volume):
            let icon = FileIcons.shared.icon(forVolume: volume.url, network: volume.isNetwork)
            icon.size = NSSize(width: 14, height: 14)
            let ejectable = Ejectability.canEject(volume)
            let button: BarButton = ejectable ? EjectableButton(ejectTitle: EjectTarget.title(for: .volume(volume))) : BarButton()
            configured(button, title: volume.name, image: icon)
            button.toolTip = volume.availableCapacity.map { String(localized: "\(volume.url.path) — \(Format.bytes($0)) free") }
                ?? volume.url.path
            if let button = button as? EjectableButton {
                button.onEject = { [weak self] in self?.onEjectVolume?(volume) }
                button.isBusy = VolumeEjector.busy.contains(volume.url)
            }
            button.menuProvider = { [weak self] in self?.volumeMenu(volume) }
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
            let button = EjectableButton(ejectTitle: String(localized: "Disconnect \(label)"))
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
        button.controlSize = PanelFont.buttonControlSize
        button.font = PanelFont.button
        button.image = image
        button.imagePosition = .imageLeading
        button.refusesFirstResponder = true
        button.lineBreakMode = .byTruncatingTail
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: PanelFont.button.pointSize, weight: .regular))
    }

    /// Volumes being ejected show a spinner in place of the ⏏.
    private func updateBusy() {
        for case let button as EjectableButton in stack.arrangedSubviews where items.indices.contains(button.tag) {
            if case .volume(let volume) = items[button.tag] { button.isBusy = VolumeEjector.busy.contains(volume.url) }
        }
    }

    private func updateStates() {
        let pressed = VolumeBarModel.pressed(local: remote == nil ? location : nil, remote: remote,
                                             volumeRoot: volumeRoot, items: items, network: network)
        for case let button as NSButton in stack.arrangedSubviews {
            button.state = button.tag == pressed ? .on : .off
        }
        let item = pressed.map { items[$0] }
        if item != pressedItem {
            pressedItem = item
            onPressedChange?()
        }
    }

    @objc private func clicked(_ sender: NSButton) {
        updateStates()
        guard items.indices.contains(sender.tag) else { return }
        switch items[sender.tag] {
        case .volume(let volume): chooseVolume(volume.url)
        case .home(let url), .iCloud(let url): onChoose?(url)
        case .network: onChooseNetwork?()
        case .server(let endpoint, _): onChooseServer?(endpoint)
        }
    }

    private func chooseVolume(_ url: URL) {
        if let onChooseVolume { onChooseVolume(url) } else { onChoose?(url) }
    }

    // MARK: Menus

    /// Network volumes mounted in macOS, the open connections, and Connect to Server…
    private func networkMenu() -> NSMenu? {
        let menu = NSMenu()
        for volume in VolumeList.shared.current where volume.isNetwork {
            let item = actionItem(volume.name) { [weak self] in self?.chooseVolume(volume.url) }
            let icon = FileIcons.shared.icon(forVolume: volume.url, network: true)
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

    /// Eject “X” (greyed out when the volume cannot be ejected) and Volume Information…
    private func volumeMenu(_ volume: VolumeInfo) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let eject = actionItem(EjectTarget.title(for: .volume(volume))) { [weak self] in self?.onEjectVolume?(volume) }
        eject.isEnabled = Ejectability.canEject(volume) && !VolumeEjector.busy.contains(volume.url)
        menu.addItem(eject)
        menu.addItem(actionItem(CommandRegistry.spec(.volumeInfo).localizedTitle) { [weak self] in
            self?.onVolumeInfo?(volume.url)
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

/// A server connection or an ejectable volume: while the pointer is over it, an eject symbol at
/// the trailing edge disconnects or ejects it (as Finder shows for ejectable volumes); while an
/// eject runs, a spinner takes its place.
private final class EjectableButton: BarButton {
    var onEject: (() -> Void)?
    var isBusy = false {
        didSet {
            guard isBusy != oldValue else { return }
            if isBusy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
            spinner.isHidden = !isBusy
            eject.isHidden = isBusy || !isHovered
        }
    }
    private let eject = NSButton()
    private let spinner = NSProgressIndicator()
    private var hoverArea: NSTrackingArea?
    private var isHovered = false

    override class var cellClass: AnyClass? {
        get { ServerButtonCell.self }
        set {}
    }

    init(ejectTitle title: String) {
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
        spinner.style = .spinning
        spinner.controlSize = .mini
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: eject.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: eject.centerYAnchor),
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
        guard event.trackingArea === hoverArea else { return }
        isHovered = true
        eject.isHidden = isBusy
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard event.trackingArea === hoverArea else { return }
        isHovered = false
        eject.isHidden = true
    }

    // The accessory bar bezel sizes the button without asking the cell's `cellSize`, so the
    // room for the eject symbol is added here.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += ServerButtonCell.ejectWidth
        return size
    }

    @objc private func ejectClicked() {
        if !isBusy { onEject?() }
    }

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
