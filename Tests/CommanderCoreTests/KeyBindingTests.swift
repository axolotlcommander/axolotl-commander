import Foundation
import Testing
@testable import CommanderCore

@Suite struct KeyBindingTests {
    private static let allKeys: [KeyChord.Key] = [
        .function(1), .function(5), .function(12), .function(20),
        .character("a"), .character("+"), .character(":"), .character("č"), .character("-"), .character("="),
        .character("["), .character("/"), .character("F"), .character("U"), .character(","),
        .character("\u{E000}"), .character("e\u{301}"), .character(" "), .character("\t"),
        .tab, .enter, .space, .escape, .backspace, .forwardDelete, .insert,
        .up, .down, .left, .right, .home, .end, .pageUp, .pageDown,
        .numPlus, .numMinus, .numStar, .numSlash, .numEnter,
    ]
    private static let allModifiers: [KeyChord.Modifiers] = [
        [], .command, .control, .option, .shift, [.command, .shift], [.control, .option],
        [.control, .option, .shift, .command],
    ]

    @Test func storageStringExamples() {
        #expect(KeyChord(.function(5), [.command, .shift]).storageString == "shift+cmd+F5")
        #expect(KeyChord(.character("a"), [.control, .option]).storageString == "ctrl+opt+char:a")
        #expect(KeyChord(.tab).storageString == "tab")
        #expect(KeyChord(.numPlus).storageString == "numPlus")
        #expect(KeyChord(.character("+"), .command).storageString == "cmd+char:+")
        #expect(KeyChord(storageString: "cmd+shift+F5") == KeyChord(.function(5), [.command, .shift]))
        #expect(KeyChord(storageString: "ctrl+char::") == KeyChord(.character(":"), .control))
    }

    @Test func storageStringRoundTripsEveryKey() {
        for key in Self.allKeys {
            for mods in Self.allModifiers {
                let chord = KeyChord(key, mods)
                let text = chord.storageString
                #expect(KeyChord(storageString: text) == chord, "\(text)")
            }
        }
    }

    @Test func storageStringRejectsGarbage() {
        for bad in ["", "cmd+", "bogus", "F", "F+5", "Fx", "F0", "char:", "char:ab", "char:U+zz", "cmd+shift", "ctrl+opt+nothing"] {
            #expect(KeyChord(storageString: bad) == nil, "\(bad)")
        }
    }

    @Test func chordCodableRoundTrip() throws {
        let chords = Self.allKeys.map { KeyChord($0, [.command, .option]) }
        let data = try JSONEncoder().encode(chords)
        #expect(try JSONDecoder().decode([KeyChord].self, from: data) == chords)
        #expect(String(decoding: try JSONEncoder().encode([KeyChord(.function(5))]), as: UTF8.self) == "[\"F5\"]")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([KeyChord].self, from: Data("[\"nonsense\"]".utf8)) }
    }

