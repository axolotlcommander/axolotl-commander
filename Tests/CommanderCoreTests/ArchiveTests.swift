// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import Darwin
@testable import CommanderCore

// All archives and files live inside a UUID-named directory under
// FileManager.default.temporaryDirectory, removed when the test ends.

private func withSandbox(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("icmd-archive-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        chmodTree(root)
        try? FileManager.default.removeItem(at: root)
    }
    try await body(root)
}

/// Makes everything writable again so the sandbox can be removed.
private func chmodTree(_ root: URL) {
    guard let e = FileManager.default.enumerator(atPath: root.path) else { return }
    while let rel = e.nextObject() as? String { chmod(root.path + "/" + rel, 0o755) }
}

private extension URL {
    func sub(_ name: String) -> URL { URL(fileURLWithPath: path + "/" + name) }
}

private func write(_ url: URL, _ data: Data) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

private func write(_ url: URL, _ text: String) throws { try write(url, Data(text.utf8)) }

private func read(_ url: URL) -> Data? { FileManager.default.contents(atPath: url.path) }

private func names(_ dir: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
}

/// Deterministic pseudo-random bytes.
private func noise(_ count: Int, seed: UInt64 = 42) -> Data {
    var state = seed
    return Data((0..<count).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return UInt8(truncatingIfNeeded: state >> 33)
    })
}

private struct ToolFailed: Error {}

private func run(_ tool: String, _ args: [String], in dir: URL) throws {
    let p = Process()
    p.executableURL = URL(filePath: tool)
    p.arguments = args
    p.currentDirectoryURL = dir
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw ToolFailed() }
}

private func python(_ script: String, _ args: [String], in dir: URL) throws {
    try run("/usr/bin/python3", ["-I", "-c", script] + args, in: dir)
}

private let noProgress: @Sendable (Int64) -> Void = { _ in }

private func extractAll(_ archive: URL, to dest: URL, members: [String] = [""], base: String = "", overwrite: Bool = false) async throws -> ExtractReport {
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    return try await ArchiveExtractor.extract(
        archive: archive, members: members, base: base, to: dest, overwrite: overwrite, progress: noProgress
    )
}

private func index(_ archive: URL) async throws -> ArchiveIndex {
    try await ArchiveCatalog().index(of: archive)
}

// MARK: - Format and paths

@Test func detectFormat() {
    #expect(ArchiveFormat.detect(fileName: "a.zip") == .zip)
    #expect(ArchiveFormat.detect(fileName: "A.ZIP") == .zip)
    #expect(ArchiveFormat.detect(fileName: "lib.jar") == .zip)
    #expect(ArchiveFormat.detect(fileName: "x.7z") == .sevenZip)
    #expect(ArchiveFormat.detect(fileName: "x.tar") == .tar)
    #expect(ArchiveFormat.detect(fileName: "x.tar.gz") == .tarGzip)
    #expect(ArchiveFormat.detect(fileName: "x.TGZ") == .tarGzip)
    #expect(ArchiveFormat.detect(fileName: "x.tar.bz2") == .tarBzip2)
    #expect(ArchiveFormat.detect(fileName: "x.tbz") == .tarBzip2)
    #expect(ArchiveFormat.detect(fileName: "x.tbz2") == .tarBzip2)
    #expect(ArchiveFormat.detect(fileName: "x.tar.xz") == .tarXz)
    #expect(ArchiveFormat.detect(fileName: "x.txz") == .tarXz)
    #expect(ArchiveFormat.detect(fileName: "x.rar") == .rar)
    #expect(ArchiveFormat.detect(fileName: "notes.txt") == nil)
    #expect(ArchiveFormat.detect(fileName: "x.gz") == nil)
    #expect(ArchiveFormat.detect(fileName: ".zip") == nil)
    #expect(!ArchiveFormat.rar.isWritable && ArchiveFormat.sevenZip.isWritable)
    #expect(ArchiveFormat.tarGzip.preferredExtension == "tar.gz")
}

@Test func splitArchivePath() throws {
    let isFile: (URL) -> Bool = { $0.path == "/a/b.zip" || $0.path == "/a/dir.zip/real.7z" }
    let p = try #require(ArchivePath.split(URL(filePath: "/a/b.zip/c/d"), isRegularFile: isFile))
    #expect(p.archive.path == "/a/b.zip")
    #expect(p.inner == "c/d")
    #expect(p.format == .zip)
    #expect(p.url.path == "/a/b.zip/c/d")
    #expect(ArchivePath.split(p.url, isRegularFile: isFile) == p)
    #expect(p.member("e") == "c/d/e")

    let root = try #require(ArchivePath.split(URL(filePath: "/a/b.zip"), isRegularFile: isFile))
    #expect(root.inner == "")
    #expect(root.member("e") == "e")
    #expect(ArchivePath.split(root.url, isRegularFile: isFile) == root)

    #expect(ArchivePath.split(URL(filePath: "/a/dir.zip/x"), isRegularFile: isFile) == nil)
    #expect(ArchivePath.split(URL(filePath: "/a/b.txt/c"), isRegularFile: isFile) == nil)
    let nested = try #require(ArchivePath.split(URL(filePath: "/a/dir.zip/real.7z/q"), isRegularFile: isFile))
    #expect(nested.archive.path == "/a/dir.zip/real.7z" && nested.inner == "q" && nested.format == .sevenZip)
}

// MARK: - Index

