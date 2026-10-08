// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import Darwin
@testable import CommanderCore

/// A "server" whose files live in a local folder; remote "/x" is `root/x`.
actor DirectoryFileSystem: RemoteFileSystem {
    let endpoint: RemoteEndpoint
    let root: String
    var isConnected = true
    /// Uploads to a name containing this fail half-way.
    var failUploadsContaining: String?
    /// Uploads to a name containing this write half the data and then wait until cancelled.
    var hangUploadsContaining: String?
    /// `replace(_:over:)` swaps atomically (like posix-rename) instead of answering "can't".
    var atomicReplace = false
    /// Like a server whose listings follow links: a link to a folder is reported as a folder,
    /// and folders carry `uniqueID` (device and inode of what they are).
    var linksAsFolders = false
    /// Every changing call, in order: "upload P", "remove P", "rename A -> B", "replace A -> B".
    private(set) var log: [String] = []
    private var renameFailures: [(from: String?, to: String?, remaining: Int)] = []

    init(endpoint: RemoteEndpoint, root: URL) {
        self.endpoint = endpoint
        self.root = root.path
    }

    func failUploads(containing text: String?) { failUploadsContaining = text }
    func hangUploads(containing text: String?) { hangUploadsContaining = text }
    func setAtomicReplace(_ on: Bool) { atomicReplace = on }
    func setLinksAsFolders(_ on: Bool) { linksAsFolders = on }

    /// The next `times` renames whose source and target contain the given texts (nil = any) fail.
    func failRename(from: String? = nil, to: String? = nil, times: Int = 1) {
        renameFailures.append((from, to, times))
    }

    /// Log entries of one kind ("upload", "remove", "rename", "replace").
    func calls(_ kind: String) -> [String] { log.filter { $0.hasPrefix(kind + " ") } }

    private func local(_ path: String) -> String { root + RemotePath.normalize(path) }

    func homeDirectory() async throws -> String { "/" }

    func list(_ path: String) async throws -> [RemoteEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: local(path)) else { throw RemoteError.notFound(path) }
        var entries: [RemoteEntry] = []
        for name in names { if let entry = try await info(RemotePath.join(path, name)) { entries.append(entry) } }
        return entries
    }

    func info(_ path: String) async throws -> RemoteEntry? {
        var st = stat()
        guard lstat(local(path), &st) == 0 else { return nil }
        let kind: RemoteEntry.Kind = switch st.st_mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .file
        case S_IFLNK: .symlink
        default: .other
        }
        var target = stat()
        let targetIsDir = kind == .symlink && stat(local(path), &target) == 0 && target.st_mode & S_IFMT == S_IFDIR
        if linksAsFolders, kind == .directory || targetIsDir {
            let real = kind == .directory ? st : target
            return RemoteEntry(name: RemotePath.name(path), kind: .directory, uniqueID: "\(real.st_dev):\(real.st_ino)")
        }
        return RemoteEntry(name: RemotePath.name(path), kind: kind, size: Int64(st.st_size),
                           modificationDate: Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)),
                           targetIsDirectory: targetIsDir)
    }

    func download(_ path: String, to local: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        guard let data = FileManager.default.contents(atPath: self.local(path)) else { throw RemoteError.notFound(path) }
        try data.write(to: local)
        progress(Int64(data.count))
    }

    func upload(_ local: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        log.append("upload \(path)")
        let data = try Data(contentsOf: local)
        if let hang = hangUploadsContaining, path.contains(hang) {
            try data.prefix(data.count / 2).write(to: URL(filePath: self.local(path)))
            progress(Int64(data.count / 2))
            do { try await Task.sleep(for: .seconds(60)) } catch { throw RemoteError.cancelled }
        }
        if let fail = failUploadsContaining, path.contains(fail) {
            try data.prefix(data.count / 2).write(to: URL(filePath: self.local(path)))
            throw RemoteError.server("disk full")
        }
        try data.write(to: URL(filePath: self.local(path)))
        progress(Int64(data.count))
    }

    func makeDirectory(_ path: String) async throws {
        guard mkdir(local(path), 0o755) == 0 else { throw RemoteError.alreadyExists(path) }
    }

    func removeFile(_ path: String) async throws {
        log.append("remove \(path)")
        guard unlink(local(path)) == 0 else { throw RemoteError.notFound(path) }
    }

    func removeDirectory(_ path: String) async throws {
        guard rmdir(local(path)) == 0 else { throw RemoteError.server("not empty") }
    }

    func rename(_ from: String, to: String) async throws {
        log.append("rename \(from) -> \(to)")
        if let i = renameFailures.firstIndex(where: { f in
            f.remaining > 0 && (f.from.map { from.contains($0) } ?? true) && (f.to.map { to.contains($0) } ?? true)
        }) {
            renameFailures[i].remaining -= 1
            throw RemoteError.server("rename refused")
        }
        guard renamex_np(local(from), local(to), UInt32(RENAME_EXCL)) == 0 else { throw RemoteError.alreadyExists(to) }
    }

    func replace(_ from: String, over to: String) async throws -> Bool {
        guard atomicReplace else { return false }
        log.append("replace \(from) -> \(to)")
        guard Darwin.rename(local(from), local(to)) == 0 else { throw RemoteError.server("replace failed") }
        return true
    }

    func close() async { isConnected = false }
}

