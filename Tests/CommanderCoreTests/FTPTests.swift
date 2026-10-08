// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import Darwin
import Synchronization
@testable import CommanderCore

// Parser tests are pure. Integration tests run scripts/ftp-test-server.py on 127.0.0.1
// (ephemeral port), rooted in a UUID-named directory under temporaryDirectory that the
// test creates and removes. They return early when /usr/bin/python3 is not runnable.
// FTPS tests also need /usr/bin/openssl (self-signed certificate made in the sandbox) and
// return early without it; the implicit-TLS test also returns early when port 990 is busy.

// MARK: - Helpers

private let utc = TimeZone(identifier: "UTC")!

private func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = utc
    return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

private func listing(_ lines: [String]) -> Data { Data(lines.joined(separator: "\r\n").utf8) }

private let pythonRunnable: Bool = {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { return false }
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/python3")
    p.arguments = ["-I", "-c", "pass"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}()

private let serverScript = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("scripts/ftp-test-server.py")

private let user = "tester"
private let password = "héslo ✓ žluť"

private struct ServerFailed: Error {}

/// Server rooted in `root/srv`; returns the port.
private func startServer(root: URL, args: [String]) async throws -> (Process, Int) {
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/python3")
    p.arguments = ["-I", serverScript.path, "--root", root.path, "--user", user,
                   "--password-hex", password.utf8.map { String(format: "%02x", $0) }.joined(),
                   "--port", "0"] + args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    try p.run()
    var line = ""
    for try await l in out.fileHandleForReading.bytes.lines {
        line = l
        break
    }
    guard let port = Int(line.trimmingCharacters(in: .whitespaces)) else {
        p.terminate()
        throw ServerFailed()
    }
    return (p, port)
}

private enum TLSMode { case none, explicit, implicit }

/// Self-signed certificate for 127.0.0.1 (valid one day); false when openssl is unavailable.
private func makeCertificate(cert: URL, key: URL) -> Bool {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/openssl") else { return false }
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/openssl")
    p.arguments = ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=127.0.0.1",
                   "-days", "1", "-keyout", key.path, "-out", cert.path]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0 && FileManager.default.fileExists(atPath: cert.path)
        && FileManager.default.fileExists(atPath: key.path)
}

/// Sandbox with `srv/` (the server root) and `local/`; skipped (returns early) when python3 is
/// unavailable, when `tls` is requested without openssl, or when a fixed `port` cannot be bound.
private func withServer(
    _ args: [String] = [],
    tls: TLSMode = .none,
    port fixedPort: Int? = nil,
    _ body: (_ port: Int, _ srv: URL, _ local: URL) async throws -> Void
) async throws {
    guard pythonRunnable else { return }  // no python3: integration tests skipped
    let sandbox = FileManager.default.temporaryDirectory
        .appendingPathComponent("icmd-ftp-\(UUID().uuidString)", isDirectory: true)
    let srv = sandbox.appendingPathComponent("srv"), local = sandbox.appendingPathComponent("local")
    try FileManager.default.createDirectory(at: srv, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: sandbox) }
    var args = args
    if tls != .none {
        let cert = sandbox.appendingPathComponent("cert.pem"), key = sandbox.appendingPathComponent("key.pem")
        guard makeCertificate(cert: cert, key: key) else { return }
        args += ["--tls-cert", cert.path, "--tls-key", key.path]
        if tls == .implicit { args.append("--implicit-tls") }
    }
    if let fixedPort { args += ["--port", String(fixedPort)] }  // the last --port wins
    let process: Process, port: Int
    do {
        (process, port) = try await startServer(root: srv, args: args)
    } catch is ServerFailed where fixedPort != nil {
        return  // fixed port busy: skipped
    }
    do {
        try await body(port, srv, local)
    } catch {
        await stop(process)
        throw error
    }
    await stop(process)
}

/// Terminates the server and waits until it has exited. Polls `isRunning` instead of calling
/// `waitUntilExit()`, which spins the run loop of the calling thread and occasionally never
/// returned on a concurrency thread although the server had already exited. Bounded: after
/// 5 s the server is killed, and after 5 more s the wait gives up.
private func stop(_ process: Process) async {
    process.terminate()
    for attempt in 0..<2 {
        if attempt == 1 && process.isRunning { kill(process.processIdentifier, SIGKILL) }
        let deadline = ContinuousClock.now + .seconds(5)
        while process.isRunning && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if !process.isRunning { return }
    }
}

