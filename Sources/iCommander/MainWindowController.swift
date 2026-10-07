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
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.delegate = self
        activate(.left)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func activate(_ side: PanelSide) {
        activeSide = side
        left.isActive = side == .left
        right.isActive = side == .right
        window?.makeFirstResponder(activePanel.tableView)
        window?.title = activePanel.model.location.path(percentEncoded: false)
    }

    func panelDidBecomeFirstResponder(_ panel: PanelViewController) {
        let side = panel === left ? PanelSide.left : .right
        if side != activeSide { activate(side) }
    }

    func panel(_ side: PanelSide) -> PanelViewController { side == .left ? left : right }

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
        case .switchPanel, .leftVolumeMenu, .rightVolumeMenu: true
        default: false
        }
    }

    private func performHere(_ command: Command) {
        switch command {
        case .switchPanel: activate(activeSide == .left ? .right : .left)
        case .leftVolumeMenu: activate(.left); left.perform(.leftVolumeMenu)
        case .rightVolumeMenu: activate(.right); right.perform(.rightVolumeMenu)
        default: break
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