private struct Sandbox {
    let root: URL
    let local: URL
    let server: URL
    let server2: URL
    let scratch: URL
    let connections = RemoteConnections()
    let endpoint = RemoteEndpoint(proto: .sftp, host: "one")
    let endpoint2 = RemoteEndpoint(proto: .ftp, host: "two")
    var transfer: RemoteTransfer { RemoteTransfer(connections: connections) }

    init() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "icmd-remote-\(UUID().uuidString)").resolvingSymlinksInPath()
        local = root.appending(path: "local")
        server = root.appending(path: "server")
        server2 = root.appending(path: "server2")
        scratch = root.appending(path: "scratch")
        for dir in [local, server, server2, scratch] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let one = DirectoryFileSystem(endpoint: endpoint, root: server)
        let two = DirectoryFileSystem(endpoint: endpoint2, root: server2)
        connections.configure(connector: { endpoint, _, _ in endpoint.host == "one" ? one : two },
                                    prompter: { _ in nil }, passwords: MemoryPasswordStore())
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func write(_ text: String, _ path: String, in base: URL) throws {
        let url = base.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ path: String, in base: URL) -> String? {
        FileManager.default.contents(atPath: base.appending(path: path).path).map { String(decoding: $0, as: UTF8.self) }
    }

    func names(_ base: URL) -> [String] {
        (FileManager.default.subpaths(atPath: base.path) ?? []).sorted()
    }

    func at(_ path: String, _ endpoint: RemoteEndpoint? = nil) -> RemoteLocation {
        RemoteLocation(endpoint: endpoint ?? self.endpoint, path: path)
    }
}

private let noConflict: RemoteTransfer.ConflictHandler = { _ in
    Issue.record("unexpected conflict")
    return .cancel
}

