import Testing
import Foundation
import Darwin
import Synchronization
@testable import CommanderCore

// All file system work happens inside a UUID-named directory under
// FileManager.default.temporaryDirectory, removed when the test ends.

private func withSandbox(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("icmd-ops-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try await body(root)
}

private extension URL {
    func sub(_ name: String) -> URL { URL(fileURLWithPath: path + "/" + name) }
}

/// Writes bytes with the exact name given (no path normalization).
private func write(_ url: URL, _ text: String) throws {
    try write(url, Data(text.utf8))
}

private func write(_ url: URL, _ data: Data) throws {
    let fd = open(url.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
    guard fd >= 0 else { throw OperationError.io("open \(url.path)") }
    defer { close(fd) }
    let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
    guard n == data.count else { throw OperationError.io("write \(url.path)") }
}

private func mkdirs(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

private func read(_ url: URL) -> String? {
    (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
}

private func names(_ url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
}

private func tree(_ url: URL) -> [String] {
    ((try? FileManager.default.subpathsOfDirectory(atPath: url.path)) ?? []).sorted()
}

private func caught<T>(_ body: () async throws -> T) async -> OperationError? {
    do {
        _ = try await body()
        return nil
    } catch let e as OperationError {
        return e
    } catch {
        return .io("unexpected \(error)")
    }
}

private final class Recorder: Sendable {
    private let state = Mutex<[String]>([])
    func add(_ s: String) { state.withLock { $0.append(s) } }
    var all: [String] { state.withLock { $0 } }
}

private let noProgress: @Sendable (OperationProgress) -> Void = { _ in }
private let noConflict: @Sendable (Conflict) async -> ConflictResolution = { c in
    Issue.record("unexpected conflict for \(c.source.name)")
    return .cancel
}

private func copy(_ sources: [URL], to dest: URL, ops: FileOperations = FileOperations(), mask: String = "*.*",
                  conflict: @escaping @Sendable (Conflict) async -> ConflictResolution = noConflict) async throws -> TransferReport {
    try await ops.transfer(TransferRequest(kind: .copy, sources: sources, destinationDirectory: dest, nameMask: mask),
                           progress: noProgress, conflict: conflict)
}

private func move(_ sources: [URL], to dest: URL, ops: FileOperations = FileOperations(),
                  conflict: @escaping @Sendable (Conflict) async -> ConflictResolution = noConflict) async throws -> TransferReport {
    try await ops.transfer(TransferRequest(kind: .move, sources: sources, destinationDirectory: dest),
                           progress: noProgress, conflict: conflict)
}

@Suite struct OperationsTests {
    // 1
    @Test func copyOntoHardLinkIsSameFile() async throws {
        try await withSandbox { root in
            let a = root.sub("a"), b = root.sub("b")
            try mkdirs(a); try mkdirs(b)
            try write(a.sub("x.txt"), "content")
            #expect(link(a.sub("x.txt").path, b.sub("x.txt").path) == 0)

            let copyErr = await caught { try await copy([a.sub("x.txt")], to: b) }
            #expect(copyErr == .sameFile(a.sub("x.txt")))
            let moveErr = await caught { try await move([a.sub("x.txt")], to: b) }
            #expect(moveErr == .sameFile(a.sub("x.txt")))

            #expect(read(a.sub("x.txt")) == "content")
            #expect(read(b.sub("x.txt")) == "content")
            #expect(FileIdentity.of(a.sub("x.txt")) == FileIdentity.of(b.sub("x.txt")))
            let attrs = try FileManager.default.attributesOfItem(atPath: a.sub("x.txt").path)
            #expect((attrs[.referenceCount] as? Int) == 2)
            #expect(names(b) == ["x.txt"])
        }
    }

    // 2
    @Test func copyThroughAliasPathIsSameFile() async throws {
        try await withSandbox { root in
            let a = root.sub("a")
            try mkdirs(a)
            try write(a.sub("x"), "data")
            // Same folder spelled through a symlinked ancestor: /var ↔ /private/var
            // (the temp dir analogue of /tmp ↔ /private/tmp), and a local alias link.
            var aliases: [URL] = []
            let p = a.path
            let alt = p.hasPrefix("/private/") ? String(p.dropFirst("/private".count)) : "/private" + p
            if FileManager.default.fileExists(atPath: alt) { aliases.append(URL(fileURLWithPath: alt)) }
            try FileManager.default.createSymbolicLink(at: root.sub("alias"), withDestinationURL: a)
            aliases.append(root.sub("alias"))
            #expect(!aliases.isEmpty)

            for dest in aliases {
                let err = await caught { try await copy([a.sub("x")], to: dest) }
                #expect(err == .sameFile(a.sub("x")), "dest \(dest.path)")
                let err2 = await caught { try await move([a.sub("x")], to: dest) }
                #expect(err2 == .sameFile(a.sub("x")))
            }
            #expect(read(a.sub("x")) == "data")
            #expect(names(a) == ["x"])
        }
    }

    // 3
    @Test func folderIntoItselfIsRefused() async throws {
        try await withSandbox { root in
            let src = root.sub("src")
            try mkdirs(src.sub("sub/deeper"))
            try write(src.sub("f.txt"), "f")
            try write(src.sub("sub/g.txt"), "g")
            try FileManager.default.createSymbolicLink(at: root.sub("alias"), withDestinationURL: src.sub("sub"))
            let before = tree(root)

            for dest in [src, src.sub("sub"), src.sub("sub/deeper"), root.sub("alias")] {
                let c = await caught { try await copy([src], to: dest) }
                #expect(c == .intoItself(src), "copy into \(dest.path)")
                let m = await caught { try await move([src], to: dest) }
                #expect(m == .intoItself(src), "move into \(dest.path)")
                let f = await caught { try await move([src], to: dest, ops: FileOperations(options: .init(forceCopyMove: true))) }
                #expect(f == .intoItself(src))
            }
            #expect(tree(root) == before)
        }
    }

    // 4
    @Test func cancelDuringOverwriteKeepsOriginal() async throws {
        try await withSandbox { root in
            let src = root.sub("src"), dst = root.sub("dst")
            try mkdirs(src); try mkdirs(dst)
            let size = 64 << 20
            try write(src.sub("big.bin"), Data(repeating: 0x42, count: size))
            try write(dst.sub("big.bin"), "original")

            let ops = FileOperations(options: .init(cloneAllowed: false))
            let seen = Recorder()
            let request = TransferRequest(kind: .copy, sources: [src.sub("big.bin")], destinationDirectory: dst)
            let task = Task {
                try await ops.transfer(request, progress: { p in
                    if p.doneBytes > 0 && p.doneBytes < p.totalBytes {
                        seen.add("mid")
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                }, conflict: { _ in .overwrite })
            }
            let err = await caught { try await task.value }
            #expect(err == .cancelled)
            #expect(!seen.all.isEmpty, "progress must arrive mid-copy")
            #expect(read(dst.sub("big.bin")) == "original")
            #expect(names(dst) == ["big.bin"], "no .~icmd-* left behind")
            #expect((try? FileManager.default.attributesOfItem(atPath: src.sub("big.bin").path)[.size] as? Int) == size)
        }
    }

    // 5
    @Test func crossVolumeMoveWithDirectoryLinkKeepsSource() async throws {
        try await withSandbox { root in
            let outside = root.sub("outside"), src = root.sub("src"), dst = root.sub("dst")
            try mkdirs(outside); try mkdirs(src.sub("folder/inner")); try mkdirs(dst)
            try write(outside.sub("important.txt"), "keep me")
            try write(src.sub("folder/a.txt"), "a")
            try write(src.sub("folder/inner/b.txt"), "b")
            try FileManager.default.createSymbolicLink(at: src.sub("folder/link"), withDestinationURL: outside)

            let ops = FileOperations(options: .init(forceCopyMove: true))
            let report = try await move([src.sub("folder")], to: dst, ops: ops)

            #expect(read(outside.sub("important.txt")) == "keep me")
            #expect(names(outside) == ["important.txt"])
            #expect(report.keptSources == [src.sub("folder")])
            #expect(read(src.sub("folder/a.txt")) == "a")
            #expect(read(src.sub("folder/inner/b.txt")) == "b")
            #expect(read(dst.sub("folder/a.txt")) == "a")
            #expect(read(dst.sub("folder/inner/b.txt")) == "b")
            let link = try FileManager.default.destinationOfSymbolicLink(atPath: dst.sub("folder/link").path)
            #expect(link == outside.path)
        }
    }

    @Test func crossVolumeMoveWithoutLinksDeletesSource() async throws {
        try await withSandbox { root in
            let src = root.sub("src"), dst = root.sub("dst")
            try mkdirs(src.sub("folder/inner")); try mkdirs(dst)
            try write(src.sub("folder/inner/b.txt"), "b")
            try FileManager.default.createSymbolicLink(atPath: src.sub("folder/filelink").path, withDestinationPath: "inner/b.txt")
            let report = try await move([src.sub("folder")], to: dst, ops: FileOperations(options: .init(forceCopyMove: true)))
            #expect(report.keptSources.isEmpty)
            #expect(report.copied == 2)
            #expect(names(src).isEmpty)
            #expect(read(dst.sub("folder/filelink")) == "b")
        }
    }

    @Test func sameVolumeMoveRenames() async throws {
        try await withSandbox { root in
            let src = root.sub("src"), dst = root.sub("dst")
            try mkdirs(src.sub("folder")); try mkdirs(dst)
            try write(src.sub("folder/a.txt"), "a")
            let id = FileIdentity.of(src.sub("folder/a.txt"))
            let report = try await move([src.sub("folder")], to: dst)
            #expect(report.copied == 1)
            #expect(names(src).isEmpty)
            #expect(FileIdentity.of(dst.sub("folder/a.txt")) == id)
        }
    }

    // 6
    @Test func conflictSkipOverwriteRename() async throws {
        try await withSandbox { root in
            let src = root.sub("src"), dst = root.sub("dst")
            try mkdirs(src); try mkdirs(dst)
            for n in ["a.txt", "b.txt", "c.txt"] {
                try write(src.sub(n), "new " + n)
                try write(dst.sub(n), "old " + n)
            }
            let asked = Recorder()
            let report = try await copy(["a.txt", "b.txt", "c.txt"].map { src.sub($0) }, to: dst) { c in
                asked.add(c.source.name)
                #expect(c.destination.size == Int64(("old " + c.source.name).utf8.count))
                switch c.source.name {
                case "a.txt": return .skip
                case "b.txt": return .overwrite
                default: return .rename("c2.txt")
                }
            }
            #expect(asked.all == ["a.txt", "b.txt", "c.txt"])
            #expect(read(dst.sub("a.txt")) == "old a.txt")
            #expect(read(dst.sub("b.txt")) == "new b.txt")
            #expect(read(dst.sub("c.txt")) == "old c.txt")
            #expect(read(dst.sub("c2.txt")) == "new c.txt")
            #expect(report.copied == 2)
            #expect(report.skipped == [src.sub("a.txt")])
            #expect(names(dst) == ["a.txt", "b.txt", "c.txt", "c2.txt"])
        }
    }

    @Test func overwriteAllAndSkipAllPersist() async throws {
        try await withSandbox { root in
            let src = root.sub("src"), d1 = root.sub("d1"), d2 = root.sub("d2")
            try mkdirs(src); try mkdirs(d1); try mkdirs(d2)
            let files = ["1", "2", "3"]
            for n in files {
                try write(src.sub(n), "new")
                try write(d1.sub(n), "old")
                try write(d2.sub(n), "old")
            }
            let asked = Recorder()
            _ = try await copy(files.map { src.sub($0) }, to: d1) { _ in asked.add("o"); return .overwriteAll }
            #expect(asked.all.count == 1)
            #expect(files.allSatisfy { read(d1.sub($0)) == "new" })

            let asked2 = Recorder()
            let r = try await copy(files.map { src.sub($0) }, to: d2) { _ in asked2.add("s"); return .skipAll }
            #expect(asked2.all.count == 1)
            #expect(r.skipped.count == 3)
            #expect(files.allSatisfy { read(d2.sub($0)) == "old" })
        }
    }

    @Test func nameMaskOnCopy() async throws {
        try await withSandbox { root in
            let src = root.sub("src"), dst = root.sub("dst")
            try mkdirs(src.sub("dir")); try mkdirs(dst)
            try write(src.sub("x.txt"), "x")
            try write(src.sub("dir/y.txt"), "y")
            _ = try await copy([src.sub("x.txt"), src.sub("dir")], to: dst, mask: "*.bak")
            #expect(names(dst) == ["dir", "x.bak"])
            #expect(names(dst.sub("dir")) == ["y.bak"])
            #expect(read(dst.sub("x.bak")) == "x")
        }
    }

    @Test func nameMaskRules() {
        #expect(NameMask.apply("*.*", to: "a.txt") == "a.txt")
        #expect(NameMask.apply("*.bak", to: "a.txt") == "a.bak")
        #expect(NameMask.apply("*.bak", to: "noext") == "noext.bak")
        #expect(NameMask.apply("new_*.*", to: "a.txt") == "new_a.txt")
        #expect(NameMask.apply("*.*", to: "noext") == "noext")
        #expect(NameMask.apply("???.*", to: "abcdef.txt") == "abc.txt")
        #expect(NameMask.apply("*.bak", to: ".bashrc") == ".bashrc.bak")
        #expect(NameMask.apply("*", to: "a.b.c") == "a.b.c")
    }

    @Test func caseOnlyRename() async throws {
        try await withSandbox { root in
            try write(root.sub("a.txt"), "a")
            try write(root.sub("other.txt"), "o")
            let ops = FileOperations()
            let renamed = try await ops.rename(root.sub("a.txt"), to: "A.txt")
            #expect(renamed.lastPathComponent == "A.txt")
            #expect(names(root) == ["A.txt", "other.txt"])
            #expect(read(root.sub("A.txt")) == "a")

            let err = await caught { try await ops.rename(root.sub("A.txt"), to: "other.txt") }
            #expect(err == .alreadyExists(root.sub("other.txt")))
            #expect(read(root.sub("other.txt")) == "o")
            let bad = await caught { try await ops.rename(root.sub("A.txt"), to: "x/y") }
            #expect(bad == .invalidName("x/y"))
        }
    }

    // 7
    @Test func nfcAndNfdNamesConflict() async throws {
        try await withSandbox { root in
            let nfc = "\u{E9}.txt", nfd = "e\u{301}.txt"
            let src = root.sub("src"), dst = root.sub("dst")
            try mkdirs(src); try mkdirs(dst)
            try write(dst.sub(nfc), "old")
            try write(src.sub(nfd), "new")
            #expect(names(dst).count == 1)

            let asked = Recorder()
            _ = try await copy([src.sub(nfd)], to: dst) { _ in asked.add("c"); return .overwrite }
            #expect(asked.all.count == 1)
            #expect(names(dst).count == 1)
            #expect(read(dst.sub(nfc)) == "new")

            // Two sources whose names differ only in normalization land on one name.
            let s1 = root.sub("s1"), s2 = root.sub("s2"), d = root.sub("d")
            try mkdirs(s1); try mkdirs(s2); try mkdirs(d)
            try write(s1.sub(nfc), "1")
            try write(s2.sub(nfd), "2")
            let asked2 = Recorder()
            let r = try await copy([s1.sub(nfc), s2.sub(nfd)], to: d) { _ in asked2.add("c"); return .skip }
            #expect(asked2.all.count == 1)
            #expect(names(d).count == 1)
            #expect(r.skipped == [s2.sub(nfd)])
        }
    }

    @Test func directoryCopyKeepsSymlinksAndMerges() async throws {
        try await withSandbox { root in
            let src = root.sub("src"), dst = root.sub("dst"), outside = root.sub("outside")
            try mkdirs(src.sub("d/e")); try mkdirs(dst.sub("d")); try mkdirs(outside)
            try write(src.sub("d/e/f.txt"), "f")
            try write(dst.sub("d/existing.txt"), "keep")
            try FileManager.default.createSymbolicLink(at: src.sub("d/l"), withDestinationURL: outside)
            let report = try await copy([src.sub("d")], to: dst)
            #expect(report.copied == 2)
            #expect(names(dst.sub("d")) == ["e", "existing.txt", "l"])
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: dst.sub("d/l").path) == outside.path)
            #expect(read(dst.sub("d/e/f.txt")) == "f")
        }
    }

    @Test func validationHappensBeforeAnyWrite() async throws {
        try await withSandbox { root in
            let src = root.sub("src"), dst = root.sub("dst")
            try mkdirs(src.sub("dir")); try mkdirs(dst)
            try write(src.sub("ok.txt"), "ok")
            // Second source is invalid (into itself): nothing may be written for the first one.
            let err = await caught { try await copy([src.sub("ok.txt"), src.sub("dir")], to: src.sub("dir")) }
            #expect(err == .intoItself(src.sub("dir")))
            #expect(names(src.sub("dir")).isEmpty)
            let missing = await caught { try await copy([src.sub("ok.txt"), src.sub("nope")], to: dst) }
            #expect(missing == .path(.notFound))
            #expect(names(dst).isEmpty)
        }
    }

    @Test func makeFileCreatesOrReturnsExisting() async throws {
        try await withSandbox { root in
            let ops = FileOperations()
            let made = try await ops.makeFile(named: "a.txt", in: root)
            #expect(made.created && names(root) == ["a.txt"])
            try write(made.url, "keep")
            let again = try await ops.makeFile(named: "A.TXT", in: root)
            #expect(!again.created && again.url.lastPathComponent == "a.txt")
            #expect(read(made.url) == "keep")
            try mkdirs(root.sub("dir"))
            let dir = await caught { try await ops.makeFile(named: "dir", in: root) }
            #expect(dir != nil)
            let bad = await caught { try await ops.makeFile(named: "a/b", in: root) }
            #expect(bad != nil)
        }
    }

    @Test func makeDirectoryAndDelete() async throws {
        try await withSandbox { root in
            let ops = FileOperations()
            let made = try await ops.makeDirectory(named: "New", in: root)
            #expect(names(root) == ["New"])
            let dup = await caught { try await ops.makeDirectory(named: "new", in: root) }
            #expect(dup != nil)
            let bad = await caught { try await ops.makeDirectory(named: "..", in: root) }
            #expect(bad == .invalidName(".."))
            let long = await caught { try await ops.makeDirectory(named: String(repeating: "x", count: 256), in: root) }
            #expect(long == .path(.nameTooLong(String(repeating: "x", count: 256))))

            let outside = root.sub("outside")
            try mkdirs(outside)
            try write(outside.sub("keep.txt"), "k")
            try mkdirs(made.sub("deep/er"))
            try write(made.sub("deep/er/f"), "f")
            try FileManager.default.createSymbolicLink(at: made.sub("link"), withDestinationURL: outside)
            let steps = Recorder()
            try await ops.deletePermanently([made]) { p in steps.add("\(p.doneItems)/\(p.totalItems)") }
            #expect(names(root) == ["outside"])
            #expect(read(outside.sub("keep.txt")) == "k")
            #expect(steps.all.last == "5/5")
        }
    }
}
