// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import Darwin
@testable import CommanderCore

/// Volumes without an exclusive rename (SMB shares, exFAT) answer ENOTSUP; the fallback is tested by
/// making the exclusive call fail that way. Everything happens in a temporary folder.
@Suite struct ExclusiveRenameTests {
    private let unsupported: (String, String) -> Int32 = { _, _ in
        errno = ENOTSUP
        return -1
    }

    private func withFolder(_ body: (String) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.path)
    }

    private func write(_ text: String, _ path: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    private func read(_ path: String) -> String? {
        FileManager.default.contents(atPath: path).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func renamesWhereTheVolumeHasNoExclusiveRename() throws {
        try withFolder { dir in
            try write("new", dir + "/temp")
            #expect(ExclusiveRename.rename(dir + "/temp", dir + "/file.txt", exclusive: unsupported) == 0)
            #expect(read(dir + "/file.txt") == "new")
            #expect(!FileManager.default.fileExists(atPath: dir + "/temp"))
        }
    }

    @Test func neverReplacesAnExistingItemInTheFallback() throws {
        try withFolder { dir in
            try write("new", dir + "/temp")
            try write("old", dir + "/file.txt")
            #expect(ExclusiveRename.rename(dir + "/temp", dir + "/file.txt", exclusive: unsupported) == -1)
            #expect(errno == EEXIST)
            #expect(read(dir + "/file.txt") == "old")
            #expect(read(dir + "/temp") == "new")
        }
    }

    @Test func caseOnlyRenameIsNoConflictInTheFallback() throws {
        try withFolder { dir in
            try write("a", dir + "/a.txt")
            // On a case-sensitive temporary folder "A.txt" does not exist yet; either way it succeeds.
            #expect(ExclusiveRename.rename(dir + "/a.txt", dir + "/A.txt", exclusive: unsupported) == 0)
            #expect(read(dir + "/A.txt") == "a")
        }
    }

    @Test func otherErrorsAreReturnedAsTheyAre() throws {
        try withFolder { dir in
            #expect(ExclusiveRename.rename(dir + "/missing", dir + "/x") == -1)
            #expect(errno == ENOENT)
            try write("old", dir + "/x")
            try write("new", dir + "/y")
            #expect(ExclusiveRename.rename(dir + "/y", dir + "/x") == -1)
            #expect(errno == EEXIST)
            #expect(read(dir + "/x") == "old")
        }
    }
}
