// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// Keys no command can get (spec 034): fixed menu items, keys macOS keeps for itself and the keys the
/// panel handles before its shortcuts.
public enum FixedKey: Equatable, Sendable {
    /// Main menu items with a key that are not in the command list.
    public enum MenuItem: Equatable, Sendable { case closeWindow, minimize, minimizeAll, hide, undo, redo }
    /// Keys macOS never passes to an app.
    public enum SystemKey: Equatable, Sendable { case switchApps, switchAppsBack, forceQuit, lockScreen, logOut }

    case menu(MenuItem)
    case system(SystemKey)
    /// ↑ ↓ ← → Page Up / Down, Home, End, alone or with ⇧: they move the panel cursor (and mark with ⇧).
    case panelMovement

    private static let menuKeys: [KeyChord: MenuItem] = [
        KeyChord(.character("w"), .command): .closeWindow,
        KeyChord(.character("m"), .command): .minimize,
        KeyChord(.character("m"), [.option, .command]): .minimizeAll,
        KeyChord(.character("h"), .command): .hide,
        KeyChord(.character("z"), .command): .undo,
        KeyChord(.character("z"), [.shift, .command]): .redo,
    ]

    private static let systemKeys: [KeyChord: SystemKey] = [
        KeyChord(.tab, .command): .switchApps,
        KeyChord(.tab, [.shift, .command]): .switchAppsBack,
        KeyChord(.escape, [.option, .command]): .forceQuit,
        KeyChord(.character("q"), [.control, .command]): .lockScreen,
        KeyChord(.character("q"), [.shift, .command]): .logOut,
    ]

    private static let movementKeys: Set<KeyChord.Key> = [.up, .down, .left, .right, .pageUp, .pageDown, .home, .end]

    /// The fixed use of `chord` in `context`, if any.
    public static func of(_ chord: KeyChord, in context: CommandContext) -> FixedKey? {
        if let item = menuKeys[chord] { return .menu(item) }
        if let key = systemKeys[chord] { return .system(key) }
        if context == .panel, movementKeys.contains(chord.key), chord.modifiers.isSubset(of: .shift) { return .panelMovement }
        return nil
    }
}

/// A macOS keyboard shortcut (System Settings → Keyboard → Keyboard Shortcuts) that is on.
public struct SystemShortcut: Equatable, Sendable {
    /// The macOS feature; the raw value is its identifier in the system's shortcut preference.
    public enum Feature: Int, Sendable, CaseIterable {
        case menuBar = 7, dock = 8, activeWindow = 9, toolbar = 10, floatingWindow = 11, tabMovesFocus = 12
        case keyboardNavigation = 13, nextWindow = 27
        case screenshot = 28, screenshotToClipboard = 29, screenshotArea = 30, screenshotAreaToClipboard = 31
        case missionControl = 32, applicationWindows = 33, showDesktop = 36, dockHiding = 52, statusMenus = 57
        case previousInputSource = 60, nextInputSource = 61, spotlight = 64, finderSearch = 65
        case spaceLeft = 79, spaceRight = 81, helpMenu = 98, accessibilityControls = 162, screenshotOptions = 184
    }

    public let feature: Feature
    public let chord: KeyChord

    public init(_ feature: Feature, _ chord: KeyChord) {
        self.feature = feature
        self.chord = chord
    }
}

