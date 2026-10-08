// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation
import Darwin
import Synchronization

/// Prompts of one connection attempt (askpass → `AuthPrompter`).
final class ConnectPrompts: Sendable {
    let endpoint: RemoteEndpoint
    private let passwordAttempts = Mutex(0)
    private let cancelled = Mutex(false)
    private let process = Mutex<SFTPProcess?>(nil)

    init(endpoint: RemoteEndpoint) { self.endpoint = endpoint }

    var isCancelled: Bool { cancelled.withLock { $0 } }

    func attach(_ p: SFTPProcess?) { process.withLock { $0 = p } }

    /// Marks the attempt cancelled and stops ssh (it would otherwise ask again).
    func cancel() {
        cancelled.withLock { $0 = true }
        process.withLock { $0?.terminate() }
    }

    func classify(_ prompt: String) -> AuthPrompt {
        let lower = prompt.lowercased()
        let message = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.contains("passphrase") { return .passphrase(endpoint, message: message) }
        if lower.contains("(yes/no") || lower.contains("continue connecting") {
            return .hostKey(endpoint, message: message)
        }
        if lower.contains("password") {
            let attempt = passwordAttempts.withLock { n in
                n += 1
                return n
            }
            return .password(endpoint, attempt: attempt, message: message)
        }
        return .other(endpoint, message: message)
    }

    func answer(_ prompt: String, using prompter: AuthPrompter) async -> String? {
        let reply = await prompter(classify(prompt))
        if reply == nil { cancel() }
        return reply
    }
}

