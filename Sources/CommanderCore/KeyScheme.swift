// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// A built-in set of chord changes over the factory chords in `CommandRegistry`. The user's own
/// changes (`KeyBindings.overrides`) apply on top of the selected scheme.
public enum KeyScheme: String, CaseIterable, Hashable, Sendable {
    /// The app's own keys: no changes.
    case axolotl
    /// Keys as classic two-panel file managers use them (tabs on ⌃T/⌃W, ⌃F2 detailed view, …).
    case classicCommander

    /// Commands whose chords this scheme replaces, with their full new chord lists in order (the
    /// first menu-safe chord is the menu's). Later features add their entries here.
    public var changes: [Command: [KeyChord]] {
        switch self {
        case .axolotl: [:]
        case .classicCommander: Self.classicCommanderChanges
        }
    }

    /// The scheme's chords for `command`: its change, otherwise the factory chords.
    public func chords(for command: Command) -> [KeyChord] {
        changes[command] ?? CommandRegistry.spec(command).chords
    }

    private static let classicCommanderChanges: [Command: [KeyChord]] = {
        typealias K = KeyChord
        let c: K.Modifiers = .control, o: K.Modifiers = .option
        let s: K.Modifiers = .shift, m: K.Modifiers = .command
        func f(_ n: Int, _ mods: K.Modifiers = []) -> K { K(.function(n), mods) }
        func ch(_ char: Character, _ mods: K.Modifiers) -> K { K(.character(char), mods) }
        return [
            .newTab: [ch("t", c), ch("t", [c, s])],
            .closeTab: [ch("w", c)],
            .closeOtherTabs: [ch("w", [c, s]), ch("w", [m, o])],
            .quickFilter: [ch("s", c), ch("f", [m, o])],
            .folderHistory: [ch("h", [c, m]), K(.down, o)],
            .makeDirectoryInOtherPanel: [f(7, s), ch("n", [m, o])],
            .changeDirectory: [ch("g", [m, s])],
            .viewCursorFile: [f(3, s), f(3, [o, s])],
            .revealInFinder: [],
            .calculateSizes: [ch("l", c), f(10, [c, s]), K(.enter, [o, s])],
            .volumeInfo: [],
            .pasteAsSymbolicLink: [ch("v", [c, m])],
            .nextTab: [K(.tab, c), K(.pageDown, [c, s])],
            .previousTab: [K(.tab, [c, s]), K(.pageUp, [c, s])],
            .focusCommandLine: [K(.down, c)],
            .goToLinkTarget: [],
            .restoreSelection: [K(.numSlash)],
            .openTerminal: [ch("/", c)],
            .viewModeDetailed: [f(2, c), ch("1", [c, o])],
            .viewModeThumbnails: [f(1, [c, s]), ch("3", [c, o])],
            .changeAttributes: [],
            .disconnect: [ch("f", [c, s]), f(12)],
            .connectToServer: [ch("k", m), ch("f", c), ch("n", c)],
            .newSymbolicLink: [f(5, [c, s]), ch("l", [c, m])],
            .saveSelection: [],
            .viewWith: [f(3, o), f(3, [c, s])],
            .quickLook: [ch("y", m)],
            .quit: [ch("q", m), f(4, o)],
        ]
    }()
}

/// Where a command's effective chords come from.
public enum ChordSource: Sendable {
    case defaults, scheme, user
}
