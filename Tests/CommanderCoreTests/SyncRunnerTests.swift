// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Synchronization
import Testing
@testable import CommanderCore

/// Moves items to the real Trash (the sandbox is on the boot volume) and removes them from it
/// afterwards, so the user's Trash is left as it was.
private final class TrashRecorder: Sendable {
    private let urls = Mutex<[URL]>([])

    var trash: @Sendable (URL) throws -> URL {
        { url in
            let trashed = try TrashSupport.moveToTrash(url)
            self.urls.withLock { $0.append(trashed) }
            return trashed
        }
    }

    var count: Int { urls.withLock { $0.count } }

    func cleanUp() {
        for url in urls.withLock({ $0 }) where url.path.contains("/.Trash") || url.path.contains("/.Trashes") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

private func run(_ c: SyncComparison, trash: TrashRecorder? = nil, available: @escaping @Sendable (URL) -> Bool = { _ in true },
                 progress: @escaping @Sendable (OperationProgress) -> Void = { _ in }) async throws -> SyncRunReport {
    let refuse: @Sendable (URL) throws -> URL = { _ in throw CocoaError(.fileWriteNoPermission) }
    return try await SyncRunner.run(SyncPlan(c), of: c, operations: FileOperations(), progress: progress,
                                    trashAvailable: available, trash: trash?.trash ?? refuse)
}

private func opts(_ change: (inout SyncOptions) -> Void) -> SyncOptions {
    var o = SyncOptions()
    change(&o)
    return o
}

private func exists(_ url: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
}

@Suite(.serialized) struct SyncRunnerTests {
    @Test func copiesBothWaysKeepDates() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "newer-left", "new left", at: syncT0.addingTimeInterval(100))
            try f.file(.right, "newer-left", "old")
            try f.file(.left, "newer-right", "old")
            try f.file(.right, "newer-right", "new right", at: syncT0.addingTimeInterval(100))
            try f.file(.left, "only-left", "L")
            try f.file(.left, "solo/a", "aaa")
            try f.file(.left, "solo/deep/b", "bb")
            try f.file(.right, "only-right", "R")
            try f.file(.left, "same", "s")
            try f.file(.right, "same", "s")
            try f.file(.left, "sub/x", "x2", at: syncT0.addingTimeInterval(-500))
            try f.file(.right, "sub/x", "x1")
            try f.link(.left, "ln", to: "same")

            let c = try await f.compare()
            let report = try await run(c)
            #expect(report.problems.isEmpty)
            #expect(report.copied == 8)
            #expect(report.trashed == 0)
            #expect(TestSandbox.read(f.url(.right, "newer-left")) == "new left")
            #expect(TestSandbox.read(f.url(.left, "newer-right")) == "new right")
            #expect(TestSandbox.read(f.url(.left, "sub/x")) == "x1")
            #expect(TestSandbox.read(f.url(.right, "solo/deep/b")) == "bb")
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: f.url(.right, "ln").path) == "same")

            let again = try await f.compare()
            #expect(again.items.allSatisfy { $0.state == .equal })
            #expect(SyncPlan(again).isEmpty)
        }
    }

    @Test func overwritesALinkWithALink() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.link(.left, "ln", to: "a", at: syncT0.addingTimeInterval(100))
            try f.link(.right, "ln", to: "b")
            let c = try await f.compare()
            #expect(c.item("ln")?.action == .toRight)
            let report = try await run(c)
            #expect(report.problems.isEmpty)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: f.url(.right, "ln").path) == "a")
        }
    }

    @Test func anUnexpectedTargetIsSkipped() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "x", "new")
            try f.file(.left, "y", "planned", at: syncT0.addingTimeInterval(100))
            try f.file(.right, "y", "old")
            var c = try await f.compare()
            // A target the comparison did not see: "x" now exists where the copy goes.
            try f.file(.right, "x", "keep me")
            let i = try #require(c.items.firstIndex { $0.path == "x" })
            c.items[i].rightPath = "not-there"
            let report = try await run(c)
            #expect(TestSandbox.read(f.url(.right, "x")) == "keep me")
            #expect(TestSandbox.read(f.url(.right, "y")) == "planned")
            #expect(report.problems == [.init(path: "x", reason: .changed)])
            #expect(report.copied == 1)
        }
    }

    @Test func aChangedItemIsSkipped() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "a", "new", at: syncT0.addingTimeInterval(100))
            try f.file(.right, "a", "old")
            try f.file(.left, "b", "fresh")
            try f.file(.left, "c", "fine")
            let c = try await f.compare()
            try f.file(.left, "a", "changed again", at: syncT0.addingTimeInterval(100))
            try f.file(.right, "b", "appeared")
            let report = try await run(c)
            #expect(TestSandbox.read(f.url(.right, "a")) == "old")
            #expect(TestSandbox.read(f.url(.right, "b")) == "appeared")
            #expect(TestSandbox.read(f.url(.right, "c")) == "fine")
            #expect(Set(report.problems) == [.init(path: "a", reason: .changed), .init(path: "b", reason: .changed)])
        }
    }

    @Test func aReplacementTrashesTheTargetFirst() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "thing", "a file")
            try f.file(.right, "thing/inside", "folder content")
            var c = try await f.compare()
            let i = try #require(c.items.firstIndex { $0.path == "thing" })
            #expect(c.items[i].state == .different)
            SyncRules.set(.toRight, at: [i], in: &c.items, options: c.options)
            let recorder = TrashRecorder()
            defer { recorder.cleanUp() }
            let report = try await run(c, trash: recorder, available: TrashSupport.isAvailable)
            #expect(report.problems.isEmpty)
            #expect(report.trashed == 1 && recorder.count == 1)
            #expect(TestSandbox.read(f.url(.right, "thing")) == "a file")
        }
    }

    @Test func deletionsGoToTheTrash() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "keep", "k")
            try f.file(.right, "extra", "e")
            try f.file(.right, "extra-dir/inner", "i")
            let c = try await f.compare(opts { $0.direction = .leftToRight; $0.deleteMissing = true })
            #expect(c.item("extra")?.action == .toRight)
            let recorder = TrashRecorder()
            defer { recorder.cleanUp() }
            let report = try await run(c, trash: recorder, available: TrashSupport.isAvailable)
            #expect(report.problems.isEmpty)
            #expect(report.trashed == 2 && recorder.count == 2)
            #expect(TestSandbox.names(in: f.right) == ["keep"])
            #expect(TestSandbox.names(in: f.left) == ["keep"])
        }
    }

    @Test func withoutATrashNothingIsDeleted() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.right, "extra", "e")
            try f.file(.left, "thing", "file")
            try f.folder(.right, "thing")
            var c = try await f.compare(opts { $0.direction = .leftToRight; $0.deleteMissing = true })
            let i = try #require(c.items.firstIndex { $0.path == "thing" })
            SyncRules.set(.toRight, at: [i], in: &c.items, options: c.options)
            let report = try await run(c, available: { _ in false })
            #expect(Set(report.problems) == [.init(path: "extra", reason: .noTrash), .init(path: "thing", reason: .noTrash)])
            #expect(report.trashed == 0 && report.copied == 0)
            #expect(exists(f.url(.right, "extra")))
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: f.url(.right, "thing").path, isDirectory: &isDir) && isDir.boolValue)
        }
    }

    @Test func aFailedTrashIsReported() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.right, "extra", "e")
            let c = try await f.compare(opts { $0.direction = .leftToRight; $0.deleteMissing = true })
            let report = try await run(c)
            #expect(report.problems.count == 1)
            guard case .failed = report.problems.first?.reason else { Issue.record("expected a failure"); return }
            #expect(exists(f.url(.right, "extra")))
        }
    }

    @Test func ignoredItemsInsideANewFolderAreNotCopied() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "proj/a", "a")
            try f.file(.left, "proj/build/out", "o")
            try f.file(.left, "proj/src/main.c", "m")
            try f.file(.left, "proj/src/main.o", "o")
            try f.file(.left, "proj/.git/HEAD", "h")
            try f.file(.left, "clean/one", "1")
            let c = try await f.compare(opts { $0.ignoreFolders = "build"; $0.ignoreFiles = "*.o" })
            let report = try await run(c)
            #expect(report.problems.isEmpty)
            #expect(TestSandbox.names(in: f.url(.right, "proj")) == ["a", "src"])
            #expect(TestSandbox.names(in: f.url(.right, "proj/src")) == ["main.c"])
            #expect(TestSandbox.names(in: f.url(.right, "clean")) == ["one"])
            let again = try await f.compare(opts { $0.ignoreFolders = "build"; $0.ignoreFiles = "*.o" })
            #expect(again.items.allSatisfy { $0.state == .equal })
        }
    }

    @Test func cancellationLeavesDeletionsUndone() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            for i in 0..<5 { try f.file(.left, "dir\(i)/file", String(repeating: "x", count: 1000)) }
            try f.file(.right, "extra", "e")
            let c = try await f.compare(opts { $0.direction = .leftToRight; $0.deleteMissing = true })
            let recorder = TrashRecorder()
            defer { recorder.cleanUp() }
            let task = Task {
                try await run(c, trash: recorder, available: TrashSupport.isAvailable, progress: { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                })
            }
            await #expect(throws: OperationError.cancelled) { try await task.value }
            #expect(exists(f.url(.right, "extra")))
            #expect(recorder.count == 0)
        }
    }

    @Test func cancelledBeforeStartingDoesNothing() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "a", "a")
            try f.file(.right, "extra", "e")
            let c = try await f.compare(opts { $0.direction = .leftToRight; $0.deleteMissing = true })
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await run(c, available: { _ in true })
            }
            await #expect(throws: OperationError.cancelled) { try await task.value }
            #expect(!exists(f.url(.right, "a")))
            #expect(exists(f.url(.right, "extra")))
        }
    }

    @Test func progressCoversThePlan() async throws {
        try await TestSandbox.with { root in
            let f = try SyncFolders(root)
            try f.file(.left, "a", "12345")
            try f.file(.left, "d/b", "123")
            try f.file(.right, "c", "1", at: syncT0.addingTimeInterval(-100))
            try f.file(.left, "c", "22")
            let last = Mutex<OperationProgress?>(nil)
            let c = try await f.compare()
            _ = try await run(c, progress: { p in last.withLock { $0 = p } })
            let p = try #require(last.withLock { $0 })
            #expect(p.totalBytes == 10 && p.doneBytes == 10)
            #expect(p.totalItems >= 3 && p.doneItems == p.totalItems)
        }
    }
}
