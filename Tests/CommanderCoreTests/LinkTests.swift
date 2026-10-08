// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Darwin
import Testing
@testable import CommanderCore

struct LinkPathsTests {
    @Test func relativePaths() {
        #expect(LinkPaths.relativePath(from: "/t/b", to: "/t/a/file.txt") == "../a/file.txt")
        #expect(LinkPaths.relativePath(from: "/t", to: "/t/a/deep/f") == "a/deep/f")
        #expect(LinkPaths.relativePath(from: "/t/a/deep", to: "/t") == "../..")
        #expect(LinkPaths.relativePath(from: "/t/a", to: "/t/a") == ".")
        #expect(LinkPaths.relativePath(from: "/", to: "/usr/bin") == "usr/bin")
        #expect(LinkPaths.relativePath(from: "/t//b/", to: "/t/./a/../a/f") == "../a/f")
    }

    @Test func storedTargets() {
        #expect(LinkPaths.storedTarget(typed: "../x", linkFolder: "/t/b", relative: false) == "../x")
        #expect(LinkPaths.storedTarget(typed: "../x", linkFolder: "/t/b", relative: true) == "../x")
        #expect(LinkPaths.storedTarget(typed: "/t/a/f", linkFolder: "/t/b", relative: false) == "/t/a/f")
        #expect(LinkPaths.storedTarget(typed: "/t/a/f", linkFolder: "/t/b", relative: true) == "../a/f")
        #expect(LinkPaths.storedTarget(typed: "~/f", linkFolder: "/t", relative: false)
            == NSHomeDirectory() + "/f")
        #expect(LinkPaths.storedTarget(typed: "/t/Résumé a.txt", linkFolder: "/t", relative: true) == "Résumé a.txt")
    }

    @Test func absoluteAndRelative() {
        #expect(LinkPaths.isRelative("../a"))
        #expect(!LinkPaths.isRelative("/a"))
        #expect(LinkPaths.absolute("../a/f", linkFolder: "/t/b") == "/t/a/f")
        #expect(LinkPaths.absolute("/t/./a//f", linkFolder: "/x") == "/t/a/f")
    }
}

