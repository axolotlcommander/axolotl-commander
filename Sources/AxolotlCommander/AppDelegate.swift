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
        if let window = controller.window {
            DispatchQueue.main.async { FunctionKeys.showNoticeIfNeeded(in: window) }
        }
        Task { await ArchiveEdits.shared.offerPendingFromLastTime() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Back from the editor: changed copies of archive members are offered back to their archives.
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await ArchiveEdits.shared.offerChanges() }
    }

    /// A running file operation is stopped only after asking (quitting in the middle of a move
    /// would leave it half done). Changed copies are offered back first; whatever stays unsaved
    /// is kept for the next launch.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let edits = ArchiveEdits.shared
        let busy = NSApp.windows.compactMap { ($0.windowController as? MainWindowController)?.operations }
            .filter(\.isBusy)
        guard edits.hasChanges || !busy.isEmpty else {
            edits.finishForQuit()
            return .terminateNow
        }
        Task {
            if let first = busy.first {
                guard await Self.confirmQuit(in: first.window) else {
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
                for operations in busy { await operations.stopAll() }
            }
            if edits.hasChanges { await edits.offerChanges() }
            edits.finishForQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Cancel is the default: Return must not interrupt an operation by accident.
    private static func confirmQuit(in window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "A file operation is still running.")
        alert.informativeText = String(localized: "Quitting stops it; items it has not finished stay as they are now.")
        let quit = alert.addButton(withTitle: String(localized: "Stop and Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        quit.keyEquivalent = ""
        alert.buttons[1].keyEquivalent = "\r"
        return await OperationsController.present(alert, in: window) == .alertFirstButtonReturn
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
        case .about, .settings, .quit, .configureKeys, .help: true
        default: false
        }
    }

    func perform(_ command: Command) {
        switch command {
        case .about: NSApp.orderFrontStandardAboutPanel(nil)
        case .settings: showSettings()
        case .configureKeys: showSettings(tab: .keyboard)
        case .quit: NSApp.terminate(nil)
        // There is no built-in help yet: the project page explains the app.
        case .help: NSWorkspace.shared.open(Self.helpURL)
        default: break
        }
    }

    static let helpURL = URL(string: "https://github.com/axolotlcommander/axolotl-commander#readme")!

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let command = menuItem.command else { return true }
        return canPerform(command)
    }

    func showSettings(tab: SettingsTab? = nil) {
        if let tab { UserDefaults.standard.set(tab.rawValue, forKey: "settings.tab") }
        if settingsWindow == nil {
            let window = SettingsWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = String(localized: "Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Esc closes Settings wherever the focus is: a focused checkbox or button keeps Esc from
/// SwiftUI's exit command. A field that is composing text (an input method) keeps its own Esc.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection([.shift, .control, .option, .command]).isEmpty,
           (firstResponder as? NSTextView)?.hasMarkedText() != true {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
