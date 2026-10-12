// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Quick filter (spec 013): matching, the model state and the chords.
@MainActor
@Suite struct QuickFilterTests {
    typealias Fixture = PanelModelTests.Fixture

    private func names(_ m: PanelModel) -> [String] { m.items.map(\.name) }

    @Test func textMatchesContainedNamesAndMasks() {
        let rules = NameRules.apfsDefault
        #expect(QuickFilter.matches("Invoice-2026.pdf", text: "voice", rules: rules))
        #expect(QuickFilter.matches("Invoice-2026.pdf", text: "INVOICE", rules: rules))
        #expect(!QuickFilter.matches("notes.md", text: "voice", rules: rules))
        #expect(QuickFilter.matches("notes.md", text: "*.md", rules: rules))
        #expect(!QuickFilter.matches("notes.md.bak", text: "*.md", rules: rules))
        #expect(QuickFilter.matches("a.txt", text: "*.md;*.txt", rules: rules))
        #expect(QuickFilter.matches("my notes.txt", text: "y n", rules: rules))
    }

    @Test func filterHidesFilesAndFoldersButKeepsParent() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        #expect(m.setQuickFilter("tx"))
        #expect(names(m) == ["..", "a.txt", "b.txt"])
        #expect(m.setQuickFilter("o"))
        #expect(names(m) == ["..", "docs", "Photos"])
        #expect(m.setQuickFilter(""))
        #expect(m.quickFilter == nil)
        #expect(names(m) == ["..", "docs", "Photos", "a.txt", "b.txt", "c.md"])
    }

    @Test func textLeavingNothingIsRefused() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        #expect(m.setQuickFilter("a."))
        #expect(!m.setQuickFilter("a.x"))
        #expect(m.quickFilter == "a.")
        #expect(names(m) == ["..", "a.txt"])
    }

    @Test func hiddenMarksAreNeverTargets() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.selectAll()
        #expect(m.setQuickFilter(".md"))
        #expect(m.selectedItems.map(\.name) == ["c.md"])
        // The marks come back when the filter is cleared.
        m.setQuickFilter(nil)
        #expect(m.selectedItems.count == 5)
    }

    @Test func navigationClearsRefreshKeeps() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.setQuickFilter("txt")
        await m.refresh()
        #expect(m.quickFilter == "txt")
        #expect(names(m) == ["..", "a.txt", "b.txt"])
        try await m.go(to: f.root.appendingPathComponent("docs"))
        #expect(m.quickFilter == nil)
        m.setQuickFilter("inner")
        try await m.goBack()
        #expect(m.quickFilter == nil)
        m.setQuickFilter("txt")
        try await m.restore(m.snapshot())
        #expect(m.quickFilter == nil)
    }

    @Test func worksOnTopOfTheMaskFilter() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.filter = WildcardMask("*.txt")
        #expect(m.setQuickFilter("b"))
        #expect(names(m) == ["..", "b.txt"])
        #expect(m.setQuickFilter("c"))
        #expect(names(m) == ["..", "docs"])  // the mask keeps folders; c.md is masked out
    }

    @Test func chords() {
        typealias K = KeyChord
        #expect(KeyMap.standard.command(for: K(.character("f"), [.command, .option])) == .quickFilter)
        #expect(KeyMap.standard.command(for: K(.character("s"), [.control, .shift])) == .quickFilterLast)
        #expect(KeyMap.standard.command(for: K(.character("f"), [.command, .option, .shift])) == .quickFilterLast)
        #expect(KeyMap.standard.command(for: K(.character("s"), .control)) == .pasteAsSymbolicLink)
        let classic = KeyMap(context: .panel, bindings: KeyBindings(scheme: .classicCommander))
        #expect(classic.command(for: K(.character("s"), .control)) == .quickFilter)
        #expect(classic.command(for: K(.character("v"), [.control, .command])) == .pasteAsSymbolicLink)
    }
}