@Suite struct RemoteTransferTests {
    @Test func uploadCopiesTreeAndSkipsFolderLinks() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("a", "dir/a.txt", in: s.local)
        try s.write("žluť", "dir/sub/kůň.txt", in: s.local)
        try s.write("outside", "elsewhere/x", in: s.root)
        try FileManager.default.createSymbolicLink(atPath: s.local.appending(path: "dir/linkdir").path,
                                                   withDestinationPath: s.root.appending(path: "elsewhere").path)
        try FileManager.default.createSymbolicLink(atPath: s.local.appending(path: "dir/linkfile").path,
                                                   withDestinationPath: "a.txt")
        let report = try await s.transfer.upload([s.local.appending(path: "dir")], to: s.at("/"), kind: .copy,
                                                 progress: { _ in }, conflict: noConflict)
        #expect(report.copied == 3)
        #expect(report.skipped.map(\.lastPathComponent) == ["linkdir"])
        #expect(s.names(s.server) == ["dir", "dir/a.txt", "dir/linkfile", "dir/sub", "dir/sub/kůň.txt"])
        #expect(s.read("dir/linkfile", in: s.server) == "a")
        #expect(s.read("dir/sub/kůň.txt", in: s.server) == "žluť")
    }

    @Test func uploadConflictsSkipAndOverwrite() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("new1", "one.txt", in: s.local)
        try s.write("new2", "two.txt", in: s.local)
        try s.write("old1", "one.txt", in: s.server)
        try s.write("old2", "two.txt", in: s.server)
        let asked = PromptLog<String>()
        let answers = PromptLog<ConflictResolution>([.skip, .overwrite])
        _ = try await s.transfer.upload([s.local.appending(path: "one.txt"), s.local.appending(path: "two.txt")],
                                        to: s.at("/"), kind: .copy, progress: { _ in }, conflict: { c in
            asked.append(c.destination.name)
            return answers.popFirst() ?? .cancel
        })
        #expect(asked.all == ["one.txt", "two.txt"])
        #expect(s.read("one.txt", in: s.server) == "old1")
        #expect(s.read("two.txt", in: s.server) == "new2")
        #expect(s.names(s.server) == ["one.txt", "two.txt"])
    }

    @Test func uploadMoveRemovesOnlyWhatArrived() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("a", "dir/a.txt", in: s.local)
        try s.write("b", "dir/fail.txt", in: s.local)
        try s.write("c", "plain/c.txt", in: s.local)
        let one = try #require(try await s.connections.session(for: s.endpoint) as? DirectoryFileSystem)
        await one.failUploads(containing: "fail")
        await #expect(throws: RemoteError.server("disk full")) {
            _ = try await s.transfer.upload([s.local.appending(path: "plain"), s.local.appending(path: "dir")], to: s.at("/"),
                                            kind: .move, progress: { _ in }, conflict: noConflict)
        }
        // "plain" went completely; in "dir" only a.txt arrived, fail.txt and the folder stay.
        #expect(s.names(s.local) == ["dir", "dir/fail.txt"])
        #expect(s.names(s.server) == ["dir", "dir/a.txt", "plain", "plain/c.txt"])
    }

    @Test func uploadMoveKeepsFolderWithLink() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("a", "dir/a.txt", in: s.local)
        try s.write("x", "elsewhere/x", in: s.root)
        try FileManager.default.createSymbolicLink(atPath: s.local.appending(path: "dir/link").path,
                                                   withDestinationPath: s.root.appending(path: "elsewhere").path)
        let report = try await s.transfer.upload([s.local.appending(path: "dir")], to: s.at("/"), kind: .move,
                                                 progress: { _ in }, conflict: noConflict)
        #expect(report.keptSources.map(\.lastPathComponent).contains("dir"))
        #expect(s.names(s.local) == ["dir", "dir/link"])
        #expect(s.read("elsewhere/x", in: s.root) == "x")
    }

    @Test func downloadMoveAndCaseConflict() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("A", "d/A.txt", in: s.server)
        try s.write("b", "d/b.txt", in: s.server)
        try s.write("old", "d/a.txt", in: s.local)
        let conflicts = PromptLog<String>()
        let report = try await s.transfer.download([s.at("/d")], to: s.local, kind: .move, progress: { _ in }, conflict: { c in
            conflicts.append(c.source.name)
            return .skip
        })
        if NameRules.forVolume(containing: s.local).same("A", "a") {
            // "A.txt" collides with the local "a.txt": skipped, so it and its folder stay on the server.
            #expect(conflicts.all == ["A.txt"])
            #expect(report.copied == 1)
            #expect(s.names(s.server) == ["d", "d/A.txt"])
            #expect(s.read("d/a.txt", in: s.local) == "old")
        } else {
            #expect(conflicts.all.isEmpty)
            #expect(s.names(s.server).isEmpty)
        }
        #expect(s.read("d/b.txt", in: s.local) == "b")
    }

    @Test func deleteRemovesLinksNotTargets() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("keep", "elsewhere/keep.txt", in: s.root)
        try s.write("x", "d/sub/x", in: s.server)
        try FileManager.default.createSymbolicLink(atPath: s.server.appending(path: "d/link").path,
                                                   withDestinationPath: s.root.appending(path: "elsewhere").path)
        try await s.transfer.delete([s.at("/d")], progress: { _ in })
        #expect(s.names(s.server).isEmpty)
        #expect(s.read("elsewhere/keep.txt", in: s.root) == "keep")
    }

    /// A server that lists a link back up as a folder with the same `uniqueID`: walks stop there.
    @Test func linkBackUpListedAsFolderDoesNotLoop() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("x", "d/sub/x", in: s.server)
        try FileManager.default.createSymbolicLink(atPath: s.server.appending(path: "d/sub/up").path, withDestinationPath: "..")
        let fs = try #require(try await s.connections.session(for: s.endpoint) as? DirectoryFileSystem)
        await fs.setLinksAsFolders(true)
        #expect(try await s.connections.totalSize(of: s.at("/d")) == 1)
        let report = try await s.transfer.download([s.at("/d")], to: s.local, kind: .copy, progress: { _ in },
                                                   conflict: noConflict)
        #expect(report.skipped.map(\.lastPathComponent) == ["up"])
        #expect(s.names(s.local) == ["d", "d/sub", "d/sub/x"])
        try await s.transfer.delete([s.at("/d")], progress: { _ in })
        #expect(s.names(s.server).isEmpty)
    }

    @Test func serverToServer() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("a", "d/a.txt", in: s.server)
        try s.write("b", "b.txt", in: s.server)
        try await s.connections.session(for: s.endpoint).makeDirectory("/target")

        // Same server, move = rename.
        _ = try await s.transfer.transfer([s.at("/b.txt")], to: s.at("/target"), kind: .move, scratch: s.scratch,
                                          progress: { _ in }, conflict: noConflict)
        #expect(s.names(s.server) == ["d", "d/a.txt", "target", "target/b.txt"])

        // Other server, move = copy through scratch, then delete.
        let report = try await s.transfer.transfer([s.at("/d")], to: s.at("/", s.endpoint2), kind: .move, scratch: s.scratch,
                                                   progress: { _ in }, conflict: noConflict)
        #expect(report.keptSources.isEmpty)
        #expect(s.names(s.server2) == ["d", "d/a.txt"])
        #expect(s.names(s.server) == ["target", "target/b.txt"])
    }

    @Test func progressReachesTotal() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write(String(repeating: "x", count: 1000), "f1", in: s.local)
        try s.write("", "f2", in: s.local)
        let last = PromptLog<OperationProgress>()
        _ = try await s.transfer.upload([s.local.appending(path: "f1"), s.local.appending(path: "f2")], to: s.at("/"),
                                        kind: .copy, progress: { last.append($0) }, conflict: noConflict)
        let final = try #require(last.all.last)
        #expect(final.doneBytes == 1000 && final.totalBytes == 1000)
        #expect(final.doneItems == 2 && final.totalItems == 2)
    }
}