struct LinkOperationsTests {
    private func setUp(_ root: URL) throws -> (a: URL, b: URL, file: URL) {
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: false)
        let file = a.appendingPathComponent("file.txt")
        try TestSandbox.write(file, "data")
        return (a, b, file)
    }

    private func stored(_ url: URL) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    }

    private func caught(_ body: () async throws -> Void) async -> (any Error)? {
        do { try await body(); return nil } catch { return error }
    }

    @Test func symbolicLinkCreatedAbsoluteRelativeAndDangling() async throws {
        try await TestSandbox.with { root in
            let (a, b, file) = try setUp(root)
            let ops = FileOperations()
            let link = try await ops.makeSymbolicLink(at: b.path + "/file.txt", storing: file.path)
            #expect(stored(link) == file.path)
            try await ops.makeSymbolicLink(at: b.path + "/rel.txt", storing: "../a/file.txt")
            #expect(try String(contentsOf: b.appendingPathComponent("rel.txt"), encoding: .utf8) == "data")
            try await ops.makeSymbolicLink(at: b.path + "/dangling", storing: a.path + "/missing")
            #expect(stored(b.appendingPathComponent("dangling")) == a.path + "/missing")
        }
    }

    @Test func symbolicLinkNeverReplaces() async throws {
        try await TestSandbox.with { root in
            let (_, b, file) = try setUp(root)
            let existing = b.appendingPathComponent("Name.txt")
            try TestSandbox.write(existing, "keep")
            let ops = FileOperations()
            for name in ["Name.txt", "name.TXT"] {
                let error = await caught { try await ops.makeSymbolicLink(at: b.path + "/" + name, storing: file.path) }
                #expect(error as? OperationError == .alreadyExists(existing))
            }
            #expect(try String(contentsOf: existing, encoding: .utf8) == "keep")
            #expect(stored(existing) == nil)
        }
    }

    @Test func symbolicLinkInvalidNameAndMissingFolder() async throws {
        try await TestSandbox.with { root in
            let (_, b, file) = try setUp(root)
            let ops = FileOperations()
            let bad = await caught { try await ops.makeSymbolicLink(at: b.path + "/..", storing: file.path) }
            #expect(bad as? OperationError == .invalidName(".."))
            let missing = await caught { try await ops.makeSymbolicLink(at: b.path + "/no/x", storing: file.path) }
            #expect(missing as? OperationError == .path(.notFound))
            let empty = await caught { try await ops.makeSymbolicLink(at: b.path + "/x", storing: "") }
            #expect(empty as? OperationError == .path(.empty))
        }
    }

    @Test func hardLinks() async throws {
        try await TestSandbox.with { root in
            let (a, b, file) = try setUp(root)
            let ops = FileOperations()
            let hard = try await ops.makeHardLink(at: b.path + "/hard.txt", to: file)
            var one = stat(), two = stat()
            lstat(file.path, &one)
            lstat(hard.path, &two)
            #expect(one.st_ino == two.st_ino)
            #expect(two.st_nlink == 2)

            let folder = await caught { try await ops.makeHardLink(at: b.path + "/dir", to: a) }
            #expect(folder as? LinkError == .folderNotAllowed(a))
            let sym = b.appendingPathComponent("sym")
            try FileManager.default.createSymbolicLink(atPath: sym.path, withDestinationPath: file.path)
            let toLink = await caught { try await ops.makeHardLink(at: b.path + "/x", to: sym) }
            #expect(toLink as? LinkError == .symbolicLinkNotAllowed(sym))
            let conflict = await caught { try await ops.makeHardLink(at: b.path + "/HARD.txt", to: file) }
            #expect(conflict as? OperationError == .alreadyExists(hard))
            #expect(!FileManager.default.fileExists(atPath: b.path + "/dir"))
        }
    }

    @Test func batchKeepsGoing() async throws {
        try await TestSandbox.with { root in
            let (a, b, file) = try setUp(root)
            let other = a.appendingPathComponent("other.txt")
            try TestSandbox.write(other, "o")
            let dir = a.appendingPathComponent("dir")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
            try TestSandbox.write(b.appendingPathComponent("file.txt"), "keep")
            let ops = FileOperations()

            let symbolic = await ops.makeLinks(.symbolic, to: [file, other, dir], in: b, relative: true)
            #expect(symbolic.map { $0.created != nil } == [false, true, true])
            #expect(stored(b.appendingPathComponent("other.txt")) == "../a/other.txt")
            #expect(stored(b.appendingPathComponent("dir")) == "../a/dir")
            #expect(try String(contentsOf: b.appendingPathComponent("file.txt"), encoding: .utf8) == "keep")

            let c = root.appendingPathComponent("c")
            try FileManager.default.createDirectory(at: c, withIntermediateDirectories: false)
            let hard = await ops.makeLinks(.hard, to: [file, dir, other], in: c, relative: false)
            #expect(hard.map { $0.created != nil } == [true, false, true])
            if case .skipped(let error) = hard[1].result { #expect(error as? LinkError == .folderNotAllowed(dir)) }

            let absolute = await ops.makeLinks(.symbolic, to: [file], in: root, relative: false)
            #expect(stored(absolute[0].created!) == file.path)
        }
    }

    @Test func relativeLinkInFolderReachedThroughALink() async throws {
        try await TestSandbox.with { root in
            let fm = FileManager.default
            let deep = root.appendingPathComponent("real/a/deep")
            try fm.createDirectory(at: deep, withIntermediateDirectories: true)
            let via = root.appendingPathComponent("via")
            try fm.createSymbolicLink(atPath: via.path, withDestinationPath: deep.path)
            let target = root.appendingPathComponent("t.txt")
            try TestSandbox.write(target, "t")
            let stored = LinkPaths.storedTarget(typed: target.path, linkFolder: via.path, relative: true)
            #expect(stored == "../../../t.txt")
            let link = try await FileOperations().makeSymbolicLink(at: via.path + "/link", storing: stored)
            #expect(fm.fileExists(atPath: link.path))
            #expect(LinkPaths.absolute(stored, linkFolder: via.path) == LinkPaths.physical(target.path))
            #expect(try LinkTarget.resolve(link).path == target.path)
            // As typed: an absolute target is stored exactly, a trailing slash too.
            #expect(LinkPaths.storedTarget(typed: root.path + "/x/../t.txt/", linkFolder: via.path, relative: false)
                == root.path + "/x/../t.txt/")
        }
    }

    @Test func retargetChangesOnlyTheLink() async throws {
        try await TestSandbox.with { root in
            let (a, b, file) = try setUp(root)
            let other = a.appendingPathComponent("other.txt")
            try TestSandbox.write(other, "o")
            let link = b.appendingPathComponent("link")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../a/file.txt")
            let ops = FileOperations()
            try await ops.retargetSymbolicLink(link, storing: "../a/other.txt")
            #expect(stored(link) == "../a/other.txt")
            #expect(try String(contentsOf: file, encoding: .utf8) == "data")
            #expect(try String(contentsOf: other, encoding: .utf8) == "o")
            #expect(try FileManager.default.contentsOfDirectory(atPath: b.path) == ["link"])

            let refused = await caught { try await ops.retargetSymbolicLink(file, storing: "/x") }
            #expect(refused as? LinkError == .notASymbolicLink(file))
            #expect(try String(contentsOf: file, encoding: .utf8) == "data")
            #expect(try FileManager.default.contentsOfDirectory(atPath: a.path).sorted() == ["file.txt", "other.txt"])
        }
    }

    @Test func resolveChainsAliasesAndErrors() throws {
        try TestSandbox.with(sync: { root in
            let (a, b, file) = try setUp(root)
            let fm = FileManager.default
            try fm.createSymbolicLink(atPath: b.path + "/c2", withDestinationPath: "../a/file.txt")
            try fm.createSymbolicLink(atPath: b.path + "/c1", withDestinationPath: b.path + "/c2")
            try fm.createSymbolicLink(atPath: root.path + "/c0", withDestinationPath: "b/c1")
            #expect(try LinkTarget.resolve(root.appendingPathComponent("c0")).path == file.path)
            #expect(LinkTarget.isLink(root.appendingPathComponent("c0")))
            #expect(!LinkTarget.isLink(file))

            try fm.createSymbolicLink(atPath: b.path + "/dir", withDestinationPath: a.path)
            let folder = try LinkTarget.resolve(b.appendingPathComponent("dir"))
            #expect(folder.path == a.path)
            #expect(folder.hasDirectoryPath)

            let alias = b.appendingPathComponent("alias")
            let bookmark = try file.bookmarkData(options: .suitableForBookmarkFile)
            try URL.writeBookmarkData(bookmark, to: alias)
            #expect(LinkTarget.isLink(alias))
            #expect(try LinkTarget.resolve(alias).path == file.path)

            try fm.createSymbolicLink(atPath: b.path + "/broken", withDestinationPath: "../a/missing")
            #expect(throws: LinkError.targetMissing(stored: "../a/missing")) {
                try LinkTarget.resolve(b.appendingPathComponent("broken"))
            }
            try fm.createSymbolicLink(atPath: b.path + "/loop1", withDestinationPath: "loop2")
            try fm.createSymbolicLink(atPath: b.path + "/loop2", withDestinationPath: "loop1")
            #expect(throws: LinkError.loop(b.appendingPathComponent("loop1"))) {
                try LinkTarget.resolve(b.appendingPathComponent("loop1"))
            }
        })
    }
}
