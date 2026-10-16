// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import CommanderCore

/// The words of the shortcut checks (spec 034) and the macOS shortcuts the app reads.
enum ShortcutCheckText {
    /// The macOS shortcuts that are on now (the system preference is only read).
    static func currentSystemShortcuts() -> [SystemShortcut] {
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
        return SystemShortcuts.current(from: value as? [String: Any])
    }

    /// `keptAnyway`: the User Menu editor keeps the key, so a fixed key is described as never running.
    static func message(_ reason: ShortcutCheck.Reason, chord: KeyChord, keptAnyway: Bool = false) -> String {
        let key = chord.description
        switch reason {
        case .fixed(.menu(let item)):
            let (title, menu) = menuItem(item)
            return keptAnyway
                ? String(localized: "\(key) is the shortcut of “\(title)” in the \(menu) menu, so this item's shortcut never runs.")
                : String(localized: "\(key) is the shortcut of “\(title)” in the \(menu) menu and cannot be assigned.")
        case .fixed(.system(let systemKey)):
            return keptAnyway
                ? String(localized: "\(key) \(systemAction(systemKey)) in macOS, so this item's shortcut never runs.")
                : String(localized: "\(key) \(systemAction(systemKey)) in macOS and cannot be assigned.")
        case .fixed(.panelMovement):
            return keptAnyway
                ? String(localized: "\(key) moves the cursor in the panel, so this item's shortcut never runs.")
                : String(localized: "\(key) moves the cursor in the panel and cannot be assigned.")
        case .typedInPanel(let commandLine):
            return commandLine
                ? String(localized: "“\(key)” is typed into the command line in the panel, so the shortcut would never run.")
                : String(localized: "“\(key)” starts quick search in the panel, so the shortcut would never run.")
        case .commands(let commands):
            let names = commands.map { command in
                let spec = CommandRegistry.spec(command)
                return "\(spec.localizedTitle.replacingOccurrences(of: "…", with: "")) (\(contextName(spec.scope)))"
            }.joined(separator: ", ")
            return String(localized: "\(key) is used by \(names); moving it here removes it there.")
        case .userMenu(let titles):
            let names = titles.map { "“\($0)”" }.joined(separator: ", ")
            return titles.count == 1
                ? String(localized: "\(key) is used by the User Menu item \(names); in the panel the User Menu item runs first.")
                : String(localized: "\(key) is used by the User Menu items \(names); in the panel the User Menu items run first.")
        case .system(let shortcut):
            return String(localized: "\(key) \(featureAction(shortcut.feature)) in macOS (System Settings → Keyboard → Keyboard Shortcuts → \(section(shortcut.feature))). The app does not receive it while it is on.")
        case .optionQuickSearch:
            return String(localized: "\(key) will run this command instead of starting quick search.")
        }
    }

    static func contextName(_ scope: CommandScope) -> String {
        switch scope {
        case .app: String(localized: "All windows")
        case .panel: String(localized: "Panels")
        case .viewer: String(localized: "Viewer")
        case .find: String(localized: "Find")
        case .compare: String(localized: "Compare")
        }
    }

    private static func menuItem(_ item: FixedKey.MenuItem) -> (title: String, menu: String) {
        switch item {
        case .closeWindow: (String(localized: "Close Window"), String(localized: "Window"))
        case .minimize: (String(localized: "Minimize"), String(localized: "Window"))
        case .minimizeAll: (String(localized: "Minimize All"), String(localized: "Window"))
        case .hide: (String(localized: "Hide Axolotl Commander"), "Axolotl Commander")
        case .undo: (String(localized: "Undo"), String(localized: "Edit Menu"))
        case .redo: (String(localized: "Redo"), String(localized: "Edit Menu"))
        }
    }

    private static func systemAction(_ key: FixedKey.SystemKey) -> String {
        switch key {
        case .switchApps: String(localized: "switches apps", comment: "macOS action of ⌘Tab: “⌘Tab switches apps in macOS”")
        case .switchAppsBack: String(localized: "switches apps backwards", comment: "macOS action of ⇧⌘Tab")
        case .forceQuit: String(localized: "opens Force Quit", comment: "macOS action of ⌥⌘Esc")
        case .lockScreen: String(localized: "locks the screen", comment: "macOS action of ⌃⌘Q")
        case .logOut: String(localized: "logs out", comment: "macOS action of ⇧⌘Q")
        }
    }

