// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct HistoryListTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }
    private func places(_ paths: [String]) -> [PanelState.Place] { paths.map { PanelState.Place(url: url($0)) } }
    private func texts(_ entries: [FolderHistory.Entry]) -> [String] { entries.map(\.text) }
    private func build(back: [String], current: String, forward: [String] = [], recent: [String] = [])
        -> [FolderHistory.Entry] {
        FolderHistory.entries(back: places(back), current: url(current), forward: places(forward),
                              recent: recent, display: \.path)
    }

    @Test func timeOrderAroundTheCurrentFolder() {
        // Visited /a, /b, /c, /d, /e, then went Back twice: the current folder is /c.
        let entries = build(back: ["/a", "/b"], current: "/c", forward: ["/e", "/d"])
        #expect(texts(entries) == ["/e", "/d", "/c", "/b", "/a"])
        #expect(entries.map(\.isCurrent) == [false, false, true, false, false])
        #expect(FolderHistory.initialSelection(in: entries) == 3)
    }

    @Test func duplicatesStayClosestToTheCurrentFolder() {
        let entries = build(back: ["/x", "/a", "/x", "/b"], current: "/a", forward: ["/x"])
        // /a is current; /x is one step forward and two steps back: the forward one stays.
        #expect(texts(entries) == ["/x", "/a", "/b"])
        #expect(entries[1].isCurrent)
    }

    @Test func recentPathsFollowWithoutDuplicates() {
        let entries = build(back: ["/a"], current: "/b", recent: ["/b/", "/c", "sftp://host/data", "/a"])
        #expect(texts(entries) == ["/b", "/a", "/c", "sftp://host/data"])
        #expect(entries[2].target == .typed("/c"))
        #expect(entries[1].target == .location(url("/a")))
    }

    @Test func linkedSystemFoldersAreOneEntry() {
        let entries = build(back: ["/tmp/w", "/private/tmp/w/c"], current: "/private/tmp/w",
                            recent: ["/tmp/w/c", "/private/var/log"])
        #expect(texts(entries) == ["/private/tmp/w", "/private/tmp/w/c", "/private/var/log"])
        #expect(FolderHistory.key("/private") == "/private")
        #expect(FolderHistory.key("/private/tmpfiles") == "/private/tmpfiles")
    }

    @Test func selectionStaysOnTheCurrentFolderWithoutBackHistory() {
        #expect(FolderHistory.initialSelection(in: build(back: [], current: "/a")) == 0)
        #expect(FolderHistory.initialSelection(in: build(back: [], current: "/a", recent: ["/r"])) == 0)
        #expect(FolderHistory.initialSelection(in: build(back: [], current: "/a", forward: ["/f"])) == 1)
        #expect(FolderHistory.initialSelection(in: []) == nil)
    }

    @Test func filterNeedsEveryWordIgnoringCaseAndDiacritics() {
        #expect(HistoryFilter.matches("/Users/me/Projekty/Účty", query: "proj ucty"))
        #expect(HistoryFilter.matches("/Users/me/Projekty", query: ""))
        #expect(HistoryFilter.matches("/Users/me/Projekty", query: "  me  "))
        #expect(!HistoryFilter.matches("/Users/me/Projekty", query: "proj docs"))
    }

    @Test func chords() {
        typealias K = KeyChord
        #expect(KeyMap.standard.command(for: K(.character("h"), [.control, .command])) == .folderHistory)
        #expect(KeyMap.standard.command(for: K(.function(8), .option)) == .commandLineHistory)
        #expect(KeyMap.standard.command(for: K(.down, .option)) == nil)
        let classic = KeyMap(context: .panel, bindings: KeyBindings(scheme: .classicCommander))
        #expect(classic.command(for: K(.down, .option)) == .folderHistory)
        #expect(classic.command(for: K(.character("h"), [.control, .command])) == .folderHistory)
        #expect(classic.command(for: K(.function(8), .option)) == .commandLineHistory)
    }
}