/// Overwriting on a server: at every moment a complete version exists under a known name (FR-001–004).
@Suite struct RemoteOverwriteTests {
    private let overwrite: RemoteTransfer.ConflictHandler = { _ in .overwrite }

    private func server(_ s: Sandbox) async throws -> DirectoryFileSystem {
        try #require(try await s.connections.session(for: s.endpoint) as? DirectoryFileSystem)
    }

    private func upload(_ s: Sandbox) async throws {
        _ = try await s.transfer.upload([s.local.appending(path: "one.txt")], to: s.at("/"), kind: .copy,
                                        progress: { _ in }, conflict: overwrite)
    }

    private func prepare() async throws -> Sandbox {
        let s = try await Sandbox()
        try s.write("new1", "one.txt", in: s.local)
        try s.write("old1", "one.txt", in: s.server)
        return s
    }

    @Test func atomicReplaceNeverRemovesTarget() async throws {
        let s = try await prepare()
        defer { s.remove() }
        let fs = try await server(s)
        await fs.setAtomicReplace(true)
        try await upload(s)
        #expect(s.read("one.txt", in: s.server) == "new1")
        #expect(s.names(s.server) == ["one.txt"])
        #expect(await fs.calls("remove").isEmpty)
        #expect(await fs.calls("replace").count == 1)
    }

    @Test func withoutAtomicReplaceOldVersionIsKeptAsideUntilNewIsInPlace() async throws {
        let s = try await prepare()
        defer { s.remove() }
        let fs = try await server(s)
        try await upload(s)
        #expect(s.read("one.txt", in: s.server) == "new1")
        #expect(s.names(s.server) == ["one.txt"])
        // The target is never removed; only the backup goes, after the new file took its name.
        let log = await fs.log
        #expect(!log.contains("remove /one.txt"))
        let toBackup = try #require(log.firstIndex { $0.hasPrefix("rename /one.txt -> /.one.txt.axo-old-") })
        let toFinal = try #require(log.firstIndex { $0.hasPrefix("rename /.one.txt.icmd-") && $0.hasSuffix("-> /one.txt") })
        let cleanup = try #require(log.firstIndex { $0.hasPrefix("remove /.one.txt.axo-old-") })
        #expect(toBackup < toFinal && toFinal < cleanup)
    }

