// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Conflict marks, automatic names and the per-operation conflict policy (spec 021).
@Suite struct ConflictPolicyTests {
    private let old = Date(timeIntervalSince1970: 1_000)
    private let new = Date(timeIntervalSince1970: 2_000)

    private func conflict(name: String = "a.txt", sourceDate: Date?, destinationDate: Date?,
                          sourceSize: Int64? = 10, destinationSize: Int64? = 10,
                          sourceIsDirectory: Bool = false, destinationIsDirectory: Bool = false,
                          canRename: Bool = true, sourcePath: String = "/src/a.txt") -> Conflict {
        Conflict(
            source: FileItemInfo(url: URL(fileURLWithPath: sourcePath), isDirectory: sourceIsDirectory,
                                 size: sourceSize, modificationDate: sourceDate),
            destination: FileItemInfo(url: URL(fileURLWithPath: "/dst/\(name)"), isDirectory: destinationIsDirectory,
                                      size: destinationSize, modificationDate: destinationDate),
            canRename: canRename)
    }

    // MARK: Marks

    @Test func marksNewerAndLarger() {
        let m = ConflictMarks(conflict(sourceDate: new, destinationDate: old, sourceSize: 5, destinationSize: 9))
        #expect(m.newer == .new)
        #expect(m.larger == .existing)
        let n = ConflictMarks(conflict(sourceDate: old, destinationDate: new, sourceSize: 9, destinationSize: 5))
        #expect(n.newer == .existing)
        #expect(n.larger == .new)
    }

    @Test func marksEmptyWhenEqualOrUnknownOrFolder() {
        #expect(ConflictMarks(conflict(sourceDate: old, destinationDate: old)) == ConflictMarks(conflict(sourceDate: nil, destinationDate: nil)))
        let unknown = ConflictMarks(conflict(sourceDate: new, destinationDate: nil, sourceSize: nil, destinationSize: 3))
        #expect(unknown.newer == nil)
        #expect(unknown.larger == nil)
        let folder = ConflictMarks(conflict(sourceDate: new, destinationDate: old, sourceSize: 100, destinationSize: 1,
                                            sourceIsDirectory: true))
        #expect(folder.newer == .new)
        #expect(folder.larger == nil)
    }

    // MARK: Automatic names

    @Test func autoNameShapes() {
        #expect(AutoName.name(for: "a.txt", isDirectory: false, attempt: 2) == "a 2.txt")
        #expect(AutoName.name(for: "a.tar.gz", isDirectory: false, attempt: 3) == "a.tar 3.gz")
        #expect(AutoName.name(for: ".zshrc", isDirectory: false, attempt: 2) == ".zshrc 2")
        #expect(AutoName.name(for: "x.", isDirectory: false, attempt: 2) == "x. 2")
        #expect(AutoName.name(for: "notes", isDirectory: false, attempt: 2) == "notes 2")
        #expect(AutoName.name(for: "my.folder", isDirectory: true, attempt: 2) == "my.folder 2")
    }

    @Test func autoNameFitsLongNames() {
        let long = String(repeating: "a", count: 300) + ".txt"
        let result = AutoName.name(for: long, isDirectory: false, attempt: 12)
        #expect(result.utf8.count == 255)
        #expect(result.hasSuffix(" 12.txt"))
        let wide = String(repeating: "é", count: 200) + ".md"   // 2 bytes each
        let wideResult = AutoName.name(for: wide, isDirectory: false, attempt: 2)
        #expect(wideResult.utf8.count <= 255)
        #expect(wideResult.hasSuffix(" 2.md"))
        #expect(wideResult.dropLast(5).allSatisfy { $0 == "é" })
        let emoji = String(repeating: "👩‍👩‍👧", count: 40)   // one Character each, 18 bytes
        let emojiResult = AutoName.name(for: emoji, isDirectory: true, attempt: 2)
        #expect(emojiResult.utf8.count <= 255)
        #expect(emojiResult.hasSuffix(" 2"))
        #expect(emojiResult.dropLast(2).allSatisfy { $0 == "👩‍👩‍👧" })
    }

    // MARK: Policy

    @Test func askModeAsks() {
        var policy = ConflictPolicy()
        #expect(policy.decide(conflict(sourceDate: new, destinationDate: old)) == .ask)
    }

