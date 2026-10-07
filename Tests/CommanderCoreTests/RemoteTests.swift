import Testing
import Foundation
@testable import CommanderCore

@Suite struct RemoteURLTests {
    @Test func typedAddressKeepsPasswordOutOfLocation() throws {
        let (location, password) = try #require(RemoteURL.parse(typed: "sftp://jan:p@ss:w0rd@example.com:2222/home/jan"))
        #expect(password == "p@ss:w0rd")
        #expect(location.endpoint == RemoteEndpoint(proto: .sftp, host: "example.com", port: 2222, user: "jan"))
        #expect(location.path == "/home/jan")
        #expect(location.url.absoluteString == "sftp://jan@example.com:2222/home/jan")
    }

    @Test func percentEncodedUserInfoAndPath() throws {
        let (location, password) = try #require(RemoteURL.parse(typed: "ftp://a%40b:h%C3%A9slo@host/%C5%BElu%C5%A5"))
        #expect(location.endpoint.user == "a@b")
        #expect(password == "héslo")
        #expect(location.path == "/žluť")
    }

    @Test func defaultPortAndEmptyUserAreDropped() throws {
        let (location, password) = try #require(RemoteURL.parse(typed: "FTPS://host:21"))
        #expect(password == nil)
        #expect(location.endpoint == RemoteEndpoint(proto: .ftps, host: "host"))
        #expect(location.endpoint.port == nil)
        #expect(location.path == "")
    }

    @Test func ipv6Host() throws {
        let (location, _) = try #require(RemoteURL.parse(typed: "sftp://u@[::1]:2200/tmp"))
        #expect(location.endpoint.host == "::1")
        #expect(location.endpoint.port == 2200)
        #expect(RemoteURL.parse(location.url) == location)
        #expect(RemoteURL.displayName(location.endpoint) == "u@[::1]:2200")
    }

    @Test func rejectsNonRemoteAndBadPorts() {
        #expect(RemoteURL.parse(typed: "/Users/x") == nil)
        #expect(RemoteURL.parse(typed: "http://host/") == nil)
        #expect(RemoteURL.parse(typed: "sftp://host:99999/") == nil)
        #expect(RemoteURL.parse(typed: "sftp://host:abc/") == nil)
        #expect(RemoteURL.parse(typed: "sftp:///path") == nil)
    }

    @Test func panelURLRoundTripWithDiacritics() throws {
        let endpoint = RemoteEndpoint(proto: .sftp, host: "h", user: "ž")
        let url = RemoteURL.make(endpoint, path: "/a b/žluťoučký kůň")
        let parsed = try #require(RemoteURL.parse(url))
        #expect(parsed.endpoint == endpoint)
        #expect(parsed.path == "/a b/žluťoučký kůň")
        #expect(RemoteURL.parse(url.deletingLastPathComponent())?.path == "/a b")
        #expect(RemoteURL.isRemote(url))
        #expect(!RemoteURL.isRemote(URL(filePath: "/tmp")))
    }

    @Test func remotePaths() {
        #expect(RemotePath.join("/", "a") == "/a")
        #expect(RemotePath.join("/a", "b") == "/a/b")
        #expect(RemotePath.parent("/a/b") == "/a")
        #expect(RemotePath.parent("/a") == "/")
        #expect(RemotePath.parent("/") == "/")
        #expect(RemotePath.normalize("a//b/./c/../d/") == "/a/b/d")
    }

    @Test func historyScrubbing() {
        #expect(Credentials.scrub("cd ftp://jan:tajné@host/x") == "cd ftp://jan@host/x")
    }
}

