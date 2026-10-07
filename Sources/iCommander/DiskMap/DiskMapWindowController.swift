import AppKit
import CommanderCore

/// ⌃⌥F10 / ⌃⇧D: what takes the space in a folder, as a treemap. Only reads the disk; the scan stays
/// on the folder's volume. Double click or Return enters a folder, ⌫ goes up, “Show in Panel” opens
/// the selected item in the active panel.
final class DiskMapWindowController: NSWindowController, NSWindowDelegate {
    private static var open: [DiskMapWindowController] = []

    static func show(_ folder: URL, from main: MainWindowController) {
        let controller = DiskMapWindowController(folder: folder, main: main)
        open.append(controller)
        controller.showWindow(nil)
        controller.scan()
    }

    private let folder: URL
    private weak var main: MainWindowController?
    private let map = TreemapView()
    private let pathControl = NSPathControl()
    private let upButton = NSButton()
    private let rescanButton = NSButton()
    private let revealButton = NSButton()
    private let statusField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let stopButton = NSButton()
    private var scanTask: Task<Void, Never>?

    init(folder: URL, main: MainWindowController) {
        self.folder = folder
        self.main = main
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Disk Map – \(folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent)")
        window.minSize = NSSize(width: 480, height: 320)
        window.setFrameAutosaveName("DiskMap")
        super.init(window: window)
        window.delegate = self
        build()
        if !window.setFrameUsingName("DiskMap") { window.center() }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        func button(_ button: NSButton, symbol: String, title: String, action: Selector) {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            button.title = title
            button.imagePosition = .imageLeading
            button.bezelStyle = .push
            button.controlSize = .regular
            button.target = self
            button.action = action
        }
        button(upButton, symbol: "arrow.up", title: String(localized: "Enclosing Folder"), action: #selector(goUp))
        button(rescanButton, symbol: "arrow.clockwise", title: String(localized: "Scan Again"), action: #selector(rescan))
        button(revealButton, symbol: "sidebar.left", title: String(localized: "Show in Panel"), action: #selector(showInPanel))
        stopButton.title = String(localized: "Stop")
        stopButton.bezelStyle = .push
        stopButton.target = self
        stopButton.action = #selector(stop)
        stopButton.keyEquivalent = "\u{1b}"

        pathControl.pathStyle = .standard
        pathControl.target = self
        pathControl.action = #selector(pathClicked)
        pathControl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pathControl.focusRingType = .none

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        statusField.lineBreakMode = .byTruncatingMiddle
        statusField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailField.lineBreakMode = .byTruncatingMiddle
        detailField.textColor = .secondaryLabelColor
        detailField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let top = NSStackView(views: [upButton, pathControl, NSView(), rescanButton, revealButton])
        top.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let legend = NSStackView(views: DiskMapKind.allCases.filter { $0 != .folder }.map(Self.legendItem))
        legend.spacing = 12
        let bottom = NSStackView(views: [spinner, statusField, NSView(), stopButton])
        bottom.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 0, right: 10)
        let detail = NSStackView(views: [detailField, NSView(), legend])
        detail.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 8, right: 10)

        map.onSelect = { [weak self] in self?.updateStatus() }
        map.onHover = { [weak self] in self?.updateStatus() }
        map.onLocationChange = { [weak self] in self?.updateLocation() }
        map.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        map.setContentHuggingPriority(.defaultLow, for: .vertical)

        let stack = NSStackView(views: [top, map, bottom, detail])
        stack.orientation = .vertical
        stack.spacing = 0
        for view in stack.arrangedSubviews { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            map.widthAnchor.constraint(greaterThanOrEqualToConstant: 440),
            map.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
        window?.contentView = stack
        window?.setContentSize(NSSize(width: 900, height: 620))
        window?.initialFirstResponder = map
        updateButtons()
    }

    private static func legendItem(_ kind: DiskMapKind) -> NSView {
        let swatch = NSView()
        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = kind.color.cgColor
        swatch.layer?.cornerRadius = 2
        NSLayoutConstraint.activate([swatch.widthAnchor.constraint(equalToConstant: 10),
                                     swatch.heightAnchor.constraint(equalToConstant: 10)])
        let label = NSTextField(labelWithString: kind.title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        let item = NSStackView(views: [swatch, label])
        item.spacing = 4
        return item
    }

    // MARK: Scanning

    private func scan() {
        scanTask?.cancel()
        spinner.startAnimation(nil)
        stopButton.isHidden = false
        statusField.stringValue = String(localized: "Scanning…")
        detailField.stringValue = folder.path(percentEncoded: false)
        updateButtons(scanning: true)
        let folder = folder
        scanTask = Task { [weak self] in
            let result: Result<DiskUsageNode, any Error>
            do {
                // Nonisolated async: runs off the main actor, and cancelling the task stops it.
                result = .success(try await DiskUsage.scan(folder) { progress in
                    Task { @MainActor in self?.showProgress(progress) }
                })
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            self.finish(result)
        }
    }

    private func showProgress(_ progress: DiskUsageProgress) {
        guard scanTask != nil else { return }
        statusField.stringValue = String(localized: "Scanning… \(progress.files) files, \(Format.bytes(progress.bytes))")
        detailField.stringValue = progress.currentPath
    }

    private func finish(_ result: Result<DiskUsageNode, any Error>) {
        scanTask = nil
        spinner.stopAnimation(nil)
        stopButton.isHidden = true
        switch result {
        case .success(let root):
            map.root = root
            updateLocation()
            window?.makeFirstResponder(map)
        case .failure(is CancellationError):
            statusField.stringValue = String(localized: "Stopped.")
            detailField.stringValue = ""
        case .failure(let error):
            statusField.stringValue = Format.error(error)
            detailField.stringValue = ""
        }
        updateButtons()
    }

    @objc private func stop() {
        guard let task = scanTask else { return }
        task.cancel()
        scanTask = nil
        spinner.stopAnimation(nil)
        stopButton.isHidden = true
        statusField.stringValue = String(localized: "Stopped.")
        detailField.stringValue = ""
        updateButtons()
    }

    @objc private func rescan() { scan() }

    // MARK: Navigation

    @objc private func goUp() { map.goUp() }

    @objc private func pathClicked() {
        guard let clicked = pathControl.clickedPathItem?.url, let root = map.root else { return }
        // Walk down from the root along the clicked folder's path components.
        let rootComponents = root.url.standardizedFileURL.pathComponents
        let target = clicked.standardizedFileURL.pathComponents
        guard target.starts(with: rootComponents) else { return }
        var path: [Int] = []
        var node = root
        for name in target.dropFirst(rootComponents.count) {
            guard let index = node.children.firstIndex(where: { $0.name == name && $0.isDirectory }) else { break }
            path.append(index)
            node = node.children[index]
        }
        map.show(path)
    }

    @objc private func showInPanel() {
        guard let main, let node = map.selectedNode ?? map.shownNode else { return }
        if node.isDirectory, !node.isPackage {
            main.activePanel.go(to: node.url)
        } else {
            main.activePanel.go(to: node.url.deletingLastPathComponent(), focusing: node.name)
        }
        main.window?.makeKeyAndOrderFront(nil)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.specialKey == nil, event.charactersIgnoringModifiers == "r", flags == .command {
            rescan()
            return true
        }
        if event.keyCode == 53 { // Esc
            if scanTask != nil { stop() } else { close() }
            return true
        }
        return false
    }

    private func updateLocation() {
        guard let node = map.shownNode else { return }
        pathControl.url = node.url
        updateButtons()
        updateStatus()
    }

    private func updateButtons(scanning: Bool = false) {
        upButton.isEnabled = !scanning && !map.location.isEmpty
        revealButton.isEnabled = !scanning && map.root != nil
        rescanButton.isEnabled = !scanning
    }

    private func updateStatus() {
        guard scanTask == nil, let shown = map.shownNode else { return }
        statusField.stringValue = String(localized: "\(shown.name): \(Format.bytes(shown.allocatedSize)) on disk, \(shown.fileCount) files")
            + (shown.isUnreadable || shown.children.contains(where: \.isUnreadable) ? "  " + String(localized: "(some folders could not be read)") : "")
        if let node = map.hoveredNode ?? map.selectedNode {
            let kind = node.isDirectory && !node.isPackage
                ? String(localized: "\(node.fileCount) files") : DiskMapKind.of(node).title
            detailField.stringValue = "\(node.url.path(percentEncoded: false))  —  \(Format.bytes(node.allocatedSize))"
                + (shown.allocatedSize > 0 ? String(format: " (%.1f %%)", Double(node.allocatedSize) * 100 / Double(shown.allocatedSize)) : "")
                + "  —  \(kind)"
        } else {
            detailField.stringValue = String(localized: "Double click enters a folder, ⌫ goes up.")
        }
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        scanTask?.cancel()
        Self.open.removeAll { $0 === self }
    }
}
