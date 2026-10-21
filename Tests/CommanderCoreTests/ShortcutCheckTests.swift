// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct ShortcutCheckTests {
    typealias K = KeyChord

    func situation(_ context: CommandContext = .panel, typing: Bool = false, system: [SystemShortcut] = [],
                   userMenu: [UserMenuItem] = []) -> ShortcutCheck.Situation {
        ShortcutCheck.Situation(context: context, typingToCommandLine: typing, system: system, userMenu: userMenu)
    }

    func check(_ chord: KeyChord, for command: Command = .copyFiles, bindings: KeyBindings = KeyBindings(),
               _ situation: ShortcutCheck.Situation? = nil) -> ShortcutCheck.Result {
        ShortcutCheck.check(chord, for: command, bindings: bindings, situation: situation ?? self.situation())
    }

    @Test func fixedMenuKeysAreRefusedEverywhere() {
        for context in CommandContext.allCases {
            #expect(check(K(.character("w"), .command), situation(context)) == .refused(.fixed(.menu(.closeWindow))))
        }
        #expect(check(K(.character("m"), [.option, .command])) == .refused(.fixed(.menu(.minimizeAll))))
        #expect(check(K(.character("z"), [.shift, .command])) == .refused(.fixed(.menu(.redo))))
        #expect(check(K(.tab, .command)) == .refused(.fixed(.system(.switchApps))))
        #expect(check(K(.character("q"), [.shift, .command])) == .refused(.fixed(.system(.logOut))))
    }

    @Test func movementKeysAreRefusedOnlyInThePanel() {
        #expect(check(K(.down)) == .refused(.fixed(.panelMovement)))
        #expect(check(K(.pageDown, .shift)) == .refused(.fixed(.panelMovement)))
        #expect(check(K(.left)) == .refused(.fixed(.panelMovement)))
        // ⌥↓ yields to a bound command, ⌃↓ and ⌘↓ reach the key map.
        #expect(check(K(.down, .option)) == .clean)
        #expect(check(K(.home, .command)) == .clean)
        #expect(check(K(.down), for: .viewerFind, situation(.viewer)) == .clean)
    }

    @Test func charactersTypedInThePanelAreRefused() {
        #expect(check(K(.character("q"))) == .refused(.typedInPanel(commandLine: false)))
        #expect(check(K(.character("q"), .shift), situation(typing: true)) == .refused(.typedInPanel(commandLine: true)))
        #expect(check(K(.character("5")), situation(typing: true)) == .refused(.typedInPanel(commandLine: true)))
        // ⌥ + character starts quick search only while typing goes to the command line.
        #expect(check(K(.character("q"), .option), situation(typing: true)) == .warnings([.optionQuickSearch]))
        #expect(check(K(.character("q"), .option)) == .clean)
        #expect(check(K(.character("q"), [.option, .command]), situation(typing: true)) == .clean)
        // Not text keys, and not in other contexts.
        for key: KeyChord.Key in [.space, .enter, .backspace, .tab, .escape] {
            if case .refused = check(K(key), situation(typing: true)) { Issue.record("\(key) refused") }
        }
        #expect(check(K(.character("q")), for: .viewerFind, situation(.viewer)) == .clean)
    }

    @Test func conflictsNameTheCommandsAndUserMenuItems() {
        let duplicate = K(.character("d"), .command)
        #expect(check(duplicate) == .warnings([.commands([.duplicate])]))
        // App-wide commands conflict in every context.
        #expect(check(K(.character(","), .command), for: .viewerFind, situation(.viewer)) == .warnings([.commands([.settings])]))
        let item = UserMenuItem(title: "Terminal", program: "open", shortcut: K(.character("1"), .command))
        let menu = [UserMenuItem(kind: .submenu, title: "Tools", children: [item])]
        #expect(check(K(.character("1"), .command), situation(userMenu: menu)) == .warnings([.userMenu(["Terminal"])]))
        // User Menu items run from the panel only (⌘1 is Text in the viewer).
        #expect(check(K(.character("1"), .command), for: .viewerFind, situation(.viewer, userMenu: menu))
                == .warnings([.commands([.viewerText])]))
    }

    @Test func severalReasonsInOneWarningAndRefusalWins() {
        let area = SystemShortcut(.screenshotArea, K(.character("4"), [.shift, .command]))
        var bindings = KeyBindings()
        bindings.set([K(.character("4"), [.shift, .command])], for: .duplicate)
        #expect(check(K(.character("4"), [.shift, .command]), bindings: bindings, situation(system: [area]))
                == .warnings([.commands([.duplicate]), .system(area)]))
        let cmdW = SystemShortcut(.nextWindow, K(.character("w"), .command))
        #expect(check(K(.character("w"), .command), situation(system: [cmdW])) == .refused(.fixed(.menu(.closeWindow))))
    }

    @Test func aKeyTheCommandHasIsClean() {
        #expect(check(K(.character("d"), .command), for: .duplicate) == .clean)
    }

    @Test func problemsOfAssignedKeys() {
        let mission = SystemShortcut(.missionControl, K(.up, .control))
        #expect(ShortcutCheck.problem(K(.up, .control), situation: situation(system: [mission])) == .system(mission))
        #expect(ShortcutCheck.problem(K(.up, .control), situation: situation()) == nil)
        #expect(ShortcutCheck.problem(K(.character("a")), situation: situation()) == .typedInPanel(commandLine: false))
        #expect(ShortcutCheck.problem(K(.character("a"), .option), situation: situation(typing: true)) == nil)
    }

    @Test(arguments: KeyScheme.allCases)
    func noDefaultKeyIsRefused(scheme: KeyScheme) {
        let bindings = KeyBindings(scheme: scheme)
        for spec in CommandRegistry.all {
            for context in CommandContext.allCases where context.includes(spec.scope) {
                for chord in bindings.chords(for: spec.command) {
                    let refusal = ShortcutCheck.reasons(chord, situation: situation(context, typing: true)).first(where: \.refuses)
                    #expect(refusal == nil, "\(spec.command) \(chord) in \(context)")
                }
            }
        }
    }
}