    @Test func overwriteAllOlder() {
        var policy = ConflictPolicy()
        let first = conflict(sourceDate: new, destinationDate: old)
        #expect(policy.choose(.overwriteAllOlder, for: first) == .overwrite)
        #expect(policy.mode == .overwriteAllOlder)
        #expect(policy.decide(conflict(sourceDate: new, destinationDate: old)) == .answer(.overwrite))
        #expect(policy.decide(conflict(sourceDate: old, destinationDate: new)) == .answer(.skip))
        #expect(policy.decide(conflict(sourceDate: old, destinationDate: old)) == .answer(.skip))
        #expect(policy.decide(conflict(sourceDate: nil, destinationDate: old)) == .answer(.skip))
        #expect(policy.decide(conflict(sourceDate: new, destinationDate: nil)) == .answer(.skip))
        #expect(policy.decide(conflict(sourceDate: new, destinationDate: old, sourceIsDirectory: true,
                                       destinationIsDirectory: true)) == .answer(.skip))
    }

    @Test func overwriteAllOlderChosenOnOlderSourceSkips() {
        var policy = ConflictPolicy()
        #expect(policy.choose(.overwriteAllOlder, for: conflict(sourceDate: old, destinationDate: new)) == .skip)
        #expect(policy.mode == .overwriteAllOlder)
    }

    @Test func plainChoicesMapDirectly() {
        var policy = ConflictPolicy()
        let c = conflict(sourceDate: new, destinationDate: old)
        #expect(policy.choose(.overwrite, for: c) == .overwrite)
        #expect(policy.choose(.overwriteAll, for: c) == .overwriteAll)
        #expect(policy.choose(.skip, for: c) == .skip)
        #expect(policy.choose(.skipAll, for: c) == .skipAll)
        #expect(policy.choose(.cancel, for: c) == .cancel)
        #expect(policy.mode == .ask)
    }

    @Test func renameAutomaticallyThenCandidateTaken() {
        var policy = ConflictPolicy()
        let c = conflict(sourceDate: new, destinationDate: old)
        #expect(policy.choose(.renameAutomatically, for: c) == .rename("a 2.txt"))
        #expect(policy.mode == .ask)
        // The backend reports "a 2.txt" as taken: next number, based on the original name.
        let taken = conflict(name: "a 2.txt", sourceDate: new, destinationDate: old)
        #expect(policy.decide(taken) == .answer(.rename("a 3.txt")))
        let taken3 = conflict(name: "a 3.txt", sourceDate: new, destinationDate: old)
        #expect(policy.decide(taken3) == .answer(.rename("a 4.txt")))
        // An unrelated conflict clears the pending state.
        #expect(policy.decide(conflict(name: "b.txt", sourceDate: new, destinationDate: old, sourcePath: "/src/b.txt")) == .ask)
        #expect(policy.decide(conflict(name: "a 4.txt", sourceDate: new, destinationDate: old)) == .ask)
    }

    @Test func renameAllMode() {
        var policy = ConflictPolicy()
        let c = conflict(sourceDate: new, destinationDate: old)
        #expect(policy.choose(.renameAllAutomatically, for: c) == .rename("a 2.txt"))
        #expect(policy.mode == .renameAllAutomatically)
        #expect(policy.decide(conflict(name: "b.txt", sourceDate: new, destinationDate: old, sourcePath: "/src/b.txt"))
                == .answer(.rename("b 2.txt")))
        // Folders get no extension split.
        #expect(policy.decide(conflict(name: "d.x", sourceDate: new, destinationDate: old, sourceIsDirectory: true,
                                       destinationIsDirectory: true, sourcePath: "/src/d.x")) == .answer(.rename("d.x 2")))
    }

    @Test func renameAllWithoutRenameAsks() {
        var policy = ConflictPolicy()
        _ = policy.choose(.renameAllAutomatically, for: conflict(sourceDate: new, destinationDate: old))
        #expect(policy.decide(conflict(name: "b.txt", sourceDate: new, destinationDate: old, canRename: false,
                                       sourcePath: "/src/b.txt")) == .ask)
    }

    @Test func manualRenameHasNoPending() {
        var policy = ConflictPolicy()
        let c = conflict(sourceDate: new, destinationDate: old)
        #expect(policy.choose(.rename("mine.txt"), for: c) == .rename("mine.txt"))
        #expect(policy.decide(conflict(name: "mine.txt", sourceDate: new, destinationDate: old)) == .ask)
    }
}
