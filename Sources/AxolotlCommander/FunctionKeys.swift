// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Whether F1–F12 reach the app without `fn`. The system setting is only read, never written:
/// the app cannot and must not change how the keyboard's media keys behave.
enum FunctionKeys {
    private static let noticeKey = "functionKeyNotice"

    /// "Use F1, F2, etc. keys as standard function keys" in System Settings → Keyboard.
    static var areStandard: Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let value = CFPreferencesCopyAppValue("com.apple.keyboard.fnState" as CFString, kCFPreferencesAnyApplication)
        return (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false
    }

    static func openKeyboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Once (at most twice) after launch, when function keys need `fn`: explains it and offers
    /// System Settings.
    static func showNoticeIfNeeded(in window: NSWindow) {
        let defaults = UserDefaults.standard
        var notice = defaults.data(forKey: noticeKey)
            .flatMap { try? JSONDecoder().decode(FunctionKeyNotice.self, from: $0) } ?? FunctionKeyNotice()
        guard notice.shouldShow(standardFunctionKeys: areStandard) else { return }
        notice.recordShown()
        save(notice)

        let alert = NSAlert()
        alert.messageText = String(localized: "Function keys need the fn key")
        alert.informativeText = String(localized: """
            On this Mac, F1–F12 control brightness, volume and media, so commands like F5 Copy work \
            only while you hold fn. To use them directly, turn on "Use F1, F2, etc. keys as standard \
            function keys" in System Settings → Keyboard → Keyboard Shortcuts → Function Keys. The \
            buttons at the bottom of the window work either way.
            """)
        alert.addButton(withTitle: String(localized: "Open Keyboard Settings"))
        alert.addButton(withTitle: String(localized: "Don't Show Again"))
        let close = alert.addButton(withTitle: String(localized: "Close"))
        close.keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { response in
            switch response {
            case .alertFirstButtonReturn: openKeyboardSettings()
            case .alertSecondButtonReturn:
                notice.suppress()
                save(notice)
            default: break
            }
        }
    }

    private static func save(_ notice: FunctionKeyNotice) {
        UserDefaults.standard.set(try? JSONEncoder().encode(notice), forKey: noticeKey)
    }
}
