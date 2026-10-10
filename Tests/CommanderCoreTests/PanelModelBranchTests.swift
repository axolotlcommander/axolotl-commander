// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@MainActor
@Suite struct PanelModelBranchTests {
    /// A temporary folder (inside a folder of its own, so ".." stays small) with b.txt, notes.txt, docs/notes.txt, docs/a.md, .hidden.txt; the test
    /// removes it.
    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "axo-branch-\(UUID().uuidString)/tree", directoryHint: .isDirectory).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appending(path: "docs"), withIntermediateDirectories: true)
        for file in ["b.txt", "notes.txt", "docs/notes.txt", "docs/a.md", ".hidden.txt"] {
            try Data(count: 1).write(to: root.appending(path: file))
        }
        return root
    }

    private func names(_ m: PanelModel) -> [String] { m.items.map(\.name) }

    @Test func showsTheBranchSortedByFileName() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        do {
            let m = PanelModel(location: root)
            try await m.go(to: root)
            try await m.showBranch(BranchListing(root: root))
            #expect(m.branch != nil)
            #expect(m.location == root)
            // ".." first, then by the file's own name; equal names by their path.
            #expect(names(m) == ["..", "docs/a.md", "b.txt", "docs/notes.txt", "notes.txt"])
            #expect(m.remote == nil && m.results == nil)
        }
    }

    @Test func quickSearchAndFilterUseTheFileName() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        do {
            let m = PanelModel(location: root)
            try await m.showBranch(BranchListing(root: root))
            #expect(m.quickSearch("a"))
            #expect(m.cursorItem?.name == "docs/a.md")
            m.filter = WildcardMask("*.md")
            #expect(names(m) == ["..", "docs/a.md"])
        }
    }

    @Test func duplicateNamesAreMarkedSeparately() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        do {
            let m = PanelModel(location: root)
            try await m.showBranch(BranchListing(root: root))
            let index = try #require(m.items.firstIndex { $0.name == "docs/notes.txt" })
            m.toggleSelection(at: index)
            #expect(m.selectedItems.map(\.name) == ["docs/notes.txt"])
        }
    }

    @Test func leavingGoesToTheFolderOrItsParent() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        do {
            let m = PanelModel(location: root)
            try await m.go(to: root)
            try await m.showBranch(BranchListing(root: root))
            try await m.go(to: root, focusing: "notes.txt")
            #expect(m.branch == nil)
            #expect(m.cursorItem?.name == "notes.txt")
            // Back returns to the branch.
            try await m.goBack()
            #expect(m.branch != nil)
            // ".." goes to the parent folder, as in a normal listing.
            try await m.goParent()
            #expect(m.branch == nil)
            #expect(m.location.standardized == root.deletingLastPathComponent().standardized)
        }
    }

    @Test func refreshAndHiddenFilesRescan() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        do {
            let m = PanelModel(location: root)
            try await m.showBranch(BranchListing(root: root))
            try Data(count: 1).write(to: root.appending(path: "docs/new.txt"))
            await m.refresh()
            #expect(names(m).contains("docs/new.txt"))
            #expect(m.branch != nil)
        }
    }

    @Test func theBranchIsNotSaved() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        do {
            let m = PanelModel(location: root)
            try await m.go(to: root)
            try await m.showBranch(BranchListing(root: root))
            let state = m.snapshot()
            #expect(state.branch != nil)
            #expect(state.title.hasSuffix(")"))
            let decoded = try JSONDecoder().decode(PanelState.self, from: JSONEncoder().encode(state))
            #expect(decoded.branch == nil)
            #expect(decoded.back.allSatisfy { $0.branch == nil })
            // A tab keeps its branch in memory: restoring scans it again.
            let other = PanelModel(location: root)
            try await other.restore(state)
            #expect(other.branch != nil)
            #expect(names(other).contains("docs/a.md"))
        }
    }

    @Test func progressIsReportedAndEnds() async throws {
        let root = try makeTree()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        do {
            let m = PanelModel(location: root)
            var reports: [BranchProgress?] = []
            m.onBranchProgress = { reports.append($0) }
            try await m.showBranch(BranchListing(root: root))
            // The reports arrive on the main actor after the scan.
            for _ in 0..<20 where reports.last != .some(nil) { await Task.yield() }
            #expect(reports.contains { $0?.files == 4 })
            #expect(reports.last == .some(nil))
            #expect(!m.isScanningBranch)
        }
    }
}