    @Test func failedSwapRestoresOldVersion() async throws {
        let s = try await prepare()
        defer { s.remove() }
        let fs = try await server(s)
        await fs.failRename(from: ".icmd-", to: "/one.txt")
        await #expect(throws: RemoteError.server("rename refused")) { try await upload(s) }
        #expect(s.read("one.txt", in: s.server) == "old1")
        #expect(s.names(s.server) == ["one.txt"])  // neither temp nor backup left
        #expect(!(await fs.log).contains("remove /one.txt"))
    }

    @Test func failedSwapAndRestoreReportsWhereBothVersionsAre() async throws {
        let s = try await prepare()
        defer { s.remove() }
        let fs = try await server(s)
        await fs.failRename(from: ".icmd-", to: "/one.txt")
        await fs.failRename(from: ".axo-old-", to: "/one.txt")
        do {
            try await upload(s)
            Issue.record("expected replaceIncomplete")
        } catch RemoteError.replaceIncomplete(let target, let newAt, let oldAt) {
            #expect(target == "/one.txt")
            #expect(s.read(String(newAt.dropFirst()), in: s.server) == "new1")
            #expect(s.read(String(oldAt.dropFirst()), in: s.server) == "old1")
            #expect(s.names(s.server).count == 2)
        }
    }

    @Test func failedUploadLeavesTargetAndNoTemp() async throws {
        let s = try await prepare()
        defer { s.remove() }
        let fs = try await server(s)
        await fs.failUploads(containing: "one.txt")
        await #expect(throws: RemoteError.server("disk full")) { try await upload(s) }
        #expect(s.read("one.txt", in: s.server) == "old1")
        #expect(s.names(s.server) == ["one.txt"])
        #expect(await fs.calls("rename").isEmpty)
    }

    @Test func cancelledUploadLeavesTargetAndNoTemp() async throws {
        let s = try await prepare()
        defer { s.remove() }
        let fs = try await server(s)
        await fs.hangUploads(containing: "one.txt")
        let task = Task { try await upload(s) }
        for _ in 0..<500 where await fs.calls("upload").isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(s.read("one.txt", in: s.server) == "old1")
        #expect(s.names(s.server) == ["one.txt"])
    }

    @Test func moveOnServerReplacesWithoutRemovingTarget() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("A", "a.txt", in: s.server)
        try s.write("old", "target/a.txt", in: s.server)
        let fs = try await server(s)
        _ = try await s.transfer.transfer([s.at("/a.txt")], to: s.at("/target"), kind: .move, scratch: s.scratch,
                                          progress: { _ in }, conflict: overwrite)
        #expect(s.names(s.server) == ["target", "target/a.txt"])
        #expect(s.read("target/a.txt", in: s.server) == "A")
        #expect(!(await fs.log).contains("remove /target/a.txt"))
    }

    @Test func failedMoveOnServerKeepsBothFiles() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("A", "a.txt", in: s.server)
        try s.write("old", "target/a.txt", in: s.server)
        let fs = try await server(s)
        await fs.failRename(from: "/a.txt", to: "/target/a.txt")
        await #expect(throws: RemoteError.server("rename refused")) {
            _ = try await s.transfer.transfer([s.at("/a.txt")], to: s.at("/target"), kind: .move, scratch: s.scratch,
                                              progress: { _ in }, conflict: overwrite)
        }
        #expect(s.names(s.server) == ["a.txt", "target", "target/a.txt"])
        #expect(s.read("a.txt", in: s.server) == "A")
        #expect(s.read("target/a.txt", in: s.server) == "old")
    }

    @Test func atomicMoveOnServer() async throws {
        let s = try await Sandbox()
        defer { s.remove() }
        try s.write("A", "a.txt", in: s.server)
        try s.write("old", "target/a.txt", in: s.server)
        let fs = try await server(s)
        await fs.setAtomicReplace(true)
        _ = try await s.transfer.transfer([s.at("/a.txt")], to: s.at("/target"), kind: .move, scratch: s.scratch,
                                          progress: { _ in }, conflict: overwrite)
        #expect(s.names(s.server) == ["target", "target/a.txt"])
        #expect(s.read("target/a.txt", in: s.server) == "A")
        #expect(await fs.calls("remove").isEmpty)
    }
}
