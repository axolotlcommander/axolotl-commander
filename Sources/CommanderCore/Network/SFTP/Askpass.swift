import Foundation
import Darwin
import Synchronization

// ssh runs SSH_ASKPASS (the app binary itself) for every prompt; that helper forwards the
// prompt over a private Unix socket to the AskpassServer in the app and prints the answer.
//
// Wire format: helper → "<token>\n<prompt bytes>", then shuts down writing;
// server → "1<answer bytes>" or "0" (cancelled), then closes.

public enum Askpass {
    static let socketVariable = "ICOMMANDER_ASKPASS"
    static let tokenVariable = "ICOMMANDER_ASKPASS_TOKEN"

    /// When launched by ssh as SSH_ASKPASS: answers the prompt and returns the exit status;
    /// nil when this is a normal launch.
    public static func runHelperIfRequested() -> Int32? {
        let env = ProcessInfo.processInfo.environment
        guard let socketPath = env[socketVariable] else { return nil }
        guard let token = env[tokenVariable] else { return 1 }
        let args = CommandLine.arguments
        let prompt = args.count > 1 ? args[1] : ""
        guard let answer = helper(prompt: prompt, socketPath: socketPath, token: token) else { return 1 }
        FileHandle.standardOutput.write(Data((answer + "\n").utf8))
        return 0
    }

    /// Asks the server; nil when it cancelled, rejected the token or is unreachable.
    static func helper(prompt: String, socketPath: String, token: String) -> String? {
        guard var addr = UnixSocket.address(socketPath) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        UnixSocket.configure(fd)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0, UnixSocket.writeAll(fd, Data((token + "\n").utf8) + Data(prompt.utf8)) else { return nil }
        shutdown(fd, SHUT_WR)
        guard let reply = UnixSocket.readAll(fd, limit: 1 << 16), reply.first == UInt8(ascii: "1") else { return nil }
        return String(decoding: reply.dropFirst(), as: UTF8.self)
    }
}

/// Listens for askpass helpers of one connection attempt.
final class AskpassServer: Sendable {
    typealias Handler = @Sendable (String) async -> String?

    let socketPath: String
    let token: String
    private let directory: String
    private let source: Mutex<(any DispatchSourceRead)?>

    init(handler: @escaping Handler) throws {
        directory = try Self.makeDirectory()
        socketPath = directory + "/s"
        var raw = [UInt8](repeating: 0, count: 16)
        arc4random_buf(&raw, raw.count)
        token = raw.map { String(format: "%02x", $0) }.joined()

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, var addr = UnixSocket.address(socketPath) else {
            if fd >= 0 { close(fd) }
            rmdir(directory)
            throw RemoteError.connectionFailed("askpass socket: \(String(cString: strerror(errno)))")
        }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(fd, 8) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            unlink(socketPath)
            rmdir(directory)
            throw RemoteError.connectionFailed("askpass socket: \(message)")
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let token = token, path = socketPath, dir = directory
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "icommander.askpass"))
        source.setEventHandler {
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { break }
                Thread { Self.serve(client, token: token, handler: handler) }.start()
            }
        }
        source.setCancelHandler {
            close(fd)
            unlink(path)
            rmdir(dir)
        }
        source.resume()
        self.source = Mutex(source)
    }

    deinit { stop() }

    /// Stops listening and removes the socket and its directory; idempotent.
    func stop() {
        source.withLock {
            $0?.cancel()
            $0 = nil
        }
    }

    private static func makeDirectory() throws -> String {
        var base = NSTemporaryDirectory()
        // sockaddr_un.sun_path holds 104 bytes; fall back to /tmp for long temp paths.
        if base.utf8.count + 24 > 100 { base = "/tmp/" }
        if !base.hasSuffix("/") { base += "/" }
        var template = Array((base + "icmd-ap-XXXXXX").utf8CString)
        guard let made = mkdtemp(&template) else {
            throw RemoteError.connectionFailed("askpass directory: \(String(cString: strerror(errno)))")
        }
        let dir = String(cString: made)
        chmod(dir, 0o700)
        return dir
    }

    /// Runs on its own thread: reads the request, asks `handler`, replies.
    private static func serve(_ fd: Int32, token: String, handler: @escaping Handler) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        // Accepted sockets inherit O_NONBLOCK from the listener.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        UnixSocket.configure(fd)
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == geteuid(),
              let request = UnixSocket.readAll(fd, limit: 1 << 16),
              let newline = request.firstIndex(of: UInt8(ascii: "\n")),
              constantTimeEqual(Array(request[..<newline]), Array(token.utf8))
        else {
            close(fd)
            return
        }
        let prompt = String(decoding: request[(newline + 1)...], as: UTF8.self)
        Task {
            let answer = await handler(prompt)
            DispatchQueue.global().async {
                let reply = answer.map { Data("1".utf8) + Data($0.utf8) } ?? Data("0".utf8)
                _ = UnixSocket.writeAll(fd, reply)
                close(fd)
            }
        }
    }

    private static func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

enum UnixSocket {
    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    static func configure(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n > 0 {
                    offset += n
                } else if n < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    /// Reads until EOF; nil on error, timeout or more than `limit` bytes.
    static func readAll(_ fd: Int32, limit: Int) -> Data? {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                result.append(contentsOf: buffer[..<n])
                if result.count > limit { return nil }
            } else if n == 0 {
                return result
            } else if errno != EINTR {
                return nil
            }
        }
    }
}
