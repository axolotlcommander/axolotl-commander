import Testing
import Foundation
import Darwin
import Synchronization
@testable import CommanderCore

// The server is the local /usr/libexec/sftp-server started in a UUID-named directory under
// FileManager.default.temporaryDirectory; every remote path points inside that directory,
// which is removed when the test ends. No ssh connection is ever made.

private let sftpServer = URL(fileURLWithPath: "/usr/libexec/sftp-server")
private let endpoint = RemoteEndpoint(proto: .sftp, host: "localhost")

private func withSandbox(_ body: (URL, String) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("icmd-sftp-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    guard let real = realpath(root.path, nil) else { throw POSIXError(.ENOENT) }
    defer { free(real) }
    try await body(root, String(cString: real))
}

/// Connects to sftp-server rooted in a fresh sandbox; `base` is the sandbox's real path.
private func withServer(_ body: (SFTPClient, URL, String) async throws -> Void) async throws {
    try await withSandbox { root, base in
        let client = try await SFTPClient.connect(
            endpoint: endpoint,
            transport: .local(executable: sftpServer, arguments: ["-d", base]),
            prompter: { _ in nil }
        )
        do {
            try await body(client, root, base)
        } catch {
            await client.close()
            throw error
        }
        await client.close()
    }
}

private func randomData(_ count: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    arc4random_buf(&bytes, count)
    return Data(bytes)
}

private func mtime(_ url: URL) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
}

private func setMtime(_ url: URL, _ date: Date) throws {
    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

/// Records progress values.
private final class ProgressLog: Sendable {
    let values = Mutex<[Int64]>([])
    func record(_ n: Int64) { values.withLock { $0.append(n) } }
    var all: [Int64] { values.withLock { $0 } }
}

/// Runs blocking code off the cooperative pool.
private func onThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { c in Thread { c.resume(returning: work()) }.start() }
}

private func connectFailure(_ script: String) async -> (any Error)? {
    do {
        let c = try await SFTPClient.connect(
            endpoint: endpoint,
            transport: .local(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script]),
            prompter: { _ in nil }
        )
        await c.close()
        return nil
    } catch {
        return error
    }
}

@Suite struct SFTPPacketTests {
    @Test func responsesRoundtrip() throws {
        let attrs = SFTPAttributes(size: 1 << 40, uid: 501, gid: 20, permissions: 0o100644, atime: 7, mtime: 1_600_000_000)
        let samples: [SFTPResponse] = [
            .version(3, extensions: ["posix-rename@openssh.com": Data("1".utf8), "limits@openssh.com": Data("1".utf8)]),
            .status(id: 9, code: SFTPStatus.noSuchFile, message: "No such file"),
            .handle(id: 1, Data([0, 1, 2, 255])),
            .data(id: 2, Data(repeating: 0xAB, count: 70000)),
            .name(id: 3, [
                SFTPName(filename: Data("žluť ✓".utf8), longname: Data("-rw-r--r--".utf8), attributes: attrs),
                SFTPName(filename: Data("x".utf8), longname: Data(), attributes: .none),
            ]),
            .attrs(id: 4, SFTPAttributes(permissions: 0o40755)),
            .extendedReply(id: 5, Data([1, 2, 3])),
        ]
        for sample in samples {
            let frame = sample.encoded()
            let length = frame.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            #expect(length == frame.count - 4)
            #expect(try SFTPResponse.decode(frame.dropFirst(4)) == sample)
        }
    }

    @Test func requestEncodingAndFraming() throws {
        let packet = SFTPEncoder.request(.open, id: 0x0102_0304) {
            $0.string("/a"); $0.u32(SFTPOpenFlags.read); $0.attributes(.none)
        }
        #expect(Array(packet) == [0, 0, 0, 19, 3, 1, 2, 3, 4, 0, 0, 0, 2, 0x2F, 0x61, 0, 0, 0, 1, 0, 0, 0, 0])

        let stream = SFTPResponse.handle(id: 1, Data("h".utf8)).encoded()
            + SFTPResponse.status(id: 2, code: 0, message: "ok").encoded()
        var framer = SFTPFramer()
        var frames: [Data] = []
        for byte in stream {
            frames += try withUnsafeBytes(of: byte) { try framer.feed($0) }
        }
        #expect(frames.count == 2)
        #expect(try SFTPResponse.decode(frames[1]) == .status(id: 2, code: 0, message: "ok"))

        var bad = SFTPFramer()
        #expect(throws: SFTPPacketError.self) { try Data("hello\n".utf8).withUnsafeBytes { try bad.feed($0) } }
        #expect(throws: SFTPPacketError.self) { try SFTPResponse.decode(Data([SFTPType.handle.rawValue, 0, 0])) }
    }
}

