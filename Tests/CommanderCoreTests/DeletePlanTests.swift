// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import Darwin
@testable import CommanderCore

/// F8 decides before the first change what goes to the Trash and what could only be deleted
/// permanently (FR-013–016). The real Trash is never used: a fake one moves items into the
/// sandbox, and "volume without a Trash" is any item below `sandbox/noTrash`.
@Suite struct DeletePlanTests {
    /// File operations whose Trash is `dir/Trash`; the `failOn`-th item (1-based) fails.
    private func operations(_ dir: URL, failOn: Int? = nil, asked: PromptLog<URL>? = nil) throws -> FileOperations {
        let trash = dir.child("Trash")
        try TestSandbox.mkdirs(trash)
        let noTrash = dir.child("noTrash").path + "/"
        let calls = PromptLog<URL>()
        var options = FileOperations.Options()
        options.trashAvailable = { url in
            asked?.append(url)
            return !url.path.hasPrefix(noTrash)
        }
        options.trashItem = { url in
            calls.append(url)
            if calls.all.count == failOn { throw CocoaError(.fileWriteNoPermission) }
            let target = trash.child(url.lastPathComponent)
            guard rename(url.path, target.path) == 0 else { throw POSIXError(.EIO) }
            return target
        }
        return FileOperations(options: options)
    }

    private func files(_ dir: URL, _ names: [String]) throws -> [URL] {
        try names.map { name in
            let url = dir.child(name)
            try TestSandbox.mkdirs(url.deletingLastPathComponent())
            try TestSandbox.write(url, name)
            return url
        }
    }

    @Test func planSplitsTrashAndPermanentWithoutChangingAnything() async throws {
        try await TestSandbox.with("axo-del") { dir in
            let urls = try files(dir, ["a.txt", "noTrash/b.txt", "c.txt", "noTrash/d.txt"])
            let asked = PromptLog<URL>()
            let ops = try operations(dir, asked: asked)
            let plan = await ops.planDelete(urls)
            #expect(plan.toTrash == [urls[0], urls[2]])
            #expect(plan.permanent == [urls[1], urls[3]])
            #expect(plan.unremovable.isEmpty)
            #expect(asked.all == urls)
            #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
    }

    @Test func itemsThatCouldNotBeDeletedAnywayAreNotAskedAbout() async throws {
        try await TestSandbox.with("axo-del") { dir in
            let urls = try files(dir, ["noTrash/locked/x.txt", "noTrash/y.txt"])
            chmod(dir.child("noTrash/locked").path, 0o555)
            defer { chmod(dir.child("noTrash/locked").path, 0o755) }
            let plan = await (try operations(dir)).planDelete(urls)
            #expect(plan.unremovable == [urls[0]])
            #expect(plan.permanent == [urls[1]])
        }
    }

    @Test func failureStopsAndReportsWithoutPermanentDeletion() async throws {
        try await TestSandbox.with("axo-del") { dir in
            let urls = try files(dir, ["a.txt", "b.txt", "c.txt", "d.txt"])
            let ops = try operations(dir, failOn: 2)
            let report = await ops.trash(urls)
            #expect(report.trashed.map(\.original) == [urls[0]])
            #expect(report.trashed.map(\.inTrash) == [dir.child("Trash/a.txt")])
            #expect(report.failed?.url == urls[1])
            #expect(report.notAttempted == [urls[2], urls[3]])
            #expect(!report.isComplete)
            // Nothing deleted permanently: everything is either in the fake Trash or in place.
            #expect(TestSandbox.names(in: dir.child("Trash")) == ["a.txt"])
            #expect(urls.dropFirst().allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        }
    }

    @Test func allTrashedIsComplete() async throws {
        try await TestSandbox.with("axo-del") { dir in
            let urls = try files(dir, ["a.txt", "b.txt"])
            let report = await (try operations(dir)).trash(urls)
            #expect(report.failed == nil)
            #expect(report.isComplete)
            #expect(report.trashed.count == 2)
            #expect(TestSandbox.names(in: dir.child("Trash")) == ["a.txt", "b.txt"])
        }
    }

    @Test func missingItemIsReportedNotThrown() async throws {
        try await TestSandbox.with("axo-del") { dir in
            let urls = try files(dir, ["a.txt"]) + [dir.child("ghost.txt")]
            let report = await (try operations(dir)).trash(urls)
            #expect(report.trashed.map(\.original) == [urls[0]])
            #expect(report.failed?.url == urls[1])
            #expect(report.notAttempted.isEmpty)
        }
    }

    /// Read-only: asks where the Trash is without creating anything.
    @Test func systemReportsTrashOnStartupVolume() throws {
        try TestSandbox.with("axo-del", sync: { dir in
            #expect(TrashSupport.isAvailable(dir))
        })
    }
}