@Test func indexSynthesizesImplicitDirectories() async throws {
    try await withSandbox { root in
        let tree = root.sub("tree")
        try write(tree.sub("top.txt"), "top")
        try write(tree.sub("x/w.txt"), "www")
        try write(tree.sub("x/y/z.txt"), "zzzzz")
        try run("/usr/bin/zip", ["-q", "-r", "-D", root.sub("t.zip").path, "top.txt", "x"], in: tree)

        let idx = try await index(root.sub("t.zip"))
        #expect(idx.format == .zip)
        #expect(idx.entry(at: "x")?.isImplicit == true)
        #expect(idx.entry(at: "x/y")?.isDirectory == true)
        #expect(idx.entry(at: "x/y")?.isImplicit == true)
        #expect(idx.children(of: "").map(\.name).sorted() == ["top.txt", "x"])
        #expect(idx.children(of: "x").map(\.name).sorted() == ["w.txt", "y"])
        #expect(idx.children(of: "x/y").map(\.name) == ["z.txt"])
        #expect(idx.children(of: "nope").isEmpty)
        #expect(idx.contains(directory: "") && idx.contains(directory: "x/y"))
        #expect(!idx.contains(directory: "top.txt") && !idx.contains(directory: "q"))
        #expect(Set(idx.entries(under: ["x"]).map(\.path)) == ["x", "x/w.txt", "x/y", "x/y/z.txt"])
        #expect(idx.totalSize(under: ["x"]) == 8)
        #expect(idx.totalSize(under: ["x", "x/y", "top.txt"]) == 11)
        #expect(idx.entries(under: ["x", "x/y"]).count == 4)
        #expect(idx.entry(at: "top.txt")?.size == 3)
        #expect(idx.entry(at: "top.txt")?.modificationDate != nil)
    }
}

@Test func indexLastDuplicateWins() {
    let idx = ArchiveIndex(format: .tar, entries: [
        ArchiveEntry(path: "a/f", isDirectory: false, size: 1),
        ArchiveEntry(path: "a", isDirectory: true),
        ArchiveEntry(path: "a/f", isDirectory: false, size: 2),
    ])
    #expect(idx.entries.count == 2)
    #expect(idx.entry(at: "a/f")?.size == 2)
    #expect(idx.entry(at: "a")?.isImplicit == false)
}

// MARK: - Round trip

