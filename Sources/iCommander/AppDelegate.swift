import AppKit
import CommanderCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var mainWindow: MainWindowController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The commander has its own panel tabs; system window tabs would only confuse the Window menu.
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = MainMenuBuilder.build()
        MainMenuBuilder.trackKeyWindow()
        RemoteSetup.configure()
        let controller = MainWindowController()
        controller.showWindow(nil)
        mainWindow = controller
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Back from the editor: changed copies of archive members are offered back to their archives.
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await ArchiveEdits.shared.offerChanges() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ArchiveEdits.shared.hasChanges else { return .terminateNow }
        Task {
            await ArchiveEdits.shared.offerChanges()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        ArchiveScratch.removeAll()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: App-scope commands (end of the responder chain)

    @objc func performCommand(_ sender: Any?) {
        guard let command = (sender as? NSMenuItem)?.command else { return }
        perform(command)
    }

    func canPerform(_ command: Command) -> Bool {
        switch command {
        case .about, .settings, .quit: true
        default: false
        }
    }

    func perform(_ command: Command) {
        switch command {
        case .about: NSApp.orderFrontStandardAboutPanel(nil)
        case .settings: showSettings()
        case .quit: NSApp.terminate(nil)
        default: break
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.command else { return true }
        return canPerform(command)
    }

    func showSettings(tab: SettingsTab? = nil) {
        if let tab { UserDefaults.standard.set(tab.rawValue, forKey: "settings.tab") }
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = String(localized: "Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