@Suite struct SSHCommandTests {
    @Test func argumentsWithAndWithoutPortAndUser() throws {
        let plain = try SSHCommand.arguments(endpoint: RemoteEndpoint(proto: .sftp, host: "example.org"))
        #expect(plain == SSHCommand.baseOptions + ["-s", "--", "example.org", "sftp"])
        #expect(!plain.contains("-p") && !plain.contains("-l"))

        let full = try SSHCommand.arguments(
            endpoint: RemoteEndpoint(proto: .sftp, host: "h.local", port: 2222, user: "tester"),
            extra: ["-v"]
        )
        #expect(full == SSHCommand.baseOptions + ["-p", "2222", "-l", "tester", "-v", "-s", "--", "h.local", "sftp"])
        #expect(full.contains("ForwardAgent=no") && full.contains("ConnectTimeout=20"))

        // Default port is dropped by RemoteEndpoint.
        let port22 = try SSHCommand.arguments(endpoint: RemoteEndpoint(proto: .sftp, host: "h", port: 22))
        #expect(!port22.contains("-p"))
        #expect(port22.suffix(4) == ["-s", "--", "h", "sftp"])
    }

    @Test func rejectsHostsAndUsersThatLookLikeOptions() {
        for host in ["-oProxyCommand=x", "a b", "", "a\tb", "a\nb"] {
            #expect(throws: RemoteError.invalidName(host)) {
                try SSHCommand.arguments(endpoint: RemoteEndpoint(proto: .sftp, host: host))
            }
        }
        #expect(throws: RemoteError.invalidName("-oX=y")) {
            try SSHCommand.arguments(endpoint: RemoteEndpoint(proto: .sftp, host: "h", user: "-oX=y"))
        }
        #expect(throws: RemoteError.invalidName("a\u{7}")) {
            try SSHCommand.arguments(endpoint: RemoteEndpoint(proto: .sftp, host: "h", user: "a\u{7}"))
        }
    }
}

@Suite struct AskpassTests {
    @Test func helperRoundtripIsByteExact() async throws {
        let password = "héslo ✓ žluť"
        let seen = ProgressLog() // reused as a call counter
        let server = try AskpassServer { prompt in
            seen.record(Int64(prompt.utf8.count))
            return prompt.hasPrefix("tester@") ? password : nil
        }
        defer { server.stop() }
        #expect(server.socketPath.utf8.count < 104)
        var st = stat()
        #expect(stat((server.socketPath as NSString).deletingLastPathComponent, &st) == 0 && st.st_mode & 0o777 == 0o700)

        let prompt = "tester@host's password: \nřádek 2"
        let (path, token) = (server.socketPath, server.token)
        let answer = await onThread { Askpass.helper(prompt: prompt, socketPath: path, token: token) }
        #expect(answer == password)
        #expect(Array(answer?.utf8 ?? "".utf8) == Array(password.utf8))
        #expect(seen.all == [Int64(prompt.utf8.count)])

        // Wrong token: the handler is not asked and the helper fails.
        let rejected = await onThread { Askpass.helper(prompt: "tester@x", socketPath: path, token: "deadbeef") }
        #expect(rejected == nil)
        #expect(seen.all.count == 1)

        // nil from the handler = cancel.
        let cancelled = await onThread { Askpass.helper(prompt: "other", socketPath: path, token: token) }
        #expect(cancelled == nil)
        #expect(seen.all.count == 2)
    }

    @Test func serverCleansUpItsDirectory() throws {
        let server = try AskpassServer { _ in "x" }
        let dir = (server.socketPath as NSString).deletingLastPathComponent
        #expect((dir as NSString).lastPathComponent.hasPrefix("icmd-ap-"))
        #expect(dir.hasPrefix(NSTemporaryDirectory()) || dir.hasPrefix("/tmp/"))
        #expect(FileManager.default.fileExists(atPath: server.socketPath))
        server.stop()
        // The cancel handler runs asynchronously on the server queue.
        for _ in 0..<200 where FileManager.default.fileExists(atPath: dir) { usleep(5000) }
        #expect(!FileManager.default.fileExists(atPath: dir))
        #expect(Askpass.helper(prompt: "p", socketPath: server.socketPath, token: server.token) == nil)
    }

    @Test func promptClassification() {
        let p = ConnectPrompts(endpoint: endpoint)
        #expect(p.classify("Enter passphrase for key '/k': ") == .passphrase(endpoint, message: "Enter passphrase for key '/k':"))
        #expect(p.classify("Are you sure you want to continue connecting (yes/no/[fingerprint])? ")
            == .hostKey(endpoint, message: "Are you sure you want to continue connecting (yes/no/[fingerprint])?"))
        #expect(p.classify("tester@h's password: ") == .password(endpoint, attempt: 1, message: "tester@h's password:"))
        #expect(p.classify("Password:") == .password(endpoint, attempt: 2, message: "Password:"))
        #expect(p.classify("Verification code: ") == .other(endpoint, message: "Verification code:"))
    }
}

