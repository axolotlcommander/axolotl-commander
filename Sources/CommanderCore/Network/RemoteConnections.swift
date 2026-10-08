// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Synchronization

/// What the user answered to an `AuthPrompt`.
public struct PromptReply: Sendable, Equatable {
    public var text: String
    /// For passwords: keep it in the password store once the login succeeds.
    public var remember: Bool

    public init(_ text: String, remember: Bool = false) {
        self.text = text
        self.remember = remember
    }
}

/// Asks the user; nil = cancelled.
public typealias UserPrompter = @Sendable (AuthPrompt) async -> PromptReply?

public struct ConnectOptions: Sendable, Equatable {
    /// FTP: passive data connections.
    public var passiveMode: Bool
    /// FTP: how the server encodes names.
    public var encoding: ServerEncoding

    public init(passiveMode: Bool = true, encoding: ServerEncoding = .auto) {
        self.passiveMode = passiveMode
        self.encoding = encoding
    }
}

/// The live server sessions panels and operations share, one per endpoint.
/// Connects on first use, answers password prompts from the password store first,
/// and reconnects once when a session turns out to be dropped.
public actor RemoteConnections {
    public typealias Connector = @Sendable (RemoteEndpoint, ConnectOptions, @escaping AuthPrompter) async throws
        -> any RemoteFileSystem

    public static let shared = RemoteConnections()

    /// Posted (object: the instance) after `openedEndpoints` changed.
    public static let didChangeNotification = Notification.Name("RemoteConnections.didChange")

    private struct Setup {
        var connector: Connector?
        var ask: UserPrompter = { _ in nil }
        var passwords: any PasswordStore = MemoryPasswordStore()
    }

    /// Set synchronously at launch, before any panel can ask for a session.
    private let setup = Mutex(Setup())
    private var sessions: [RemoteEndpoint: any RemoteFileSystem] = [:]
    private var pending: [RemoteEndpoint: Task<any RemoteFileSystem, any Error>] = [:]
    private var options: [RemoteEndpoint: ConnectOptions] = [:]
    /// Endpoints in the order their first session opened; a dropped session stays listed
    /// until the user disconnects.
    private var opened: [RemoteEndpoint] = []

    public init() {}

    public nonisolated func configure(connector: @escaping Connector, prompter: @escaping UserPrompter, passwords: any PasswordStore) {
        setup.withLock { $0 = Setup(connector: connector, ask: prompter, passwords: passwords) }
    }

    private var passwords: any PasswordStore { setup.withLock { $0.passwords } }

    /// Endpoints with an open session, sorted by display name.
    public var connected: [RemoteEndpoint] {
        sessions.keys.sorted { RemoteURL.displayName($0) < RemoteURL.displayName($1) }
    }

    public func isConnected(_ endpoint: RemoteEndpoint) -> Bool { sessions[endpoint] != nil }

    /// Connections the user opened and has not closed, in opening order, including dropped ones.
    public var openedEndpoints: [RemoteEndpoint] { opened }

    /// The open session, or a new one. `password` (typed in a dialog or an address) is tried
    /// before the stored one; `options` are kept for later reconnects.
    public func session(
        for endpoint: RemoteEndpoint,
        password: String? = nil,
        options newOptions: ConnectOptions? = nil
    ) async throws -> any RemoteFileSystem {
        if let newOptions { options[endpoint] = newOptions }
        if let open = sessions[endpoint] {
            if await open.isConnected { return open }
            sessions[endpoint] = nil
        }
        if let task = pending[endpoint] { return try await task.value }
        let (connector, ask) = setup.withLock { ($0.connector, $0.ask) }
        guard let connector else { throw RemoteError.connectionFailed("No connector") }

        let attempt = ConnectAttempt(typed: password, stored: passwords.password(for: endpoint))
        let prompter: AuthPrompter = { prompt in
            if case .password = prompt, let automatic = attempt.nextAutomatic() { return automatic }
            let reply = await ask(prompt)
            if case .password = prompt { attempt.typedReply(reply) }
            return reply?.text
        }
        let opts = options[endpoint] ?? ConnectOptions()
        let task = Task { try await connector(endpoint, opts, prompter) }
        pending[endpoint] = task
        defer { pending[endpoint] = nil }
        let session = try await task.value
        sessions[endpoint] = session
        if !opened.contains(endpoint) {
            opened.append(endpoint)
            postChange()
        }
        if let reply = attempt.lastReply, reply.remember {
            try? passwords.save(reply.text, for: endpoint)
        }
        return session
    }

    /// Runs `body` on the session; a dropped session is reopened and `body` retried once.
    public func perform<T: Sendable>(
        on endpoint: RemoteEndpoint,
        _ body: @Sendable (any RemoteFileSystem) async throws -> T
    ) async throws -> T {
        let fs = try await session(for: endpoint)
        do {
            return try await body(fs)
        } catch RemoteError.disconnected {
            if let current = sessions[endpoint], current === fs { sessions[endpoint] = nil }
            return try await body(session(for: endpoint))
        }
    }

    /// Fills in the login directory when `location.path` is "".
    public func resolve(_ location: RemoteLocation) async throws -> RemoteLocation {
        guard location.path.isEmpty else { return location }
        let home = try await perform(on: location.endpoint) { try await $0.homeDirectory() }
        return RemoteLocation(endpoint: location.endpoint, path: home)
    }

    /// The folder as panel items.
    public func list(_ location: RemoteLocation, includeHidden: Bool) async throws -> [FileItem] {
        let resolved = try await resolve(location)
        let entries = try await perform(on: location.endpoint) { try await $0.list(resolved.path) }
        return entries.compactMap { entry in
            let hidden = entry.name.hasPrefix(".")
            if hidden && !includeHidden { return nil }
            let path = RemotePath.join(resolved.path, entry.name)
            return FileItem(
                url: RemoteURL.make(location.endpoint, path: path),
                name: entry.name,
                isDirectory: entry.isDirectoryLike,
                isSymlink: entry.kind == .symlink,
                isHidden: hidden,
                size: entry.isDirectoryLike ? nil : entry.size,
                modificationDate: entry.modificationDate
            )
        }
    }

    /// Sum of file sizes below a folder; symlinks are not followed, and a folder the server
    /// reports under the same `uniqueID` as one already counted is not entered again.
    public func totalSize(of folder: RemoteLocation) async throws -> Int64 {
        var total: Int64 = 0
        var stack = [folder.path]
        var seen = Set<String>()
        while let dir = stack.popLast() {
            try Task.checkCancellation()
            for entry in try await perform(on: folder.endpoint, { try await $0.walkList(dir) }) {
                switch entry.kind {
                case .directory:
                    if let id = entry.uniqueID, !seen.insert(id).inserted { break }
                    stack.append(RemotePath.join(dir, entry.name))
                case .file: total += entry.size ?? 0
                case .symlink, .other: break
                }
            }
        }
        return total
    }

    /// Closes the session (if any) and drops the endpoint from `openedEndpoints`.
    public func disconnect(_ endpoint: RemoteEndpoint) async {
        if await close(endpoint) { postChange() }
    }

    public func disconnectAll() async {
        var changed = false
        for endpoint in opened + sessions.keys {
            if await close(endpoint) { changed = true }
        }
        if changed { postChange() }
    }

    /// True when `opened` lost the endpoint.
    private func close(_ endpoint: RemoteEndpoint) async -> Bool {
        pending[endpoint]?.cancel()
        let index = opened.firstIndex(of: endpoint)
        if let index { opened.remove(at: index) }
        if let session = sessions.removeValue(forKey: endpoint) { await session.close() }
        return index != nil
    }

    private func postChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    public func forgetPassword(for endpoint: RemoteEndpoint) {
        passwords.remove(for: endpoint)
    }
}

/// Password answers during one connect: the typed one first, then the stored one, each once.
private final class ConnectAttempt: Sendable {
    private struct State {
        var automatic: [String]
        var lastReply: PromptReply?
    }

    private let state: Mutex<State>

    init(typed: String?, stored: String?) {
        var automatic = [typed, stored].compactMap(\.self)
        if automatic.count == 2, automatic[0] == automatic[1] { automatic.removeLast() }
        state = Mutex(State(automatic: automatic))
    }

    func nextAutomatic() -> String? {
        state.withLock { $0.automatic.isEmpty ? nil : $0.automatic.removeFirst() }
    }

    func typedReply(_ reply: PromptReply?) {
        state.withLock { $0.lastReply = reply }
    }

    var lastReply: PromptReply? { state.withLock { $0.lastReply } }
}