@Test(arguments: [ArchiveFormat.zip, .sevenZip, .tar, .tarGzip, .tarBzip2, .tarXz])
func createIndexExtractRoundTrip(format: ArchiveFormat) async throws {
    try await withSandbox { root in
        let czech = "žluťoučký kůň.txt".decomposedStringWithCanonicalMapping
        let src = root.sub("src")
        let big = noise(300_000)
        try write(src.sub(czech), "příliš")
        try write(src.sub("sub/big.bin"), big)
        try FileManager.default.createDirectory(at: src.sub("sub/empty"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: src.sub("link").path, withDestinationPath: czech)

        let archive = root.sub("out." + format.preferredExtension)
        let maxProgress = ProgressBox()
        try await ArchiveWriter.create(archive, format: format, adding: [ArchiveWriter.Source(file: src, path: "src")]) {
            maxProgress.set($0)
        }
        #expect(maxProgress.value == Int64(big.count + "příliš".utf8.count))
        #expect(names(root) == ["out." + format.preferredExtension, "src"])

        let idx = try await index(archive)
        #expect(idx.format == format)
        let text = try #require(idx.entry(at: "src/" + czech))
        #expect(text.path.utf8.elementsEqual(("src/" + czech).utf8))
        #expect(text.size == Int64("příliš".utf8.count))
        #expect(idx.entry(at: "src/sub/big.bin")?.size == Int64(big.count))
        #expect(idx.entry(at: "src/sub/empty")?.isDirectory == true)
        #expect(idx.entry(at: "src")?.isImplicit == false)
        let link = try #require(idx.entry(at: "src/link"))
        #expect(link.isSymlink && link.linkTarget == czech)

        let dest = root.sub("dest")
        let report = try await extractAll(archive, to: dest)
        #expect(report.skipped.isEmpty)
        #expect(read(dest.sub("src/" + czech)) == Data("příliš".utf8))
        #expect(read(dest.sub("src/sub/big.bin")) == big)
        #expect(names(dest.sub("src/sub/empty")).isEmpty)
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: dest.sub("src/link").path)
        #expect(target == czech)
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int64 = 0
    func set(_ v: Int64) { lock.withLock { stored = max(stored, v) } }
    var value: Int64 { lock.withLock { stored } }
}

// MARK: - Extraction safety

@Test func extractionSanitizesPaths() async throws {
    #expect(ArchiveExtractor.sanitize("../x") == "x")
    #expect(ArchiveExtractor.sanitize("/etc/passwd") == "etc/passwd")
    #expect(ArchiveExtractor.sanitize("a/../../b") == "a/b")
    #expect(ArchiveExtractor.sanitize("C:\\win\\x.txt") == "win/x.txt")
    #expect(ArchiveExtractor.sanitize("//server/share/f") == "server/share/f")
    #expect(ArchiveExtractor.sanitize("./a/./b/") == "a/b")
    #expect(ArchiveExtractor.sanitize("../..") == nil)

    try await withSandbox { root in
        let script = """
        import sys, zipfile
        with zipfile.ZipFile(sys.argv[1], 'w') as z:
            z.writestr(zipfile.ZipInfo('../x'), 'dotdot')
            z.writestr(zipfile.ZipInfo('/abs/y'), 'absolute')
            z.writestr(zipfile.ZipInfo('ok.txt'), 'ok')
        """
        try python(script, [root.sub("evil.zip").path], in: root)
        let idx = try await index(root.sub("evil.zip"))
        #expect(idx.entry(at: "../x") != nil)
        #expect(idx.entry(at: "abs/y") != nil)

        let out = root.sub("out")
        let dest = out.sub("dest")
        _ = try await extractAll(root.sub("evil.zip"), to: dest)
        #expect(read(dest.sub("x")) == Data("dotdot".utf8))
        #expect(read(dest.sub("abs/y")) == Data("absolute".utf8))
        #expect(read(dest.sub("ok.txt")) == Data("ok".utf8))
        #expect(names(out) == ["dest"])
        #expect(names(root) == ["evil.zip", "out"])
    }
}

@Test func extractionDoesNotFollowSymlinks() async throws {
    try await withSandbox { root in
        let outside = root.sub("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let script = """
        import io, sys, tarfile
        with tarfile.open(sys.argv[1], 'w') as t:
            link = tarfile.TarInfo('link')
            link.type = tarfile.SYMTYPE
            link.linkname = sys.argv[2]
            t.addfile(link)
            data = b'evil'
            f = tarfile.TarInfo('link/evil.txt')
            f.size = len(data)
            t.addfile(f, io.BytesIO(data))
        """
        try python(script, [root.sub("evil.tar").path, outside.path], in: root)
        let dest = root.sub("dest")
        _ = try? await extractAll(root.sub("evil.tar"), to: dest)
        #expect(names(outside).isEmpty)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: dest.sub("link").path)) == outside.path)
    }
}

@Test func extractionStripsBaseFolder() async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub("dir/sub/f.txt"), "f")
        try write(src.sub("dir/sub/deep/g.txt"), "g")
        try write(src.sub("dir/h.txt"), "h")
        let archive = root.sub("a.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [.init(file: src.sub("dir"), path: "dir")], progress: noProgress)

        let dest = root.sub("dest")
        let report = try await extractAll(archive, to: dest, members: ["dir/sub"], base: "dir")
        #expect(names(dest) == ["sub"])
        #expect(read(dest.sub("sub/f.txt")) == Data("f".utf8))
        #expect(read(dest.sub("sub/deep/g.txt")) == Data("g".utf8))
        #expect(report.written.map(\.lastPathComponent).contains("f.txt"))
    }
}

@Test func extractionSkipsExistingWithoutOverwrite() async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub("a.txt"), "new")
        try write(src.sub("b.txt"), "b")
        let archive = root.sub("a.tar.gz")
        try await ArchiveWriter.create(archive, format: .tarGzip, adding: [
            .init(file: src.sub("a.txt"), path: "a.txt"), .init(file: src.sub("b.txt"), path: "b.txt"),
        ], progress: noProgress)

        let dest = root.sub("dest")
        try write(dest.sub("a.txt"), "old")
        let report = try await extractAll(archive, to: dest)
        #expect(report.skipped == ["a.txt"])
        #expect(read(dest.sub("a.txt")) == Data("old".utf8))
        #expect(read(dest.sub("b.txt")) == Data("b".utf8))

        let again = try await extractAll(archive, to: dest, overwrite: true)
        #expect(again.skipped.isEmpty)
        #expect(read(dest.sub("a.txt")) == Data("new".utf8))
    }
}

@Test func extractionCancelsAndRemovesPartialFile() async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub("big.bin"), noise(1_000_000))
        let archive = root.sub("a.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [.init(file: src.sub("big.bin"), path: "big.bin")], progress: noProgress)
        let dest = root.sub("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let task = Task {
            try await ArchiveExtractor.extract(archive: archive, members: [""], base: "", to: dest, overwrite: false) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: ArchiveError.cancelled) { _ = try await task.value }
        #expect(names(dest).isEmpty)
    }
}

// MARK: - Update

@Test func updateAddsRemovesAndRenames() async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub("docs/readme.txt"), "readme")
        try write(src.sub("docs/notes/n1.txt"), "n1")
        try write(src.sub("keep.bin"), noise(70_000))
        try write(src.sub("upper.txt"), "upper")
        try write(src.sub("lower.txt"), "lower")
        try write(src.sub("lower2.txt"), "lower2")
        try write(src.sub("new.txt"), "new")
        let archive = root.sub("u.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [
            .init(file: src.sub("docs"), path: "docs"),
            .init(file: src.sub("keep.bin"), path: "keep.bin"),
            .init(file: src.sub("upper.txt"), path: "A.txt"),
            .init(file: src.sub("lower.txt"), path: "a.txt"),
        ], progress: noProgress)
        chmod(archive.path, 0o640)

        try await ArchiveWriter.update(archive, adding: [.init(file: src.sub("new.txt"), path: "docs/notes/new.txt")], progress: noProgress)
        var idx = try await index(archive)
        #expect(idx.entry(at: "docs/notes/new.txt")?.size == 3)
        var dest = root.sub("d1")
        _ = try await extractAll(archive, to: dest, members: ["docs", "keep.bin"])
        #expect(read(dest.sub("docs/readme.txt")) == Data("readme".utf8))
        #expect(read(dest.sub("docs/notes/n1.txt")) == Data("n1".utf8))
        #expect(read(dest.sub("docs/notes/new.txt")) == Data("new".utf8))
        #expect(read(dest.sub("keep.bin")) == noise(70_000))

        try await ArchiveWriter.update(archive, removing: ["keep.bin"], progress: noProgress)
        idx = try await index(archive)
        #expect(idx.entry(at: "keep.bin") == nil)
        #expect(idx.entry(at: "docs/readme.txt") != nil)

        try await ArchiveWriter.update(archive, renaming: ["docs": "papers"], progress: noProgress)
        idx = try await index(archive)
        #expect(idx.entry(at: "docs") == nil)
        #expect(idx.entry(at: "papers")?.isDirectory == true)
        #expect(Set(idx.entries(under: ["papers"]).map(\.path))
            == ["papers", "papers/readme.txt", "papers/notes", "papers/notes/n1.txt", "papers/notes/new.txt"])
        dest = root.sub("d2")
        _ = try await extractAll(archive, to: dest, members: ["papers"])
        #expect(read(dest.sub("papers/notes/n1.txt")) == Data("n1".utf8))

        try await ArchiveWriter.update(archive, adding: [.init(file: src.sub("lower2.txt"), path: "a.txt")], progress: noProgress)
        idx = try await index(archive)
        #expect(idx.entries.filter { $0.name == "a.txt" }.count == 1)
        #expect(idx.entries.filter { $0.name == "A.txt" }.count == 1)
        let upper = root.sub("upper")
        let lower = root.sub("lower")
        _ = try await extractAll(archive, to: upper, members: ["A.txt"])
        _ = try await extractAll(archive, to: lower, members: ["a.txt"])
        #expect(read(upper.sub("A.txt")) == Data("upper".utf8))
        #expect(read(lower.sub("a.txt")) == Data("lower2".utf8))

        var st = stat()
        stat(archive.path, &st)
        #expect(st.st_mode & 0o777 == 0o640)
        #expect(names(root).filter { $0.hasPrefix(".") }.isEmpty)

        await #expect(throws: ArchiveError.notFound("nope")) {
            try await ArchiveWriter.update(archive, removing: ["nope"], progress: noProgress)
        }
        await #expect(throws: ArchiveError.notFound("ghost")) {
            try await ArchiveWriter.update(archive, renaming: ["ghost": "x"], progress: noProgress)
        }
    }
}

@Test(arguments: [ArchiveFormat.sevenZip, .tarXz])
func updateOtherFormats(format: ArchiveFormat) async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub("d/a.txt"), "a")
        try write(src.sub("b.txt"), "b")
        let archive = root.sub("x." + format.preferredExtension)
        try await ArchiveWriter.create(archive, format: format, adding: [.init(file: src.sub("d"), path: "d")], progress: noProgress)
        try await ArchiveWriter.update(archive, renaming: ["d": "e"], adding: [.init(file: src.sub("b.txt"), path: "e/b.txt")], progress: noProgress)
        let idx = try await index(archive)
        #expect(idx.format == format)
        #expect(Set(idx.entries.map(\.path)) == ["e", "e/a.txt", "e/b.txt"])
        let dest = root.sub("dest")
        _ = try await extractAll(archive, to: dest)
        #expect(read(dest.sub("e/a.txt")) == Data("a".utf8))
        #expect(read(dest.sub("e/b.txt")) == Data("b".utf8))
    }
}

@Test func failedUpdateLeavesOriginalUntouched() async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub("a.txt"), "a")
        try write(src.sub("locked.txt"), "secret")
        let work = root.sub("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let archive = work.sub("a.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [.init(file: src.sub("a.txt"), path: "a.txt")], progress: noProgress)
        let before = try #require(read(archive))

        await #expect(throws: ArchiveError.notFound(src.sub("missing.txt").path)) {
            try await ArchiveWriter.update(archive, adding: [.init(file: src.sub("missing.txt"), path: "m.txt")], progress: noProgress)
        }
        #expect(read(archive) == before)
        #expect(names(work) == ["a.zip"])

        chmod(src.sub("locked.txt").path, 0)
        await #expect(throws: ArchiveError.self) {
            try await ArchiveWriter.update(archive, adding: [.init(file: src.sub("locked.txt"), path: "l.txt")], progress: noProgress)
        }
        #expect(read(archive) == before)
        #expect(names(work) == ["a.zip"])

        let cancelled = Task {
            try await ArchiveWriter.update(archive, adding: [.init(file: src.sub("a.txt"), path: "b.txt")]) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: ArchiveError.cancelled) { try await cancelled.value }
        #expect(read(archive) == before)
        #expect(names(work) == ["a.zip"])

        await #expect(throws: ArchiveError.alreadyExists(archive.path)) {
            try await ArchiveWriter.create(archive, format: .zip, adding: [], progress: noProgress)
        }
    }
}

@Test func updateRefusesArchiveChangedSinceRead() async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub("a.txt"), "a")
        try write(src.sub("b.txt"), "b")
        let work = root.sub("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let archive = work.sub("a.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [.init(file: src.sub("a.txt"), path: "a.txt")], progress: noProgress)
        let stamp = try #require(PersistentFileStamp(archive))

        // Someone else updates the archive after the member was taken out.
        try await ArchiveWriter.update(archive, adding: [.init(file: src.sub("b.txt"), path: "other.txt")], progress: noProgress)
        let changed = try #require(read(archive))
        await #expect(throws: ArchiveError.changedSinceRead(archive.path)) {
            try await ArchiveWriter.update(archive, adding: [.init(file: src.sub("a.txt"), path: "a.txt")],
                                           expecting: stamp, progress: noProgress)
        }
        #expect(read(archive) == changed)
        #expect(names(work) == ["a.zip"])

        // With the current stamp it goes through.
        try await ArchiveWriter.update(archive, adding: [.init(file: src.sub("b.txt"), path: "a.txt")],
                                       expecting: PersistentFileStamp(archive), progress: noProgress)
        #expect(read(archive) != changed)
    }
}

@Test func rarIsReadOnly() async throws {
    try await withSandbox { root in
        let rar = root.sub("x.rar")
        try write(rar, "not really a rar")
        await #expect(throws: ArchiveError.readOnly) {
            try await ArchiveWriter.update(rar, removing: ["a"], progress: noProgress)
        }
        await #expect(throws: ArchiveError.readOnly) {
            try await ArchiveWriter.create(root.sub("y.rar"), format: .rar, adding: [], progress: noProgress)
        }
        #expect(read(rar) == Data("not really a rar".utf8))
        #expect(names(root) == ["x.rar"])
    }
}

// MARK: - Catalog

@Test func catalogCachesAndLists() async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub(".hidden"), "h")
        try write(src.sub("visible.txt"), "v")
        try write(src.sub("dir/x.txt"), "x")
        try write(src.sub("new.txt"), "n")
        let archive = root.sub("c.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [
            .init(file: src.sub(".hidden"), path: ".hidden"),
            .init(file: src.sub("visible.txt"), path: "visible.txt"),
            .init(file: src.sub("dir"), path: "dir"),
        ], progress: noProgress)

        let catalog = ArchiveCatalog()
        let first = try await catalog.index(of: archive)
        let second = try await catalog.index(of: archive)
        #expect(first.entries == second.entries)

        let path = ArchivePath(archive: archive, format: .zip)
        let visible = try await catalog.list(path, includeHidden: false)
        #expect(visible.map(\.name).sorted() == ["dir", "visible.txt"])
        let all = try await catalog.list(path, includeHidden: true)
        #expect(all.map(\.name).sorted() == [".hidden", "dir", "visible.txt"])
        #expect(all.first { $0.name == ".hidden" }?.isHidden == true)
        let dir = try #require(all.first { $0.name == "dir" })
        #expect(dir.isDirectory && dir.size == nil && dir.url.path == archive.path + "/dir")
        let inner = try await catalog.list(ArchivePath(archive: archive, inner: "dir", format: .zip), includeHidden: false)
        #expect(inner.map(\.name) == ["x.txt"])
        #expect(inner.first?.size == 1)
        #expect(inner.first?.url.path == archive.path + "/dir/x.txt")
        await #expect(throws: ArchiveError.notFound("nope")) {
            _ = try await catalog.list(ArchivePath(archive: archive, inner: "nope", format: .zip), includeHidden: true)
        }

        try await ArchiveWriter.update(archive, adding: [.init(file: src.sub("new.txt"), path: "new.txt")], progress: noProgress)
        let updated = try await catalog.list(path, includeHidden: false)
        #expect(updated.map(\.name).sorted() == ["dir", "new.txt", "visible.txt"])
    }
}

/// The panel may reach an archive through a symlinked folder or in another letter case;
/// invalidating it by any of its paths drops the cached index.
@Test func catalogInvalidatesThroughSymlinkAndCase() async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub("a.txt"), "1")
        let real = root.sub("Real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        let archive = real.sub("Box.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [.init(file: src.sub("a.txt"), path: "a.txt")], progress: noProgress)
        try FileManager.default.createSymbolicLink(atPath: root.sub("link").path, withDestinationPath: "Real")
        let viaLink = root.sub("link/Box.zip")

        let catalog = ArchiveCatalog()
        #expect(try await catalog.index(of: viaLink).entries.map(\.name) == ["a.txt"])

        // Same size and date: only an invalidation can tell the cache apart.
        var st = stat()
        #expect(stat(archive.path, &st) == 0)
        try write(src.sub("b.txt"), "2")
        let other = root.sub("other.zip")
        try await ArchiveWriter.create(other, format: .zip, adding: [.init(file: src.sub("b.txt"), path: "b.txt")], progress: noProgress)
        var ot = stat()
        #expect(stat(other.path, &ot) == 0 && ot.st_size == st.st_size)
        #expect(rename(other.path, archive.path) == 0)
        var times = [st.st_atimespec, st.st_mtimespec]
        #expect(utimensat(AT_FDCWD, archive.path, &times, 0) == 0)
        #expect(try await catalog.index(of: viaLink).entries.map(\.name) == ["a.txt"])

        await catalog.invalidate(root.sub("real/box.ZIP"))
        #expect(try await catalog.index(of: viaLink).entries.map(\.name) == ["b.txt"])
    }
}

// MARK: - Legacy names

/// Writes a zip whose members have exactly the given name bytes and no UTF-8 flag,
/// as old Windows tools make them.
private func makeLegacyZip(_ archive: URL, names: [[UInt8]], in dir: URL) throws {
    let script = """
    import sys, zipfile, struct
    path = sys.argv[1]
    names = [bytes.fromhex(h) for h in sys.argv[2:]]
    with zipfile.ZipFile(path, 'w') as z:
        for i, n in enumerate(names):
            z.writestr(zipfile.ZipInfo(chr(65 + i) * len(n)), b'data')
    b = bytearray(open(path, 'rb').read())
    for i, n in enumerate(names):
        ph = (chr(65 + i) * len(n)).encode()
        j = b.find(ph)
        while j != -1:
            b[j:j + len(n)] = n
            j = b.find(ph, j + 1)
    for sig, off in ((b'PK\\x03\\x04', 6), (b'PK\\x01\\x02', 8)):
        j = b.find(sig)
        while j != -1:
            struct.pack_into('<H', b, j + off, struct.unpack_from('<H', b, j + off)[0] & ~0x800)
            j = b.find(sig, j + 1)
    open(path, 'wb').write(b)
    """
    try python(script, [archive.path] + names.map { $0.map { String(format: "%02x", $0) }.joined() }, in: dir)
}

@Test func legacyCodePagesFollowTheLanguage() {
    // "Archivní návrat čřšžěů" in CP852.
    var cp852: [UInt8] = Array("Archivn".utf8)
    cp852 += [0xA1, 0x20, 0x6E, 0xA0]
    cp852 += Array("vrat ".utf8)
    cp852 += [0x9F, 0xFD, 0xE7, 0xA7, 0xD8, 0x85]
    #expect(LegacyNames.decode(cp852, legacy: LegacyNames.codePages(language: "cs-CZ").oem) == "Archivní návrat čřšžěů")
    #expect(LegacyNames.decode([0x8E, 0x72], legacy: LegacyNames.codePages(language: "en-US").oem) == "Är")
    #expect(LegacyNames.decode([0x8E, 0x72], legacy: LegacyNames.codePages(language: "ru").oem) == "Оr")
    #expect(LegacyNames.decode([0xE8], legacy: LegacyNames.codePages(language: "cs").ansi) == "č")
    #expect(LegacyNames.decode([0xE8], legacy: LegacyNames.codePages(language: "de").ansi) == "è")
    // Valid UTF-8 always wins.
    #expect(LegacyNames.decode(Array("návrat".utf8), legacy: LegacyNames.codePages(language: "cs").oem) == "návrat")
}

/// Names without the UTF-8 flag: UTF-8 bytes stay UTF-8, other bytes come from the OEM code
/// page, in the listing and on disk alike (never "?" or U+FFFD).
@Test func zipWithoutUTF8FlagKeepsReadableNames() async throws {
    try await withSandbox { root in
        let utf8 = Array("Archivní dokumenty k návratu 01.pdf".utf8)
        var oem: [UInt8] = Array("Archivn".utf8)
        oem.append(0xA1)
        oem += Array(" dokument.txt".utf8)
        let archive = root.sub("legacy.zip")
        try makeLegacyZip(archive, names: [utf8, oem], in: root)
        let expectedOEM = LegacyNames.decode(oem, legacy: LegacyNames.current.oem)
        #expect(!expectedOEM.contains("\u{FFFD}"))

        let listed = try await index(archive).entries.map(\.name).sorted()
        #expect(listed == ["Archivní dokumenty k návratu 01.pdf", expectedOEM].sorted())

        let dest = root.sub("out")
        _ = try await extractAll(archive, to: dest)
        let disk = names(dest).map { $0.precomposedStringWithCanonicalMapping }
        #expect(disk == listed.map { $0.precomposedStringWithCanonicalMapping })
    }
}

// MARK: - Encryption and owners

/// Zip with encrypted "a.txt" and "sub/big.bin" plus a plain "plain.txt" (password "secret").
private func makeEncryptedZip(_ root: URL, method: String) throws -> (archive: URL, big: Data) {
    let src = root.sub("src")
    let big = noise(200_000)
    try write(src.sub("a.txt"), "hello")
    try write(src.sub("sub/big.bin"), big)
    try write(src.sub("plain.txt"), "plain")
    let archive = root.sub("enc.zip")
    if method == "zip-P" {
        try run("/usr/bin/zip", ["-q", "-r", "-P", "secret", archive.path, "a.txt", "sub"], in: src)
    } else {
        try run("/usr/bin/bsdtar", ["--format", "zip", "--options", "zip:encryption=\(method)", "--passphrase", "secret",
                                    "-cf", archive.path, "a.txt", "sub"], in: src)
    }
    try run("/usr/bin/zip", ["-q", archive.path, "plain.txt"], in: src)
    return (archive, big)
}

@Test(arguments: ["zip-P", "traditional", "aes256"])
func encryptedZipNeedsRightPassword(method: String) async throws {
    try await withSandbox { root in
        let (archive, big) = try makeEncryptedZip(root, method: method)
        let idx = try await index(archive)
        #expect(idx.hasEncryptedEntries)
        #expect(idx.entry(at: "a.txt")?.isEncrypted == true)
        #expect(idx.entry(at: "plain.txt")?.isEncrypted == false)

        // Plain members need no password.
        try await ArchiveExtractor.verifyPassphrase(archive: archive, members: ["plain.txt"], passphrases: [])
        let plain = root.sub("plain")
        _ = try await extractAll(archive, to: plain, members: ["plain.txt"])
        #expect(read(plain.sub("plain.txt")) == Data("plain".utf8))

        await #expect(throws: ArchiveError.passwordRequired("a.txt")) {
            try await ArchiveExtractor.verifyPassphrase(archive: archive, members: [""], passphrases: [])
        }
        await #expect(throws: ArchiveError.wrongPassword("a.txt")) {
            try await ArchiveExtractor.verifyPassphrase(archive: archive, members: ["a.txt"], passphrases: ["wrong"])
        }
        try await ArchiveExtractor.verifyPassphrase(archive: archive, members: [""], passphrases: ["secret"])

        let none = root.sub("none")
        await #expect(throws: ArchiveError.passwordRequired("a.txt")) {
            _ = try await extractAll(archive, to: none, members: ["a.txt"])
        }
        #expect(names(none).isEmpty)
        let wrong = root.sub("wrong")
        try FileManager.default.createDirectory(at: wrong, withIntermediateDirectories: true)
        await #expect(throws: ArchiveError.wrongPassword("sub/big.bin")) {
            _ = try await ArchiveExtractor.extract(archive: archive, members: ["sub"], base: "", to: wrong,
                                                   overwrite: false, passphrases: ["wrong"], progress: noProgress)
        }
        #expect(read(wrong.sub("sub/big.bin")) == nil)

        let right = root.sub("right")
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        _ = try await ArchiveExtractor.extract(archive: archive, members: [""], base: "", to: right,
                                               overwrite: false, passphrases: ["wrong", "secret"], progress: noProgress)
        #expect(read(right.sub("a.txt")) == Data("hello".utf8))
        #expect(read(right.sub("sub/big.bin")) == big)
        #expect(read(right.sub("plain.txt")) == Data("plain".utf8))

        // Rewriting would drop the encryption: still refused.
        await #expect(throws: ArchiveError.readOnly) {
            try await ArchiveWriter.update(archive, removing: ["plain.txt"], progress: noProgress)
        }
    }
}

/// Reads a NUL-terminated field of a tar header.
private func tarField(_ data: Data, _ offset: Int, _ length: Int) -> String {
    let bytes = data[offset..<(offset + length)].prefix { $0 != 0 }
    return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
}

@Test func addedMembersKeepTheSourceOwner() async throws {
    try await withSandbox { root in
        let file = root.sub("owned.txt")
        try write(file, "mine")
        var st = stat()
        #expect(lstat(file.path, &st) == 0)
        let user = try #require(getpwuid(st.st_uid).map { String(cString: $0.pointee.pw_name) })
        let group = try #require(getgrgid(st.st_gid).map { String(cString: $0.pointee.gr_name) })

        let created = root.sub("c.tar")
        try await ArchiveWriter.create(created, format: .tar, adding: [.init(file: file, path: "owned.txt")], progress: noProgress)
        let updated = root.sub("u.tar")
        try await ArchiveWriter.create(updated, format: .tar, adding: [], progress: noProgress)
        try await ArchiveWriter.update(updated, adding: [.init(file: file, path: "owned.txt")], progress: noProgress)

        for archive in [created, updated] {
            let header = try #require(read(archive))
            #expect(tarField(header, 0, 100) == "owned.txt")
            #expect(Int(tarField(header, 108, 8), radix: 8) == Int(st.st_uid))
            #expect(Int(tarField(header, 116, 8), radix: 8) == Int(st.st_gid))
            #expect(tarField(header, 265, 32) == user)
            #expect(tarField(header, 297, 32) == group)
        }
    }
}

// MARK: - Hard links

/// Tar made by /usr/bin/tar from `a` (data) and `b`, `c` hard links to it, so `b` and `c`
/// are stored as hard-link members naming `a`.
private func makeHardLinkTar(_ root: URL, format: ArchiveFormat) throws -> URL {
    let src = root.sub("src")
    try write(src.sub("a"), noise(70_000))
    #expect(link(src.sub("a").path, src.sub("b").path) == 0)
    #expect(link(src.sub("a").path, src.sub("c").path) == 0)
    let archive = root.sub("h." + format.preferredExtension)
    try run("/usr/bin/tar", [format == .tarGzip ? "-czf" : "-cf", archive.path, "a", "b", "c"], in: src)
    return archive
}

/// Member path -> hard-link target, read straight from the archive headers.
private func hardLinks(_ archive: URL) throws -> [String: String] {
    try withUTF8Locale {
        let reader = try ArchiveReadHandle(path: archive.path)
        var links: [String: String] = [:]
        while let e = try reader.next() {
            let info = RawEntryInfo(e, legacy: reader.legacyNames)
            if let link = info.hardlink { links[normalizeMemberPath(info.path)] = normalizeMemberPath(link) }
            try reader.skip()
        }
        return links
    }
}

private func inode(_ url: URL) -> ino_t? {
    var st = stat()
    return lstat(url.path, &st) == 0 ? st.st_ino : nil
}

@Test(arguments: [ArchiveFormat.tar, .tarGzip])
func removingHardLinkTargetKeepsLinkData(format: ArchiveFormat) async throws {
    try await withSandbox { root in
        let archive = try makeHardLinkTar(root, format: format)
        try #require(try hardLinks(archive) == ["b": "a", "c": "a"])

        try await ArchiveWriter.update(archive, removing: ["a"], renaming: ["c": "d/c"], progress: noProgress)
        // `b` now carries the data; the other link points to it.
        #expect(try hardLinks(archive) == ["d/c": "b"])
        let dest = root.sub("dest")
        let report = try await extractAll(archive, to: dest)
        #expect(report.skipped.isEmpty)
        #expect(names(dest) == ["b", "d"])
        #expect(read(dest.sub("b")) == noise(70_000))
        #expect(read(dest.sub("d/c")) == noise(70_000))
        #expect(inode(dest.sub("b")) == inode(dest.sub("d/c")))
    }
}

@Test func replacingHardLinkTargetKeepsLinkData() async throws {
    try await withSandbox { root in
        let archive = try makeHardLinkTar(root, format: .tar)
        let fresh = root.sub("fresh.txt")
        try write(fresh, "fresh")

        // Replacing `a` puts a new member in its place; the links keep the content they
        // had (the old data of `a`) instead of following the replacement, which is
        // appended after them and is a separate file.
        try await ArchiveWriter.update(archive, adding: [.init(file: fresh, path: "a")], progress: noProgress)
        #expect(try hardLinks(archive) == ["c": "b"])
        let dest = root.sub("dest")
        let report = try await extractAll(archive, to: dest)
        #expect(report.skipped.isEmpty)
        #expect(read(dest.sub("a")) == Data("fresh".utf8))
        #expect(read(dest.sub("b")) == noise(70_000))
        #expect(read(dest.sub("c")) == noise(70_000))
        #expect(inode(dest.sub("b")) == inode(dest.sub("c")))
        #expect(inode(dest.sub("a")) != inode(dest.sub("b")))
    }
}

@Test func keptHardLinkTargetStaysLinked() async throws {
    try await withSandbox { root in
        let archive = try makeHardLinkTar(root, format: .tar)
        try await ArchiveWriter.update(archive, removing: ["b"], renaming: ["a": "x/a"], progress: noProgress)
        #expect(try hardLinks(archive) == ["c": "x/a"])
        let dest = root.sub("dest")
        _ = try await extractAll(archive, to: dest)
        #expect(read(dest.sub("c")) == noise(70_000))
        #expect(inode(dest.sub("x/a")) == inode(dest.sub("c")))
    }
}

// MARK: - Writing to disk

/// The process umask, read without changing it: the mode a new file gets.
private func probeUmask(in dir: URL) -> mode_t {
    let path = dir.path + "/umask-probe-\(UUID().uuidString)"
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o777)
    defer { close(fd); unlink(path) }
    var st = stat()
    fstat(fd, &st)
    return ~st.st_mode & 0o777
}

private func lstatOf(_ url: URL) -> stat? {
    var st = stat()
    return lstat(url.path, &st) == 0 ? st : nil
}

/// Modes, dates (a folder's too, set after its contents), symlinks and hard links.
@Test func extractionKeepsModesDatesAndLinks() async throws {
    try await withSandbox { root in
        let script = """
        import io, sys, tarfile
        def add(t, name, kind=tarfile.REGTYPE, mode=0o644, mtime=0, data=b'', link=''):
            i = tarfile.TarInfo(name); i.type = kind; i.mode = mode; i.mtime = mtime; i.linkname = link
            i.size = len(data) if kind == tarfile.REGTYPE else 0
            t.addfile(i, io.BytesIO(data) if kind == tarfile.REGTYPE else None)
        with tarfile.open(sys.argv[1], 'w', format=tarfile.PAX_FORMAT) as t:
            add(t, 'd', tarfile.DIRTYPE, 0o750, 1000000000)
            add(t, 'd/f.txt', mtime=1050000000, data=b'f')
            add(t, 'run.sh', mode=0o755, mtime=1100000000, data=b'#!/bin/sh')
            add(t, 'private.txt', mode=0o600, mtime=1100000000, data=b'p')
            add(t, 'zero.txt', mode=0, mtime=1100000000, data=b'z')
            add(t, 'ln', tarfile.SYMTYPE, mtime=1200000000, link='run.sh')
            add(t, 'hard', tarfile.LNKTYPE, mtime=1100000000, link='run.sh')
        """
        let archive = root.sub("modes.tar")
        try python(script, [archive.path], in: root)
        let dest = root.sub("dest")
        _ = try await extractAll(archive, to: dest)
        let mask = probeUmask(in: root)

        let d = try #require(lstatOf(dest.sub("d")))
        #expect(d.st_mode & 0o777 == 0o750 & ~mask)
        #expect(d.st_mtimespec.tv_sec == 1_000_000_000)
        #expect(lstatOf(dest.sub("d/f.txt"))?.st_mtimespec.tv_sec == 1_050_000_000)
        let run = try #require(lstatOf(dest.sub("run.sh")))
        #expect(run.st_mode & 0o777 == 0o755 & ~mask)
        #expect(run.st_mtimespec.tv_sec == 1_100_000_000)
        #expect(lstatOf(dest.sub("private.txt")).map { $0.st_mode & 0o777 } == 0o600 & ~mask)
        #expect(lstatOf(dest.sub("zero.txt")).map { $0.st_mode & 0o777 } == 0o644 & ~mask)
        let ln = try #require(lstatOf(dest.sub("ln")))
        #expect(ln.st_mode & S_IFMT == S_IFLNK && ln.st_mtimespec.tv_sec == 1_200_000_000)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: dest.sub("ln").path)) == "run.sh")
        #expect(lstatOf(dest.sub("hard"))?.st_ino == run.st_ino)
        #expect(read(dest.sub("hard")) == Data("#!/bin/sh".utf8))
    }
}

/// Overwriting replaces a symlink at the target instead of writing through it,
/// and a file standing where the archive has a folder.
@Test func extractionOverwriteReplacesLinksAndFiles() async throws {
    try await withSandbox { root in
        let outside = root.sub("outside.txt")
        try write(outside, "keep")
        let dest = root.sub("dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: dest.sub("a.txt").path, withDestinationPath: outside.path)
        try write(dest.sub("d"), "a file where a folder comes")

        let src = root.sub("src")
        try write(src.sub("a.txt"), "new")
        try write(src.sub("d/in.txt"), "in")
        let archive = root.sub("o.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [
            .init(file: src.sub("a.txt"), path: "a.txt"),
            .init(file: src.sub("d"), path: "d"),
        ], progress: noProgress)

        _ = try await extractAll(archive, to: dest, overwrite: true)
        #expect(read(outside) == Data("keep".utf8))
        #expect(lstatOf(dest.sub("a.txt")).map { $0.st_mode & S_IFMT } == S_IFREG)
        #expect(read(dest.sub("a.txt")) == Data("new".utf8))
        #expect(read(dest.sub("d/in.txt")) == Data("in".utf8))
    }
}

/// Files that other threads create while archives are extracted keep their normal mode
/// (libarchive's disk writer set the process umask to 0 for a moment).
@Test func extractionLeavesTheUmaskAlone() async throws {
    try await withSandbox { root in
        let src = root.sub("src")
        try write(src.sub("x.txt"), "x")
        let archive = root.sub("u.zip")
        try await ArchiveWriter.create(archive, format: .zip, adding: [.init(file: src.sub("x.txt"), path: "x.txt")], progress: noProgress)
        let probes = root.sub("probes")
        try FileManager.default.createDirectory(at: probes, withIntermediateDirectories: true)
        let expected = 0o666 & ~probeUmask(in: probes)

        // Threads create files while archives are extracted, until the extractions end.
        let done = Flag()
        let watchers = (0..<4).map { w in
            watchFileModes(probes.path + "/w\(w)", expected: expected, until: done)
        }
        for i in 0..<1_500 {
            _ = try await extractAll(archive, to: root.sub("out/\(i)"))
        }
        done.set()
        var wrong = 0
        for watcher in watchers { wrong += await watcher.value }
        #expect(wrong == 0)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}

/// Creates and removes `path` until `flag` is set; returns how many times the file
/// did not get the `expected` mode.
private func watchFileModes(_ path: String, expected: mode_t, until flag: Flag) -> Task<Int, Never> {
    Task.detached {
        var wrong = 0
        while !flag.isSet {
            for _ in 0..<64 {
                let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o666)
                guard fd >= 0 else { continue }
                var st = stat()
                fstat(fd, &st)
                if st.st_mode & 0o777 != expected { wrong += 1 }
                close(fd)
                unlink(path)
            }
        }
        return wrong
    }
}
