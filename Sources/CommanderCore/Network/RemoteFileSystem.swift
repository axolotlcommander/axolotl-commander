// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Protocols a panel can browse on a server.
public enum RemoteProtocol: String, Codable, Sendable, CaseIterable {
    case sftp
    /// Plain FTP.
    case ftp
    /// FTP with TLS: explicit (AUTH TLS on the control connection, protected data connections),
    /// implicit on port 990.
    case ftps

    public var defaultPort: Int {
        switch self {
        case .sftp: 22
        case .ftp, .ftps: 21
        }
    }
}

/// Where to connect; identifies one live connection.
public struct RemoteEndpoint: Hashable, Codable, Sendable {
    public var proto: RemoteProtocol
    public var host: String
    /// nil = the protocol's default port.
    public var port: Int?
    /// nil = SFTP: ssh decides (config / login name); FTP: anonymous.
    public var user: String?

    public init(proto: RemoteProtocol, host: String, port: Int? = nil, user: String? = nil) {
        self.proto = proto
        self.host = host
        self.port = port == proto.defaultPort ? nil : port
        self.user = user?.isEmpty == true ? nil : user
    }

    public var effectivePort: Int { port ?? proto.defaultPort }
}

/// One directory entry on a server.
public struct RemoteEntry: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case file, directory, symlink, other }

    public var name: String
    public var kind: Kind
    /// nil when unknown or for directories.
    public var size: Int64?
    public var modificationDate: Date?
    /// POSIX mode bits (0o7777) when the server reports them.
    public var permissions: UInt32?
    public var linkTarget: String?
    /// For symlinks: true when the target is a directory (resolved by the client when cheap).
    public var targetIsDirectory: Bool

    public init(
        name: String,
        kind: Kind,
        size: Int64? = nil,
        modificationDate: Date? = nil,
        permissions: UInt32? = nil,
        linkTarget: String? = nil,
        targetIsDirectory: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.size = kind == .directory ? nil : size
        self.modificationDate = modificationDate
        self.permissions = permissions
        self.linkTarget = linkTarget
        self.targetIsDirectory = targetIsDirectory
    }

    /// Browsed like a folder (directories and symlinks to directories).
    public var isDirectoryLike: Bool { kind == .directory || (kind == .symlink && targetIsDirectory) }

    /// A name a listing may contain: not empty, ".", "..", and without "/" or NUL. A broken or
    /// hostile server listing "x/../../etc" would otherwise let a recursive delete or move leave
    /// the selected tree.
    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}

public enum RemoteError: Error, Equatable, Sendable {
    /// Could not reach the server or the session ended during setup (message from ssh / the server).
    case connectionFailed(String)
    case authenticationFailed
    /// The user declined an unknown host key, or ssh refused a changed one.
    case hostKeyRejected(String)
    case notFound(String)
    case permissionDenied(String)
    case alreadyExists(String)
    /// A name the protocol cannot carry (e.g. CR/LF in an FTP path).
    case invalidName(String)
    /// Any other failure reported by the server.
    case server(String)
    /// The connection dropped after it was established.
    case disconnected
    case cancelled
    /// Replacing `target` failed half-way and the old version could not be put back: the new
    /// version is at `newAt`, the old one at `oldAt` (both complete).
    case replaceIncomplete(target: String, newAt: String, oldAt: String)
}

/// A question asked while connecting; the answer nil means the user cancelled.
public enum AuthPrompt: Sendable, Equatable {
    /// Password for `endpoint`; `attempt` starts at 1, > 1 means the previous one was rejected.
    case password(RemoteEndpoint, attempt: Int, message: String)
    /// Passphrase of a private key (SFTP).
    case passphrase(RemoteEndpoint, message: String)
    /// Unknown host key; answer "yes" to accept, anything else rejects (SFTP).
    case hostKey(RemoteEndpoint, message: String)
    /// Any other prompt ssh shows (e.g. keyboard-interactive); answered as typed.
    case other(RemoteEndpoint, message: String)
}

public typealias AuthPrompter = @Sendable (AuthPrompt) async -> String?

/// A connected session. Paths are absolute, "/"-separated, without a trailing "/" (except "/").
/// Calls are serialized by the actor; long transfers honor task cancellation (throw `.cancelled`).
public protocol RemoteFileSystem: Actor {
    var endpoint: RemoteEndpoint { get }
    /// The login directory (absolute).
    func homeDirectory() async throws -> String
    /// Entries of `path` without "." and "..".
    func list(_ path: String) async throws -> [RemoteEntry]
    /// The entry itself (symlinks not followed); nil when it does not exist.
    func info(_ path: String) async throws -> RemoteEntry?
    /// Writes the remote file into `local` (created or truncated). `progress` gets cumulative bytes.
    func download(_ path: String, to local: URL, progress: @escaping @Sendable (Int64) -> Void) async throws
    /// Creates or replaces the remote file with the contents of `local`.
    func upload(_ local: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws
    func makeDirectory(_ path: String) async throws
    func removeFile(_ path: String) async throws
    /// Removes an empty directory.
    func removeDirectory(_ path: String) async throws
    /// Fails with `.alreadyExists` when `to` exists.
    func rename(_ from: String, to: String) async throws
    /// Puts `from` in place of the existing file `to` in one step, so `to` never goes missing.
    /// false = the server can't do that and nothing was changed.
    func replace(_ from: String, over to: String) async throws -> Bool
    /// True until the session ends (closed, dropped).
    var isConnected: Bool { get }
    func close() async
}

extension RemoteFileSystem {
    public func replace(_ from: String, over to: String) async throws -> Bool { false }
}

public enum RemotePath {
    /// "/a/b" + "c" → "/a/b/c"; "/" + "c" → "/c".
    public static func join(_ directory: String, _ name: String) -> String {
        directory.hasSuffix("/") ? directory + name : directory + "/" + name
    }

    /// "/a/b" → "/a"; "/a" → "/"; "/" → "/".
    public static func parent(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/"), path != "/" else { return "/" }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }

    /// Absolute, no empty or "." components, no trailing "/"; ".." pops a component.
    public static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }
}
