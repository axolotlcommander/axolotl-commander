// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import Darwin
@testable import CommanderCore

/// Copying or moving into an archive must not go into itself, whatever path names the
/// archive (FR-010–012). Everything lives in a sandbox under the temporary directory.
@Suite struct ArchiveTransferCheckTests {
    /// `dir/a.zip` with `docs/old/x.txt`, plus the bytes of the archive file.
    private func makeArchive(_ dir: URL) async throws -> (URL, Data) {
        let src = dir.child("src")
        try TestSandbox.mkdirs(src.child("docs/old"))
        try TestSandbox.write(src.child("docs/old/x.txt"), "x")
        let archive = dir.child("a.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [.init(file: src.child("docs"), path: "docs")],
                                       progress: { _ in })
        return (archive, try Data(contentsOf: archive))
    }

    @Test func moveIntoOwnDescendantIsRefusedThroughAnyPath() async throws {
        try await TestSandbox.with("axo-archeck") { dir in
            let (archive, bytes) = try await makeArchive(dir)
            let link = dir.child("link.zip")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: archive)
            let other = dir.child("A.ZIP")  // same file on a case-insensitive volume, else skip that path
            let caseInsensitive = FileManager.default.fileExists(atPath: other.path)

            let source = ArchivePath(archive: link, inner: "", format: .zip)
            for path in [archive, link] + (caseInsensitive ? [other] : []) {
                let target = ArchivePath(archive: path, inner: "docs/old", format: .zip)
                #expect(throws: OperationError.intoItself(URL(filePath: "docs"))) {
                    try ArchiveTransferCheck.validate(source: source, names: ["docs"], target: target)
                }
                // The member itself as target, too.
                #expect(throws: OperationError.intoItself(URL(filePath: "docs"))) {
                    try ArchiveTransferCheck.validate(source: source, names: ["docs"],
                                                      target: ArchivePath(archive: path, inner: "docs", format: .zip))
                }
            }
            // Sideways in the same archive and into another archive are fine.
            try ArchiveTransferCheck.validate(source: ArchivePath(archive: archive, inner: "docs", format: .zip),
                                              names: ["old"], target: ArchivePath(archive: link, inner: "", format: .zip))
            try ArchiveTransferCheck.validate(source: source, names: ["docs"], target: ArchivePath(archive: archive, inner: "docsx", format: .zip))
            try TestSandbox.mkdirs(dir.child("second"))
            let (second, _) = try await makeArchive(dir.child("second"))
            try ArchiveTransferCheck.validate(source: source, names: ["docs"],
                                              target: ArchivePath(archive: second, inner: "docs/old", format: .zip))
            #expect(try Data(contentsOf: archive) == bytes)
        }
    }

    @Test func packIntoOwnSourceFolderIsRefused() throws {
        try TestSandbox.with("axo-archeck", sync: { dir in
            let project = dir.child("projekt")
            try TestSandbox.mkdirs(project.child("sub"))
            try TestSandbox.write(project.child("sub/a.txt"), "a")
            let before = TestSandbox.names(in: project)

            #expect(throws: OperationError.intoItself(project)) {
                try ArchiveTransferCheck.validatePack(archive: project.child("zaloha.zip"), sources: [project])
            }
            #expect(throws: OperationError.intoItself(project)) {
                try ArchiveTransferCheck.validatePack(archive: project.child("sub/zaloha.zip"), sources: [project])
            }
            // Through a symlink to the folder.
            let link = dir.child("plink")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: project)
            #expect(throws: OperationError.intoItself(project)) {
                try ArchiveTransferCheck.validatePack(archive: link.child("zaloha.zip"), sources: [project])
            }
            #expect(TestSandbox.names(in: project) == before)

            // Next to the folder is fine.
            try ArchiveTransferCheck.validatePack(archive: dir.child("projekt.zip"), sources: [project])
        })
    }

    @Test func archiveAmongItsOwnSourcesIsRefused() async throws {
        try await TestSandbox.with("axo-archeck") { dir in
            let (archive, bytes) = try await makeArchive(dir)
            try TestSandbox.write(dir.child("b.txt"), "b")
            #expect(throws: OperationError.intoItself(archive)) {
                try ArchiveTransferCheck.validatePack(archive: archive, sources: [dir.child("b.txt"), archive])
            }
            // A hard link to the archive is the same file.
            let hard = dir.child("hard.zip")
            #expect(link(archive.path, hard.path) == 0)
            #expect(throws: OperationError.intoItself(hard)) {
                try ArchiveTransferCheck.validatePack(archive: archive, sources: [hard])
            }
            try ArchiveTransferCheck.validatePack(archive: archive, sources: [dir.child("b.txt")])
            #expect(try Data(contentsOf: archive) == bytes)
        }
    }
}