@Suite struct SFTPClientTests {
    @Test func handshakeAndHome() async throws {
        try await withServer { client, _, base in
            #expect(await client.isConnected)
            let home = try await client.homeDirectory()
            #expect(home == base)
            #expect(await client.extensions["posix-rename@openssh.com"] != nil)
            #expect(await client.maxReadLength >= 32768)
        }
    }

    @Test func listing() async throws {
        try await withServer { client, root, base in
            let fm = FileManager.default
            try Data("hello".utf8).write(to: root.appendingPathComponent("file.txt"))
            try Data().write(to: root.appendingPathComponent(".hidden"))
            try Data("x".utf8).write(to: root.appendingPathComponent("a b.txt"))
            try Data("kůň".utf8).write(to: root.appendingPathComponent("žluťoučký kůň.txt"))
            try fm.createDirectory(at: root.appendingPathComponent("dir"), withIntermediateDirectories: false)
            try fm.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "dir")
            try fm.createSymbolicLink(atPath: root.appendingPathComponent("dangling").path, withDestinationPath: "nowhere")
            let date = Date(timeIntervalSince1970: 1_500_000_000)
            try setMtime(root.appendingPathComponent("file.txt"), date)

            let entries = try await client.list(base)
            let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })
            #expect(Set(byName.keys) == ["file.txt", ".hidden", "a b.txt", "žluťoučký kůň.txt", "dir", "link", "dangling"])
            let file = try #require(byName["file.txt"])
            #expect(file.kind == .file && file.size == 5 && file.modificationDate == date)
            #expect(file.permissions != nil)
            #expect(byName["žluťoučký kůň.txt"]?.size == Int64("kůň".utf8.count))
            let dir = try #require(byName["dir"])
            #expect(dir.kind == .directory && dir.size == nil && dir.isDirectoryLike)
            let link = try #require(byName["link"])
            #expect(link.kind == .symlink && link.targetIsDirectory && link.isDirectoryLike && link.linkTarget == "dir")
            let dangling = try #require(byName["dangling"])
            #expect(dangling.kind == .symlink && !dangling.targetIsDirectory && dangling.linkTarget == "nowhere")

            #expect(try await client.list(base + "/dir").isEmpty)
            #expect(try await client.list(base + "/link").isEmpty)
            await #expect(throws: RemoteError.notFound(base + "/missing")) { try await client.list(base + "/missing") }
        }
    }

    @Test func info() async throws {
        try await withServer { client, root, base in
            #expect(try await client.info(base + "/missing") == nil)
            try Data("abc".utf8).write(to: root.appendingPathComponent("f"))
            let f = try #require(try await client.info(base + "/f"))
            #expect(f.name == "f" && f.kind == .file && f.size == 3)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("d"), withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("l").path, withDestinationPath: "d")
            let l = try #require(try await client.info(base + "/l"))
            #expect(l.kind == .symlink && l.targetIsDirectory)
        }
    }

    @Test(arguments: [0, 1000, 3 * 1024 * 1024 + 17])
    func uploadDownloadRoundtrip(size: Int) async throws {
        try await withServer { client, root, base in
            let fm = FileManager.default
            let local = root.appendingPathComponent("local", isDirectory: true)
            try fm.createDirectory(at: local, withIntermediateDirectories: false)
            let source = local.appendingPathComponent("source.bin")
            let back = local.appendingPathComponent("back.bin")
            let data = randomData(size)
            try data.write(to: source)
            chmod(source.path, 0o640)
            let date = Date(timeIntervalSince1970: 1_600_000_000)
            try setMtime(source, date)

            let up = ProgressLog()
            try await client.upload(source, to: base + "/remote.bin") { up.record($0) }
            #expect(up.all.last == Int64(size))
            #expect(up.all == up.all.sorted())

            let remote = try #require(try await client.info(base + "/remote.bin"))
            #expect(remote.size == Int64(size))
            #expect(remote.modificationDate == date)
            #expect(remote.permissions == 0o640)
            #expect(fm.contents(atPath: root.appendingPathComponent("remote.bin").path) == data)

            let down = ProgressLog()
            try await client.download(base + "/remote.bin", to: back) { down.record($0) }
            #expect(down.all.last == Int64(size))
            #expect(down.all == down.all.sorted())
            #expect(fm.contents(atPath: back.path) == data)
            #expect(mtime(back) == date)
        }
    }

    @Test func directoryOperations() async throws {
        try await withServer { client, root, base in
            try await client.makeDirectory(base + "/new dir")
            #expect(try await client.info(base + "/new dir")?.kind == .directory)
            await #expect(throws: RemoteError.alreadyExists(base + "/new dir")) {
                try await client.makeDirectory(base + "/new dir")
            }
            try Data("1".utf8).write(to: root.appendingPathComponent("a"))
            try Data("2".utf8).write(to: root.appendingPathComponent("b"))
            await #expect(throws: RemoteError.alreadyExists(base + "/b")) { try await client.rename(base + "/a", to: base + "/b") }
            try await client.rename(base + "/a", to: base + "/new dir/č")
            #expect(FileManager.default.contents(atPath: root.path + "/new dir/č") == Data("1".utf8))
            await #expect(throws: RemoteError.notFound(base + "/a")) { try await client.rename(base + "/a", to: base + "/c") }

            await #expect(throws: RemoteError.self) { try await client.removeDirectory(base + "/new dir") }
            try await client.removeFile(base + "/new dir/č")
            try await client.removeDirectory(base + "/new dir")
            try await client.removeFile(base + "/b")
            #expect(try await client.list(base).isEmpty)
            await #expect(throws: RemoteError.notFound(base + "/b")) { try await client.removeFile(base + "/b") }
        }
    }

    @Test func missingDownloadIsNotFound() async throws {
        try await withServer { client, root, base in
            let local = root.appendingPathComponent("out.bin")
            await #expect(throws: RemoteError.notFound(base + "/nope")) {
                try await client.download(base + "/nope", to: local) { _ in }
            }
            #expect(!FileManager.default.fileExists(atPath: local.path))
            let small = root.appendingPathComponent("small")
            try Data("s".utf8).write(to: small)
            await #expect(throws: RemoteError.notFound(base + "/no/such/dir/x")) {
                try await client.upload(small, to: base + "/no/such/dir/x") { _ in }
            }
        }
    }

    @Test func permissionDenied() async throws {
        try await withServer { client, root, base in
            let locked = root.appendingPathComponent("locked")
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
            try Data("s".utf8).write(to: locked.appendingPathComponent("secret"))
            chmod(locked.path, 0o000)
            defer { chmod(locked.path, 0o755) }
            await #expect(throws: RemoteError.permissionDenied(base + "/locked")) { try await client.list(base + "/locked") }
            await #expect(throws: RemoteError.permissionDenied(base + "/locked/secret")) {
                try await client.download(base + "/locked/secret", to: root.appendingPathComponent("s")) { _ in }
            }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("s").path))
        }
    }

    @Test func cancellingDownloadRemovesPartialFile() async throws {
        final class TaskBox: Sendable { let task = Mutex<Task<Void, any Error>?>(nil) }
        try await withServer { client, root, base in
            try randomData(30 * 1024 * 1024).write(to: root.appendingPathComponent("big.bin"))
            let local = root.appendingPathComponent("partial.bin")
            let box = TaskBox()
            let task = Task {
                try await client.download(base + "/big.bin", to: local) { _ in
                    for _ in 0..<400 {
                        if let t = box.task.withLock({ $0 }) {
                            t.cancel()
                            return
                        }
                        usleep(5000)
                    }
                }
            }
            box.task.withLock { $0 = task }
            await #expect(throws: RemoteError.cancelled) { try await task.value }
            #expect(!FileManager.default.fileExists(atPath: local.path))
            // The session survives a cancelled transfer.
            #expect(try await client.info(base + "/big.bin")?.size == 30 * 1024 * 1024)
        }
    }

    @Test func closeDisconnects() async throws {
        try await withServer { client, _, base in
            await client.close()
            #expect(await !client.isConnected)
            await #expect(throws: RemoteError.disconnected) { try await client.list(base) }
            await #expect(throws: RemoteError.disconnected) { try await client.homeDirectory() }
        }
    }

    @Test func killedServerDisconnects() async throws {
        try await withServer { client, _, base in
            #expect(kill(client.processIdentifier, SIGKILL) == 0)
            for _ in 0..<500 {
                if await !client.isConnected { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(await !client.isConnected)
            await #expect(throws: RemoteError.disconnected) { try await client.info(base) }
        }
    }

    @Test func setupFailuresAreMapped() async {
        #expect(await connectFailure("exit 3") as? RemoteError == .connectionFailed("sh exited with status 3"))
        #expect(await connectFailure("echo 'tester@h: Permission denied (publickey).' >&2; exit 255") as? RemoteError
            == .authenticationFailed)
        #expect(await connectFailure("echo 'Host key verification failed.' >&2; exit 255") as? RemoteError
            == .hostKeyRejected("Host key verification failed."))
        #expect(await connectFailure("echo 'ssh: Could not resolve hostname x' >&2; exit 255") as? RemoteError
            == .connectionFailed("ssh: Could not resolve hostname x"))
        #expect(await connectFailure("echo 'Welcome to my shell'; sleep 5") as? RemoteError
            == .connectionFailed("The server did not answer with the SFTP protocol"))
    }
}
