import Testing
@testable import CommanderCore

@Suite struct KeyMapTests {
    @Test func everyCommandIsDeclaredOnce() {
        #expect(CommandRegistry.all.count == Command.allCases.count)
    }

    @Test func noChordBoundTwice() {
        var seen: [KeyChord: Command] = [:]
        for spec in CommandRegistry.all {
            for chord in spec.chords {
                #expect(seen[chord] == nil, "\(chord) bound to \(seen[chord].map(\.rawValue) ?? "") and \(spec.command.rawValue)")
                seen[chord] = spec.command
            }
        }
    }

    @Test(arguments: [
        (KeyChord(.function(5)), Command.copy),
        (KeyChord(.function(6)), .move),
        (KeyChord(.function(8)), .delete),
        (KeyChord(.forwardDelete, .shift), .deletePermanently),
        (KeyChord(.tab), .switchPanel),
        (KeyChord(.backspace), .goParent),
        (KeyChord(.function(3), .control), .sortByName),
        (KeyChord(.left, [.control, .option]), .goBack),
        (KeyChord(.function(1), [.control, .option]), .leftVolumeMenu),
    ])
    func windowsBindingsSurvive(chord: KeyChord, command: Command) {
        #expect(KeyMap.standard.command(for: chord) == command)
    }

    @Test func overrideWins() {
        let map = KeyMap(overrides: [KeyChord(.function(5)): .move])
        #expect(map.command(for: KeyChord(.function(5))) == .move)
    }

    @Test func plainKeysAreNotMenuEquivalents() {
        #expect(!KeyChord(.backspace).isMenuSafe)
        #expect(!KeyChord(.character("a"), .shift).isMenuSafe)
        #expect(KeyChord(.function(5)).isMenuSafe)
        #expect(KeyChord(.character("c"), .command).isMenuSafe)
    }
}
