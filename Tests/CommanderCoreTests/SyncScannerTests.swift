// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Darwin
import Synchronization
import Testing
@testable import CommanderCore

let syncT0 = Date(timeIntervalSince1970: 1_500_000_000)

/// Two sandbox folders L and R to compare.
struct SyncFolders {
    let left: URL
    let right: URL

    init(_ root: URL) throws {
        left = root.appending(path: "L")
        right = root.appending(path: "R")
        try TestSandbox.mkdirs(left)
        try TestSandbox.mkdirs(right)
    }

    func url(_ side: Side, _ path: String) -> URL {
        (side == .left ? left : right).appending(path: path)
    }

    /// A file with the given text and date (folders on the way are created).
    func file(_ side: Side, _ path: String, _ text: String = "x", at date: Date = syncT0) throws {
        let url = url(side, path)
        try TestSandbox.mkdirs(url.deletingLastPathComponent())
        try TestSandbox.write(url, text)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func folder(_ side: Side, _ path: String) throws {
        try TestSandbox.mkdirs(url(side, path))
    }

    /// A symbolic link with its own date (the target is not touched).
    func link(_ side: Side, _ path: String, to target: String, at date: Date = syncT0) throws {
        let url = url(side, path)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: target)
        var times = [timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0),
                     timeval(tv_sec: Int(date.timeIntervalSince1970), tv_usec: 0)]
        #expect(lutimes(url.path, &times) == 0)
    }

    func compare(_ options: SyncOptions = SyncOptions(), hidden: Bool = false) async throws -> SyncComparison {
        try await SyncScanner.compare(left: left, right: right, options: options, includeHidden: hidden, progress: { _ in })
    }
}

extension SyncComparison {
    func item(_ path: String) -> SyncItem? { items.first { $0.path == path } }
    var paths: [String] { items.map(\.path) }
}

private func opts(_ change: (inout SyncOptions) -> Void) -> SyncOptions {
    var o = SyncOptions()
    change(&o)
    return o
}