/// SFTP v3 session over ssh (or any program speaking SFTP on stdin/stdout).
/// Transfers keep several requests in flight; the actor interleaves them.
public actor SFTPClient: RemoteFileSystem {
    public nonisolated let endpoint: RemoteEndpoint
    public private(set) var isConnected = true
    /// Server extensions announced in VERSION.
    public private(set) var extensions: [String: Data] = [:]
    /// Chunk sizes of READ / WRITE (from limits@openssh.com when offered).
    public private(set) var maxReadLength = 32768
    public private(set) var maxWriteLength = 32768

    nonisolated var processIdentifier: pid_t { process.pid }

    static let pipelineDepth = 16
    private static let defaultChunk = 32768
    private static let maxChunk = 255 * 1024

    private let process: SFTPProcess
    private let prompts: ConnectPrompts
    private var nextID: UInt32 = 1
    private var pending: [UInt32: CheckedContinuation<SFTPResponse, any Error>] = [:]
    private var versionWaiter: CheckedContinuation<SFTPResponse, any Error>?
    private var malformedReply = false

    private init(endpoint: RemoteEndpoint, process: SFTPProcess, prompts: ConnectPrompts) {
        self.endpoint = endpoint
        self.process = process
        self.prompts = prompts
    }

    // MARK: Connecting

    public static func connect(
        endpoint: RemoteEndpoint,
        transport: SFTPTransport,
        prompter: @escaping AuthPrompter
    ) async throws -> SFTPClient {
        guard !Task.isCancelled else { throw RemoteError.cancelled }
        let prompts = ConnectPrompts(endpoint: endpoint)
        var server: AskpassServer?
        // The askpass server lives until the handshake finished or failed.
        defer { server?.stop() }

        let executable: String
        let arguments: [String]
        var environment = ProcessInfo.processInfo.environment
        switch transport {
        case .local(let url, let args):
            executable = url.path
            arguments = args
        case .ssh(let options):
            arguments = try SSHCommand.arguments(endpoint: endpoint, extra: options.extraArguments)
            guard let askpass = options.askpassExecutable ?? Bundle.main.executableURL else {
                throw RemoteError.connectionFailed("No askpass program")
            }
            let s = try AskpassServer { prompt in await prompts.answer(prompt, using: prompter) }
            server = s
            executable = options.sshPath.path
            environment["SSH_ASKPASS"] = askpass.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment[Askpass.socketVariable] = s.socketPath
            environment[Askpass.tokenVariable] = s.token
        }

        let process = try SFTPProcess.spawn(executable: executable, arguments: arguments, environment: environment)
        prompts.attach(process)
        defer { prompts.attach(nil) }
        let client = SFTPClient(endpoint: endpoint, process: process, prompts: prompts)
        do {
            try await client.handshake()
        } catch {
            await client.close()
            throw error
        }
        return client
    }

    private func handshake() async throws {
        startReader()
        let process = process, prompts = prompts
        let reply = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<SFTPResponse, any Error>) in
                guard isConnected else {
                    c.resume(throwing: setupError())
                    return
                }
                versionWaiter = c
                process.send(SFTPEncoder.request(.initialize, id: nil) { $0.u32(3) })
            }
        } onCancel: {
            prompts.cancel()
        }
        guard case .version(let version, let ext) = reply, version >= 3 else {
            throw RemoteError.connectionFailed("Unsupported SFTP protocol version")
        }
        extensions = ext
        guard ext["limits@openssh.com"] != nil else { return }
        do {
            let r = try await send(.extended) { $0.string("limits@openssh.com") }
            if case .extendedReply(_, let data) = r {
                var d = SFTPDecoder(data)
                _ = try? d.u64()
                if let read = try? d.u64(), read > 0 { maxReadLength = Self.chunk(read) }
                if let write = try? d.u64(), write > 0 { maxWriteLength = Self.chunk(write) }
            }
        } catch RemoteError.disconnected {
            throw setupError()
        }
    }

    private static func chunk(_ limit: UInt64) -> Int {
        Int(min(max(limit, 1024), UInt64(maxChunk)))
    }

    /// Why the session ended before VERSION.
    private func setupError() -> RemoteError {
        if prompts.isCancelled { return .cancelled }
        let stderr = process.stderrText
        if stderr.contains("Permission denied") { return .authenticationFailed }
        let lines = stderr.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let tail = lines.suffix(8).joined(separator: "\n")
        if stderr.contains("Host key verification failed") || stderr.contains("REMOTE HOST IDENTIFICATION HAS CHANGED") {
            return .hostKeyRejected(tail)
        }
        if process.sawProtocolError || malformedReply {
            return .connectionFailed("The server did not answer with the SFTP protocol")
        }
        if !tail.isEmpty { return .connectionFailed(tail) }
        let name = process.executableName
        guard let status = process.exitStatus else { return .connectionFailed("\(name) closed the connection") }
        if status & 0x7f == 0 { return .connectionFailed("\(name) exited with status \((status >> 8) & 0xff)") }
        return .connectionFailed("\(name) terminated by signal \(status & 0x7f)")
    }

    // MARK: Request plumbing

    private func startReader() {
        let frames = process.frames
        Task.detached { [weak self] in
            for await frame in frames {
                guard let self else { return }
                await self.receive(frame)
            }
            await self?.connectionEnded()
        }
    }

    private func receive(_ frame: Data) {
        guard let response = try? SFTPResponse.decode(frame) else {
            malformedReply = true
            process.terminate()
            return
        }
        if case .version = response {
            versionWaiter?.resume(returning: response)
            versionWaiter = nil
        } else if let id = response.requestID, let c = pending.removeValue(forKey: id) {
            c.resume(returning: response)
        }
    }

    private func connectionEnded() {
        isConnected = false
        failPending()
        if let w = versionWaiter {
            versionWaiter = nil
            w.resume(throwing: setupError())
        }
    }

    private func failPending() {
        let waiting = pending
        pending = [:]
        for c in waiting.values { c.resume(throwing: RemoteError.disconnected) }
    }

    private func send(_ type: SFTPType, _ body: (inout SFTPEncoder) -> Void) async throws -> SFTPResponse {
        guard isConnected else { throw RemoteError.disconnected }
        let id = nextID
        nextID &+= 1
        let packet = SFTPEncoder.request(type, id: id, body)
        return try await withCheckedThrowingContinuation { c in
            pending[id] = c
            process.send(packet)
        }
    }

    private static func error(code: UInt32, message: String, path: String) -> RemoteError {
        switch code {
        case SFTPStatus.noSuchFile: .notFound(path)
        case SFTPStatus.permissionDenied: .permissionDenied(path)
        default: .server(message.isEmpty ? "SFTP error \(code)" : message)
        }
    }

    private static func unexpected(_ r: SFTPResponse, _ path: String) -> RemoteError {
        if case .status(_, let code, let message) = r, code != SFTPStatus.ok {
            return error(code: code, message: message, path: path)
        }
        return .server("Unexpected SFTP response")
    }

    private static func expectOK(_ r: SFTPResponse, _ path: String) throws {
        guard case .status(_, SFTPStatus.ok, _) = r else { throw unexpected(r, path) }
    }

    private func handle(_ r: SFTPResponse, _ path: String) throws -> Data {
        guard case .handle(_, let h) = r else { throw Self.unexpected(r, path) }
        return h
    }

    private func closeHandle(_ handle: Data) async {
        _ = try? await send(.close) { $0.string(handle) }
    }

    /// STAT / LSTAT; nil when the path does not exist.
    private func attributes(_ path: String, follow: Bool) async throws -> SFTPAttributes? {
        let r = try await send(follow ? .stat : .lstat) { $0.string(path) }
        switch r {
        case .attrs(_, let a): return a
        case .status(_, SFTPStatus.noSuchFile, _): return nil
        default: throw Self.unexpected(r, path)
        }
    }

    private func readlink(_ path: String) async throws -> String? {
        let r = try await send(.readlink) { $0.string(path) }
        guard case .name(_, let names) = r, let first = names.first else { return nil }
        return String(decoding: first.filename, as: UTF8.self)
    }

    private static func mapCancellation(_ error: any Error) -> any Error {
        error is CancellationError ? RemoteError.cancelled : error
    }

    // MARK: Entries

    private static func entry(name: String, attributes a: SFTPAttributes, longname: Data = Data()) -> RemoteEntry {
        let kind: RemoteEntry.Kind
        switch a.fileType {
        case 0o040000?: kind = .directory
        case 0o100000?: kind = .file
        case 0o120000?: kind = .symlink
        case nil:
            switch longname.first {
            case UInt8(ascii: "d"): kind = .directory
            case UInt8(ascii: "l"): kind = .symlink
            case UInt8(ascii: "-"): kind = .file
            default: kind = .other
            }
        default: kind = .other
        }
        return RemoteEntry(
            name: name,
            kind: kind,
            size: kind == .file ? a.size.map { Int64(clamping: $0) } : nil,
            modificationDate: a.mtime.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            permissions: a.permissions.map { $0 & 0o7777 }
        )
    }

    /// Fills `targetIsDirectory` and `linkTarget` of symlink entries (a few requests at a time).
    private func resolveLinks(_ entries: inout [RemoteEntry], in directory: String) async {
        let links = entries.indices.filter { entries[$0].kind == .symlink }
        guard !links.isEmpty else { return }
        let names = links.map { RemotePath.join(directory, entries[$0].name) }
        let results = await withTaskGroup(of: (Int, Bool, String?).self) { group in
            var out: [(Int, Bool, String?)] = []
            var next = 0
            func add(_ group: inout TaskGroup<(Int, Bool, String?)>) {
                let i = next, path = names[i]
                next += 1
                group.addTask {
                    let target = try? await self.attributes(path, follow: true)
                    let isDir = target?.fileType == 0o040000
                    return (i, isDir, try? await self.readlink(path))
                }
            }
            while next < names.count, next < Self.pipelineDepth { add(&group) }
            while let r = await group.next() {
                out.append(r)
                if next < names.count { add(&group) }
            }
            return out
        }
        for (i, isDir, target) in results {
            entries[links[i]].targetIsDirectory = isDir
            entries[links[i]].linkTarget = target
        }
    }

    // MARK: RemoteFileSystem

    public func homeDirectory() async throws -> String {
        let r = try await send(.realpath) { $0.string(".") }
        guard case .name(_, let names) = r, let first = names.first else { throw Self.unexpected(r, ".") }
        return String(decoding: first.filename, as: UTF8.self)
    }

    public func list(_ path: String) async throws -> [RemoteEntry] {
        let dir = try handle(try await send(.opendir) { $0.string(path) }, path)
        var entries: [RemoteEntry] = []
        do {
            reading: while true {
                let r = try await send(.readdir) { $0.string(dir) }
                switch r {
                case .name(_, let names):
                    for n in names {
                        let name = String(decoding: n.filename, as: UTF8.self)
                        if name == "." || name == ".." { continue }
                        entries.append(Self.entry(name: name, attributes: n.attributes, longname: n.longname))
                    }
                case .status(_, SFTPStatus.eof, _):
                    break reading
                default:
                    throw Self.unexpected(r, path)
                }
            }
        } catch {
            await closeHandle(dir)
            throw error
        }
        await closeHandle(dir)
        await resolveLinks(&entries, in: path)
        return entries
    }

    public func info(_ path: String) async throws -> RemoteEntry? {
        guard let a = try await attributes(path, follow: false) else { return nil }
        let name = path == "/" ? "/" : String(path.split(separator: "/").last ?? Substring(path))
        var entries = [Self.entry(name: name, attributes: a)]
        await resolveLinks(&entries, in: RemotePath.parent(path))
        return entries[0]
    }

    public func download(_ path: String, to local: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        if Task.isCancelled { throw RemoteError.cancelled }
        let file = try handle(try await send(.open) {
            $0.string(path); $0.u32(SFTPOpenFlags.read); $0.attributes(.none)
        }, path)
        var mtime: UInt32?
        if case .attrs(_, let a)? = try? await send(.fstat, { $0.string(file) }) { mtime = a.mtime }
        let fd = open(local.path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0o644)
        guard fd >= 0 else {
            let code = errno
            await closeHandle(file)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        do {
            try await readAll(file, into: fd, path: path, progress: progress)
            Darwin.close(fd)
            await closeHandle(file)
        } catch {
            Darwin.close(fd)
            await closeHandle(file)
            unlink(local.path)
            throw Self.mapCancellation(error)
        }
        if let mtime {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(mtime))], ofItemAtPath: local.path)
        }
    }

    /// Pipelined READs into `fd` until EOF; short reads are completed by follow-up requests.
    private func readAll(_ file: Data, into fd: Int32, path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let chunk = UInt32(maxReadLength)
        var written: Int64 = 0
        try await withThrowingTaskGroup(of: (UInt64, UInt32, Data?).self) { group in
            var nextOffset: UInt64 = 0
            var eof = false
            var outstanding = 0
            while true {
                while !eof, outstanding < Self.pipelineDepth {
                    let offset = nextOffset
                    nextOffset += UInt64(chunk)
                    outstanding += 1
                    group.addTask { (offset, chunk, try await self.readChunk(file, offset, chunk, path)) }
                }
                guard let (offset, length, data) = try await group.next() else { break }
                outstanding -= 1
                if Task.isCancelled { throw RemoteError.cancelled }
                guard let data, !data.isEmpty else {
                    eof = true
                    continue
                }
                try Self.pwriteAll(fd, data, at: offset)
                written += Int64(data.count)
                progress(written)
                if data.count < Int(length) {
                    let rest = offset + UInt64(data.count), remaining = length - UInt32(data.count)
                    outstanding += 1
                    group.addTask { (rest, remaining, try await self.readChunk(file, rest, remaining, path)) }
                }
            }
        }
        if written == 0 { progress(0) }
    }

    private func readChunk(_ file: Data, _ offset: UInt64, _ length: UInt32, _ path: String) async throws -> Data? {
        let r = try await send(.read) { $0.string(file); $0.u64(offset); $0.u32(length) }
        switch r {
        case .data(_, let d): return d
        case .status(_, SFTPStatus.eof, _): return nil
        default: throw Self.unexpected(r, path)
        }
    }

    private static func pwriteAll(_ fd: Int32, _ data: Data, at offset: UInt64) throws {
        try data.withUnsafeBytes { raw in
            var done = 0
            while done < raw.count {
                let n = pwrite(fd, raw.baseAddress! + done, raw.count - done, off_t(offset) + off_t(done))
                if n > 0 {
                    done += n
                } else if n < 0, errno == EINTR {
                    continue
                } else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
        }
    }

    public func upload(_ local: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        if Task.isCancelled { throw RemoteError.cancelled }
        let fd = open(local.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let file = try handle(try await send(.open) {
            $0.string(path)
            $0.u32(SFTPOpenFlags.write | SFTPOpenFlags.create | SFTPOpenFlags.truncate)
            $0.attributes(.none)
        }, path)
        var closed = false
        do {
            try await writeAll(file, from: fd, size: Int64(st.st_size), path: path, progress: progress)
            if Task.isCancelled { throw RemoteError.cancelled }
            let mtime = UInt32(clamping: st.st_mtimespec.tv_sec)
            let atime = UInt32(clamping: st.st_atimespec.tv_sec)
            let full = SFTPAttributes(permissions: UInt32(st.st_mode) & 0o777, atime: atime, mtime: mtime)
            let r = try await send(.fsetstat) { $0.string(file); $0.attributes(full) }
            if (try? Self.expectOK(r, path)) == nil {
                _ = try await send(.fsetstat) {
                    $0.string(file); $0.attributes(SFTPAttributes(atime: atime, mtime: mtime))
                }
            }
            closed = true
            try Self.expectOK(try await send(.close) { $0.string(file) }, path)
        } catch {
            if !closed { await closeHandle(file) }
            _ = try? await send(.remove) { $0.string(path) }
            throw Self.mapCancellation(error)
        }
    }

    /// Pipelined WRITEs of the first `size` bytes of `fd`.
    private func writeAll(_ file: Data, from fd: Int32, size: Int64, path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let chunk = maxWriteLength
        var acked: Int64 = 0
        try await withThrowingTaskGroup(of: Int.self) { group in
            var offset: Int64 = 0
            var end = size
            var outstanding = 0
            while true {
                while offset < end, outstanding < Self.pipelineDepth {
                    if Task.isCancelled { throw RemoteError.cancelled }
                    let data = try Self.pread(fd, count: Int(min(Int64(chunk), end - offset)), at: offset)
                    if data.isEmpty {
                        end = offset // the file shrank
                        break
                    }
                    let at = UInt64(offset)
                    offset += Int64(data.count)
                    outstanding += 1
                    group.addTask {
                        try await self.writeChunk(file, data, at: at, path: path)
                        return data.count
                    }
                }
                guard let n = try await group.next() else { break }
                outstanding -= 1
                if Task.isCancelled { throw RemoteError.cancelled }
                acked += Int64(n)
                progress(acked)
            }
        }
        if acked == 0 { progress(0) }
    }

    private func writeChunk(_ file: Data, _ data: Data, at offset: UInt64, path: String) async throws {
        let r = try await send(.write) { $0.string(file); $0.u64(offset); $0.string(data) }
        try Self.expectOK(r, path)
    }

    private static func pread(_ fd: Int32, count: Int, at offset: Int64) throws -> Data {
        var data = Data(count: count)
        let n = data.withUnsafeMutableBytes { raw -> Int in
            while true {
                let n = Darwin.pread(fd, raw.baseAddress, count, off_t(offset))
                if n < 0, errno == EINTR { continue }
                return n
            }
        }
        guard n >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        data.count = n
        return data
    }

    public func makeDirectory(_ path: String) async throws {
        let r = try await send(.mkdir) { $0.string(path); $0.attributes(.none) }
        if case .status(_, SFTPStatus.failure, _) = r, (try? await attributes(path, follow: false)) != nil {
            throw RemoteError.alreadyExists(path)
        }
        try Self.expectOK(r, path)
    }

    public func removeFile(_ path: String) async throws {
        try Self.expectOK(try await send(.remove) { $0.string(path) }, path)
    }

    public func removeDirectory(_ path: String) async throws {
        try Self.expectOK(try await send(.rmdir) { $0.string(path) }, path)
    }

    public func rename(_ from: String, to: String) async throws {
        if try await attributes(to, follow: false) != nil { throw RemoteError.alreadyExists(to) }
        try Self.expectOK(try await send(.rename) { $0.string(from); $0.string(to) }, from)
    }

    public func close() async {
        isConnected = false
        failPending()
        process.terminate()
    }
}