    @Test func everyFactoryChordRoundTrips() {
        for spec in CommandRegistry.all {
            for chord in spec.chords { #expect(KeyChord(storageString: chord.storageString) == chord) }
        }
    }

    @Test func bindingsCodableRoundTrip() throws {
        var bindings = KeyBindings()
        bindings.set([KeyChord(.character("+"), .command), KeyChord(.function(9), .shift)], for: .move)
        bindings.set([], for: .rename)
        let data = try JSONEncoder().encode(bindings)
        #expect(try JSONDecoder().decode(KeyBindings.self, from: data) == bindings)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: [String]])
        #expect(json["move"] == ["cmd+char:+", "shift+F9"])
        #expect(json["rename"] == [])
    }

    @Test func decodeIgnoresUnknownCommandsAndBadChords() throws {
        let json = #"{"futureCommand": ["F1"], "move": ["cmd+F9"], "copy": ["garbage"]}"#
        let bindings = try JSONDecoder().decode(KeyBindings.self, from: Data(json.utf8))
        #expect(bindings.overrides == [.move: [KeyChord(.function(9), .command)]])
        #expect(!bindings.isCustomized(.copy))
    }

    @Test func factoryBindings() {
        let factory = KeyBindings.factory
        #expect(factory.overrides.isEmpty)
        #expect(factory.chords(for: .copy) == [KeyChord(.function(5))])
        #expect(!factory.isCustomized(.copy))
        #expect(KeyMap(bindings: .factory).bindings == KeyMap.standard.bindings)
        for context in CommandContext.allCases {
            #expect(KeyMap(context: context, bindings: .factory).bindings == KeyMap(context: context).bindings)
        }
    }

    @Test func overridingF5MovesItAndResetRestoresCopy() {
        var bindings = KeyBindings()
        bindings.set([KeyChord(.function(5))], for: .properties)
        #expect(bindings.isCustomized(.properties))
        var map = KeyMap(bindings: bindings)
        #expect(map.command(for: KeyChord(.function(5))) == .properties)
        #expect(map.chords(for: .copy).isEmpty)
        #expect(map.chords(for: .properties) == [KeyChord(.function(5))])
        // The old chord of .properties is gone because it was replaced.
        #expect(map.command(for: KeyChord(.character("i"), .command)) == nil)

        // Turning the remapping off gives F5 back to Copy.
        bindings.reset(.properties)
        map = KeyMap(bindings: bindings)
        #expect(map.command(for: KeyChord(.function(5))) == .copy)
        #expect(map.chords(for: .copy) == [KeyChord(.function(5))])
        #expect(!bindings.isCustomized(.properties))
    }

    @Test func commandKeepsItsOtherChords() {
        var bindings = KeyBindings()
        bindings.set([KeyChord(.function(8))], for: .rename)
        let map = KeyMap(bindings: bindings)
        #expect(map.command(for: KeyChord(.function(8))) == .rename)
        #expect(map.chords(for: .delete) == [KeyChord(.forwardDelete), KeyChord(.backspace, .command)])
        #expect(map.command(for: KeyChord(.forwardDelete)) == .delete)
    }

    @Test func emptyOverrideMeansNoShortcut() {
        var bindings = KeyBindings()
        bindings.set([], for: .copy)
        #expect(bindings.isCustomized(.copy))
        #expect(bindings.chords(for: .copy).isEmpty)
        let map = KeyMap(bindings: bindings)
        #expect(map.command(for: KeyChord(.function(5))) == nil)
        #expect(map.chords(for: .copy).isEmpty)
    }

    @Test func setEqualToFactoryRemovesOverride() {
        var bindings = KeyBindings()
        bindings.set([KeyChord(.function(9))], for: .copy)
        #expect(bindings.isCustomized(.copy))
        bindings.set(CommandRegistry.spec(.copy).chords, for: .copy)
        #expect(!bindings.isCustomized(.copy))
        #expect(bindings == .factory)
        #expect(KeyBindings(overrides: [.copy: [KeyChord(.function(5))]]) == .factory)
    }

    @Test func resetAll() {
        var bindings = KeyBindings()
        bindings.set([], for: .copy)
        bindings.set([KeyChord(.function(9))], for: .move)
        bindings.resetAll()
        #expect(bindings == .factory)
    }

    @Test func explicitChordBeatsFactoryChordOfAnotherCommand() {
        var bindings = KeyBindings()
        // The user takes ⌘Q (a factory chord of .quit, app scope) for a viewer command.
        bindings.set([KeyChord(.character("q"), .command)], for: .viewerClose)
        let map = KeyMap(context: .viewer, bindings: bindings)
        #expect(map.command(for: KeyChord(.character("q"), .command)) == .viewerClose)
        #expect(map.chords(for: .quit).isEmpty)
        // Other contexts are untouched.
        #expect(KeyMap(context: .panel, bindings: bindings).command(for: KeyChord(.character("q"), .command)) == .quit)
    }

    @Test func overridesOnlyAffectTheirContext() {
        var bindings = KeyBindings()
        bindings.set([KeyChord(.function(11), .shift)], for: .viewerText)
        #expect(KeyMap(context: .viewer, bindings: bindings).command(for: KeyChord(.function(11), .shift)) == .viewerText)
        #expect(KeyMap(context: .panel, bindings: bindings).command(for: KeyChord(.function(11), .shift)) == nil)
    }

    @Test func conflictsWithinPanelScope() {
        let bindings = KeyBindings.factory
        #expect(bindings.conflicts(KeyChord(.function(5)), for: .move) == [.copy])
        #expect(bindings.conflicts(KeyChord(.function(5)), for: .copy).isEmpty)
        #expect(bindings.conflicts(KeyChord(.function(11), .shift), for: .copy).isEmpty)
        // App-scope commands overlap every window kind.
        #expect(bindings.conflicts(KeyChord(.character("q"), .command), for: .copy) == [.quit])
        #expect(bindings.conflicts(KeyChord(.character("q"), .command), for: .viewerClose) == [.quit])
    }

    @Test func noConflictBetweenViewerAndCompareContexts() {
        let bindings = KeyBindings.factory
        // Space is bound in panel, viewer, find and compare contexts; they never overlap each other.
        #expect(bindings.conflicts(KeyChord(.space), for: .viewerNextFile).isEmpty)
        #expect(bindings.conflicts(KeyChord(.space), for: .compareNextDifference).isEmpty)
        #expect(bindings.conflicts(KeyChord(.space), for: .toggleSelectionAndSize).isEmpty)
        #expect(bindings.conflicts(KeyChord(.space), for: .findShowInPanel).isEmpty)
        // Cmd+C is copy in panel, viewer, find and compare.
        #expect(bindings.conflicts(KeyChord(.character("c"), .command), for: .viewerCopy).isEmpty)
        #expect(bindings.conflicts(KeyChord(.character("c"), .command), for: .compareCopy).isEmpty)
        #expect(bindings.conflicts(KeyChord(.character("c"), .command), for: .copyFiles).isEmpty)
        #expect(bindings.conflicts(KeyChord(.character("c"), .command), for: .properties) == [.copyFiles])
    }

    @Test func conflictsSeeUserBindings() {
        var bindings = KeyBindings()
        bindings.set([KeyChord(.function(11), .shift)], for: .rename)
        #expect(bindings.conflicts(KeyChord(.function(11), .shift), for: .move) == [.rename])
        // F2 is free now.
        #expect(bindings.conflicts(KeyChord(.function(2)), for: .move).isEmpty)
        // A command never conflicts with itself.
        #expect(bindings.conflicts(KeyChord(.function(11), .shift), for: .rename).isEmpty)
    }

    @Test func legacyOverrideInitStillWorks() {
        let map = KeyMap(overrides: [KeyChord(.function(5)): .move])
        #expect(map.command(for: KeyChord(.function(5))) == .move)
        #expect(map.chords(for: .move).contains(KeyChord(.function(5))))
        #expect(map.chords(for: .copy).isEmpty)
    }

    @Test func menuCanPickFirstMenuSafeChord() {
        let map = KeyMap.standard
        #expect(map.chords(for: .delete).first(where: \.isMenuSafe) == KeyChord(.function(8)))
        #expect(map.chords(for: .makeDirectory) == [KeyChord(.function(7)), KeyChord(.character("n"), [.command, .shift])])
    }
}