/// In-memory server: paths → entries.
actor FakeFileSystem: RemoteFileSystem {
    let endpoint: RemoteEndpoint
    var tree: [String: [RemoteEntry]]
    var isConnected = true
    var failNextWithDisconnect = false

    init(endpoint: RemoteEndpoint, tree: [String: [RemoteEntry]]) {
        self.endpoint = endpoint
        self.tree = tree
    }

    func dropConnection() { failNextWithDisconnect = true }

    func homeDirectory() async throws -> String { "/home" }

    func list(_ path: String) async throws -> [RemoteEntry] {
        if failNextWithDisconnect {
            failNextWithDisconnect = false
            isConnected = false
            throw RemoteError.disconnected
        }
        guard let entries = tree[path] else { throw RemoteError.notFound(path) }
        return entries
    }

    func info(_ path: String) async throws -> RemoteEntry? {
        tree[RemotePath.parent(path)]?.first { $0.name == (path as NSString).lastPathComponent }
    }

    func download(_ path: String, to local: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {}
    func upload(_ local: URL, to path: String, progress: @escaping @Sendable (Int64) -> Void) async throws {}
    func makeDirectory(_ path: String) async throws {}
    func removeFile(_ path: String) async throws {}
    func removeDirectory(_ path: String) async throws {}
    func rename(_ from: String, to: String) async throws {}
    func close() async { isConnected = false }
}

/// Records connects; logs in when the prompter answers `secret`.
final class FakeServer: Sendable {
    let endpoint = RemoteEndpoint(proto: .sftp, host: "server", user: "jan")
    let secret: String
    let connects = Mutex(0)
    let prompts = Mutex<[AuthPrompt]>([])
    let lastSession = Mutex<FakeFileSystem?>(nil)

    init(secret: String) { self.secret = secret }

    var connector: RemoteConnections.Connector {
        { [self] endpoint, _, prompter in
            connects.withLock { $0 += 1 }
            try await Task.sleep(for: .milliseconds(20))
            for attempt in 1...3 {
                let prompt = AuthPrompt.password(endpoint, attempt: attempt, message: "Password:")
                guard let answer = await prompter(prompt) else { throw RemoteError.cancelled }
                if answer == secret {
                    let fs = FakeFileSystem(endpoint: endpoint, tree: [
                        "/home": [
                            RemoteEntry(name: "a.txt", kind: .file, size: 10),
                            RemoteEntry(name: ".hidden", kind: .file, size: 1),
                            RemoteEntry(name: "dir", kind: .directory),
                            RemoteEntry(name: "link", kind: .symlink, targetIsDirectory: true),
                        ],
                        "/home/dir": [RemoteEntry(name: "b", kind: .file, size: 5), RemoteEntry(name: "sub", kind: .directory)],
                        "/home/dir/sub": [RemoteEntry(name: "c", kind: .file, size: 7)],
                    ])
                    lastSession.withLock { $0 = fs }
                    return fs
                }
            }
            throw RemoteError.authenticationFailed
        }
    }
}

import Synchronization

final class PromptLog<T: Sendable>: Sendable {
    let items: Mutex<[T]>
    init(_ items: [T] = []) { self.items = Mutex(items) }
    var all: [T] { items.withLock { $0 } }
    func append(_ item: T) { items.withLock { $0.append(item) } }
    func popFirst() -> T? { items.withLock { $0.isEmpty ? nil : $0.removeFirst() } }
}

@Suite struct RemoteConnectionsTests {
    private func make(secret: String = "héslo ✓", stored: String? = nil, replies: [PromptReply?] = [])
        async -> (RemoteConnections, FakeServer, MemoryPasswordStore, PromptLog<AuthPrompt>) {
        let server = FakeServer(secret: secret)
        let store = MemoryPasswordStore()
        if let stored { try? store.save(stored, for: server.endpoint) }
        let asked = PromptLog<AuthPrompt>()
        let queue = PromptLog<PromptReply?>(replies)
        let connections = RemoteConnections()
        connections.configure(connector: server.connector, prompter: { prompt in
            asked.append(prompt)
            return queue.popFirst() ?? nil
        }, passwords: store)
        return (connections, server, store, asked)
    }

    @Test func storedPasswordConnectsWithoutAsking() async throws {
        let (connections, server, _, asked) = await make(stored: "héslo ✓")
        _ = try await connections.session(for: server.endpoint)
        #expect(asked.all.isEmpty)
        #expect(await connections.connected == [server.endpoint])
    }

    @Test func wrongStoredPasswordAsksAndRemembers() async throws {
        let (connections, server, store, asked) = await make(stored: "staré", replies: [PromptReply("héslo ✓", remember: true)])
        _ = try await connections.session(for: server.endpoint)
        #expect(asked.all == [.password(server.endpoint, attempt: 2, message: "Password:")])
        #expect(store.password(for: server.endpoint) == "héslo ✓")
    }

    @Test func typedPasswordIsNotStoredUnlessAsked() async throws {
        let (connections, server, store, asked) = await make(replies: [PromptReply("héslo ✓")])
        _ = try await connections.session(for: server.endpoint)
        #expect(asked.all.count == 1)
        #expect(store.password(for: server.endpoint) == nil)

        // Disconnect + reconnect asks again (nothing stored).
        await connections.disconnect(server.endpoint)
        #expect(await connections.connected.isEmpty)
        await #expect(throws: RemoteError.cancelled) { try await connections.session(for: server.endpoint) }
    }

    @Test func oneShotPasswordIsTriedFirst() async throws {
        let (connections, server, _, asked) = await make(stored: "staré")
        _ = try await connections.session(for: server.endpoint, password: "héslo ✓")
        #expect(asked.all.isEmpty)
    }

    @Test func concurrentRequestsShareOneConnect() async throws {
        let (connections, server, _, _) = await make(stored: "héslo ✓")
        async let a = connections.session(for: server.endpoint)
        async let b = connections.session(for: server.endpoint)
        let (x, y) = try await (a, b)
        #expect(x === y)
        #expect(server.connects.withLock { $0 } == 1)
    }

    @Test func listResolvesHomeAndMapsEntries() async throws {
        let (connections, server, _, _) = await make(stored: "héslo ✓")
        let home = try await connections.resolve(RemoteLocation(endpoint: server.endpoint, path: ""))
        #expect(home.path == "/home")
        let items = try await connections.list(home, includeHidden: false)
        #expect(items.map(\.name) == ["a.txt", "dir", "link"])
        #expect(items[0].url.absoluteString == "sftp://jan@server/home/a.txt")
        #expect(items[0].size == 10)
        #expect(items[2].isDirectory && items[2].isSymlink)
        #expect(try await connections.list(home, includeHidden: true).count == 4)
        #expect(try await connections.totalSize(of: home) == 10 + 1 + 5 + 7)
    }

    @Test func droppedSessionReconnectsOnce() async throws {
        let (connections, server, _, _) = await make(stored: "héslo ✓")
        let home = RemoteLocation(endpoint: server.endpoint, path: "/home")
        _ = try await connections.list(home, includeHidden: false)
        await server.lastSession.withLock { $0 }?.dropConnection()
        let items = try await connections.list(home, includeHidden: false)
        #expect(items.count == 3)
        #expect(server.connects.withLock { $0 } == 2)
    }
}
