import Testing
@testable import CommanderCore

@Suite struct KeyMapTests {
    @Test func everyCommandIsDeclaredOnce() {
        #expect(CommandRegistry.all.count == Command.allCases.count)
    }

    @Test(arguments: [CommandContext.panel, .viewer])
    func noChordBoundTwice(context: CommandContext) {
        var seen: [KeyChord: Command] = [:]
        for spec in CommandRegistry.all where context.includes(spec.scope) {
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

    @Test func viewerKeysStayInViewer() {
        #expect(KeyMap.viewer.command(for: KeyChord(.space)) == .viewerNextFile)
        #expect(KeyMap.standard.command(for: KeyChord(.space)) == .toggleSelectionAndSize)
        #expect(KeyMap.viewer.command(for: KeyChord(.character("q"), .command)) == .quit)
        #expect(KeyMap.viewer.command(for: KeyChord(.function(5))) == .viewerText)
        #expect(!CommandRegistry.items(in: .file, context: .viewer).contains { $0.command == .copy })
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
