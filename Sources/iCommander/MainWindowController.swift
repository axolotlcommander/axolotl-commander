import AppKit
import CommanderCore
import OSLog

let log = Logger(subsystem: "cz.acidek.icommander", category: "app")

enum PanelSide { case left, right }

/// Owns the two panels and routes every command: panel-scope commands go to
/// the active panel, window-scope ones are handled here, the rest fall to the app.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let left = PanelViewController(side: .left)
    let right = PanelViewController(side: .right)
    private(set) var activeSide: PanelSide = .left
    private(set) lazy var operations = OperationsController(windowController: self)
    let commandLine = CommandLineBar()
    private var keyMonitor: Any?

    var activePanel: PanelViewController { activeSide == .left ? left : right }
    var inactivePanel: PanelViewController { activeSide == .left ? right : left }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "iCommander"
        window.minSize = NSSize(width: 600, height: 360)
        super.init(window: window)

        let split = NSSplitViewController()
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.splitView.autosaveName = "PanelSplit"
        for panel in [left, right] {
            panel.router = self
            let item = NSSplitViewItem(viewController: panel)
            item.minimumThickness = 240
            split.addSplitViewItem(item)
        }
        window.contentViewController = Self.container(split: split, commandLine: commandLine)
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.delegate = self
        commandLine.onExecute = { [weak self] line in self?.execute(line) }
        commandLine.onLeave = { [weak self] in self.map { $0.activate($0.activeSide) } }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.interceptKey(event) ? nil : event
        }
        activate(.left)
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
        activeSide = side
        left.isActive = side == .left
        right.isActive = side == .right
        window?.makeFirstResponder(activePanel.tableView)
        panelLocationChanged(activePanel)
    }

    func panelLocationChanged(_ panel: PanelViewController) {
        guard panel === activePanel else { return }
        window?.title = panel.model.location.path(percentEncoded: false)
        commandLine.setDirectory(panel.model.location)
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
    private var panelHasFocus: Bool {
        window?.firstResponder === activePanel.tableView
    }

    func canPerform(_ command: Command) -> Bool {
        switch CommandRegistry.spec(command).scope {
        case .app:
            return (NSApp.delegate as? AppDelegate)?.canPerform(command) ?? false
        case .panel:
            guard panelHasFocus else { return false }
            if canPerformHere(command) { return true }
            return activePanel.canPerform(command)
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
        case .switchPanel, .leftVolumeMenu, .rightVolumeMenu, .focusCommandLine,
             .insertNameToCommandLine, .insertPathToCommandLine,
             .insertLeftPathToCommandLine, .insertRightPathToCommandLine: true
        default: false
        }
    }

    private func performHere(_ command: Command) {
        switch command {
        case .switchPanel: activate(activeSide == .left ? .right : .left)
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

    // MARK: Command line

    private func insertPath(of panel: PanelViewController) {
        commandLine.insert(ShellQuote.quote(panel.model.location.path(percentEncoded: false)) + " ")
    }

    /// Keys handled before AppKit: ⌃Tab (the window would use it for key-view cycling) and,
    /// while the command line edits, the panel chords that make sense there.
    private func interceptKey(_ event: NSEvent) -> Bool {
        if commandLine.isEditing { return handleCommandLineKey(event) }
        guard panelHasFocus, let chord = KeyChord(event: event),
              KeyMap.standard.command(for: chord) == .focusCommandLine else { return false }
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
        guard let command = KeyMap.standard.command(for: chord) else { return false }
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
                do { try await Launcher.run(command, in: directory) } catch { operations.report(error) }
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
        return canPerform(command)
    }
}
