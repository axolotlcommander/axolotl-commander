// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// The bar must name exactly the command the key press runs (SC-002), with a translated short
/// name where it has one.
@Suite struct FunctionKeyBarTests {
    /// All 16 combinations of ⇧⌃⌥⌘.
    private static let modifierSets: [KeyChord.Modifiers] = (0..<16).map { KeyChord.Modifiers(rawValue: $0) }

    private func expectSlotsMatchKeyPresses(_ map: KeyMap) {
        for modifiers in Self.modifierSets {
            let slots = FunctionKeyBar.slots(in: map, modifiers: modifiers)
            #expect(slots.count == FunctionKeyBar.count)
            for n in 1...FunctionKeyBar.count {
                #expect(slots[n - 1] == map.command(for: KeyChord(.function(n), modifiers)),
                        "F\(n) with \(KeyChord(.function(n), modifiers))")
            }
        }
    }

    @Test func slotsMatchKeyPressesInFactoryMap() {
        expectSlotsMatchKeyPresses(KeyMap(context: .panel, bindings: .factory))
    }

    @Test func slotsFollowRemappedKeys() {
        var bindings = KeyBindings()
        bindings.set([KeyChord(.function(2))], for: .comparePanels)
        bindings.set([], for: .copy)
        let map = KeyMap(context: .panel, bindings: bindings)
        expectSlotsMatchKeyPresses(map)
        let plain = FunctionKeyBar.slots(in: map, modifiers: [])
        #expect(plain[1] == .comparePanels)
        #expect(plain[4] == nil)
    }

    @Test func factoryPlainSet() {
        let plain = FunctionKeyBar.slots(in: KeyMap(context: .panel, bindings: .factory), modifiers: [])
        #expect(plain == [.help, .rename, .view, .edit, .copy, .move, .makeDirectory, .delete, .userMenu,
                          nil, nil, .disconnect])
    }

    @Test func commandWithSeveralChordsAppearsInEverySlot() {
        let map = KeyMap(context: .panel, bindings: .factory)
        #expect(FunctionKeyBar.slots(in: map, modifiers: .option)[4] == .pack)
        #expect(FunctionKeyBar.slots(in: map, modifiers: [.control, .option])[4] == .pack)
    }

    @Test func viewerCommandsNeverShow() {
        let map = KeyMap(context: .panel, bindings: .factory)
        for modifiers in Self.modifierSets {
            for command in FunctionKeyBar.slots(in: map, modifiers: modifiers).compactMap({ $0 }) {
                let scope = CommandRegistry.spec(command).scope
                #expect(scope == .app || scope == .panel, "\(command)")
            }
        }
    }

    @Test func shortTitlesAreShorter() {
        for command in Command.allCases {
            guard let short = CommandRegistry.shortTitle(command) else { continue }
            var title = CommandRegistry.spec(command).title
            if title.hasSuffix("…") { title.removeLast() }
            #expect(short.count < title.count, "\(command): \(short) vs \(title)")
        }
    }

    /// Titles and short titles shown in the bar are translated (the app looks them up by English text).
    @Test func barTextsAreTranslated() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])
        func czech(_ key: String) -> String? {
            let entry = strings[key] as? [String: Any]
            let cs = (entry?["localizations"] as? [String: Any])?["cs"] as? [String: Any]
            return (cs?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        var keys = Set(Command.allCases.compactMap(CommandRegistry.shortTitle))
        keys.formUnion(factoryFunctionKeyCommands.map { CommandRegistry.spec($0).title })
        keys.formUnion([Command.toggleCommandLine, .toggleFunctionKeyBar].map { CommandRegistry.spec($0).title })
        for key in keys.sorted() {
            #expect(czech(key) != nil, "missing Czech translation for \"\(key)\"")
        }
    }

    private var factoryFunctionKeyCommands: Set<Command> {
        let map = KeyMap(context: .panel, bindings: .factory)
        return Set(Self.modifierSets.flatMap { FunctionKeyBar.slots(in: map, modifiers: $0) }.compactMap { $0 })
    }
}
