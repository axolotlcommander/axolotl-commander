import AppKit
import CommanderCore

/// Row of mounted volumes above a panel (the Windows drive bar). Clicking one opens its root
/// in that panel; the volume of the current folder is shown pressed.
final class VolumeBar: NSView {
    var onChoose: ((URL) -> Void)?
    private let stack = NSStackView()
    private var volumes: [VolumeInfo] = []
    private var current: URL?
    private var observers: [any NSObjectProtocol] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    isolated deinit {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    /// Marks the volume that contains `location`.
    func show(location: URL) {
        let root = Volumes.root(of: location)
        guard root != current else { return }
        current = root
        updateStates()
    }

    private func reload() {
        volumes = Volumes.mounted()
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, volume) in volumes.enumerated() {
            let button = NSButton(title: volume.name, target: self, action: #selector(clicked(_:)))
            button.tag = index
            button.bezelStyle = .accessoryBarAction
            button.setButtonType(.pushOnPushOff)
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            let icon = NSWorkspace.shared.icon(forFile: volume.url.path)
            icon.size = NSSize(width: 14, height: 14)
            button.image = icon
            button.imagePosition = .imageLeading
            button.refusesFirstResponder = true
            button.toolTip = volume.availableCapacity.map { String(localized: "\(volume.url.path) — \(Format.bytes($0)) free") } ?? volume.url.path
            button.lineBreakMode = .byTruncatingTail
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(button)
        }
        updateStates()
    }

    private func updateStates() {
        for case let button as NSButton in stack.arrangedSubviews {
            button.state = volumes.indices.contains(button.tag) && volumes[button.tag].url == current ? .on : .off
        }
    }

    @objc private func clicked(_ sender: NSButton) {
        updateStates()
        guard volumes.indices.contains(sender.tag) else { return }
        onChoose?(volumes[sender.tag].url)
    }
}