@Suite struct SyncScannerTests {
    @Test func onlyLeftAndOnlyRight() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "a.txt", "abc")
            try f.file(.right, "b.txt", "defg")
            let c = try await f.compare()
            #expect(c.paths == ["a.txt", "b.txt"])
            let a = try #require(c.item("a.txt"))
            #expect(a.state == .onlyLeft && a.action == .toRight && a.right == nil)
            #expect(a.left == SyncSide(kind: .file, size: 3, fileCount: 1, modified: syncT0))
            let b = try #require(c.item("b.txt"))
            #expect(b.state == .onlyRight && b.action == .toLeft && b.left == nil && b.right?.size == 4)
        }
    }

    @Test func datesWithinToleranceAndTheHourRule() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "close", at: syncT0)
            try f.file(.right, "close", at: syncT0.addingTimeInterval(1))
            try f.file(.left, "two", at: syncT0)
            try f.file(.right, "two", at: syncT0.addingTimeInterval(-2))
            try f.file(.left, "hour", at: syncT0.addingTimeInterval(3600))
            try f.file(.right, "hour", at: syncT0)
            try f.file(.left, "hourish", at: syncT0)
            try f.file(.right, "hourish", at: syncT0.addingTimeInterval(3601))
            try f.file(.left, "newer", at: syncT0.addingTimeInterval(10))
            try f.file(.right, "newer", at: syncT0)
            try f.file(.left, "older", at: syncT0)
            try f.file(.right, "older", at: syncT0.addingTimeInterval(10))
            let c = try await f.compare()
            #expect(c.item("close")?.state == .equal)
            #expect(c.item("two")?.state == .equal)
            #expect(c.item("hour")?.state == .equal)
            #expect(c.item("hourish")?.state == .equal)
            #expect(c.item("newer")?.state == .leftNewer)
            #expect(c.item("newer")?.action == .toRight)
            #expect(c.item("older")?.state == .rightNewer)
            #expect(c.item("older")?.action == .toLeft)
            #expect(c.item("close")?.action == SyncAction.none)

            let strict = try await f.compare(opts { $0.ignoreHourDifference = false })
            #expect(strict.item("hour")?.state == .leftNewer)
            #expect(strict.item("hourish")?.state == .rightNewer)
            #expect(strict.item("close")?.state == .equal)
        }
    }

    @Test func sizeDifference() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "size", "abc")
            try f.file(.right, "size", "abcd")
            // A newer date wins over a size difference.
            try f.file(.left, "both", "abc", at: syncT0.addingTimeInterval(100))
            try f.file(.right, "both", "abcd")
            let c = try await f.compare()
            #expect(c.item("size")?.state == .different)
            #expect(c.item("size")?.action == SyncAction.none)
            #expect(c.item("both")?.state == .leftNewer)
            let sizeOnly = try await f.compare(opts { $0.compareDate = false })
            #expect(sizeOnly.item("both")?.state == .different)
            let nothing = try await f.compare(opts { $0.compareDate = false; $0.compareSize = false })
            #expect(nothing.item("size")?.state == .equal)
        }
    }

    @Test func contentOnlyWhenAskedAndOnlyForSameSizes() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "same", "hello")
            try f.file(.right, "same", "hello")
            try f.file(.left, "bytes", "hello")
            try f.file(.right, "bytes", "jello")
            let c = try await f.compare()
            #expect(c.item("bytes")?.state == .equal)
            let content = try await f.compare(opts { $0.compareContent = true })
            #expect(content.item("bytes")?.state == .different)
            #expect(content.item("same")?.state == .equal)

            // A newer side is not read.
            try f.file(.left, "bytes", "hello", at: syncT0.addingTimeInterval(50))
            let newer = try await f.compare(opts { $0.compareContent = true })
            #expect(newer.item("bytes")?.state == .leftNewer)
        }
    }

    @Test func differentSizesAreNotRead() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "a", "short")
            try f.file(.right, "a", "much longer")
            let read = Mutex<Int64>(0)
            let c = try await SyncScanner.compare(
                left: f.left, right: f.right, options: opts { $0.compareSize = false; $0.compareContent = true },
                includeHidden: false, progress: { p in read.withLock { $0 = max($0, p.bytesRead) } })
            #expect(c.item("a")?.state == .different)
            #expect(read.withLock { $0 } == 0)

            try f.file(.right, "a", "SHORT")
            let read2 = Mutex<Int64>(0)
            _ = try await SyncScanner.compare(
                left: f.left, right: f.right, options: opts { $0.compareContent = true },
                includeHidden: false, progress: { p in read2.withLock { $0 = max($0, p.bytesRead) } })
            #expect(read2.withLock { $0 } == 10)
        }
    }

    @Test func fileFacingAFolder() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "thing", "abc")
            try f.file(.right, "thing/inner1", "12345")
            try f.file(.right, "thing/sub/inner2", "12")
            let c = try await f.compare()
            #expect(c.paths == ["thing"])
            let t = try #require(c.item("thing"))
            #expect(t.state == .different && t.action == SyncAction.none)
            #expect(t.right == SyncSide(kind: .folder, size: 7, fileCount: 2, modified: t.right?.modified))
        }
    }

    @Test func linksByTargetNeverFollowed() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "big/one", "1111")
            try f.link(.left, "same", to: "big")
            try f.link(.right, "same", to: "big")
            try f.link(.left, "other", to: "x")
            try f.link(.right, "other", to: "y")
            try f.link(.left, "newer", to: "x", at: syncT0.addingTimeInterval(100))
            try f.link(.right, "newer", to: "y")
            try f.link(.left, "vsfile", to: "big")
            try f.file(.right, "vsfile", "data")
            try f.link(.left, "dirlink", to: f.left.appending(path: "big").path)
            let c = try await f.compare()
            #expect(c.item("same")?.state == .equal)
            #expect(c.item("same")?.left?.kind == .link(target: "big"))
            #expect(c.item("other")?.state == .different)
            #expect(c.item("newer")?.state == .leftNewer)
            #expect(c.item("vsfile")?.state == .different)
            // A link to a folder is a link: one row, not walked, no folder totals.
            let d = try #require(c.item("dirlink"))
            #expect(d.state == .onlyLeft && d.left?.kind == .link(target: f.left.appending(path: "big").path))
            #expect(d.left?.fileCount == 1)
            #expect(!c.paths.contains { $0.hasPrefix("dirlink/") })
            let undated = try await f.compare(opts { $0.compareDate = false })
            #expect(undated.item("newer")?.state == .different)
        }
    }

    @Test func packagesAreWalked() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "Tool.app/Contents/Info.plist", "aaa", at: syncT0.addingTimeInterval(10))
            try f.file(.right, "Tool.app/Contents/Info.plist", "aaa")
            let c = try await f.compare()
            #expect(c.paths == ["Tool.app", "Tool.app/Contents", "Tool.app/Contents/Info.plist"])
            #expect(c.item("Tool.app")?.state == .equal)
            #expect(c.item("Tool.app/Contents/Info.plist")?.state == .leftNewer)
            #expect(c.item("Tool.app/Contents/Info.plist")?.depth == 2)
        }
    }

    @Test func composedAndDecomposedNamesMatch() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try TestSandbox.write(f.left.child("caf\u{E9}"), "x")
            try TestSandbox.write(f.right.child("cafe\u{301}"), "x")
            for url in [f.left.child("caf\u{E9}"), f.right.child("cafe\u{301}")] {
                try FileManager.default.setAttributes([.modificationDate: syncT0], ofItemAtPath: url.path)
            }
            let c = try await f.compare()
            #expect(c.items.count == 1)
            #expect(c.items.first?.state == .equal)
        }
    }

    @Test func caseOnCaseInsensitiveRules() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            guard !NameRules.forVolume(containing: root).caseSensitive else { return }
            try f.file(.left, "Docs/Readme.txt", "abc", at: syncT0.addingTimeInterval(10))
            try f.file(.right, "docs/README.txt", "abc")
            let c = try await f.compare()
            #expect(c.paths == ["Docs", "Docs/Readme.txt"])
            let r = try #require(c.item("Docs/Readme.txt"))
            #expect(r.state == .leftNewer)
            #expect(r.leftPath == "Docs/Readme.txt" && r.rightPath == "docs/README.txt")
            #expect(c.url(of: r, on: .right).path == f.right.path + "/docs/README.txt")
        }
    }

    @Test func missingSideKeepsItsParentSpelling() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            guard !NameRules.forVolume(containing: root).caseSensitive else { return }
            try f.file(.left, "Docs/new.txt")
            try f.folder(.right, "docs")
            let c = try await f.compare()
            let n = try #require(c.item("Docs/new.txt"))
            #expect(c.url(of: n, on: .right).path == f.right.path + "/docs/new.txt")
        }
    }

    @Test func nameClashIsAnErrorRow() throws {
        try TestSandbox.with(sync: { root in
            let f = try SyncFolders(root)
            try f.file(.left, "a.txt")
            try f.file(.right, "a.txt")
            try f.file(.right, "b.txt")
            // A case-sensitive side lists "a.txt" and "A.TXT"; this volume cannot hold both.
            let list: (URL, SyncFilter) throws -> [SyncEntry] = { url, filter in
                var entries = try SyncEntry.list(url, filter: filter)
                if url == f.right, let a = entries.first(where: { $0.name == "a.txt" }) {
                    var twin = a
                    twin.name = "A.TXT"
                    entries.append(twin)
                }
                return entries
            }
            let c = try SyncScanner.compare(left: f.left, right: f.right, options: SyncOptions(), includeHidden: false,
                                            rules: .apfsDefault, list: list, progress: { _ in })
            #expect(c.paths == ["A.TXT", "a.txt", "b.txt"])
            for path in ["A.TXT", "a.txt"] {
                let item = try #require(c.item(path))
                guard case .error(let reason) = item.state else { Issue.record("not an error row"); continue }
                #expect(reason.contains(path == "a.txt" ? "A.TXT" : "a.txt"))
                #expect(item.action == SyncAction.none)
                #expect(SyncRules.possible(item, options: SyncOptions()) == [SyncAction.none])
            }
            #expect(c.item("a.txt")?.left != nil && c.item("A.TXT")?.left == nil)
            #expect(c.item("b.txt")?.state == .onlyRight)
        })
    }

    @Test func ignoreMasksAtEveryDepth() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "main.o")
            try f.file(.left, "src/deep/x.o")
            try f.file(.left, "src/deep/x.c")
            try f.file(.right, "src/build/out")
            try f.file(.left, "build/out")
            try f.file(.right, "src/.git/HEAD")
            try f.folder(.left, "x.o")
            let o = opts { $0.ignoreFiles = "*.o;.DS_Store"; $0.ignoreFolders = "build;.git" }
            let c = try await f.compare(o, hidden: true)
            #expect(c.paths == ["src", "src/deep", "x.o"])
            #expect(c.item("src/deep")?.left?.fileCount == 1)
            let blank = try await f.compare(opts { $0.ignoreFiles = "  "; $0.ignoreFolders = "" }, hidden: true)
            #expect(blank.paths.contains("main.o") && blank.paths.contains("build"))
        }
    }

    @Test func hiddenItemsFollowTheSetting() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, ".env")
            try f.file(.left, "dir/.hidden")
            try f.file(.left, "dir/shown")
            let flagged = f.url(.left, "flagged")
            try TestSandbox.write(flagged, "x")
            var values = URLResourceValues()
            values.isHidden = true
            var target = flagged
            try target.setResourceValues(values)
            let shown = try await f.compare()
            #expect(shown.paths == ["dir"])
            #expect(shown.item("dir")?.left?.fileCount == 1)
            let all = try await f.compare(hidden: true)
            #expect(all.paths == [".env", "dir", "flagged"])
            #expect(all.item("dir")?.left?.fileCount == 2)
        }
    }

    @Test func oneSidedFolderIsOneRowWithTotals() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "proj/a", "12345")
            try f.file(.left, "proj/sub/b", "123")
            try f.file(.left, "proj/sub/deeper/c", "1")
            try f.link(.left, "proj/link", to: "nowhere")
            try f.folder(.right, "empty")
            let c = try await f.compare()
            #expect(c.paths == ["empty", "proj"])
            let p = try #require(c.item("proj"))
            #expect(p.state == .onlyLeft && p.action == .toRight)
            #expect(p.left?.kind == .folder && p.left?.fileCount == 4)
            #expect(p.left?.size == 9 + Int64("nowhere".utf8.count))
            #expect(c.item("empty")?.right?.fileCount == 0)
        }
    }

    @Test func unreadableFolderIsAnErrorRow() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "locked/a", "1")
            try f.file(.right, "locked/a", "2", at: syncT0.addingTimeInterval(100))
            try f.file(.left, "fine", "1")
            #expect(chmod(f.url(.left, "locked").path, 0o000) == 0)
            defer { chmod(f.url(.left, "locked").path, 0o755) }
            let c = try await f.compare()
            #expect(c.paths == ["fine", "locked"])
            let l = try #require(c.item("locked"))
            guard case .error = l.state else { Issue.record("expected an error row"); return }
            #expect(l.action == SyncAction.none)
        }
    }

    @Test func unreadableTopFolderThrows() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            await #expect(throws: (any Error).self) {
                try await SyncScanner.compare(left: f.left.appending(path: "missing"), right: f.right,
                                              options: SyncOptions(), includeHidden: false, progress: { _ in })
            }
        }
    }

    @Test func subfoldersOff() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "both/a", "1", at: syncT0.addingTimeInterval(100))
            try f.file(.right, "both/a", "1")
            try f.file(.left, "solo/x", "12")
            try f.file(.left, "top", "1")
            let c = try await f.compare(opts { $0.includeSubfolders = false })
            #expect(c.paths == ["both", "solo", "top"])
            #expect(c.item("both")?.state == .equal)
            #expect(c.item("solo")?.left?.fileCount == 1)
            let deep = try await f.compare()
            #expect(deep.paths == ["both", "both/a", "solo", "top"])
        }
    }

    @Test func sortedFolderBeforeItsContents() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "b/z")
            try f.file(.right, "b/a")
            try f.file(.left, "a10")
            try f.file(.right, "a2")
            try f.file(.left, "b-file")
            try f.folder(.right, "b")
            let c = try await f.compare()
            #expect(c.paths == ["a2", "a10", "b", "b/a", "b/z", "b-file"])
        }
    }

    @Test func cancellation() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            for i in 0..<50 { try f.file(.left, "d\(i)/f", "x"); try f.file(.right, "d\(i)/f", "x") }
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await f.compare()
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    @Test func progressEndsWithTheTotal() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "a")
            try f.file(.right, "b/c")
            let last = Mutex<SyncProgress?>(nil)
            _ = try await SyncScanner.compare(left: f.left, right: f.right, options: SyncOptions(), includeHidden: false,
                                              progress: { p in last.withLock { $0 = p } })
            #expect(last.withLock { $0 } == SyncProgress(scanned: 3, folder: "", bytesRead: 0))
        }
    }
}