public enum SystemShortcuts {
    /// The macOS defaults of the shortcuts the app knows.
    public static let defaults: [SystemShortcut] = {
        typealias K = KeyChord
        let c: K.Modifiers = .control
        return [
            SystemShortcut(.keyboardNavigation, K(.function(1), c)),
            SystemShortcut(.menuBar, K(.function(2), c)),
            SystemShortcut(.dock, K(.function(3), c)),
            SystemShortcut(.activeWindow, K(.function(4), c)),
            SystemShortcut(.toolbar, K(.function(5), c)),
            SystemShortcut(.floatingWindow, K(.function(6), c)),
            SystemShortcut(.tabMovesFocus, K(.function(7), c)),
            SystemShortcut(.statusMenus, K(.function(8), c)),
            SystemShortcut(.nextWindow, K(.character("`"), .command)),
            SystemShortcut(.screenshot, K(.character("3"), [.shift, .command])),
            SystemShortcut(.screenshotToClipboard, K(.character("3"), [.control, .shift, .command])),
            SystemShortcut(.screenshotArea, K(.character("4"), [.shift, .command])),
            SystemShortcut(.screenshotAreaToClipboard, K(.character("4"), [.control, .shift, .command])),
            SystemShortcut(.screenshotOptions, K(.character("5"), [.shift, .command])),
            SystemShortcut(.missionControl, K(.up, c)),
            SystemShortcut(.applicationWindows, K(.down, c)),
            SystemShortcut(.spaceLeft, K(.left, c)),
            SystemShortcut(.spaceRight, K(.right, c)),
            SystemShortcut(.showDesktop, K(.function(11))),
            SystemShortcut(.dockHiding, K(.character("d"), [.option, .command])),
            SystemShortcut(.previousInputSource, K(.space, c)),
            SystemShortcut(.nextInputSource, K(.space, [.control, .option])),
            SystemShortcut(.spotlight, K(.space, .command)),
            SystemShortcut(.finderSearch, K(.space, [.option, .command])),
            SystemShortcut(.helpMenu, K(.character("/"), [.shift, .command])),
            SystemShortcut(.accessibilityControls, K(.function(5), [.option, .command])),
        ]
    }()

    /// The shortcuts that are on, after the user's changes stored by macOS (`AppleSymbolicHotKeys` of
    /// `com.apple.symbolichotkeys`). The preference lists only changed shortcuts; a missing or malformed
    /// entry keeps the default, a turned-off one or one without a key is left out.
    public static func current(from hotKeys: [String: Any]?) -> [SystemShortcut] {
        defaults.compactMap { shortcut in
            guard let entry = hotKeys?[String(shortcut.feature.rawValue)] as? [String: Any] else { return shortcut }
            guard let enabled = number(entry["enabled"]) else { return shortcut }
            if enabled == 0 { return nil }
            guard let value = entry["value"] as? [String: Any] else { return shortcut }
            guard let parameters = value["parameters"] as? [Any], parameters.count >= 3,
                  let character = number(parameters[0]), let keyCode = number(parameters[1]),
                  let mask = number(parameters[2]) else { return shortcut }
            // 65535 everywhere: the shortcut has no key.
            if character == 65535, keyCode == 65535 { return nil }
            guard let chord = chord(character: character, keyCode: keyCode, modifierMask: mask) else { return shortcut }
            return SystemShortcut(shortcut.feature, chord)
        }
    }

    private static func number(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: int
        case let bool as Bool: bool ? 1 : 0
        case let double as Double: Int(exactly: double)
        default: nil
        }
    }

    private static let keyCodes: [Int: KeyChord.Key] = [
        122: .function(1), 120: .function(2), 99: .function(3), 118: .function(4), 96: .function(5),
        97: .function(6), 98: .function(7), 100: .function(8), 101: .function(9), 109: .function(10),
        103: .function(11), 111: .function(12), 105: .function(13), 107: .function(14), 113: .function(15),
        106: .function(16), 64: .function(17), 79: .function(18), 80: .function(19), 90: .function(20),
        126: .up, 125: .down, 123: .left, 124: .right, 115: .home, 119: .end, 116: .pageUp, 121: .pageDown,
        48: .tab, 36: .enter, 49: .space, 53: .escape, 51: .backspace, 117: .forwardDelete,
    ]

    /// A chord from the system's parameters: character code (65535 = none), virtual key code and the
    /// modifier mask (⇧ 0x20000, ⌃ 0x40000, ⌥ 0x80000, ⌘ 0x100000; the fn bit of arrows and F-keys is ignored).
    public static func chord(character: Int, keyCode: Int, modifierMask: Int) -> KeyChord? {
        var modifiers: KeyChord.Modifiers = []
        if modifierMask & 0x20000 != 0 { modifiers.insert(.shift) }
        if modifierMask & 0x40000 != 0 { modifiers.insert(.control) }
        if modifierMask & 0x80000 != 0 { modifiers.insert(.option) }
        if modifierMask & 0x100000 != 0 { modifiers.insert(.command) }
        if let key = keyCodes[keyCode] { return KeyChord(key, modifiers) }
        guard character != 65535, character > 32, let scalar = Unicode.Scalar(character) else { return nil }
        guard let lower = String(Character(scalar)).lowercased().first else { return nil }
        return KeyChord(.character(lower), modifiers)
    }
}