    private static func featureAction(_ feature: SystemShortcut.Feature) -> String {
        switch feature {
        case .keyboardNavigation: String(localized: "turns keyboard navigation on or off", comment: "macOS shortcut action")
        case .menuBar: String(localized: "moves the focus to the menu bar", comment: "macOS shortcut action")
        case .dock: String(localized: "moves the focus to the Dock", comment: "macOS shortcut action")
        case .activeWindow: String(localized: "moves the focus to the active window", comment: "macOS shortcut action")
        case .toolbar: String(localized: "moves the focus to the window toolbar", comment: "macOS shortcut action")
        case .floatingWindow: String(localized: "moves the focus to the floating window", comment: "macOS shortcut action")
        case .tabMovesFocus: String(localized: "changes the way Tab moves the focus", comment: "macOS shortcut action")
        case .statusMenus: String(localized: "moves the focus to the status menus", comment: "macOS shortcut action")
        case .nextWindow: String(localized: "moves the focus to the next window", comment: "macOS shortcut action")
        case .screenshot: String(localized: "saves a screenshot", comment: "macOS shortcut action")
        case .screenshotToClipboard: String(localized: "copies a screenshot", comment: "macOS shortcut action")
        case .screenshotArea: String(localized: "takes a screenshot of an area", comment: "macOS shortcut action")
        case .screenshotAreaToClipboard: String(localized: "copies a screenshot of an area", comment: "macOS shortcut action")
        case .screenshotOptions: String(localized: "opens the screenshot options", comment: "macOS shortcut action")
        case .missionControl: String(localized: "opens Mission Control", comment: "macOS shortcut action")
        case .applicationWindows: String(localized: "shows the windows of the app", comment: "macOS shortcut action")
        case .spaceLeft: String(localized: "moves one space to the left", comment: "macOS shortcut action")
        case .spaceRight: String(localized: "moves one space to the right", comment: "macOS shortcut action")
        case .showDesktop: String(localized: "shows the desktop", comment: "macOS shortcut action")
        case .dockHiding: String(localized: "hides or shows the Dock", comment: "macOS shortcut action")
        case .previousInputSource: String(localized: "selects the previous input source", comment: "macOS shortcut action")
        case .nextInputSource: String(localized: "selects the next input source", comment: "macOS shortcut action")
        case .spotlight: String(localized: "opens Spotlight", comment: "macOS shortcut action")
        case .finderSearch: String(localized: "opens a Finder search window", comment: "macOS shortcut action")
        case .helpMenu: String(localized: "opens the Help menu", comment: "macOS shortcut action")
        case .accessibilityControls: String(localized: "shows the accessibility controls", comment: "macOS shortcut action")
        }
    }

    /// The section of System Settings → Keyboard → Keyboard Shortcuts.
    private static func section(_ feature: SystemShortcut.Feature) -> String {
        switch feature {
        case .keyboardNavigation, .menuBar, .dock, .activeWindow, .toolbar, .floatingWindow, .tabMovesFocus,
             .statusMenus, .nextWindow:
            String(localized: "Keyboard", comment: "Section of System Settings → Keyboard → Keyboard Shortcuts")
        case .screenshot, .screenshotToClipboard, .screenshotArea, .screenshotAreaToClipboard, .screenshotOptions:
            String(localized: "Screenshots", comment: "Section of System Settings → Keyboard → Keyboard Shortcuts")
        case .missionControl, .applicationWindows, .spaceLeft, .spaceRight, .showDesktop:
            String(localized: "Mission Control", comment: "Section of System Settings → Keyboard → Keyboard Shortcuts")
        case .dockHiding:
            String(localized: "Launchpad & Dock", comment: "Section of System Settings → Keyboard → Keyboard Shortcuts")
        case .previousInputSource, .nextInputSource:
            String(localized: "Input Sources", comment: "Section of System Settings → Keyboard → Keyboard Shortcuts")
        case .spotlight, .finderSearch:
            String(localized: "Spotlight", comment: "Section of System Settings → Keyboard → Keyboard Shortcuts")
        case .helpMenu:
            String(localized: "App Shortcuts", comment: "Section of System Settings → Keyboard → Keyboard Shortcuts")
        case .accessibilityControls:
            String(localized: "Accessibility", comment: "Section of System Settings → Keyboard → Keyboard Shortcuts")
        }
    }
}
