// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import OSLog

let log = Logger(subsystem: "cz.acidek.axolotlcommander", category: "app")

enum PanelSide { case left, right }

/// Owns the two panels and routes every command: panel-scope commands go to
/// the active panel, window-scope ones are handled here, the rest fall to the app.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let left: PanelViewController
    let right: PanelViewController
    private(set) var activeSide: PanelSide = .left
    private(set) lazy var operations = OperationsController(windowController: self)
    let commandLine = CommandLineBar()
    let functionKeyBar = FunctionKeyBarView()
    private let commandLineSeparator = NSBox()
    private let functionKeyBarSeparator = NSBox()
    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    /// Modifiers whose commands the function key bar shows (held while the window is key).
    private var barModifiers: KeyChord.Modifiers = []
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
        window.title = "Axolotl Commander"
        window.minSize = NSSize(width: 600, height: 360)
        super.init(window: window)

        for panel in [left, right] {
            panel.router = self
            let item = NSSplitViewItem(viewController: panel)
            item.minimumThickness = 240
            item.canCollapse = true
            split.addSplitViewItem(item)
        }
        window.contentViewController = container()
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.delegate = self
        window.toolbar = MainToolbar.make(delegate: self)
        window.toolbarStyle = .unifiedCompact
        commandLine.onExecute = { [weak self] line in self?.execute(line) }
        commandLine.onLeave = { [weak self] in self.map { $0.activate($0.activeSide) } }
        functionKeyBar.onClick = { [weak self] command in self?.performFromBar(command) }
        functionKeyBar.onHide = { UserDefaults.standard.set(false, forKey: Self.showFunctionKeyBarKey) }
        applyChromeSettings()
        refreshFunctionKeyBar()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            return self.interceptKey(event) ? nil : event
        }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            if let self, event.window === self.window { self.showFunctionKeys(for: KeyChord.Modifiers(flags: event.modifierFlags)) }
            return event
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSSplitView.didResizeSubviewsNotification, object: split.splitView,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutChanged() }
        })
        observers.append(center.addObserver(forName: KeyMaps.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFunctionKeyBar()
                self?.functionKeyBar.reload()
            }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyChromeSettings() }
        })
        observers.append(center.addObserver(forName: NSWindow.didUpdateNotification, object: window,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.validateFunctionKeyBar() }
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

    /// Panels on top, then the command line and the function key bar across the whole window.
    private func container() -> NSViewController {
        let container = NSViewController()
        container.view = NSView()
        container.addChild(split)
        commandLineSeparator.boxType = .separator
        functionKeyBarSeparator.boxType = .separator
        let views: [NSView] = [split.view, commandLineSeparator, commandLine, functionKeyBarSeparator, functionKeyBar]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        split.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        commandLine.setContentHuggingPriority(.required, for: .vertical)
        functionKeyBar.setContentHuggingPriority(.required, for: .vertical)
        container.view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
        ] + views.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
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

    /// Window commands that work while the command line edits too.
    private static let focusIndependent: Set<Command> = [.toggleCommandLine, .toggleFunctionKeyBar]

    func canPerform(_ command: Command) -> Bool {
        if CommandRegistry.spec(command).scope == .panel, !panelHasFocus, !Self.focusIndependent.contains(command) {
            return false
        }
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
        route(command)
    }

    /// A function key button: runs the command for the active panel like its key would, but without
    /// requiring or moving keyboard focus (the command line may keep editing).
    func performFromBar(_ command: Command) {
        guard canPerformIgnoringFocus(command) else { return }
        route(command)
    }

    private func route(_ command: Command) {
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
             .swapPanels, .sameFolderAsOther,
             .insertNameToCommandLine, .insertPathToCommandLine,
             .insertLeftPathToCommandLine, .insertRightPathToCommandLine,
             .toggleCommandLine, .toggleFunctionKeyBar: true
        case .openInLeftPanel, .openInRightPanel: activePanel.model.otherPanelTarget != nil
        default: false
        }
    }

    private func performHere(_ command: Command) {
        if Self.commandLineCommands.contains(command) { showCommandLine() }
        switch command {
        case .switchPanel: activate(activeSide == .left ? .right : .left)
        case .maximizePanel: setMaximized(maximizedSide == nil ? activeSide : nil)
        case .comparePanels: CompareSheet.show(in: window) { [weak self] in self?.comparePanels() }
        case .swapPanels:
            // ⌃U: the panels exchange their current tab (folder, cursor, selection, sort, history).
            let (leftState, rightState) = (left.model.snapshot(), right.model.snapshot())
            Task {
                await left.restoreTab(rightState)
                await right.restoreTab(leftState)
            }
        case .sameFolderAsOther:
            let other = activeSide == .left ? right : left
            if other.model.results != nil {
                Task { await activePanel.restoreTab(other.model.snapshot()) }
            } else {
                activePanel.go(to: other.model.location, focusing: other.model.cursorItem.flatMap { $0.isParent ? nil : $0.name })
            }
        case .openInLeftPanel, .openInRightPanel:
            // Always into the other panel; the arrow pointing at it also moves the focus there.
            guard let target = activePanel.model.otherPanelTarget else { return }
            let other = activeSide == .left ? right : left
            other.go(to: target.url, focusing: target.focus)
            if (command == .openInRightPanel) == (activeSide == .left) { activate(other.side) }
        case .leftVolumeMenu: activate(.left); left.perform(.leftVolumeMenu)
        case .rightVolumeMenu: activate(.right); right.perform(.rightVolumeMenu)
        case .focusCommandLine:
            if commandLine.isEditing { activate(activeSide) } else { commandLine.focus() }
        case .insertNameToCommandLine:
            if let item = activePanel.model.cursorItem { commandLine.insert(ShellQuote.quote(item.isParent ? ".." : item.name) + " ") }
        case .insertPathToCommandLine: insertPath(of: activePanel)
        case .insertLeftPathToCommandLine: insertPath(of: left)
        case .insertRightPathToCommandLine: insertPath(of: right)
        case .toggleCommandLine:
            UserDefaults.standard.set(commandLine.isHidden, forKey: Self.showCommandLineKey)
        case .toggleFunctionKeyBar:
            UserDefaults.standard.set(functionKeyBar.isHidden, forKey: Self.showFunctionKeyBarKey)
        default: break
        }
    }

    // MARK: Function key bar

    private func refreshFunctionKeyBar() {
        functionKeyBar.update(slots: FunctionKeyBar.slots(in: KeyMaps.panel, modifiers: barModifiers),
                              modifiers: barModifiers)
        validateFunctionKeyBar()
    }

    /// The bar follows the held modifiers (⌥ → Pack, Unpack…), only while the window is key.
    private func showFunctionKeys(for modifiers: KeyChord.Modifiers) {
        let shown = window?.isKeyWindow == true ? modifiers : []
        guard shown != barModifiers else { return }
        barModifiers = shown
        refreshFunctionKeyBar()
    }

    // The real state when focus comes or goes, so the bar never stays on a modifier set after ⌘Tab.
    func windowDidBecomeKey(_ notification: Notification) {
        showFunctionKeys(for: KeyChord.Modifiers(flags: NSEvent.modifierFlags))
    }

    func windowDidResignKey(_ notification: Notification) { showFunctionKeys(for: []) }

    private func validateFunctionKeyBar() {
        guard !functionKeyBar.isHidden else { return }
        functionKeyBar.validate { [unowned self] in canPerformIgnoringFocus($0) }
    }

    // MARK: Command line and function key bar visibility

    static let showCommandLineKey = "showCommandLine"
    static let showFunctionKeyBarKey = "showFunctionKeyBar"

    /// Commands that work with the command line; they show it first when it is hidden.
    private static let commandLineCommands: Set<Command> = [
        .focusCommandLine, .insertNameToCommandLine, .insertPathToCommandLine,
        .insertLeftPathToCommandLine, .insertRightPathToCommandLine,
    ]

    /// Both are shown unless the user turned them off (View menu, Settings, the bar's menu).
    private static func isShown(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    private func showCommandLine() {
        guard commandLine.isHidden else { return }
        UserDefaults.standard.set(true, forKey: Self.showCommandLineKey)
        applyChromeSettings()
    }

    private func applyChromeSettings() {
        let showCommandLine = Self.isShown(Self.showCommandLineKey)
        if commandLine.isHidden == showCommandLine {
            if !showCommandLine, commandLine.isEditing { activate(activeSide) }
            commandLine.isHidden = !showCommandLine
            commandLineSeparator.isHidden = !showCommandLine
        }
        let showBar = Self.isShown(Self.showFunctionKeyBarKey)
        if functionKeyBar.isHidden == showBar {
            functionKeyBar.isHidden = !showBar
            functionKeyBarSeparator.isHidden = !showBar
            validateFunctionKeyBar()
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
        showCommandLine()
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
        if command == .toggleCommandLine { menuItem.state = commandLine.isHidden ? .off : .on }
        if command == .toggleFunctionKeyBar { menuItem.state = functionKeyBar.isHidden ? .off : .on }
        let sortFields: [Command: SortField] = [.sortByName: .name, .sortByExtension: .ext, .sortByDate: .date, .sortBySize: .size]
        if let field = sortFields[command] { menuItem.state = activePanel.model.sort.field == field ? .on : .off }
        if command == .maximizePanel { menuItem.title = maximizedSide == nil ? CommandRegistry.spec(.maximizePanel).localizedTitle
                                                  : String(localized: "Restore Panels") }
        return canPerform(command)
    }
}
