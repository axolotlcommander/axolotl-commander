// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

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
        // Panels offer their files to Services (also in the context menu).
        NSApp.registerServicesMenuSendTypes([.fileURL], returnTypes: [])
        RemoteSetup.configure()
        let controller = MainWindowController()
        controller.showWindow(nil)
        mainWindow = controller
        NSApp.activate()
        Task { await ArchiveEdits.shared.offerPendingFromLastTime() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Back from the editor: changed copies of archive members are offered back to their archives.
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await ArchiveEdits.shared.offerChanges() }
    }

    /// Changed copies are offered back first; whatever stays unsaved is kept for the next launch.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let edits = ArchiveEdits.shared
        guard edits.hasChanges else {
            edits.finishForQuit()
            return .terminateNow
        }
        Task {
            await edits.offerChanges()
            edits.finishForQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Only temporary copies (view, open, compare); edited copies are in ArchiveEdits.store.
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
        case .about, .settings, .quit, .configureKeys: true
        default: false
        }
    }

    func perform(_ command: Command) {
        switch command {
        case .about: NSApp.orderFrontStandardAboutPanel(nil)
        case .settings: showSettings()
        case .configureKeys: showSettings(tab: .keyboard)
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
