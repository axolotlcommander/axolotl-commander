import AppKit
import CommanderCore
import OSLog

let log = Logger(subsystem: "cz.acidek.icommander", category: "app")

enum PanelSide { case left, right }

/// Owns the two panels and routes every command: panel-scope commands go to
/// the active panel, window-scope ones are handled here, the rest fall to the app.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let left: PanelViewController
    let right: PanelViewController
    private(set) var activeSide: PanelSide = .left
    private(set) lazy var operations = OperationsController(windowController: self)
    let commandLine = CommandLineBar()
    private var keyMonitor: Any?
    private let split = PanelSplitViewController()
    /// The panel shown alone (⌃F11), or nil when both are visible.
    private(set) var maximizedSide: PanelSide?
    private var saveTask: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    var activePanel: PanelViewController { activeSide == .left ? left : right }
    var inactivePanel: PanelViewController { activeSide == .left ? right : left }

    init() {
        let layout = Self.loadLayout()
        left = PanelViewController(side: .left, tabs: layout.left)
        right = PanelViewController(side: .right, tabs: layout.right)
        left.viewMode = layout.leftMode
        right.viewMode = layout.rightMode
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "iCommander"
        window.minSize = NSSize(width: 600, height: 360)
        super.init(window: window)

        for panel in [left, right] {
            panel.router = self
            let item = NSSplitViewItem(viewController: panel)
            item.minimumThickness = 240
            item.canCollapse = true
            split.addSplitViewItem(item)
        }
        window.contentViewController = Self.container(split: split, commandLine: commandLine)
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.delegate = self
        window.toolbar = MainToolbar.make(delegate: self)
        window.toolbarStyle = .unifiedCompact
        commandLine.onExecute = { [weak self] line in self?.execute(line) }
        commandLine.onLeave = { [weak self] in self.map { $0.activate($0.activeSide) } }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.interceptKey(event) ? nil : event
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: split.splitView,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutChanged() }
        })
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveLayout() }
        })
        split.view.layoutSubtreeIfNeeded()
        split.splitView.setPosition(((split.splitView.bounds.width - split.splitView.dividerThickness)
                                     * layout.splitFraction).rounded(), ofDividerAt: 0)
        activate(layout.activeSide == .left ? .left : .right)
        if let maximized = layout.maximized { setMaximized(maximized == .left ? .left : .right) }
    }

    /// Panels on top, the command line across the whole window below them.
    private static func container(split: NSSplitViewController, commandLine: CommandLineBar) -> NSViewController {
        let container = NSViewController()
        container.view = NSView()
        container.addChild(split)
        let separator = NSBox()
        separator.boxType = .separator
        let stack = NSStackView(views: [split.view, separator, commandLine])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        split.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        commandLine.setContentHuggingPriority(.required, for: .vertical)
        container.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
            split.view.widthAnchor.constraint(equalTo: stack.widthAnchor),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            commandLine.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return container
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func activate(_ side: PanelSide) {
        // The hidden panel cannot take focus; showing it again ends maximization.
        if let maximizedSide, maximizedSide != side { setMaximized(nil) }
        activeSide = side
        layoutChanged()
        left.isActive = side == .left
        right.isActive = side == .right
        window?.makeFirstResponder(activePanel.listView)
        panelLocationChanged(activePanel)
    }

    func panelLocationChanged(_ panel: PanelViewController) {
        guard panel === activePanel else { return }
        window?.title = panel.model.results.map { "\($0.title) — \(panel.model.location.displayPath)" }
            ?? panel.model.location.displayPath
        commandLine.setDirectory(panel.diskFolder)
    }

    func panelDidBecomeFirstResponder(_ panel: PanelViewController) {
        let side = panel === left ? PanelSide.left : .right
        if side != activeSide { activate(side) }
    }

    func panel(_ side: PanelSide) -> PanelViewController { side == .left ? left : right }

    func otherPanel(than panel: PanelViewController) -> PanelViewController { panel === left ? right : left }

    func refreshPanels() async {
        await left.model.refresh()
        await right.model.refresh()
    }

    // MARK: Routing

    /// True when a panel table (not a text field) has keyboard focus.
    var panelHasFocus: Bool {
        window?.firstResponder === activePanel.listView
    }

    func canPerform(_ command: Command) -> Bool {
        if CommandRegistry.spec(command).scope == .panel, !panelHasFocus { return false }
        return canPerformIgnoringFocus(command)
    }

    /// Availability as if the active panel had focus (toolbar buttons focus it before performing).
    func canPerformIgnoringFocus(_ command: Command) -> Bool {
        switch CommandRegistry.spec(command).scope {
        case .app: (NSApp.delegate as? AppDelegate)?.canPerform(command) ?? false
        case .panel: canPerformHere(command) || activePanel.canPerform(command)
        case .viewer, .find, .compare: false
        }
    }

    func perform(_ command: Command) {
        guard canPerform(command) else {
            log.debug("command \(command.rawValue) not available")
            return
        }
        if CommandRegistry.spec(command).scope == .app {
            (NSApp.delegate as? AppDelegate)?.perform(command)
        } else if canPerformHere(command) {
            performHere(command)
        } else {
            activePanel.perform(command)
        }
    }

    private func canPerformHere(_ command: Command) -> Bool {
        switch command {
        case .switchPanel, .leftVolumeMenu, .rightVolumeMenu, .focusCommandLine, .maximizePanel, .comparePanels,
             .insertNameToCommandLine, .insertPathToCommandLine,
             .insertLeftPathToCommandLine, .insertRightPathToCommandLine: true
        default: false
        }
    }

    private func performHere(_ command: Command) {
        switch command {
        case .switchPanel: activate(activeSide == .left ? .right : .left)
        case .maximizePanel: setMaximized(maximizedSide == nil ? activeSide : nil)
        case .comparePanels: CompareSheet.show(in: window) { [weak self] in self?.comparePanels() }
        case .leftVolumeMenu: activate(.left); left.perform(.leftVolumeMenu)
        case .rightVolumeMenu: activate(.right); right.perform(.rightVolumeMenu)
        case .focusCommandLine:
            if commandLine.isEditing { activate(activeSide) } else { commandLine.focus() }
        case .insertNameToCommandLine:
            if let item = activePanel.model.cursorItem { commandLine.insert(ShellQuote.quote(item.isParent ? ".." : item.name) + " ") }
        case .insertPathToCommandLine: insertPath(of: activePanel)
        case .insertLeftPathToCommandLine: insertPath(of: left)
        case .insertRightPathToCommandLine: insertPath(of: right)
        default: break
        }
    }

    // MARK: Layout

    private static let layoutKey = "window.layout"

    /// Saved layout, or one built from the stage 1–4 per-panel defaults.
    private static func loadLayout() -> WindowLayout {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: layoutKey), let layout = WindowLayout.decode(data) { return layout }
        func legacy(_ side: String) -> TabList {
            let path = defaults.string(forKey: "panel.\(side).path")
            var state = PanelState(location: path.map { URL(filePath: $0, directoryHint: .isDirectory) }
                                   ?? FileManager.default.homeDirectoryForCurrentUser)
            if let raw = defaults.data(forKey: "panel.\(side).sort"),
               let sort = try? JSONDecoder().decode(SortSpec.self, from: raw) { state.sort = sort }
            return TabList(state)
        }
        return WindowLayout(left: legacy("left"), right: legacy("right"))
    }

    /// Something worth persisting changed; saved shortly after, coalescing bursts.
    func layoutChanged() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            saveLayout()
        }
    }

    func saveLayout() {
        let splitView = split.splitView
        let total = splitView.bounds.width - splitView.dividerThickness
        var fraction = 0.5
        if maximizedSide == nil, total > 0, let first = splitView.arrangedSubviews.first {
            fraction = first.frame.width / total
        } else if let data = UserDefaults.standard.data(forKey: Self.layoutKey),
                  let previous = WindowLayout.decode(data) {
            fraction = previous.splitFraction
        }
        let layout = WindowLayout(left: left.tabs, right: right.tabs, leftMode: left.viewMode, rightMode: right.viewMode,
                                  activeSide: activeSide == .left ? .left : .right,
                                  maximized: maximizedSide.map { $0 == .left ? .left : .right },
                                  splitFraction: fraction)
        UserDefaults.standard.set(layout.encoded(), forKey: Self.layoutKey)
    }

    /// ⌃F11: shows the active panel alone; the next press brings the other one back.
    func setMaximized(_ side: PanelSide?) {
        if maximizedSide == nil, side != nil { saveLayout() }  // keep the divider position
        maximizedSide = side
        layoutChanged()
        split.splitViewItems[0].animator().isCollapsed = side == .right
        split.splitViewItems[1].animator().isCollapsed = side == .left
    }

    /// ⌃F10: marks what is missing or differs on the other side (names, sizes, dates).
    private func comparePanels() {
        if maximizedSide != nil { setMaximized(nil) }
        let rules = left.model.rules.caseSensitive && right.model.rules.caseSensitive ? left.model.rules : .apfsDefault
        let result = PanelComparison.compare(left: left.model.items, right: right.model.items,
                                             options: AppSettings.shared.comparison, rules: rules)
        left.model.setSelection(names: result.left)
        right.model.setSelection(names: result.right)
        if result.isIdentical {
            let alert = NSAlert()
            alert.messageText = String(localized: "The folders match")
            alert.informativeText = String(localized: "Both panels contain the same files.")
            if let window { alert.beginSheetModal(for: window) }
        }
    }

    // MARK: Command line

    private func insertPath(of panel: PanelViewController) {
        commandLine.insert(ShellQuote.quote(panel.model.location.displayPath) + " ")
    }

    /// Keys handled before AppKit: ⌃Tab (the window would use it for key-view cycling) and,
    /// while the command line edits, the panel chords that make sense there.
    private func interceptKey(_ event: NSEvent) -> Bool {
        if commandLine.isEditing { return handleCommandLineKey(event) }
        guard panelHasFocus, let chord = KeyChord(event: event),
              KeyMaps.panel.command(for: chord) == .focusCommandLine else { return false }
        commandLine.focus()
        return true
    }

    /// Keys while the command line edits: panel chords that make sense there; the rest is text.
    private func handleCommandLineKey(_ event: NSEvent) -> Bool {
        guard let chord = KeyChord(event: event) else { return false }
        switch (chord.key, chord.modifiers) {
        case (.enter, .shift):
            // Shift+Enter works on the panel item, as in the Windows commander.
            activate(activeSide)
            activePanel.perform(.open)
            return true
        case (.up, .control): commandLine.showOlder(); return true
        case (.down, .control): commandLine.showNewer(); return true
        default: break
        }
        guard let command = KeyMaps.panel.command(for: chord) else { return false }
        switch command {
        case .focusCommandLine, .insertNameToCommandLine, .insertPathToCommandLine,
             .insertLeftPathToCommandLine, .insertRightPathToCommandLine:
            performHere(command)
            return true
        default:
            return false
        }
    }

    private func execute(_ line: String) {
        let panel = activePanel
        let directory = panel.model.location
        switch CommandInput.parse(line, in: directory, home: FileManager.default.homeDirectoryForCurrentUser) {
        case .none:
            // Enter on an empty line opens the panel item.
            activate(activeSide)
            panel.perform(.open)
        case .changeDirectory(let url):
            commandLine.commit(line)
            panel.go(to: url)
        case .back:
            commandLine.commit(line)
            panel.perform(.goBack)
        case .open(let url):
            commandLine.commit(line)
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true, values?.isPackage != true {
                panel.go(to: url)
            } else {
                NSWorkspace.shared.open(url)
            }
        case .run(let command):
            commandLine.commit(line)
            Task {
                do { try await Launcher.run(command, in: panel.diskFolder) } catch { operations.report(error) }
            }
        case .invalid(let error):
            NSSound.beep()
            operations.report(error)
        }
    }

    // MARK: Responder chain entry points

    @objc func performCommand(_ sender: Any?) {
        guard let command = (sender as? NSMenuItem)?.command else { return }
        perform(command)
    }

    @objc func copy(_ sender: Any?) { perform(.copyFiles) }
    @objc func paste(_ sender: Any?) { perform(.pasteFiles) }
    @objc override func selectAll(_ sender: Any?) { perform(.selectAll) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.command else { return true }
        if command == .toggleHidden { menuItem.state = activePanel.showsHidden ? .on : .off }
        if command == .viewModeDetailed { menuItem.state = activePanel.viewMode == .detailed ? .on : .off }
        if command == .viewModeBrief { menuItem.state = activePanel.viewMode == .brief ? .on : .off }
        if command == .maximizePanel { menuItem.title = maximizedSide == nil ? CommandRegistry.spec(.maximizePanel).localizedTitle
                                                  : String(localized: "Restore Panels") }
        return canPerform(command)
    }
}