private func endpoint(_ port: Int, user: String? = user, proto: RemoteProtocol = .ftp) -> RemoteEndpoint {
    RemoteEndpoint(proto: proto, host: "127.0.0.1", port: port, user: user)
}

private let noPrompt: AuthPrompter = { _ in nil }

/// FTPS login to the self-signed test server (certificate verification off).
private func loginFTPS(_ port: Int) async throws -> FTPClient {
    try await FTPClient.connect(endpoint: endpoint(port, proto: .ftps), password: password, prompter: noPrompt,
                                options: FTPOptions(connectTimeout: 5, responseTimeout: 10, verifyTLS: false))
}

/// Login, listing and upload/download roundtrip (small and multi-chunk) over an FTPS server.
private func exerciseFTPS(port: Int, srv: URL, local: URL) async throws {
    try Data("hello".utf8).write(to: srv.appendingPathComponent("žluť.txt"))
    try FileManager.default.createDirectory(at: srv.appendingPathComponent("sub dir"),
                                            withIntermediateDirectories: true)
    let c = try await loginFTPS(port)
    #expect(await c.isConnected)
    #expect(try await c.homeDirectory() == "/")
    let root = try await c.list("/").sorted { $0.name < $1.name }
    #expect(root.map(\.name) == ["sub dir", "žluť.txt"])
    #expect(root.map(\.kind) == [.directory, .file])
    #expect(root[1].size == 5)
    #expect(try await c.info("/žluť.txt")?.size == 5)

    for (i, size) in [0, 1000, 3_000_000].enumerated() {
        let data = noise(size)
        let src = local.appendingPathComponent("src\(i)")
        try data.write(to: src)
        let remote = "/sub dir/up ž \(i).bin"
        try await c.upload(src, to: remote) { _ in }
        #expect(FileManager.default.contents(atPath: srv.appendingPathComponent("sub dir/up ž \(i).bin").path) == data)
        let dst = local.appendingPathComponent("dst\(i)")
        try await c.download(remote, to: dst) { _ in }
        #expect(FileManager.default.contents(atPath: dst.path) == data)
    }
    #expect(try await c.list("/sub dir").count == 3)
    await c.close()
}

private func login(_ port: Int, encoding: ServerEncoding = .auto) async throws -> FTPClient {
    try await FTPClient.connect(endpoint: endpoint(port), password: password, prompter: noPrompt,
                                options: FTPOptions(connectTimeout: 5, responseTimeout: 10, encoding: encoding))
}

private final class Recorder<T: Sendable>: Sendable {
    private let items = Mutex<[T]>([])
    func add(_ x: T) { items.withLock { $0.append(x) } }
    var all: [T] { items.withLock { $0 } }
}

private func expectRemote(_ expected: RemoteError, _ body: () async throws -> Void) async {
    do {
        try await body()
        Issue.record("expected \(expected)")
    } catch let e as RemoteError {
        #expect(e == expected)
    } catch {
        Issue.record("unexpected \(error)")
    }
}

/// Deterministic pseudo-random bytes.
private func noise(_ count: Int) -> Data {
    var state: UInt64 = 7
    var bytes = [UInt8](repeating: 0, count: count)
    for i in 0..<count {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        bytes[i] = UInt8(truncatingIfNeeded: state >> 33)
    }
    return Data(bytes)
}

// MARK: - Parser

