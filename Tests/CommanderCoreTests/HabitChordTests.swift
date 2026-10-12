// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
@testable import CommanderCore

/// The extra default chords from classic two-panel file manager habits (spec 010, FR-001).
@Suite struct HabitChordTests {
    typealias K = KeyChord

    static let habitChords: [(KeyChord, Command)] = [
        (K(.left, .control), .openInLeftPanel),
        (K(.right, .control), .openInRightPanel),
        (K(.left, .option), .goBack),
        (K(.right, .option), .goForward),
        (K(.function(1), .control), .viewModeBrief),
        (K(.function(2), .shift), .comparePanels),
        (K(.function(6), .shift), .rename),
        (K(.character("r"), .control), .refresh),
        (K(.character("a"), .control), .selectAll),
        (K(.character("c"), .control), .copyFiles),
        (K(.character("v"), .control), .pasteFiles),
        (K(.character("i"), .control), .switchPanel),
        (K(.character("d"), .control), .hotPaths),
        (K(.character("f"), .control), .connectToServer),
        (K(.character("n"), .control), .connectToServer),
        (K(.character("j"), .control), .insertNameToCommandLine),
        (K(.character("p"), .control), .insertPathToCommandLine),
        (K(.character("b"), [.control, .shift]), .branchViewSelected),
        (K(.enter, .option), .properties),
        (K(.enter, [.option, .shift]), .calculateSizes),
        (K(.numPlus, .option), .selectSameExtension),
        (K(.numMinus, .option), .deselectSameExtension),
        (K(.function(9), .option), .unpack),
        (K(.enter, [.control, .shift]), .insertFullPathToCommandLine),
    ]

    @Test func thereAreTwentyFour() {
        #expect(Self.habitChords.count == 24)
    }

    @Test(arguments: habitChords)
    func habitChordRunsItsCommand(chord: KeyChord, command: Command) {
        #expect(KeyMap.standard.command(for: chord) == command)
    }

    /// Keys `PanelViewController` handles before the key map.
    @Test func habitChordsLeaveDirectPanelKeysAlone() {
        var direct: Set<KeyChord> = [
            K(.up, .option), K(.down, .option), K(.home, .option), K(.end, .option),
            K(.up, .control), K(.down, .control),
        ]
        for key: KeyChord.Key in [.up, .down, .left, .right, .home, .end, .pageUp, .pageDown] {
            direct.insert(K(key))
            direct.insert(K(key, .shift))
        }
        for chord in Self.habitChords.map(\.0) {
            #expect(!direct.contains(chord), "\(chord)")
            if case .character = chord.key {
                // Quick search takes characters typed without ⌃, ⌘ and ⌥.
                #expect(!chord.modifiers.intersection([.control, .command, .option]).isEmpty, "\(chord)")
            }
        }
    }

    /// The new chords go after the existing ones, so menus keep their key equivalents.
    @Test func menuChordsStay() {
        let map = KeyMap.standard
        let expected: [(Command, KeyChord)] = [
            (.goBack, K(.left, [.control, .option])),
            (.goForward, K(.right, [.control, .option])),
            (.rename, K(.function(2))),
            (.refresh, K(.function(9), .control)),
            (.selectAll, K(.character("a"), .command)),
            (.copyFiles, K(.character("c"), .command)),
            (.pasteFiles, K(.character("v"), .command)),
            (.properties, K(.character("i"), .command)),
            (.viewModeBrief, K(.character("2"), [.control, .option])),
            (.hotPaths, K(.function(9), .shift)),
            (.connectToServer, K(.character("k"), .command)),
            (.comparePanels, K(.function(10), .control)),
            (.unpack, K(.function(6), .option)),
        ]
        for (command, chord) in expected {
            #expect(map.chords(for: command).first(where: \.isMenuSafe) == chord, "\(command)")
        }
    }
}

/// The tab commands' chords (spec 012, FR-012 and FR-013).
@Suite struct TabChordTests {
    typealias K = KeyChord

    @Test(arguments: [
        (K(.up, .control), Command.openInNewTab),
        (K(.down, [.command, .option]), .openInNewTab),
        (K(.down, [.command, .option, .shift]), .openInBackgroundTab),
        (K(.up, [.control, .shift]), .openInNewTabOtherPanel),
        (K(.character("t"), [.command, .shift]), .reopenClosedTab),
        (K(.character("w"), [.command, .option]), .closeOtherTabs),
        (K(.character("a"), [.control, .shift]), .tabList),
        (K(.character("\\"), [.command, .shift]), .tabList),
        (K(.character("u"), [.control, .shift]), .swapPanelsWithTabs),
    ])
    func factoryChord(chord: KeyChord, command: Command) {
        #expect(KeyMap.standard.command(for: chord) == command)
    }

    @Test func classicCommanderMovesControlShiftW() {
        let classic = KeyBindings(scheme: .classicCommander, overrides: [:])
        let map = KeyMap(context: .panel, bindings: classic)
        #expect(map.command(for: K(.character("w"), [.control, .shift])) == .closeOtherTabs)
        #expect(map.command(for: K(.character("w"), .control)) == .closeTab)
        #expect(KeyMap.standard.command(for: K(.character("w"), [.control, .shift])) == .closeTab)
    }
}
