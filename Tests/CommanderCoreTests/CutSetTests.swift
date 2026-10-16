// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct CutSetTests {
    let a = URL(filePath: "/tmp/src/a.txt")
    let b = URL(filePath: "/tmp/src/b.txt")
    let folder = URL(filePath: "/tmp/src/Photos/", directoryHint: .isDirectory)
    let target = URL(filePath: "/tmp/dst/", directoryHint: .isDirectory)

    @Test func cutItemsAreKnownWhileThePasteboardIsUnchanged() {
        let cut = CutSet(urls: [a, folder], changeCount: 7)
        #expect(cut.contains(a, changeCount: 7))
        #expect(cut.contains(URL(filePath: "/tmp/src/Photos"), changeCount: 7))
        #expect(!cut.contains(b, changeCount: 7))
        #expect(!cut.contains(a, changeCount: 8))
        #expect(!cut.isActive(changeCount: 8))
    }

    @Test func pasteMovesOnlyWhatWasCut() {
        let cut = CutSet(urls: [a, b], changeCount: 3)
        #expect(cut.pasteAction(for: [a, b], destination: target, changeCount: 3) == .move)
        // Another app wrote the pasteboard since the cut: copy.
        #expect(cut.pasteAction(for: [a, b], destination: target, changeCount: 4) == .copy)
        // A file list that is not the cut one: copy.
        #expect(cut.pasteAction(for: [a, URL(filePath: "/tmp/other.txt")], destination: target, changeCount: 3) == .copy)
        #expect(cut.pasteAction(for: [], destination: target, changeCount: 3) == .copy)
    }

    @Test func pasteIntoTheSourceFolderDoesNothing() {
        let cut = CutSet(urls: [a, b], changeCount: 3)
        #expect(cut.pasteAction(for: [a, b], destination: URL(filePath: "/tmp/src/", directoryHint: .isDirectory),
                                changeCount: 3) == .sameFolder)
        #expect(cut.pasteAction(for: [a, b], destination: URL(filePath: "/tmp/src"), changeCount: 3) == .sameFolder)
    }

    @Test func itemsLeftAfterAMoveStayCut() {
        let cut = CutSet(urls: [b, a], changeCount: 1)
        #expect(cut.remaining { $0.lastPathComponent == "b.txt" } == [URL(filePath: "/tmp/src/b.txt")])
        #expect(cut.remaining { _ in false }.isEmpty)
        #expect(cut.remaining { _ in true }.map(\.lastPathComponent) == ["a.txt", "b.txt"])
    }

    @Test func emptyCutIsNeverActive() {
        #expect(!CutSet(urls: [], changeCount: 1).isActive(changeCount: 1))
    }
}

@Suite struct BasicCommandKeysTests {
    typealias K = KeyChord

    @Test(arguments: [
        (K(.character("x"), .command), Command.cutFiles),
        (K(.character("x"), .control), .cutFiles),
        (K(.character("d"), .command), .duplicate),
        (K(.character("t"), .command), .newTab),
        (K(.character("t"), [.control, .shift]), .newTab),
        (K(.character("]"), [.command, .shift]), .nextTab),
        (K(.character("["), [.command, .shift]), .previousTab),
        (K(.pageDown, [.control, .shift]), .nextTab),
        (K(.character("d"), [.command, .shift]), .goDesktop),
        (K(.character("o"), [.command, .shift]), .goDocuments),
        (K(.character("l"), [.command, .option]), .goDownloads),
        (K(.tab, .control), .focusCommandLine),
        (K(.character("a"), [.command, .shift]), .deselectAll),
    ])
    func defaultChord(chord: KeyChord, command: Command) {
        #expect(KeyMap(context: .panel).command(for: chord) == command)
    }

    @Test(arguments: [
        (K(.character("t"), .command), Command.newTab),
        (K(.character("t"), .control), .newTab),
        (K(.character("]"), [.command, .shift]), .nextTab),
        (K(.character("["), [.command, .shift]), .previousTab),
        (K(.tab, .control), .nextTab),
        (K(.character("x"), .control), .cutFiles),
    ])
    func classicChord(chord: KeyChord, command: Command) {
        #expect(KeyMap(context: .panel, bindings: KeyBindings(scheme: .classicCommander)).command(for: chord) == command)
    }

    @Test func newChordsCollideWithNothing() {
        let bindings = KeyBindings(scheme: .axolotl)
        for command in [Command.cutFiles, .duplicate, .newTab, .nextTab, .previousTab, .goDesktop, .goDocuments, .goDownloads] {
            for chord in bindings.chords(for: command) {
                #expect(bindings.conflicts(chord, for: command).isEmpty, "\(chord) of \(command)")
            }
        }
        #expect(bindings.chords(for: .goApplications).isEmpty)
    }
}