@Suite struct FTPListParserTests {
    @Test func mlsd() {
        let data = listing([
            "type=cdir;modify=20240101000000; .",
            "type=pdir;modify=20240101000000; ..",
            "type=file;size=1234;modify=20240102101530;UNIX.mode=0644;perm=rwadf; report.txt",
            "Type=dir;sizd=4096;modify=20240102101530.250;unix.mode=755;perm=elcmf; sub dir",
            "type=OS.unix=symlink;size=7;modify=20240102101530; link",
            "type=OS.unix=slink:/etc/hosts;modify=20240102101530; hosts",
            "type=file;size=3; name; with; semicolons ",
            "type=OS.unix=chr-13/29; tty",
            "garbage",
        ])
        let e = FTPListParser.parseMLSD(data)
        #expect(e.map(\.name) == ["report.txt", "sub dir", "link", "hosts", "name; with; semicolons ", "tty"])
        #expect(e[0] == RemoteEntry(name: "report.txt", kind: .file, size: 1234,
                                    modificationDate: utcDate(2024, 1, 2, 10, 15, 30), permissions: 0o644))
        #expect(e[1].kind == .directory && e[1].size == nil && e[1].permissions == 0o755)
        #expect(e[1].modificationDate == utcDate(2024, 1, 2, 10, 15, 30).addingTimeInterval(0.25))
        #expect(e[2].kind == .symlink && e[2].linkTarget == nil && !e[2].targetIsDirectory)
        #expect(e[3].kind == .symlink && e[3].linkTarget == "/etc/hosts")
        #expect(e[4].size == 3)
        #expect(e[5].kind == .other)
    }

    @Test func namesWithSlashAreDropped() {
        // A recursive delete or move must never leave the selected tree through a listed name.
        let mlsd = FTPListParser.parseMLSD(listing([
            "type=file;size=1; x/../../etc",
            "type=dir; /abs",
            "type=file;size=1; ok.txt",
        ]))
        #expect(mlsd.map(\.name) == ["ok.txt"])
        let list = FTPListParser.parseLIST(listing([
            "-rw-r--r--    1 1000     1000            1 Jan  5 10:15 a/../b",
            "-rw-r--r--    1 1000     1000            1 Jan  5 10:15 fine",
        ]))
        #expect(list.map(\.name) == ["fine"])
        #expect(!RemoteEntry.isValidName("") && !RemoteEntry.isValidName("..") && !RemoteEntry.isValidName("a\0b"))
        #expect(RemoteEntry.isValidName("a b") && RemoteEntry.isValidName("..."))
    }

    @Test func unix() throws {
        let ref = utcDate(2024, 6, 15, 12)
        let data = listing([
            "total 24",
            "drwxr-xr-x    2 1000     1000         4096 Jan  5 10:15 .",
            "drwxr-xr-x    2 1000     1000         4096 Jan  5 10:15 ..",
            "drwxr-xr-x    2 1000     1000         4096 Jan  5 10:15 docs",
            "-rw-r--r--    1 owner    staff     1234567 Mar  5  2023 my file  name.txt",
            "lrwxrwxrwx    1 root     root            7 Jun 14 23:59 current -> releases/v 2",
            "-rwsr-x--T    1 root     wheel          10 Feb 29 08:00 suid",
            "crw-rw-rw-    1 root     root       1,   3 Jan  1  2020 null",
            "-rw-r--r--+   1 u g 5 2024-05-01 09:30 iso",
            "-rw-r--r-- 1 ftp 42 Jun 1 01:02 nogroup",
        ])
        let e = FTPListParser.parseLIST(data, referenceDate: ref, timeZone: utc)
        #expect(e.map(\.name) == ["docs", "my file  name.txt", "current", "suid", "null", "iso", "nogroup"])
        #expect(e[0] == RemoteEntry(name: "docs", kind: .directory,
                                    modificationDate: utcDate(2024, 1, 5, 10, 15), permissions: 0o755))
        #expect(e[1].kind == .file && e[1].size == 1_234_567 && e[1].modificationDate == utcDate(2023, 3, 5))
        #expect(e[1].permissions == 0o644)
        #expect(e[2].kind == .symlink && e[2].linkTarget == "releases/v 2" && e[2].permissions == 0o777)
        #expect(e[2].modificationDate == utcDate(2024, 6, 14, 23, 59))
        #expect(e[3].permissions == 0o5750)  // rws r-x --T
        #expect(e[4].kind == .other && e[4].size == nil)
        #expect(e[5].size == 5 && e[5].modificationDate == utcDate(2024, 5, 1, 9, 30))
        #expect(e[6].size == 42 && e[6].modificationDate == utcDate(2024, 6, 1, 1, 2))
    }

    @Test func unixYearRollover() {
        let ref = utcDate(2024, 1, 10, 12)
        func date(_ line: String) -> Date? {
            FTPListParser.parseLISTLine("-rw-r--r-- 1 o g 1 \(line) f", referenceDate: ref, timeZone: utc)?
                .modificationDate
        }
        #expect(date("Dec 31 23:59") == utcDate(2023, 12, 31, 23, 59))
        #expect(date("Jan 10 10:00") == utcDate(2024, 1, 10, 10))
        #expect(date("Jan 11 11:00") == utcDate(2024, 1, 11, 11))  // within a day ahead: clock skew
        #expect(date("Jan 12 13:00") == utcDate(2023, 1, 12, 13))
        let prague = TimeZone(identifier: "Europe/Prague")!
        let local = FTPListParser.parseLISTLine("-rw-r--r-- 1 o g 1 Jan 10 10:00 f", referenceDate: ref, timeZone: prague)
        #expect(local?.modificationDate == utcDate(2024, 1, 10, 9))
    }

    @Test func dos() {
        let data = listing([
            "01-02-24  10:15AM       <DIR>          Program Files",
            "12-31-99  12:05PM              1,234 old file.txt",
            "01-02-2024 22:15 1234 new.txt",
            "07-04-23  12:00AM                  0 midnight",
        ])
        let e = FTPListParser.parseLIST(data, referenceDate: utcDate(2024, 6, 1), timeZone: utc)
        #expect(e.map(\.name) == ["Program Files", "old file.txt", "new.txt", "midnight"])
        #expect(e[0].kind == .directory && e[0].modificationDate == utcDate(2024, 1, 2, 10, 15))
        #expect(e[1].kind == .file && e[1].size == 1234 && e[1].modificationDate == utcDate(1999, 12, 31, 12, 5))
        #expect(e[2].size == 1234 && e[2].modificationDate == utcDate(2024, 1, 2, 22, 15))
        #expect(e[3].size == 0 && e[3].modificationDate == utcDate(2023, 7, 4, 0, 0))
    }

    @Test func namesDecoding() {
        var bytes = Data("-rw-r--r-- 1 o g 1 Jan  1  2020 caf".utf8)
        bytes.append(0xE9)  // Latin-1 "é", invalid UTF-8
        bytes.append(contentsOf: Array("\r\n-rw-r--r-- 1 o g 1 Jan  1  2020 žluť\n".utf8))
        let e = FTPListParser.parseLIST(bytes, timeZone: utc)
        #expect(e.map(\.name) == ["café", "žluť"])
        #expect(FTPListParser.parseLIST(Data("total 0\r\n\r\nnonsense line here\n".utf8)).isEmpty)
    }
}

