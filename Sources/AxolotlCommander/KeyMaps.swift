// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The key maps in use: factory chords, the key scheme and the user's changes (Settings → Keyboard).
enum KeyMaps {
    static let defaultsKey = "keys.bindings"
    static let schemeKey = "keys.scheme"
    static let didChange = Notification.Name("KeyBindingsDidChange")

    private(set) static var bindings: KeyBindings = saved()
    private(set) static var panel = KeyMap(context: .panel, bindings: bindings)
    private(set) static var viewer = KeyMap(context: .viewer, bindings: bindings)
    private(set) static var find = KeyMap(context: .find, bindings: bindings)
    private(set) static var compare = KeyMap(context: .compare, bindings: bindings)

    /// The stored overrides on top of the stored scheme; missing or unknown values are the defaults.
    private static func saved() -> KeyBindings {
        let defaults = UserDefaults.standard
        var bindings = defaults.data(forKey: defaultsKey)
            .flatMap { try? JSONDecoder().decode(KeyBindings.self, from: $0) } ?? .factory
        bindings.scheme = defaults.string(forKey: schemeKey).flatMap(KeyScheme.init(rawValue:)) ?? .axolotl
        return bindings
    }

    static func map(for context: CommandContext) -> KeyMap {
        switch context {
        case .panel: panel
        case .viewer: viewer
        case .find: find
        case .compare: compare
        }
    }

    /// Stores new bindings and updates the maps and the menu bar.
    static func update(_ new: KeyBindings) {
        guard new != bindings else { return }
        bindings = new
        let defaults = UserDefaults.standard
        if new.overrides.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(try? JSONEncoder().encode(new), forKey: defaultsKey)
        }
        if new.scheme == .axolotl {
            defaults.removeObject(forKey: schemeKey)
        } else {
            defaults.set(new.scheme.rawValue, forKey: schemeKey)
        }
        rebuild()
    }

    /// Reads the stored scheme and overrides again (after a settings import wrote them).
    static func reload() {
        let stored = saved()
        guard stored != bindings else { return }
        bindings = stored
        rebuild()
    }

    private static func rebuild() {
        panel = KeyMap(context: .panel, bindings: bindings)
        viewer = KeyMap(context: .viewer, bindings: bindings)
        find = KeyMap(context: .find, bindings: bindings)
        compare = KeyMap(context: .compare, bindings: bindings)
        MainMenuBuilder.refreshKeyEquivalents()
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// The chord a menu item shows for `command`: its first menu-safe effective chord.
    static func menuChord(for command: Command, in context: CommandContext) -> KeyChord? {
        map(for: context).chords(for: command).first(where: \.isMenuSafe)
    }

    /// The menu bar already answers `chord` for `command` (its item shows that chord), so a window's
    /// own key handling must leave it alone. Further chords of the command (F2 next to ⌃W…) are not.
    static func menuHandles(_ chord: KeyChord, for command: Command, in context: CommandContext) -> Bool {
        CommandRegistry.spec(command).menu != nil && menuChord(for: command, in: context) == chord
    }
}
