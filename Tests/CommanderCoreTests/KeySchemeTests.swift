// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct KeySchemeTests {
    typealias K = KeyChord
    static let classic = KeyBindings(scheme: .classicCommander)

    @Test func axolotlChangesNothing() {
        #expect(KeyScheme.axolotl.changes.isEmpty)
        for context in CommandContext.allCases {
            #expect(KeyMap(context: context, bindings: KeyBindings(scheme: .axolotl)).bindings
                    == KeyMap(context: context).bindings)
        }
    }

    @Test(arguments: [
        (K(.character("t"), .control), Command.newTab),
        (K(.character("t"), [.control, .shift]), .newTab),
        (K(.character("w"), .control), .closeTab),
        // Spec 012 FR-013: ⌃⇧W moved from Close Tab to Close Other Tabs.
        (K(.character("w"), [.control, .shift]), .closeOtherTabs),
        (K(.tab, .control), .nextTab),
        (K(.tab, [.control, .shift]), .previousTab),
        (K(.pageDown, [.control, .shift]), .nextTab),
        (K(.down, .control), .focusCommandLine),
        (K(.numSlash), .restoreSelection),
        (K(.character("/"), .control), .openTerminal),
        (K(.function(2), .control), .viewModeDetailed),
        (K(.character("1"), [.control, .option]), .viewModeDetailed),
        (K(.character("f"), [.control, .shift]), .disconnect),
        (K(.function(12)), .disconnect),
        (K(.character("f"), .control), .connectToServer),
        (K(.function(5), [.control, .shift]), .newSymbolicLink),
        (K(.function(3), .option), .viewWith),
        (K(.function(4), .option), .quit),
        (K(.character("q"), .command), .quit),
        (K(.function(2)), .rename),
        (K(.function(6), .shift), .rename),
    ])
    func classicCommanderChord(chord: KeyChord, command: Command) {
        #expect(KeyMap(context: .panel, bindings: Self.classic).command(for: chord) == command)
    }

    @Test func classicCommanderMenuChords() {
        let map = KeyMap(context: .panel, bindings: Self.classic)
        for command in [Command.goToLinkTarget, .changeAttributes, .saveSelection] {
            #expect(map.chords(for: command).isEmpty, "\(command)")
        }
        #expect(map.chords(for: .quickLook) == [K(.character("y"), .command)])
        #expect(map.chords(for: .quit).first(where: \.isMenuSafe) == K(.character("q"), .command))
        #expect(map.chords(for: .newTab).first(where: \.isMenuSafe) == K(.character("t"), .control))
    }

    /// FR-007: no chord is bound to two commands of one context in any scheme.
    @Test(arguments: KeyScheme.allCases)
    func noChordBoundTwice(scheme: KeyScheme) {
        for context in CommandContext.allCases {
            var seen: [KeyChord: Command] = [:]
            for spec in CommandRegistry.all where context.includes(spec.scope) {
                for chord in scheme.chords(for: spec.command) {
                    #expect(seen[chord] == nil,
                            "\(scheme) \(context): \(chord) bound to \(seen[chord].map(\.rawValue) ?? "") and \(spec.command.rawValue)")
                    seen[chord] = spec.command
                }
            }
        }
    }

    /// FR-010: the user's chord beats the scheme's.
    @Test func userChordBeatsSchemeChord() {
        var bindings = Self.classic
        bindings.set([K(.character("t"), .control)], for: .goToLinkTarget)
        let map = KeyMap(context: .panel, bindings: bindings)
        #expect(map.command(for: K(.character("t"), .control)) == .goToLinkTarget)
        #expect(map.chords(for: .newTab) == [K(.character("t"), [.control, .shift])])
        #expect(bindings.conflicts(K(.character("t"), .control), for: .newTab) == [.goToLinkTarget])
    }

    /// FR-011: a change equal to the scheme is not the user's.
    @Test func settingTheSchemeChordsStoresNoOverride() {
        var bindings = Self.classic
        bindings.set([K(.character("t"), .control), K(.character("t"), [.control, .shift])], for: .newTab)
        #expect(bindings.overrides.isEmpty)
        #expect(bindings.source(for: .newTab) == .scheme)
        #expect(bindings.source(for: .copy) == .defaults)
        #expect(KeyBindings.factory.source(for: .newTab) == .defaults)
        #expect(KeyBindings(scheme: .classicCommander, overrides: [.quit: [K(.character("q"), .command), K(.function(4), .option)]])
                .overrides.isEmpty)
    }

    /// FR-013: switching keeps the user's changes.
    @Test func switchingSchemesKeepsOverrides() {
        var bindings = KeyBindings()
        let tabs = [K(.character("t"), .control), K(.character("t"), [.control, .shift])]
        bindings.set(tabs, for: .newTab)
        bindings.set([K(.function(11), .shift)], for: .rename)
        #expect(bindings.source(for: .newTab) == .user)

        bindings.scheme = .classicCommander
        #expect(bindings.overrides.count == 2)
        #expect(bindings.source(for: .newTab) == .scheme)
        #expect(!bindings.isCustomized(.newTab))
        #expect(bindings.chords(for: .rename) == [K(.function(11), .shift)])

        bindings.scheme = .axolotl
        #expect(bindings.source(for: .newTab) == .user)
        #expect(bindings.chords(for: .newTab) == tabs)
    }

    /// FR-014: reset goes back to the selected scheme.
    @Test func resetGoesToTheScheme() {
        var bindings = Self.classic
        bindings.set([], for: .newTab)
        bindings.set([K(.function(11), .shift)], for: .rename)
        bindings.reset(.newTab)
        #expect(bindings.chords(for: .newTab) == KeyScheme.classicCommander.chords(for: .newTab))
        bindings.resetAll()
        #expect(bindings == Self.classic)
        #expect(bindings.scheme == .classicCommander)
    }

    /// FR-012 / SC-006: overrides written by 0.3.x load unchanged on top of Axolotl.
    @Test func previousFormatStillLoads() throws {
        let json = #"{"rename":["shift+F11"],"copy":[]}"#
        let bindings = try JSONDecoder().decode(KeyBindings.self, from: Data(json.utf8))
        #expect(bindings.scheme == .axolotl)
        #expect(bindings.chords(for: .rename) == [K(.function(11), .shift)])
        #expect(bindings.chords(for: .copy).isEmpty)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(String(decoding: try encoder.encode(bindings), as: UTF8.self) == #"{"copy":[],"rename":["shift+F11"]}"#)
    }

    /// Under Classic Commander, pinning New Tab to the factory ⌃⇧T only is a real change.
    @Test func overrideEqualToFactorySurvivesDecoding() throws {
        var bindings = Self.classic
        bindings.set([K(.character("t"), [.control, .shift])], for: .newTab)
        #expect(bindings.isCustomized(.newTab))
        var decoded = try JSONDecoder().decode(KeyBindings.self, from: JSONEncoder().encode(bindings))
        decoded.scheme = .classicCommander
        #expect(decoded == bindings)
    }
}