// MARK: - Client against the test server

@Suite struct FTPClientTests {
    @Test func loginHomeAndList() async throws {
        try await withServer { port, srv, _ in
            try Data("hello".utf8).write(to: srv.appendingPathComponent("žluťoučký kůň.txt"))
            try Data().write(to: srv.appendingPathComponent(".hidden"))
            try FileManager.default.createDirectory(at: srv.appendingPathComponent("sub dir/inner"),
                                                    withIntermediateDirectories: true)
            try Data(count: 10).write(to: srv.appendingPathComponent("sub dir/a;b #1%.bin"))

            let c = try await login(port)
            #expect(await c.isConnected)
            #expect(try await c.homeDirectory() == "/")
            let root = try await c.list("/").sorted { $0.name < $1.name }
            #expect(root.map(\.name) == [".hidden", "sub dir", "žluťoučký kůň.txt"])
            #expect(root.map(\.kind) == [.file, .directory, .file])
            #expect(root[2].size == 5 && root[2].modificationDate != nil && root[2].permissions != nil)
            let sub = try await c.list("/sub dir").sorted { $0.name < $1.name }
            #expect(sub.map(\.name) == ["a;b #1%.bin", "inner"])
            #expect(sub[0].size == 10)
            #expect(try await c.list("/sub dir/inner").isEmpty)

            #expect(try await c.info("/")?.kind == .directory)
            #expect(try await c.info("/sub dir/a;b #1%.bin")?.size == 10)
            #expect(try await c.info("/missing.txt") == nil)
            #expect(try await c.info("/no/such/dir/x") == nil)
            await expectRemote(.notFound("/missing")) { _ = try await c.list("/missing") }
            await expectRemote(.invalidName("/a\r\nDELE x")) { _ = try await c.list("/a\r\nDELE x") }
            await c.close()
        }
    }

