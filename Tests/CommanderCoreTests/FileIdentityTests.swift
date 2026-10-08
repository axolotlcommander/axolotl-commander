// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import Darwin
@testable import CommanderCore

@Suite struct FileIdentityTests {
    @Test func linkCountCountsHardLinks() throws {
        try TestSandbox.with("axo-id", sync: { dir in
            let a = dir.child("a.txt"), b = dir.child("b.txt")
            try TestSandbox.write(a, "x")
            guard case .exists(let before) = FileProbe.probe(a.path, followingLinks: false) else {
                Issue.record("a.txt missing"); return
            }
            #expect(before.linkCount == 1)
            #expect(link(a.path, b.path) == 0)
            guard case .exists(let after) = FileProbe.probe(a.path, followingLinks: false) else {
                Issue.record("a.txt missing"); return
            }
            #expect(after.linkCount == 2)
            #expect(FileIdentity.of(a) == FileIdentity.of(b))
        })
    }

    @Test func sandboxVolumeHasReliableIdentity() throws {
        try TestSandbox.with("axo-id", sync: { dir in
            let traits = VolumeTraits.of(dir)
            #expect(traits.identityReliable)
            #expect(traits.uuid != nil)
            // A path that does not exist yet reports its nearest existing ancestor's volume.
            #expect(VolumeTraits.of(dir.child("missing/deeper")) == traits)
        })
    }

    @Test func persistentStampChangesOnWriteAndRoundTrips() throws {
        try TestSandbox.with("axo-id", sync: { dir in
            let f = dir.child("f.bin")
            try TestSandbox.write(f, "one")
            let first = try #require(PersistentFileStamp(f))
            #expect(first.size == 3)
            #expect(PersistentFileStamp(f) == first)

            let data = try JSONEncoder().encode(first)
            #expect(try JSONDecoder().decode(PersistentFileStamp.self, from: data) == first)

            try TestSandbox.write(f, "two!")
            #expect(PersistentFileStamp(f) != first)
            #expect(PersistentFileStamp(dir.child("missing")) == nil)
        })
    }

    @Test func replacedFileHasDifferentStamp() throws {
        try TestSandbox.with("axo-id", sync: { dir in
            let f = dir.child("f.bin"), other = dir.child("g.bin")
            try TestSandbox.write(f, "abc")
            let first = try #require(PersistentFileStamp(f))
            try TestSandbox.write(other, "abc")
            #expect(rename(other.path, f.path) == 0)
            #expect(PersistentFileStamp(f)?.fileID != first.fileID)
        })
    }
}
