// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct BranchScannerTests {
    /// a.txt, notes.txt, docs/notes.txt, docs/deep/d.txt, .hidden/h.txt, .dot.txt, App.app/inner,
    /// loop -> . (a link to the folder itself), locked/x.txt.
    private func makeTree(_ root: URL) throws {
        let fm = FileManager.default
        for dir in ["docs/deep", ".hidden", "App.app/Contents", "locked"] {
            try fm.createDirectory(at: root.appending(path: dir), withIntermediateDirectories: true)
        }
        for (file, bytes) in [("a.txt", 1), ("notes.txt", 2), ("docs/notes.txt", 3), ("docs/deep/d.txt", 4),
                              (".hidden/h.txt", 5), (".dot.txt", 6), ("App.app/Contents/inner", 7), ("locked/x.txt", 8)] {
            try Data(count: bytes).write(to: root.appending(path: file))
        }
        try fm.createSymbolicLink(at: root.appending(path: "loop"), withDestinationURL: root)
    }

    private func names(_ result: BranchResult) -> [String] { result.items.map(\.name).sorted() }

    @Test func listsTheFilesOfTheWholeTree() async throws {
        try await TestSandbox.with("branch") { root in
            try makeTree(root)
            let result = try await BranchScanner.scan(BranchListing(root: root), source: LocalFileSource(), includeHidden: false)
            // Files only, named by their path below the root; the package is a file; the link to the
            // folder is not entered.
            #expect(names(result) == ["App.app", "a.txt", "docs/deep/d.txt", "docs/notes.txt", "locked/x.txt", "notes.txt"])
            #expect(result.unreadable == 0)
            let deep = try #require(result.items.first { $0.name == "docs/deep/d.txt" })
            #expect(deep.url.resolvingSymlinksInPath() == root.appending(path: "docs/deep/d.txt").resolvingSymlinksInPath())
            #expect(deep.fileName == "d.txt")
            #expect(deep.size == 4)
        }
    }

    @Test func hiddenItemsFollowTheSetting() async throws {
        try await TestSandbox.with("branch") { root in
            try makeTree(root)
            let result = try await BranchScanner.scan(BranchListing(root: root), source: LocalFileSource(), includeHidden: true)
            #expect(names(result).contains(".hidden/h.txt"))
            #expect(names(result).contains(".dot.txt"))
        }
    }

    @Test func unreadableFoldersAreCountedAndSkipped() async throws {
        try await TestSandbox.with("branch") { root in
            try makeTree(root)
            chmod(root.appending(path: "locked").path, 0o000)
            defer { chmod(root.appending(path: "locked").path, 0o755) }
            let result = try await BranchScanner.scan(BranchListing(root: root), source: LocalFileSource(), includeHidden: false)
            #expect(result.unreadable == 1)
            #expect(!names(result).contains("locked/x.txt"))
            #expect(names(result).contains("docs/deep/d.txt"))
        }
    }

    @Test func aMissingRootIsAnError() async throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "branch-missing-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            _ = try await BranchScanner.scan(BranchListing(root: missing), source: LocalFileSource(), includeHidden: false)
        }
    }

    @Test func markedItemsListTheFilesAndTheFoldersContents() async throws {
        try await TestSandbox.with("branch") { root in
            try makeTree(root)
            let listing = BranchListing(root: root, starts: [root.appending(path: "a.txt"), root.appending(path: "docs")])
            let result = try await BranchScanner.scan(listing, source: LocalFileSource(), includeHidden: false)
            #expect(names(result) == ["a.txt", "docs/deep/d.txt", "docs/notes.txt"])
        }
    }

    @Test func progressEndsWithTheCount() async throws {
        try await TestSandbox.with("branch") { root in
            try makeTree(root)
            let reports = Reports()
            _ = try await BranchScanner.scan(BranchListing(root: root), source: LocalFileSource(), includeHidden: false,
                                             progress: { reports.add($0) })
            #expect(reports.last == BranchProgress(files: 6, folder: ""))
        }
    }

    @Test func cancellingStopsTheScan() async throws {
        let source = SlowSource()
        let task = Task {
            try await BranchScanner.scan(BranchListing(root: URL(string: "sftp://host/top")!), source: source, includeHidden: false)
        }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func serverAndArchiveFoldersAreWalkedThroughTheSource() async throws {
        let root = URL(string: "sftp://host/top")!
        let tree: [String: [FileItem]] = [
            "sftp://host/top": [FileItem(url: URL(string: "sftp://host/top/a.txt")!, size: 1),
                                FileItem(url: URL(string: "sftp://host/top/sub")!, isDirectory: true)],
            "sftp://host/top/sub": [FileItem(url: URL(string: "sftp://host/top/sub/b.txt")!, size: 2),
                                    FileItem(url: URL(string: "sftp://host/top/sub/gone")!, isDirectory: true)],
        ]
        let result = try await BranchScanner.scan(BranchListing(root: root), source: TreeSource(tree: tree), includeHidden: false)
        #expect(names(result) == ["a.txt", "sub/b.txt"])
        #expect(result.unreadable == 1)
        #expect(result.items.first { $0.name == "sub/b.txt" }?.url.absoluteString == "sftp://host/top/sub/b.txt")
    }

    @Test func sourcesAreGroupedByFolder() {
        let urls = [URL(filePath: "/a/z.zip/x/1"), URL(filePath: "/a/z.zip/2"), URL(filePath: "/a/z.zip/x/3")]
        let groups = SourceGroups.byFolder(urls)
        #expect(groups.map(\.folder.path) == ["/a/z.zip/x", "/a/z.zip"])
        #expect(groups.map(\.names) == [["1", "3"], ["2"]])
    }

    @Test func fileNameAndExtensionIgnoreTheFolder() {
        let item = FileItem(url: URL(filePath: "/r/docs.v2/readme"), name: "docs.v2/readme")
        #expect(item.fileName == "readme")
        #expect(item.fileExtension == "")
        #expect(item.baseName == "docs.v2/readme")
        let pdf = FileItem(url: URL(filePath: "/r/vzorky/tisk.pdf"), name: "vzorky/tisk.pdf")
        #expect(pdf.fileExtension == "pdf")
        #expect(pdf.baseName == "vzorky/tisk")
        #expect(pdf.fileBaseName == "tisk")
    }
}

private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [BranchProgress] = []
    func add(_ p: BranchProgress) { lock.withLock { items.append(p) } }
    var last: BranchProgress? { lock.withLock { items.last } }
}

/// Folders listed from a dictionary by URL; a missing folder fails like a vanished one.
private struct TreeSource: FileSource {
    let tree: [String: [FileItem]]
    func list(_ directory: URL, includeHidden: Bool) async throws -> [FileItem] {
        guard let items = tree[directory.absoluteString] else { throw PathError.notFound }
        return items
    }
}

/// An endless, slow server: every folder holds one more folder.
private struct SlowSource: FileSource {
    func list(_ directory: URL, includeHidden: Bool) async throws -> [FileItem] {
        try await Task.sleep(for: .milliseconds(10))
        return [FileItem(url: directory.appending(path: "f"), size: 1),
                FileItem(url: directory.appending(path: "d"), isDirectory: true)]
    }
}
