internal import CCurl
public import Foundation

public struct FTPOptions: Sendable, Hashable {
    /// Passive data connections (EPSV, falling back to PASV); false = active (PORT/EPRT).
    public var passive: Bool
    public var connectTimeout: TimeInterval
    /// Longest wait for one server reply.
    public var responseTimeout: TimeInterval
    /// FTPS: verify the server certificate and host name.
    public var verifyTLS: Bool

    public init(passive: Bool = true, connectTimeout: TimeInterval = 20,
                responseTimeout: TimeInterval = 60, verifyTLS: Bool = true) {
        self.passive = passive
        self.connectTimeout = connectTimeout
        self.responseTimeout = responseTimeout
        self.verifyTLS = verifyTLS
    }
}

/// FTP / FTPS (explicit AUTH TLS) session over libcurl. One easy handle per client keeps the
/// control connection open between calls; libcurl logs in again by itself when the server
/// dropped it. Paths are sent absolute: URLs start with "%2F", raw commands use the full path.
public actor FTPClient: RemoteFileSystem {
    public nonisolated let endpoint: RemoteEndpoint
    private let session: CurlSession
    private let settings: CurlSettings
    private let home: String
    private var connected = true
    private var mlsdSupported = true
    /// LIST variants still worth trying ("LIST -a" is dropped once a server rejects it).
    private var listCommands = ["LIST -a", "LIST"]

    public var isConnected: Bool { connected }

    private init(endpoint: RemoteEndpoint, session: CurlSession, settings: CurlSettings, home: String) {
        self.endpoint = endpoint
        self.session = session
        self.settings = settings
        self.home = home
    }

    private static let maxPasswordAttempts = 5

    /// Logs in. `endpoint.user` nil = anonymous; a missing or rejected password is asked from `prompter`.
    public static func connect(
        endpoint: RemoteEndpoint,
        password: String?,
        prompter: @escaping AuthPrompter,
        options: FTPOptions = .init()
    ) async throws -> FTPClient {
        guard endpoint.proto == .ftp || endpoint.proto == .ftps else {
            throw RemoteError.connectionFailed("Not an FTP endpoint")
        }
        guard !endpoint.host.isEmpty, !endpoint.host.contains(where: { "/@?#\r\n\0 ".contains($0) }) else {
            throw RemoteError.connectionFailed("Invalid host name: \(endpoint.host)")
        }
        let anonymous = endpoint.user == nil
        let user = endpoint.user ?? "anonymous"
        var pass: String? = anonymous ? "anonymous@example.com" : password
        var attempt = pass == nil ? 0 : 1
        // The prompt names the server itself; a message only explains a refused login.
        var message = ""
        let session = CurlSession()
        let probe = CurlRequest(url: baseURL(endpoint) + "/", noBody: true, quote: ["*OPTS UTF8 ON"])

        while true {
            if pass == nil {
                attempt += 1
                pass = await prompter(.password(endpoint, attempt: attempt, message: message))
                guard pass != nil else {
                    await session.close()
                    throw RemoteError.cancelled
                }
            }
            let settings = CurlSettings(
                user: user, password: pass!, useTLS: endpoint.proto == .ftps, verifyTLS: options.verifyTLS,
                passive: options.passive, connectTimeout: options.connectTimeout,
                responseTimeout: options.responseTimeout)
            let r = await session.perform(probe, settings: settings)
            if r.ok {
                var home = r.entryPath ?? "/"
                if !home.hasPrefix("/") { home = "/" }
                return FTPClient(endpoint: endpoint, session: session, settings: settings,
                                 home: RemotePath.normalize(home))
            }
            if r.cancelled {
                await session.close()
                throw RemoteError.cancelled
            }
            if r.code == CURLE_LOGIN_DENIED.rawValue, !anonymous, attempt < maxPasswordAttempts {
                message = r.lastReply ?? "Login incorrect."
                pass = nil
                continue
            }
            await session.close()
            if r.code == CURLE_LOGIN_DENIED.rawValue { throw RemoteError.authenticationFailed }
            throw RemoteError.connectionFailed(r.lastReply.map { "\(r.errorText) (\($0))" } ?? r.errorText)
        }
    }

    // MARK: RemoteFileSystem

    public func homeDirectory() async throws -> String {
        guard connected else { throw RemoteError.disconnected }
        return home
    }

    public func list(_ path: String) async throws -> [RemoteEntry] {
        let path = try checked(path)
        switch try await fetchListing(path) {
        case .success(let entries): return entries
        case .failure(let r): throw await failure(r, path: path)
        }
    }

    public func info(_ path: String) async throws -> RemoteEntry? {
        let path = try checked(path)
        if path == "/" { return RemoteEntry(name: "/", kind: .directory) }
        guard case .success(let entries) = try await fetchListing(RemotePath.parent(path)) else { return nil }
        let name = String(path[path.index(after: path.lastIndex(of: "/")!)...])
        return entries.first { $0.name == name }
    }

    public func download(_ path: String, to local: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let path = try checked(path)
        let r = try await perform(
            CurlRequest(url: url(path, directory: false), output: .file(local), wantFileTime: true),
            progress: progress)
        guard r.ok else {
            if r.code != CurlResult.localFailure { try? FileManager.default.removeItem(at: local) }
            throw await failure(r, path: path)
        }
        if let t = r.fileTime {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(t))], ofItemAtPath: local.path)
        }
        progress(r.transferred)
    }

    public func upload(_ local: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let path = try checked(path)
        guard path != "/" else { throw RemoteError.invalidName(path) }
        let r = try await perform(CurlRequest(url: url(path, directory: false), upload: local), progress: progress)
        guard r.ok else {
            if r.dataStarted {
                // Remove the partial file; must not run when cancelled, so detach from this task.
                let cleanup = CurlRequest(url: Self.baseURL(endpoint) + "/", noBody: true, quote: ["DELE \(path)"])
                let session = session, settings = settings
                _ = await Task { await session.perform(cleanup, settings: settings) }.value
            }
            throw await failure(r, path: path)
        }
        progress(r.transferred)
    }

    public func makeDirectory(_ path: String) async throws {
        let path = try checked(path)
        let r = try await command(["MKD \(path)"])
        guard r.ok else {
            if r.cancelled || !isServerReply(r) { throw await failure(r, path: path) }
            if (try? await info(path)) ?? nil != nil { throw RemoteError.alreadyExists(path) }
            throw await failure(r, path: path)
        }
    }

    public func removeFile(_ path: String) async throws {
        let path = try checked(path)
        let r = try await command(["DELE \(path)"])
        guard r.ok else { throw await failure(r, path: path) }
    }

    public func removeDirectory(_ path: String) async throws {
        let path = try checked(path)
        let r = try await command(["RMD \(path)"])
        guard r.ok else { throw await failure(r, path: path) }
    }

    public func rename(_ from: String, to: String) async throws {
        let from = try checked(from), to = try checked(to)
        guard from != to else { return }
        if try await info(to) != nil { throw RemoteError.alreadyExists(to) }
        let r = try await command(["RNFR \(from)", "RNTO \(to)"])
        guard r.ok else { throw await failure(r, path: from) }
    }

    public func close() async {
        guard connected else { return }
        connected = false
        await session.close()
    }

    // MARK: Transfers

    private func perform(
        _ request: CurlRequest, progress: (@Sendable (Int64) -> Void)? = nil
    ) async throws -> CurlResult {
        guard connected else { throw RemoteError.disconnected }
        let r = await session.perform(request, settings: settings, progress: progress)
        if r.code == CurlResult.disconnected { throw RemoteError.disconnected }
        return r
    }

    /// Raw commands on the login URL (no CWD, no data transfer).
    private func command(_ commands: [String]) async throws -> CurlResult {
        try await perform(CurlRequest(url: Self.baseURL(endpoint) + "/", noBody: true, quote: commands))
    }

    private enum Listing { case success([RemoteEntry]), failure(CurlResult) }

    /// MLSD, or LIST when the server does not know it. Throws only for cancellation and
    /// connection-level failures.
    private func fetchListing(_ path: String) async throws -> Listing {
        let dirURL = url(path, directory: true)
        if mlsdSupported {
            let r = try await perform(CurlRequest(url: dirURL, customRequest: "MLSD", output: .memory))
            if r.ok { return .success(FTPListParser.parseMLSD(r.body)) }
            try rethrowFatal(r)
            guard [500, 501, 502].contains(r.responseCode) else { return .failure(r) }
            mlsdSupported = false
        }
        var last: CurlResult?
        for (i, cmd) in listCommands.enumerated() {
            let r = try await perform(CurlRequest(url: dirURL, customRequest: cmd, output: .memory))
            if r.ok {
                if i > 0 { listCommands = Array(listCommands[i...]) }
                return .success(FTPListParser.parseLIST(r.body))
            }
            try rethrowFatal(r)
            last = r
        }
        return .failure(last!)
    }

    // MARK: Errors

    private func isServerReply(_ r: CurlResult) -> Bool {
        [CURLE_QUOTE_ERROR, CURLE_REMOTE_ACCESS_DENIED, CURLE_REMOTE_FILE_NOT_FOUND,
         CURLE_FTP_COULDNT_RETR_FILE, CURLE_UPLOAD_FAILED, CURLE_FTP_COULDNT_SET_TYPE,
         CURLE_REMOTE_DISK_FULL, CURLE_REMOTE_FILE_EXISTS, CURLE_FTP_PORT_FAILED]
            .contains { $0.rawValue == r.code } && r.responseCode >= 400
    }

    /// Cancellation, login and connection failures.
    private func fatal(_ r: CurlResult) -> RemoteError? {
        if r.cancelled { return .cancelled }
        if r.code == CURLE_LOGIN_DENIED.rawValue { return .authenticationFailed }
        if r.code == CurlResult.localFailure || r.code == CURLE_URL_MALFORMAT.rawValue { return nil }
        if isServerReply(r) || r.code == CURLE_WRITE_ERROR.rawValue || r.code == CURLE_READ_ERROR.rawValue {
            return nil
        }
        return .connectionFailed(r.errorText)
    }

    private func rethrowFatal(_ r: CurlResult) throws {
        if let e = fatal(r) { throw e }
    }

    private func failure(_ r: CurlResult, path: String) async -> any Error {
        if let e = fatal(r) { return e }
        if r.code == CurlResult.localFailure {
            return POSIXError(POSIXErrorCode(rawValue: r.localErrno) ?? .EIO)
        }
        if r.code == CURLE_URL_MALFORMAT.rawValue { return RemoteError.invalidName(path) }
        guard isServerReply(r) else { return RemoteError.server(r.errorText) }
        let text = r.lastReply ?? r.errorText
        let lower = text.lowercased()
        if r.responseCode == 553 || lower.contains("permission") || lower.contains("access denied") {
            return RemoteError.permissionDenied(path)
        }
        if [450, 550].contains(r.responseCode), (try? await info(path)) ?? nil == nil {
            return RemoteError.notFound(path)
        }
        return RemoteError.server(text)
    }

    // MARK: Paths

    /// Normalized absolute path; CR, LF and NUL cannot be sent in an FTP command.
    private func checked(_ path: String) throws -> String {
        guard connected else { throw RemoteError.disconnected }
        if path.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" || $0 == "\r\n" }) {
            throw RemoteError.invalidName(path)
        }
        return RemotePath.normalize(path)
    }

    private static func baseURL(_ e: RemoteEndpoint) -> String {
        let host = e.host.contains(":") ? "[\(e.host)]" : e.host
        // Port 990 is implicit FTPS (TLS from the first byte); elsewhere TLS starts with AUTH TLS.
        let scheme = e.proto == .ftps && e.effectivePort == 990 ? "ftps" : "ftp"
        return "\(scheme)://\(host):\(e.effectivePort)"
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// `ftp://host:port/%2F<components>[/]`: "%2F" makes libcurl CWD from the root, not the
    /// login directory; each component is percent-encoded UTF-8.
    private func url(_ path: String, directory: Bool) -> String {
        let parts = path.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? String($0)
        }
        return Self.baseURL(endpoint) + "/%2F" + parts.joined(separator: "/") + (directory ? "/" : "")
    }
}
