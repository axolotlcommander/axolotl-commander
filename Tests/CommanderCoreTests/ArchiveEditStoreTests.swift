// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import Darwin
@testable import CommanderCore

/// Edited copies of archive members survive quitting (FR-005–009). Store root, archives and
/// copies all live in a sandbox under the temporary directory.
@Suite struct ArchiveEditStoreTests {
    /// A store over `dir/Edits` with one edit of member "doc.txt" of `dir/a.zip`.
    private func begin(_ dir: URL, _ store: ArchiveEditStore? = nil) async throws -> (ArchiveEditStore, PendingEdit) {
        let store = store ?? ArchiveEditStore(root: dir.child("Edits"))
        let archive = dir.child("a.zip")
        if !FileManager.default.fileExists(atPath: archive.path) {
            try TestSandbox.write(archive, "not really a zip")
        }
        let edit = try await store.begin(target: .member(archive: archive, path: "docs/doc.txt"),
                                         archiveStamp: PersistentFileStamp(archive)) { folder in
            let copy = folder.child("doc.txt")
            try TestSandbox.write(copy, "original")
            return copy
        }
        return (store, edit)
    }

    /// Changes the copy so its size differs (mtime alone could tie within a clock tick).
    private func modify(_ store: ArchiveEditStore, _ edit: PendingEdit, _ text: String = "changed text") throws {
        try TestSandbox.write(store.copyURL(edit), text)
    }

    @Test func unchangedCopyIsRemovedOnQuit() async throws {
        try await TestSandbox.with("axo-edits") { dir in
            let (store, edit) = try await begin(dir)
            #expect(store.changed().isEmpty)
            #expect(try store.cleanupForQuit().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: store.copyURL(edit).path))
            #expect(ArchiveEditStore(root: store.root).all.isEmpty)
        }
    }

    @Test func changedCopySurvivesQuitAndRestart() async throws {
        try await TestSandbox.with("axo-edits") { dir in
            let (store, edit) = try await begin(dir)
            try modify(store, edit)
            #expect(store.changed().map(\.id) == [edit.id])
            #expect(try store.cleanupForQuit().map(\.id) == [edit.id])

            let next = ArchiveEditStore(root: store.root)
            let pending = try next.loadPending()
            #expect(pending.map(\.id) == [edit.id])
            #expect(pending.first?.target == .member(archive: dir.child("a.zip"), path: "docs/doc.txt"))
            #expect(TestSandbox.read(next.copyURL(pending[0])) == "changed text")
        }
    }

    @Test func declinedCopyIsKeptEvenThoughUnchangedSinceDecline() async throws {
        try await TestSandbox.with("axo-edits") { dir in
            let (store, edit) = try await begin(dir)
            try modify(store, edit)
            try store.decline(edit.id)
            // Not asked again in this session until a further change...
            #expect(store.changed().isEmpty)
            // ...but never thrown away.
            #expect(try store.cleanupForQuit().map(\.id) == [edit.id])
            let pending = try ArchiveEditStore(root: store.root).loadPending()
            #expect(pending.map(\.declined) == [true])
            #expect(FileManager.default.fileExists(atPath: store.copyURL(edit).path))

            try modify(store, edit, "changed again!")
            #expect(store.changed().map(\.id) == [edit.id])
        }
    }

    @Test func savedCopyWithoutFurtherChangesIsRemoved() async throws {
        try await TestSandbox.with("axo-edits") { dir in
            let (store, edit) = try await begin(dir)
            try modify(store, edit)
            try store.decline(edit.id)
            try store.markSaved(edit.id, archiveStamp: PersistentFileStamp(dir.child("a.zip")))
            #expect(store.all.first?.declined == false)
            #expect(store.changed().isEmpty)
            #expect(try store.cleanupForQuit().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: store.copyURL(edit).path))
        }
    }

    @Test func discardRemovesCopyAndRecord() async throws {
        try await TestSandbox.with("axo-edits") { dir in
            let (store, edit) = try await begin(dir)
            try modify(store, edit)
            try store.discard(edit.id)
            #expect(store.all.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: store.copyURL(edit).deletingLastPathComponent().path))
            #expect(try ArchiveEditStore(root: store.root).loadPending().isEmpty)
        }
    }

    @Test func changedOrRemovedArchiveIsNotWrittenBlindly() async throws {
        try await TestSandbox.with("axo-edits") { dir in
            let (store, edit) = try await begin(dir)
            try modify(store, edit)
            try store.verifyArchiveUnchanged(edit)

            // Replaced by another file of the same size: different file id.
            let archive = dir.child("a.zip")
            try TestSandbox.write(dir.child("other.zip"), "not really a zip")
            #expect(rename(dir.child("other.zip").path, archive.path) == 0)
            #expect(throws: ArchiveError.changedSinceRead(archive.path)) { try store.verifyArchiveUnchanged(edit) }

            // Removed.
            try FileManager.default.removeItem(at: archive)
            #expect(throws: ArchiveError.changedSinceRead(archive.path)) { try store.verifyArchiveUnchanged(edit) }
            // The copy stays.
            #expect(TestSandbox.read(store.copyURL(edit)) == "changed text")
            #expect(store.unsaved().map(\.id) == [edit.id])
        }
    }

    @Test func recordWithoutCopyIsDroppedAtLaunch() async throws {
        try await TestSandbox.with("axo-edits") { dir in
            let (store, edit) = try await begin(dir)
            try modify(store, edit)
            let (_, second) = try await begin(dir, store)
            try modify(store, second)
            try FileManager.default.removeItem(at: store.copyURL(edit).deletingLastPathComponent())
            let next = ArchiveEditStore(root: store.root)
            #expect(try next.loadPending().map(\.id) == [second.id])
            #expect(ArchiveEditStore(root: store.root).all.map(\.id) == [second.id])
        }
    }

    @Test func failedCopyRecordsNothing() async throws {
        try await TestSandbox.with("axo-edits") { dir in
            let store = ArchiveEditStore(root: dir.child("Edits"))
            await #expect(throws: ArchiveError.wrongPassword("x")) {
                _ = try await store.begin(target: .member(archive: dir.child("a.zip"), path: "x"), archiveStamp: nil) { _ in
                    throw ArchiveError.wrongPassword("x")
                }
            }
            #expect(store.all.isEmpty)
            #expect(TestSandbox.names(in: dir.child("Edits")).filter { $0 != "manifest.json" }.isEmpty)
        }
    }

    @Test func serverTargetRoundTrips() async throws {
        try await TestSandbox.with("axo-edits") { dir in
            let store = ArchiveEditStore(root: dir.child("Edits"))
            let remote = RemoteLocation(endpoint: RemoteEndpoint(proto: .sftp, host: "example.test", user: "me"), path: "/home/me/x.txt")
            let edit = try await store.begin(target: .server(remote.url), archiveStamp: nil) { folder in
                try TestSandbox.write(folder.child("x.txt"), "x")
                return folder.child("x.txt")
            }
            try modify(store, edit)
            let pending = try ArchiveEditStore(root: store.root).loadPending()
            guard case .server(let url)? = pending.first?.target else { Issue.record("no server edit"); return }
            #expect(RemoteURL.parse(url) == remote)
            #expect(store.edit(for: .server(remote.url))?.id == edit.id)
        }
    }
}
