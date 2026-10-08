// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation
import Darwin
import Synchronization

/// How `SFTPClient` reaches an SFTP server.
public enum SFTPTransport: Sendable {
    /// `ssh -s <host> sftp` with the user's ssh configuration, agent and known_hosts.
    case ssh(SSHOptions)
    /// Any program speaking SFTP on stdin/stdout (tests, debugging: `/usr/libexec/sftp-server -d <dir>`).
    case local(executable: URL, arguments: [String])
}

public struct SSHOptions: Sendable, Hashable {
    public var sshPath: URL
    /// The program ssh runs for prompts; nil = the running app binary.
    public var askpassExecutable: URL?
    /// Inserted before `-s -- <host> sftp`.
    public var extraArguments: [String]

    public init(
        sshPath: URL = URL(fileURLWithPath: "/usr/bin/ssh"),
        askpassExecutable: URL? = nil,
        extraArguments: [String] = []
    ) {
        self.sshPath = sshPath
        self.askpassExecutable = askpassExecutable
        self.extraArguments = extraArguments
    }
}

public enum SSHCommand {
    /// Options that keep the session a plain file channel.
    public static let baseOptions = [
        "-o", "ForwardX11=no",
        "-o", "ForwardAgent=no",
        "-o", "ClearAllForwardings=yes",
        "-o", "PermitLocalCommand=no",
        "-o", "ServerAliveInterval=30",
        "-o", "ConnectTimeout=20",
    ]

    /// ssh arguments for an SFTP subsystem session; rejects hosts/users ssh could read as options.
    public static func arguments(endpoint: RemoteEndpoint, extra: [String] = []) throws -> [String] {
        let host = endpoint.host
        if host.isEmpty || host.hasPrefix("-")
            || host.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.properties.generalCategory == .control }) {
            throw RemoteError.invalidName(host)
        }
        var args = baseOptions
        if let port = endpoint.port { args += ["-p", String(port)] }
        if let user = endpoint.user {
            if user.hasPrefix("-") || user.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
                throw RemoteError.invalidName(user)
            }
            args += ["-l", user]
        }
        return args + extra + ["-s", "--", host, "sftp"]
    }
}

/// State shared with the I/O threads (they must not keep `SFTPProcess` alive).
private final class ProcessState: Sendable {
    struct Exit {
        var exited = false
        var status: Int32?
    }

    let exit = Mutex(Exit())
    let stderrTail = Mutex(Data())
    let inputClosed = Mutex(false)
    let protocolError = Mutex(false)
    let exitSignal = DispatchSemaphore(value: 0)
    let stderrDone = DispatchSemaphore(value: 0)

    static let tailLimit = 4096

    func appendStderr(_ bytes: UnsafeRawBufferPointer) {
        stderrTail.withLock {
            $0.append(contentsOf: bytes)
            if $0.count > Self.tailLimit { $0 = Data($0.suffix(Self.tailLimit)) }
        }
    }
}

/// A child process speaking SFTP on its stdin/stdout. Frames arrive on `frames`, which
/// finishes when stdout closes (after the process exited or a short grace period).
final class SFTPProcess: Sendable {
    let pid: pid_t
    let executableName: String
    let frames: AsyncStream<Data>
    private let stdinFD: Int32
    private let state = ProcessState()
    private let writeQueue = DispatchQueue(label: "icommander.sftp.write")

    private init(pid: pid_t, executableName: String, stdinFD: Int32, frames: AsyncStream<Data>) {
        self.pid = pid
        self.executableName = executableName
        self.stdinFD = stdinFD
        self.frames = frames
    }

    deinit { terminate() }

