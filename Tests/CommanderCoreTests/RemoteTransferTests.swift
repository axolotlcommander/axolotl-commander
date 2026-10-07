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

    init(endpoint: RemoteEndpoint, root: URL) {
        self.endpoint = endpoint
        self.root = root.path
    }

    func failUploads(containing text: String?) { failUploadsContaining = text }

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
        let data = try Data(contentsOf: local)
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
        guard unlink(local(path)) == 0 else { throw RemoteError.notFound(path) }
    }

    func removeDirectory(_ path: String) async throws {
        guard rmdir(local(path)) == 0 else { throw RemoteError.server("not empty") }
    }

    func rename(_ from: String, to: String) async throws {
        guard renamex_np(local(from), local(to), UInt32(RENAME_EXCL)) == 0 else { throw RemoteError.alreadyExists(to) }
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
        await connections.configure(connector: { endpoint, _, _ in endpoint.host == "one" ? one : two },
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
