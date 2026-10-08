// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

@MainActor
@Suite struct PanelModelTests {
    /// Temp tree: dirs `docs/`, `Photos/`; files a.txt (3 B), b.txt (5 B), c.md (10 B), docs/inner.txt (7 B), docs/sub/deep.bin (100 B).
    final class Fixture {
        let root: URL
        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("AxolotlTests-\(UUID().uuidString)", isDirectory: true)
            let fm = FileManager.default
            try fm.createDirectory(at: root.appendingPathComponent("docs/sub"), withIntermediateDirectories: true)
            try fm.createDirectory(at: root.appendingPathComponent("Photos"), withIntermediateDirectories: true)
            try write("a.txt", 3); try write("b.txt", 5); try write("c.md", 10)
            try write("docs/inner.txt", 7); try write("docs/sub/deep.bin", 100)
        }
        func write(_ rel: String, _ bytes: Int) throws {
            try Data(count: bytes).write(to: root.appendingPathComponent(rel))
        }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    func names(_ m: PanelModel) -> [String] { m.items.map(\.name) }

    @Test func listing() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        #expect(names(m) == ["..", "docs", "Photos", "a.txt", "b.txt", "c.md"])
        #expect(m.items[0].isParent)
        #expect(m.items[1].isDirectory && m.items[1].size == nil)
        #expect(m.items[3].size == 3)
        #expect(m.cursor == 0)
        #expect(!m.isLoading)
    }

    @Test func hiddenFiles() async throws {
        let f = try Fixture()
        try f.write(".secret", 1)
        let m = PanelModel(location: f.root)
        await m.refresh()
        #expect(!names(m).contains(".secret"))
        m.showHidden = true
        await m.refresh()
        #expect(names(m).contains(".secret"))
        #expect(m.items.first { $0.name == ".secret" }?.isHidden == true)
    }

    @Test func symlinkToDirectoryIsDirectory() async throws {
        let f = try Fixture()
        try FileManager.default.createSymbolicLink(
            at: f.root.appendingPathComponent("link"), withDestinationURL: f.root.appendingPathComponent("docs"))
        let m = PanelModel(location: f.root)
        await m.refresh()
        let link = try #require(m.items.first { $0.name == "link" })
        #expect(link.isDirectory && link.isSymlink)
    }

    @Test func enterParentRestoresFocus() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.moveCursor(to: 1)  // docs
        #expect(try await m.enterCursor() == nil)
        #expect(m.location.lastPathComponent == "docs")
        #expect(names(m) == ["..", "sub", "inner.txt"])
        #expect(m.cursor == 0)
        m.moveCursor(to: 1)
        _ = try await m.enterCursor()
        #expect(m.location.lastPathComponent == "sub")
        try await m.goParent()
        #expect(m.cursorItem?.name == "sub")
        try await m.goParent()
        #expect(m.cursorItem?.name == "docs")
        // Parent row enters the parent too.
        m.moveCursor(to: 1)
        _ = try await m.enterCursor()
        m.moveCursor(to: 0)
        #expect(try await m.enterCursor() == nil)
        #expect(m.cursorItem?.name == "docs")
    }

    @Test func enterFileReturnsIt() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.moveCursor(to: 3)
        let item = try await m.enterCursor()
        #expect(item?.name == "a.txt")
        #expect(m.location == f.root)
    }

    @Test func backForwardRestoreCursor() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        #expect(!m.canGoBack && !m.canGoForward)
        m.moveCursor(to: 4)  // b.txt
        try await m.go(to: f.root.appendingPathComponent("docs"))
        #expect(m.canGoBack && !m.canGoForward)
        m.moveCursor(to: 2)  // inner.txt
        try await m.goBack()
        #expect(m.location == f.root)
        #expect(m.cursorItem?.name == "b.txt")
        #expect(m.canGoForward)
        try await m.goForward()
        #expect(m.location.lastPathComponent == "docs")
        #expect(m.cursorItem?.name == "inner.txt")
        #expect(!m.canGoForward)
    }

    @Test func failedNavigationLeavesStateUnchanged() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.moveCursor(to: 3)
        m.toggleSelection(at: 3)
        await #expect(throws: PathError.notFound) { try await m.go(to: f.root.appendingPathComponent("nope")) }
        await #expect(throws: PathError.notADirectory) { try await m.go(to: f.root.appendingPathComponent("a.txt")) }
        #expect(m.location == f.root)
        #expect(m.cursor == 3 && m.selection.count == 1)
        #expect(!m.canGoBack)
        #expect(m.lastError != nil)
    }

    @Test func historyIsCapped() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        let docs = f.root.appendingPathComponent("docs")
        for i in 0..<(PanelModel.historyLimit + 10) {
            try await m.go(to: i.isMultiple(of: 2) ? docs : f.root)
        }
        var steps = 0
        while m.canGoBack { try await m.goBack(); steps += 1 }
        #expect(steps == PanelModel.historyLimit)
    }

    @Test func goRootGoesToVolumeRoot() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        try await m.goRoot()
        #expect(m.location == Volumes.root(of: f.root))
    }

    @Test func selectionSurvivesSortFilterAndRefresh() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.toggleSelection(at: 0)  // parent row: ignored
        #expect(m.selection.isEmpty)
        m.toggleSelection(at: 3)  // a.txt
        m.toggleSelection(at: 5)  // c.md
        m.moveCursor(to: 5)

        m.sort = SortSpec(field: .size, ascending: false)
        #expect(names(m) == ["..", "docs", "Photos", "c.md", "b.txt", "a.txt"])
        #expect(m.cursorItem?.name == "c.md")
        #expect(m.selectedItems.map(\.name).sorted() == ["a.txt", "c.md"])

        m.filter = WildcardMask("*.txt")
        #expect(names(m) == ["..", "docs", "Photos", "b.txt", "a.txt"])
        #expect(m.selection.count == 2)
        #expect(m.selectedItems.map(\.name) == ["a.txt"])
        m.filter = nil
        #expect(m.selectedItems.count == 2)
        m.moveCursor(to: m.items.firstIndex { $0.name == "c.md" }!)

        try f.write("new.txt", 1)
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("a.txt"))
        await m.refresh()
        #expect(names(m).contains("new.txt") && !names(m).contains("a.txt"))
        #expect(m.selectedItems.map(\.name) == ["c.md"])
        #expect(m.cursorItem?.name == "c.md")
    }

    @Test func selectionOperations() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.select(mask: WildcardMask("*.txt"), true)
        #expect(m.selectedItems.map(\.name) == ["a.txt", "b.txt"])
        m.select(mask: WildcardMask("a.*"), false)
        #expect(m.selectedItems.map(\.name) == ["b.txt"])
        m.invertSelection()
        #expect(m.selectedItems.map(\.name) == ["a.txt", "c.md"])  // directories excluded by default
        m.deselectAll()
        m.selectAll()
        #expect(m.selectedItems.count == 5)  // parent never selected
        #expect(!m.isSelected(m.items[0]))
        m.deselectAll()
        m.moveCursor(to: 3)
        m.selectSameExtension(true)
        #expect(m.selectedItems.map(\.name) == ["a.txt", "b.txt"])
        m.selectSameExtension(false)
        #expect(m.selection.isEmpty)
        m.setSelected(true, range: 0...2)
        #expect(m.selectedItems.map(\.name) == ["docs", "Photos"])
        m.select(mask: WildcardMask("*"), true, includeDirectories: true)
        #expect(m.selectedItems.count == 5)
    }

    @Test func filterKeepsDirectories() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.filter = WildcardMask("*.md")
        #expect(names(m) == ["..", "docs", "Photos", "c.md"])
    }

    @Test func quickSearchWithNormalizationAndCycling() async throws {
        let f = try Fixture()
        try f.write("e\u{301}clair.txt", 1)  // NFD on disk
        try f.write("Echo.txt", 1)
        try f.write("echo2.txt", 1)
        let m = PanelModel(location: f.root)
        await m.refresh()
        #expect(m.quickSearch("\u{E9}cl"))  // NFC typed
        // Code units, not canonical equivalence: the stored NFD name, not an NFC copy of it.
        #expect(m.cursorItem.map { Array($0.name.unicodeScalars) } == Array("e\u{301}clair.txt".unicodeScalars))
        let before = m.cursor
        #expect(!m.quickSearch("zzz"))
        #expect(m.cursor == before)
        #expect(m.quickSearch("E"))
        let first = m.cursorItem?.name
        #expect(m.quickSearchNext("E", forward: true))
        let second = m.cursorItem?.name
        #expect(first != second)
        #expect(m.quickSearchNext("E", forward: true))
        #expect(m.cursorItem?.name == first)  // wrapped
        #expect(m.quickSearchNext("E", forward: false))
        #expect(m.cursorItem?.name == second)
        #expect(!m.quickSearch("."))  // parent row is not searchable
    }

    @Test func summaryAndCalculateSize() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        #expect(m.totals == SelectionSummary(files: 3, directories: 2, bytes: 18))
        m.toggleSelection(at: 1)  // docs
        m.toggleSelection(at: 4)  // b.txt
        #expect(m.summary == SelectionSummary(files: 1, directories: 1, bytes: 5))
        await m.calculateSize(of: m.items[1])
        #expect(m.directorySizes["docs"] == 107)
        #expect(m.summary == SelectionSummary(files: 1, directories: 1, bytes: 112))
        await m.refresh()
        #expect(m.directorySizes["docs"] == 107)  // survives refresh
        try await m.go(to: f.root.appendingPathComponent("docs"))
        #expect(m.directorySizes.isEmpty)
    }

    @Test func calculateSizeIgnoresSymlinks() async throws {
        let f = try Fixture()
        try FileManager.default.createSymbolicLink(
            at: f.root.appendingPathComponent("docs/loop"), withDestinationURL: f.root)
        let m = PanelModel(location: f.root)
        await m.refresh()
        await m.calculateSize(of: m.items[1])
        #expect(m.directorySizes["docs"] == 107)
    }

    @Test func cursorClamping() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.moveCursor(to: 99)
        #expect(m.cursor == m.items.count - 1)
        m.moveCursor(by: -99)
        #expect(m.cursor == 0)
    }

    @Test func fakeSourceAndRoot() async throws {
        struct Fake: FileSource {
            func list(_ directory: URL, includeHidden: Bool) async throws -> [FileItem] {
                [FileItem(url: directory.appendingPathComponent("x"), size: 1)]
            }
        }
        let m = PanelModel(location: URL(fileURLWithPath: "/"), source: Fake())
        await m.refresh()
        #expect(names(m) == ["x"])  // no parent row at "/"
    }

    // MARK: Find results in the panel

    @Test func resultsListRelativeNamesAndGoBack() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        await m.refresh()
        let listing = ResultsListing(title: "Found", urls: [
            f.root.appendingPathComponent("docs/sub/deep.bin"),
            f.root.appendingPathComponent("docs/inner.txt"),
        ])
        #expect(listing.root.standardizedFileURL.path == f.root.appendingPathComponent("docs").standardizedFileURL.path)
        try await m.showResults(listing, focusing: "inner.txt")
        #expect(m.results == listing)
        #expect(names(m) == ["..", "inner.txt", "sub/deep.bin"])
        #expect(m.cursorItem?.name == "inner.txt")
        #expect(m.items[2].url.lastPathComponent == "deep.bin" && m.items[2].size == 100)
        #expect(m.snapshot().title == "Found")

        // ".." leaves for the root folder; Back returns to the results.
        try await m.goParent()
        #expect(m.results == nil)
        #expect(names(m) == ["..", "sub", "inner.txt"])
        try await m.goBack()
        #expect(m.results == listing)
        #expect(m.cursorItem?.name == "inner.txt")
        try await m.goBack()
        #expect(m.results == nil)
        #expect(m.location.standardizedFileURL.path == f.root.standardizedFileURL.path)
        try await m.goForward()
        #expect(m.results == listing)
    }

    @Test func resultsFollowRenamedItems() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        let listing = ResultsListing(title: "Found", urls: [
            f.root.appendingPathComponent("docs/sub/deep.bin"),
            f.root.appendingPathComponent("docs/inner.txt"),
        ])
        try await m.showResults(listing)
        let docs = f.root.appendingPathComponent("docs")
        try FileManager.default.moveItem(at: docs.appendingPathComponent("sub"), to: docs.appendingPathComponent("lower"))
        m.replaceResult(docs.appendingPathComponent("sub"), with: docs.appendingPathComponent("lower"))
        try FileManager.default.moveItem(at: docs.appendingPathComponent("inner.txt"), to: docs.appendingPathComponent("outer.txt"))
        m.replaceResult(docs.appendingPathComponent("inner.txt"), with: docs.appendingPathComponent("outer.txt"))
        await m.refresh()
        #expect(names(m) == ["..", "lower/deep.bin", "outer.txt"])
        // A sibling whose name merely starts the same is left alone.
        let other = listing.replacing(docs.appendingPathComponent("su"), with: docs.appendingPathComponent("x"))
        #expect(other.urls == listing.urls)
    }

    @Test func resultsRefreshDropsVanishedItems() async throws {
        let f = try Fixture()
        let m = PanelModel(location: f.root)
        try await m.showResults(ResultsListing(title: "R", urls: [
            f.root.appendingPathComponent("a.txt"), f.root.appendingPathComponent("docs/inner.txt"),
        ]))
        #expect(names(m) == ["..", "a.txt", "docs/inner.txt"])
        m.selectAll()
        #expect(m.summary.files == 2)
        try FileManager.default.removeItem(at: f.root.appendingPathComponent("a.txt"))
        await m.refresh()
        #expect(names(m) == ["..", "docs/inner.txt"])
        #expect(m.summary.files == 1)
    }

    @Test func resultsAreNotPersisted() throws {
        let listing = ResultsListing(title: "R", urls: [URL(filePath: "/tmp/a")])
        let state = PanelState(location: URL(filePath: "/tmp"), back: [.init(url: URL(filePath: "/"), results: listing)],
                               results: listing)
        let decoded = try JSONDecoder().decode(PanelState.self, from: JSONEncoder().encode(state))
        #expect(decoded.results == nil && decoded.back.first?.results == nil)
        #expect(decoded.back.first?.url.path == "/")
    }

    @Test(arguments: [
        (["/a/b/c.txt", "/a/b/d/e.txt"], "/a/b"),
        (["/a/b/c.txt", "/a/x/e.txt"], "/a"),
        (["/a/c.txt", "/b/e.txt"], "/"),
        (["/a/b/c.txt"], "/a/b"),
        ([String](), "/"),
    ])
    func commonFolder(paths: [String], expected: String) {
        #expect(ResultsListing.commonFolder(of: paths.map { URL(filePath: $0) }).path == expected)
    }

    @Test func archiveIsEnteredLikeAFolder() async throws {
        let f = try Fixture()
        let zip = f.root.appendingPathComponent("pack.zip")
        try await ArchiveWriter.create(zip, format: .zip, adding: [
            .init(file: f.root.appendingPathComponent("docs"), path: "docs"),
            .init(file: f.root.appendingPathComponent("a.txt"), path: "A.txt"),
            .init(file: f.root.appendingPathComponent("b.txt"), path: "a.txt"),
        ], progress: { _ in })
        let m = PanelModel(location: f.root)
        await m.refresh()
        m.moveCursor(to: try #require(m.items.firstIndex { $0.name == "pack.zip" }))
        #expect(try await m.enterCursor() == nil)
        #expect(m.archive?.archive.lastPathComponent == "pack.zip")
        #expect(m.archive?.inner == "")
        // Case-sensitive inside: two members differing only in case are two rows.
        #expect(names(m) == ["..", "docs", "a.txt", "A.txt"] || names(m) == ["..", "docs", "A.txt", "a.txt"])
        m.moveCursor(to: 1)
        _ = try await m.enterCursor()
        #expect(m.archive?.inner == "docs")
        #expect(names(m) == ["..", "sub", "inner.txt"])
        await m.calculateSize(of: m.items[1])
        #expect(m.directorySizes[m.rules.key("sub")] == 100)

        try await m.goParent()
        #expect(m.archive?.inner == "")
        #expect(m.cursorItem?.name == "docs")
        try await m.goParent()
        #expect(m.archive == nil)
        #expect(m.cursorItem?.name == "pack.zip")
        // The pseudo path is restorable like any folder.
        try await m.go(to: zip.appendingPathComponent("docs/sub"))
        #expect(names(m) == ["..", "deep.bin"])
    }

    @Test func otherPanelTarget() async throws {
        let f = try Fixture()
        try f.write("pack.zip", 1)
        try FileManager.default.createDirectory(at: f.root.appendingPathComponent("App.app"), withIntermediateDirectories: true)
        let m = PanelModel(location: f.root)
        await m.refresh()
        func target(_ name: String) -> (url: URL, focus: String?)? {
            m.moveCursor(to: m.items.firstIndex { $0.name == name } ?? 0)
            return m.otherPanelTarget
        }
        #expect(target("..") == nil)
        // A folder (or an archive) opens; a file or a package is shown in its folder.
        #expect(target("docs")?.url.lastPathComponent == "docs")
        #expect(target("docs")?.focus == nil)
        #expect(target("pack.zip")?.url.lastPathComponent == "pack.zip")
        #expect(target("pack.zip")?.focus == nil)
        #expect(target("a.txt")?.url.standardizedFileURL.path == f.root.standardizedFileURL.path)
        #expect(target("a.txt")?.focus == "a.txt")
        #expect(target("App.app")?.focus == "App.app")
    }
}

@Suite struct DirectoryWatcherTests {
    @Test func reportsChangesDebounced() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AxolotlWatch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let count = LockedCounter()
        let watcher = try #require(DirectoryWatcher(url: dir) { count.increment() })
        for i in 0..<5 { try Data().write(to: dir.appendingPathComponent("f\(i)")) }
        try await Task.sleep(for: .milliseconds(600))
        #expect(count.value >= 1 && count.value <= 2)
        watcher.cancel()
        try Data().write(to: dir.appendingPathComponent("after"))
        let seen = count.value
        try await Task.sleep(for: .milliseconds(400))
        #expect(count.value == seen)
        #expect(DirectoryWatcher(url: dir.appendingPathComponent("missing"), onChange: {}) == nil)
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}