    @Test func passwordPrompts() async throws {
        try await withServer { port, _, _ in
            let asked = Recorder<AuthPrompt>()
            let c = try await FTPClient.connect(endpoint: endpoint(port), password: "wrong", prompter: { p in
                asked.add(p)
                return password
            })
            #expect(asked.all.count == 1)
            if case .password(_, let attempt, _) = asked.all.first { #expect(attempt == 2) } else { Issue.record("no prompt") }
            #expect(try await c.list("/").isEmpty)
            await c.close()

            let asked2 = Recorder<Int>()
            let c2 = try await FTPClient.connect(endpoint: endpoint(port), password: nil, prompter: { p in
                if case .password(_, let attempt, _) = p { asked2.add(attempt) }
                return password
            })
            #expect(asked2.all == [1])
            await c2.close()

            await expectRemote(.cancelled) {
                _ = try await FTPClient.connect(endpoint: endpoint(port), password: "nope", prompter: noPrompt)
            }
            await expectRemote(.authenticationFailed) {
                _ = try await FTPClient.connect(endpoint: endpoint(port, user: nil), password: nil, prompter: noPrompt)
            }
        }
    }

    @Test func anonymousAllowed() async throws {
        try await withServer(["--anonymous"]) { port, _, _ in
            let c = try await FTPClient.connect(endpoint: endpoint(port, user: nil), password: nil, prompter: noPrompt)
            #expect(try await c.homeDirectory() == "/")
            await c.close()
        }
    }

    @Test func connectionFailures() async throws {
        try await withServer { port, _, _ in
            // The test server has no TLS: AUTH TLS is refused, so FTPS must not fall back to plain.
            do {
                _ = try await FTPClient.connect(endpoint: endpoint(port, proto: .ftps), password: password,
                                                prompter: noPrompt)
                Issue.record("FTPS connected without TLS")
            } catch let RemoteError.connectionFailed(message) {
                #expect(!message.isEmpty)
            }
        }
        // Nothing listens on a fresh closed port.
        let s = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = bind(s, $0, len)
                return getsockname(s, $0, &len)
            }
        }
        let closedPort = Int(UInt16(bigEndian: addr.sin_port))
        Darwin.close(s)
        do {
            _ = try await FTPClient.connect(endpoint: endpoint(closedPort), password: password, prompter: noPrompt)
            Issue.record("connected to a closed port")
        } catch let RemoteError.connectionFailed(message) {
            #expect(!message.isEmpty)
        }
    }

    @Test func uploadDownloadRoundtrip() async throws {
        try await withServer { port, srv, local in
            let c = try await login(port)
            for (i, size) in [0, 1000, 3_000_000].enumerated() {
                let data = noise(size)
                let src = local.appendingPathComponent("src\(i)")
                try data.write(to: src)
                let remote = "/up ž \(i).bin"
                let up = Recorder<Int64>()
                try await c.upload(src, to: remote) { up.add($0) }
                #expect(up.all == up.all.sorted() && up.all.last == Int64(size))
                #expect(FileManager.default.contents(atPath: srv.appendingPathComponent("up ž \(i).bin").path) == data)
                #expect(try await c.info(remote)?.size == Int64(size))

                let mtime = Date(timeIntervalSince1970: 1_600_000_000)
                try FileManager.default.setAttributes([.modificationDate: mtime],
                                                      ofItemAtPath: srv.appendingPathComponent("up ž \(i).bin").path)
                let dst = local.appendingPathComponent("dst\(i)")
                try Data("stale contents longer than some".utf8).write(to: dst)
                let down = Recorder<Int64>()
                try await c.download(remote, to: dst) { down.add($0) }
                #expect(down.all == down.all.sorted() && down.all.last == Int64(size))
                #expect(FileManager.default.contents(atPath: dst.path) == data)
                let got = try FileManager.default.attributesOfItem(atPath: dst.path)[.modificationDate] as? Date
                #expect(got == mtime)
            }
            // Replacing an existing remote file.
            let small = local.appendingPathComponent("small")
            try Data("x".utf8).write(to: small)
            try await c.upload(small, to: "/up ž 2.bin") { _ in }
            #expect(try await c.info("/up ž 2.bin")?.size == 1)

            let missing = local.appendingPathComponent("missing")
            await expectRemote(.notFound("/nope.bin")) { try await c.download("/nope.bin", to: missing) { _ in } }
            #expect(!FileManager.default.fileExists(atPath: missing.path))
            await expectRemote(.notFound("/no dir/x.bin")) { try await c.upload(small, to: "/no dir/x.bin") { _ in } }
            await c.close()
        }
    }

    @Test func directoryOperations() async throws {
        try await withServer { port, srv, _ in
            let c = try await login(port)
            try await c.makeDirectory("/nová složka")
            #expect(try await c.info("/nová složka")?.kind == .directory)
            await expectRemote(.alreadyExists("/nová složka")) { try await c.makeDirectory("/nová složka") }
            try Data("a".utf8).write(to: srv.appendingPathComponent("nová složka/a.txt"))
            try Data("b".utf8).write(to: srv.appendingPathComponent("b.txt"))

            try await c.rename("/nová složka/a.txt", to: "/a moved.txt")
            #expect(try await c.info("/a moved.txt")?.size == 1)
            #expect(try await c.info("/nová složka/a.txt") == nil)
            await expectRemote(.alreadyExists("/b.txt")) { try await c.rename("/a moved.txt", to: "/b.txt") }
            await expectRemote(.notFound("/ghost")) { try await c.rename("/ghost", to: "/ghost2") }
            try await c.rename("/nová složka", to: "/renamed")
            #expect(try await c.info("/renamed")?.kind == .directory)

            try await c.removeFile("/a moved.txt")
            #expect(try await c.info("/a moved.txt") == nil)
            await expectRemote(.notFound("/a moved.txt")) { try await c.removeFile("/a moved.txt") }
            try await c.removeDirectory("/renamed")
            #expect(try await c.info("/renamed") == nil)
            await expectRemote(.notFound("/renamed")) { try await c.removeDirectory("/renamed") }
            await expectRemote(.invalidName("/x\ny")) { try await c.makeDirectory("/x\ny") }
            #expect(try await c.list("/").map(\.name) == ["b.txt"])
            await c.close()
        }
    }

    @Test func replaceRefusedByServerChangesNothing() async throws {
        try await withServer { port, srv, _ in
            let c = try await login(port)
            try Data("new".utf8).write(to: srv.appendingPathComponent("tmp"))
            try Data("old".utf8).write(to: srv.appendingPathComponent("target"))
            // The test server answers 553 to RNTO onto an existing name.
            #expect(try await c.replace("/tmp", over: "/target") == false)
            #expect(FileManager.default.contents(atPath: srv.path + "/target") == Data("old".utf8))
            #expect(FileManager.default.contents(atPath: srv.path + "/tmp") == Data("new".utf8))
            await expectRemote(.notFound("/ghost")) { _ = try await c.replace("/ghost", over: "/target") }
            await c.close()
        }
    }

    @Test func rootConfinement() async throws {
        try await withServer { port, srv, _ in
            try FileManager.default.createSymbolicLink(atPath: srv.appendingPathComponent("out").path,
                                                       withDestinationPath: "/")
            let c = try await login(port)
            #expect(try await c.list("/../..").map(\.name) == ["out"])
            #expect(try await c.info("/out")?.kind == .symlink)
            do {
                _ = try await c.list("/out")
                Issue.record("listed outside the root")
            } catch is RemoteError {}
            await c.close()
        }
    }

    @Test func listFallbackWithoutMLSD() async throws {
        try await withServer(["--no-mlsd"]) { port, srv, _ in
            try Data("12345".utf8).write(to: srv.appendingPathComponent("soubor s mezerou.txt"))
            // Explicit mode: libarchive briefly sets the process umask to 0 while other tests extract.
            chmod(srv.appendingPathComponent("soubor s mezerou.txt").path, 0o644)
            try Data().write(to: srv.appendingPathComponent(".skrytý"))
            try FileManager.default.createDirectory(at: srv.appendingPathComponent("adresář"),
                                                    withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(atPath: srv.appendingPathComponent("odkaz").path,
                                                       withDestinationPath: "adresář")
            let c = try await login(port)
            let e = try await c.list("/").sorted { $0.name < $1.name }
            #expect(e.map(\.name) == [".skrytý", "adresář", "odkaz", "soubor s mezerou.txt"])
            #expect(e.map(\.kind) == [.file, .directory, .symlink, .file])
            #expect(e[2].linkTarget == "adresář" && !e[2].targetIsDirectory)
            #expect(e[3].size == 5 && e[3].permissions == 0o644)
            #expect(try await c.info("/adresář")?.kind == .directory)
            #expect(try await c.list("/adresář").isEmpty)
            await c.close()
        }
    }

    @Test func cancelDownload() async throws {
        try await withServer { port, srv, local in
            try Data(count: 30_000_000).write(to: srv.appendingPathComponent("big.bin"))
            let c = try await login(port)
            let dst = local.appendingPathComponent("big.bin")
            let box = Recorder<Task<Void, any Error>>()
            let task = Task {
                try await c.download("/big.bin", to: dst) { bytes in
                    if bytes > 1_000_000 { box.all.first?.cancel() }
                }
            }
            box.add(task)
            do {
                try await task.value
                Issue.record("download was not cancelled")
            } catch let e as RemoteError {
                #expect(e == .cancelled)
            }
            #expect(!FileManager.default.fileExists(atPath: dst.path))
            // The session recovers (libcurl reconnects when needed).
            #expect(try await c.list("/").map(\.name) == ["big.bin"])
            await c.close()
        }
    }

    @Test func closeDisconnects() async throws {
        try await withServer { port, _, _ in
            let c = try await login(port)
            await c.close()
            #expect(await !c.isConnected)
            await expectRemote(.disconnected) { _ = try await c.list("/") }
            await expectRemote(.disconnected) { _ = try await c.homeDirectory() }
            await c.close()
        }
    }

    // MARK: FTPS

    /// Explicit FTPS: AUTH TLS, PBSZ 0, PROT P on a random port.
    @Test func explicitFTPS() async throws {
        try await withServer(tls: .explicit) { port, srv, local in
            try await exerciseFTPS(port: port, srv: srv, local: local)
        }
    }

    /// A self-signed certificate is refused while verification is on.
    @Test func selfSignedCertificateRejected() async throws {
        try await withServer(tls: .explicit) { port, _, _ in
            do {
                _ = try await FTPClient.connect(
                    endpoint: endpoint(port, proto: .ftps), password: password, prompter: noPrompt,
                    options: FTPOptions(connectTimeout: 5, responseTimeout: 10))
                Issue.record("connected despite an untrusted certificate")
            } catch let RemoteError.connectionFailed(message) {
                #expect(!message.isEmpty)
            }
        }
    }

    /// Implicit-TLS mode of the test server, checked with the system curl on a random port
    /// (the client only uses implicit FTPS on 990, which an unprivileged process cannot bind
    /// on 127.0.0.1 on macOS).
    @Test func implicitServerWithCurl() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") else { return }
        try await withServer(["--anonymous"], tls: .implicit) { port, srv, _ in
            try Data("hello".utf8).write(to: srv.appendingPathComponent("a.txt"))
            func curl(_ path: String) throws -> (Int32, String) {
                let p = Process()
                p.executableURL = URL(filePath: "/usr/bin/curl")
                p.arguments = ["-sS", "-k", "--ssl-reqd", "-m", "10", "-u", "anonymous:x",
                               "ftps://127.0.0.1:\(port)/\(path)"]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = FileHandle.nullDevice
                try p.run()
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                return (p.terminationStatus, String(decoding: data, as: UTF8.self))
            }
            let (rc, text) = try curl("a.txt")
            #expect(rc == 0 && text == "hello")
            let (rc2, listing) = try curl("")
            #expect(rc2 == 0 && listing.contains("a.txt"))
        }
    }

    /// Implicit FTPS on the conventional port 990 (skipped when it cannot be bound).
    @Test func implicitFTPS() async throws {
        try await withServer(tls: .implicit, port: 990) { port, srv, local in
            #expect(port == 990)
            try await exerciseFTPS(port: port, srv: srv, local: local)
        }
    }

    // The server keeps UTF-8 names on disk but speaks Windows-1250 on the wire.

    @Test(arguments: [[String](), ["--no-mlsd"]])
    func windows1250Names(_ extra: [String]) async throws {
        try await withServer(["--wire-encoding", "cp1250"] + extra) { port, srv, local in
            try Data("obsah".utf8).write(to: srv.appendingPathComponent("žluťoučký.txt"))
            try FileManager.default.createDirectory(at: srv.appendingPathComponent("složka"),
                                                    withIntermediateDirectories: false)
            try Data("kůň".utf8).write(to: srv.appendingPathComponent("složka/kůň.txt"))

            let c = try await login(port, encoding: .windows1250)
            #expect(try await c.list("/").map(\.name).sorted() == ["složka", "žluťoučký.txt"])
            #expect(try await c.list("/složka").map(\.name) == ["kůň.txt"])
            #expect(try await c.info("/žluťoučký.txt")?.size == 5)

            let down = local.appendingPathComponent("down.txt")
            try await c.download("/složka/kůň.txt", to: down) { _ in }
            #expect(FileManager.default.contents(atPath: down.path) == Data("kůň".utf8))

            let up = local.appendingPathComponent("up.txt")
            try Data("nový".utf8).write(to: up)
            try await c.upload(up, to: "/složka/nový ěščř.txt") { _ in }
            #expect(FileManager.default.contents(atPath: srv.appendingPathComponent("složka/nový ěščř.txt").path)
                    == Data("nový".utf8))
            try await c.rename("/složka/nový ěščř.txt", to: "/složka/přejmenovaný.txt")
            #expect(try await c.list("/složka").map(\.name).sorted() == ["kůň.txt", "přejmenovaný.txt"])
            try await c.makeDirectory("/další složka")
            #expect(try await c.info("/další složka")?.kind == .directory)
            try await c.removeDirectory("/další složka")
            try await c.removeFile("/složka/přejmenovaný.txt")
            try await c.removeFile("/žluťoučký.txt")
            #expect(try await c.list("/").map(\.name) == ["složka"])
            #expect(try await c.list("/složka").map(\.name) == ["kůň.txt"])
            // Not in the code page.
            await expectRemote(.invalidName("/✓.txt")) { try await c.upload(up, to: "/✓.txt") { _ in } }
            await expectRemote(.invalidName("/✓")) { try await c.makeDirectory("/✓") }
            await c.close()
        }
    }

    @Test func autoKeepsLatin1NamesWorking() async throws {
        try await withServer(["--wire-encoding", "cp1250"]) { port, srv, local in
            try FileManager.default.createDirectory(at: srv.appendingPathComponent("složka"),
                                                    withIntermediateDirectories: false)
            try Data("kůň".utf8).write(to: srv.appendingPathComponent("složka/kůň.txt"))
            try Data("ascii".utf8).write(to: srv.appendingPathComponent("plain.txt"))
            func mojibake(_ name: String) -> String { ServerEncoding.latin1(ServerEncoding.windows1250.encode(name)!) }

            let c = try await login(port)
            let folder = "/" + mojibake("složka")
            #expect(try await c.list("/").map(\.name).sorted() == ["plain.txt", mojibake("složka")])
            let file = folder + "/" + mojibake("kůň.txt")
            #expect(try await c.list(folder).map(\.name) == [mojibake("kůň.txt")])
            #expect(try await c.info(file)?.size == 5)

            let down = local.appendingPathComponent("down.txt")
            try await c.download(file, to: down) { _ in }
            #expect(FileManager.default.contents(atPath: down.path) == Data("kůň".utf8))
            try await c.rename(file, to: folder + "/renamed.txt")
            #expect(FileManager.default.fileExists(atPath: srv.appendingPathComponent("složka/renamed.txt").path))
            try await c.removeFile(folder + "/renamed.txt")
            try await c.removeDirectory(folder)
            #expect(try await c.list("/").map(\.name) == ["plain.txt"])
            await c.close()
        }
    }
}