@Suite struct SystemShortcutsTests {
    typealias K = KeyChord

    @Test func missingPreferenceKeepsTheDefaults() {
        #expect(SystemShortcuts.current(from: nil) == SystemShortcuts.defaults)
        #expect(SystemShortcuts.current(from: [:]) == SystemShortcuts.defaults)
    }

    @Test func userChangesApply() {
        let prefs: [String: Any] = [
            // Mission Control turned off.
            "32": ["enabled": false, "value": ["parameters": [65535, 126, 8650752], "type": "standard"]],
            // Spotlight moved to ⌥Space.
            "64": ["enabled": 1, "value": ["parameters": [32, 49, 524288], "type": "standard"]],
            // Screenshot of an area without a key.
            "30": ["enabled": 1, "value": ["parameters": [65535, 65535, 0], "type": "standard"]],
            // Malformed: keeps the default.
            "28": ["enabled": 1, "value": ["parameters": ["x"]]],
            "33": "nonsense",
            // Unknown identifiers are ignored.
            "999": ["enabled": 1, "value": ["parameters": [97, 0, 1048576]]],
        ]
        let current = SystemShortcuts.current(from: prefs)
        #expect(!current.contains { $0.feature == .missionControl })
        #expect(!current.contains { $0.feature == .screenshotArea })
        #expect(current.first { $0.feature == .spotlight }?.chord == K(.space, .option))
        #expect(current.first { $0.feature == .screenshot }?.chord == K(.character("3"), [.shift, .command]))
        #expect(current.first { $0.feature == .applicationWindows }?.chord == K(.down, .control))
        #expect(current.count == SystemShortcuts.defaults.count - 2)
    }

    @Test func chordsFromSystemParameters() {
        #expect(SystemShortcuts.chord(character: 52, keyCode: 21, modifierMask: 1179648) == K(.character("4"), [.shift, .command]))
        #expect(SystemShortcuts.chord(character: 65535, keyCode: 126, modifierMask: 8650752) == K(.up, .control))
        #expect(SystemShortcuts.chord(character: 65535, keyCode: 103, modifierMask: 8388608) == K(.function(11)))
        #expect(SystemShortcuts.chord(character: 32, keyCode: 49, modifierMask: 786432) == K(.space, [.control, .option]))
        #expect(SystemShortcuts.chord(character: 68, keyCode: 2, modifierMask: 1572864) == K(.character("d"), [.option, .command]))
        #expect(SystemShortcuts.chord(character: 65535, keyCode: 7777, modifierMask: 0) == nil)
    }
}
