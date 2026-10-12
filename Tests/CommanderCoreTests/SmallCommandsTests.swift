// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Small commands (spec 015): Copy As, name suggestions, Test Archives, files-only selection, chords.
@Suite struct SmallCommandsTests {
    private static let noProgress: @Sendable (OperationProgress) -> Void = { _ in }
    private static let noConflict: @Sendable (Conflict) async -> ConflictResolution = { _ in .cancel }

    private static func copyAs(_ source: URL, _ name: String) async throws -> TransferReport {
        let request = TransferRequest(kind: .copy, sources: [source],
                                      destinationDirectory: source.deletingLastPathComponent(), targetName: name)
        return try await FileOperations().transfer(request, progress: Self.noProgress, conflict: Self.noConflict)
    }

    @Test func copyAsCopiesAFileNextToItself() async throws {
        try await TestSandbox.with { root in
            try TestSandbox.write(root.child("a.txt"), "hello")
            _ = try await Self.copyAs(root.child("a.txt"), "a copy.txt")
            #expect(TestSandbox.read(root.child("a copy.txt")) == "hello")
            #expect(TestSandbox.read(root.child("a.txt")) == "hello")
        }
    }

    @Test func copyAsKeepsInnerNamesOfAFolder() async throws {
        try await TestSandbox.with { root in
            try TestSandbox.mkdirs(root.child("docs/sub"))
            try TestSandbox.write(root.child("docs/sub/x.txt"), "x")
            try TestSandbox.write(root.child("docs/y.md"), "y")
            _ = try await Self.copyAs(root.child("docs"), "docs2")
            #expect(TestSandbox.read(root.child("docs2/sub/x.txt")) == "x")
            #expect(TestSandbox.read(root.child("docs2/y.md")) == "y")
            #expect(TestSandbox.names(in: root).sorted() == ["docs", "docs2"])
        }
    }

    @Test func copyAsOntoItselfIsRefused() async throws {
        try await TestSandbox.with { root in
            try TestSandbox.write(root.child("a.txt"), "hello")
            await #expect(throws: OperationError.sameFile(root.child("a.txt"))) {
                _ = try await Self.copyAs(root.child("a.txt"), "a.txt")
            }
            #expect(TestSandbox.read(root.child("a.txt")) == "hello")
        }
    }

    @Test func nameSuggestions() {
        #expect(CopyAsName.suggestion(for: "config.json", isFolder: false) == "config copy.json")
        #expect(CopyAsName.suggestion(for: "Makefile", isFolder: false) == "Makefile copy")
        #expect(CopyAsName.suggestion(for: ".zshrc", isFolder: false) == ".zshrc copy")
        #expect(CopyAsName.suggestion(for: "my.app.d", isFolder: true) == "my.app.d copy")
        #expect(CopyAsName.suggestion(for: "a.txt", isFolder: false, suffix: "kopie") == "a kopie.txt")
        #expect(NewFolderName.suggestion(for: "photos-2026.zip", isFolder: false) == "photos-2026")
        #expect(NewFolderName.suggestion(for: "v1.2", isFolder: true) == "v1.2")
    }

    @Test func archiveTesterPassesASoundArchiveAndCatchesDamage() async throws {
        try await TestSandbox.with { root in
            let text = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 2000)
            try TestSandbox.write(root.child("a.txt"), text)
            let archive = root.child("a.zip")
            try await ArchiveWriter.create(archive, format: .zip, adding: [.init(file: root.child("a.txt"), path: "a.txt")],
                                           progress: { _ in })
            try await ArchiveTester.test(archive: archive)

            var data = try Data(contentsOf: archive)
            for i in 60..<120 { data[i] ^= 0x5A }
            let damaged = root.child("damaged.zip")
            try data.write(to: damaged)
            await #expect(throws: (any Error).self) { try await ArchiveTester.test(archive: damaged) }
        }
    }

    @MainActor @Test func filesOnlySelectionLeavesFolders() async throws {
        let f = try PanelModelTests.Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        let docs = try #require(m.items.first { $0.name == "docs" })
        m.toggleSelection(at: try #require(m.items.firstIndex(of: docs)))
        m.selectFiles(true)
        #expect(Set(m.selectedItems.map(\.name)) == ["a.txt", "b.txt", "c.md", "docs"])
        m.selectFiles(false)
        #expect(m.selectedItems.map(\.name) == ["docs"])
    }

    @Test func chords() {
        typealias K = KeyChord
        let factory = KeyMap.standard
        #expect(factory.command(for: K(.function(5), .shift)) == .copyAs)
        #expect(factory.command(for: K(.character("n"), [.command, .option])) == .makeDirectoryInOtherPanel)
        #expect(factory.command(for: K(.function(3), [.option, .shift])) == .viewCursorFile)
        #expect(factory.command(for: K(.function(5), [.option, .shift])) == .packAndMove)
        #expect(factory.command(for: K(.function(9), [.option, .shift])) == .testArchives)
        #expect(factory.command(for: K(.character("j"), [.control, .shift])) == .insertFullPathToCommandLine)
        #expect(factory.command(for: K(.up, [.option, .shift])) == .toggleSelectionInPlace)
        #expect(factory.command(for: K(.numPlus, [.control, .shift])) == .selectAllFiles)
        #expect(factory.command(for: K(.numMinus, [.control, .shift])) == .deselectAllFiles)
        #expect(factory.command(for: K(.function(7), .shift)) == .changeDirectory)
        #expect(factory.command(for: K(.function(3), .shift)) == .revealInFinder)
        #expect(factory.command(for: K(.character("l"), .control)) == .volumeInfo)

        let classic = KeyMap(context: .panel, bindings: KeyBindings(scheme: .classicCommander))
        #expect(classic.command(for: K(.function(7), .shift)) == .makeDirectoryInOtherPanel)
        #expect(classic.command(for: K(.character("g"), [.command, .shift])) == .changeDirectory)
        #expect(classic.command(for: K(.function(3), .shift)) == .viewCursorFile)
        #expect(classic.command(for: K(.character("l"), .control)) == .calculateSizes)
    }
}