    static func spawn(executable: String, arguments: [String], environment: [String: String]) throws -> SFTPProcess {
        var inPipe: [Int32] = [-1, -1], outPipe: [Int32] = [-1, -1], errPipe: [Int32] = [-1, -1]
        guard pipe(&inPipe) == 0 else { throw spawnError(errno) }
        guard pipe(&outPipe) == 0 else {
            let e = errno; closeAll(inPipe); throw spawnError(e)
        }
        guard pipe(&errPipe) == 0 else {
            let e = errno; closeAll(inPipe + outPipe); throw spawnError(e)
        }
        for fd in inPipe + outPipe + errPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
        _ = fcntl(inPipe[1], F_SETNOSIGPIPE, 1)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, inPipe[0], 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        var defaults = sigset_t(), mask = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        sigaddset(&defaults, SIGINT)
        sigaddset(&defaults, SIGTERM)
        sigemptyset(&mask)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        posix_spawnattr_setsigmask(&attr, &mask)
        // New session: no controlling terminal, so ssh asks only through SSH_ASKPASS.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF
            | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSID))

        let argv = ([executable] + arguments).map { strdup($0) }
        let envp = environment.map { strdup("\($0.key)=\($0.value)") }
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        let rc = (argv + [nil]).withUnsafeBufferPointer { a in
            (envp + [nil]).withUnsafeBufferPointer { e in
                posix_spawn(&pid, executable, &actions, &attr, a.baseAddress, e.baseAddress)
            }
        }
        Darwin.close(inPipe[0]); Darwin.close(outPipe[1]); Darwin.close(errPipe[1])
        guard rc == 0 else {
            closeAll([inPipe[1], outPipe[0], errPipe[0]])
            throw spawnError(rc)
        }

        let (frames, continuation) = AsyncStream.makeStream(of: Data.self)
        let process = SFTPProcess(
            pid: pid,
            executableName: (executable as NSString).lastPathComponent,
            stdinFD: inPipe[1],
            frames: frames
        )
        process.startThreads(stdout: outPipe[0], stderr: errPipe[0], continuation: continuation)
        return process
    }

    private func startThreads(stdout: Int32, stderr: Int32, continuation: AsyncStream<Data>.Continuation) {
        let state = state, pid = pid
        Thread {
            // Detect exit without reaping, so `terminate` never signals a recycled pid.
            var info = siginfo_t()
            while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) != 0, errno == EINTR {}
            state.exit.withLock {
                var status: Int32 = 0
                while waitpid(pid, &status, 0) < 0, errno == EINTR {}
                $0.exited = true
                $0.status = status
            }
            state.exitSignal.signal()
        }.start()
        Thread {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = buffer.withUnsafeMutableBytes { read(stderr, $0.baseAddress, $0.count) }
                if n > 0 {
                    buffer.withUnsafeBytes { state.appendStderr(UnsafeRawBufferPointer(rebasing: $0[..<n])) }
                } else if n < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            Darwin.close(stderr)
            state.stderrDone.signal()
        }.start()
        Thread {
            var framer = SFTPFramer()
            var buffer = [UInt8](repeating: 0, count: 256 * 1024)
            reading: while true {
                let n = buffer.withUnsafeMutableBytes { read(stdout, $0.baseAddress, $0.count) }
                if n > 0 {
                    do {
                        let frames = try buffer.withUnsafeBytes { try framer.feed(UnsafeRawBufferPointer(rebasing: $0[..<n])) }
                        for frame in frames { continuation.yield(frame) }
                    } catch {
                        state.protocolError.withLock { $0 = true }
                        Self.kill(state: state, pid: pid)
                        break reading
                    }
                } else if n < 0, errno == EINTR {
                    continue
                } else {
                    break
                }
            }
            Darwin.close(stdout)
            // Let the exit status and the last stderr lines arrive before reporting the end.
            _ = state.exitSignal.wait(timeout: .now() + 3)
            _ = state.stderrDone.wait(timeout: .now() + 1)
            continuation.finish()
        }.start()
    }

    /// Queues `data` for stdin; silently dropped once the input is closed or broken.
    func send(_ data: Data) {
        let state = state, fd = stdinFD
        writeQueue.async {
            guard !state.inputClosed.withLock({ $0 }) else { return }
            data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if n > 0 {
                        offset += n
                    } else if n < 0, errno == EINTR {
                        continue
                    } else {
                        return
                    }
                }
            }
        }
    }

    /// Closes stdin after the queued writes.
    func closeInput() {
        let state = state, fd = stdinFD
        writeQueue.async {
            let wasClosed = state.inputClosed.withLock { closed in
                defer { closed = true }
                return closed
            }
            if !wasClosed { Darwin.close(fd) }
        }
    }

    /// Closes stdin and stops the process (SIGTERM, SIGKILL after 2 s).
    func terminate() {
        closeInput()
        Self.kill(state: state, pid: pid)
    }

    private static func kill(state: ProcessState, pid: pid_t) {
        let alive = state.exit.withLock { e -> Bool in
            if !e.exited { Darwin.kill(pid, SIGTERM) }
            return !e.exited
        }
        guard alive else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            state.exit.withLock { e in
                if !e.exited { Darwin.kill(pid, SIGKILL) }
            }
        }
    }

    var stderrText: String {
        String(decoding: state.stderrTail.withLock { $0 }, as: UTF8.self)
    }

    /// Raw wait status once the process has exited.
    var exitStatus: Int32? { state.exit.withLock { $0.status } }

    var sawProtocolError: Bool { state.protocolError.withLock { $0 } }

    private static func spawnError(_ code: Int32) -> RemoteError {
        .connectionFailed(String(cString: strerror(code)))
    }

    private static func closeAll(_ fds: [Int32]) {
        for fd in fds where fd >= 0 { Darwin.close(fd) }
    }
}