/// Checks a key before it is given to a command in Settings → Keyboard (spec 034).
public enum ShortcutCheck {
    /// Why a key is refused or needs the user's decision.
    public enum Reason: Equatable, Sendable {
        /// Refused: a fixed key.
        case fixed(FixedKey)
        /// Refused: the panel types this character into the command line (`commandLine`) or quick search.
        case typedInPanel(commandLine: Bool)
        /// These commands lose the key when it is moved.
        case commands([Command])
        /// User Menu items with the key (their titles); they run first in the panel.
        case userMenu([String])
        /// macOS takes the key while this shortcut is on.
        case system(SystemShortcut)
        /// ⌥ + character no longer starts quick search.
        case optionQuickSearch

        public var refuses: Bool {
            switch self {
            case .fixed, .typedInPanel: true
            default: false
            }
        }
    }

    public enum Result: Equatable, Sendable {
        case clean
        case refused(Reason)
        case warnings([Reason])
    }

    /// What the check knows besides the key bindings.
    public struct Situation: Sendable {
        public var context: CommandContext
        public var typingToCommandLine: Bool
        public var system: [SystemShortcut]
        public var userMenu: [UserMenuItem]

        public init(context: CommandContext, typingToCommandLine: Bool, system: [SystemShortcut] = [],
                    userMenu: [UserMenuItem] = []) {
            self.context = context
            self.typingToCommandLine = typingToCommandLine
            self.system = system
            self.userMenu = userMenu
        }
    }

    /// The check of `chord` for `command` (the command the user records a key for).
    public static func check(_ chord: KeyChord, for command: Command, bindings: KeyBindings,
                             situation: Situation) -> Result {
        if bindings.chords(for: command).contains(chord) { return .clean }
        var reasons = reasons(chord, situation: situation)
        if let refusal = reasons.first(where: \.refuses) { return .refused(refusal) }
        let others = bindings.conflicts(chord, for: command)
        if !others.isEmpty { reasons.insert(.commands(others), at: 0) }
        if situation.context == .panel {
            let items = UserMenuStore.commands(in: situation.userMenu).filter { $0.shortcut == chord }
            if !items.isEmpty { reasons.insert(.userMenu(items.map { $0.title.isEmpty ? $0.program : $0.title }), at: others.isEmpty ? 0 : 1) }
        }
        return reasons.isEmpty ? .clean : .warnings(reasons)
    }

    /// The reasons that do not depend on other commands: fixed keys, typed characters, macOS shortcuts and
    /// ⌥ + character (the User Menu editor shows them as warnings).
    public static func reasons(_ chord: KeyChord, situation: Situation) -> [Reason] {
        if let fixed = FixedKey.of(chord, in: situation.context) { return [.fixed(fixed)] }
        var reasons: [Reason] = []
        if situation.context == .panel, case .character = chord.key {
            if chord.modifiers.isSubset(of: .shift) { return [.typedInPanel(commandLine: situation.typingToCommandLine)] }
            if situation.typingToCommandLine, chord.modifiers.contains(.option),
               chord.modifiers.isDisjoint(with: [.command, .control]) {
                reasons.append(.optionQuickSearch)
            }
        }
        if let system = situation.system.first(where: { $0.chord == chord }) { reasons.insert(.system(system), at: 0) }
        return reasons
    }

    /// Why an assigned chord cannot run: a fixed key, a typed character, or a macOS shortcut that is on.
    public static func problem(_ chord: KeyChord, situation: Situation) -> Reason? {
        reasons(chord, situation: situation).first { reason in
            switch reason {
            case .fixed, .typedInPanel, .system: true
            default: false
            }
        }
    }
}
