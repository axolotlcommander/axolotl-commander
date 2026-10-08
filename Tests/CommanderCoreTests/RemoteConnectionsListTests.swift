// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Synchronization
import Testing
@testable import CommanderCore

/// The list of opened connections behind the volume bar's server buttons (fake server only).
@Suite struct RemoteConnectionsListTests {
    private let secret = "tajné"

    /// Connections answering every prompt with "cancel"; logins go through a typed password.
    private func make() -> (RemoteConnections, FakeServer) {
        let server = FakeServer(secret: secret)
        let connections = RemoteConnections()
        connections.configure(connector: server.connector, prompter: { _ in nil }, passwords: MemoryPasswordStore())
        return (connections, server)
    }

    private func endpoint(_ host: String, user: String = "jan") -> RemoteEndpoint {
        RemoteEndpoint(proto: .sftp, host: host, user: user)
    }

    /// Records change notifications of one instance; remove the observer when done.
    private func observe(_ connections: RemoteConnections) -> (PromptLog<Int>, any NSObjectProtocol) {
        let log = PromptLog<Int>()
        let token = NotificationCenter.default.addObserver(
            forName: RemoteConnections.didChangeNotification, object: connections, queue: nil
        ) { _ in log.append(1) }
        return (log, token)
    }

    @Test func listKeepsOpeningOrder() async throws {
        let (connections, _) = make()
        let zeta = endpoint("zeta"), alpha = endpoint("alpha")
        _ = try await connections.session(for: zeta, password: secret)
        _ = try await connections.session(for: alpha, password: secret)
        _ = try await connections.session(for: zeta)
        #expect(await connections.openedEndpoints == [zeta, alpha])
        #expect(await connections.connected == [alpha, zeta])
    }

    @Test func failedLoginIsNotListed() async throws {
        let (connections, _) = make()
        let (changes, token) = observe(connections)
        defer { NotificationCenter.default.removeObserver(token) }
        await #expect(throws: RemoteError.cancelled) {
            try await connections.session(for: endpoint("server"), password: "wrong")
        }
        #expect(await connections.openedEndpoints.isEmpty)
        #expect(changes.all.count == 0)
    }

    @Test func droppedSessionStaysListedUntilDisconnect() async throws {
        let (connections, server) = make()
        let host = endpoint("server")
        _ = try await connections.session(for: host, password: secret)
        // The session drops and logging in again is cancelled.
        await server.lastSession.withLock { $0 }?.close()
        await #expect(throws: RemoteError.cancelled) { try await connections.session(for: host) }
        #expect(await connections.connected.isEmpty)
        #expect(await connections.openedEndpoints == [host])

        // Disconnecting without a session still removes it.
        await connections.disconnect(host)
        #expect(await connections.openedEndpoints.isEmpty)
    }

    @Test func reconnectAfterDropKeepsThePosition() async throws {
        let (connections, server) = make()
        let first = endpoint("first"), second = endpoint("second")
        _ = try await connections.session(for: first, password: secret)
        let dropped = server.lastSession.withLock { $0 }
        _ = try await connections.session(for: second, password: secret)
        await dropped?.close()
        _ = try await connections.session(for: first, password: secret)
        #expect(await connections.openedEndpoints == [first, second])
    }

    @Test func changesArePosted() async throws {
        let (connections, _) = make()
        let (changes, token) = observe(connections)
        defer { NotificationCenter.default.removeObserver(token) }
        let one = endpoint("one"), two = endpoint("two")
        _ = try await connections.session(for: one, password: secret)
        #expect(changes.all.count == 1)
        _ = try await connections.session(for: one)
        #expect(changes.all.count == 1)
        await connections.disconnect(one)
        #expect(changes.all.count == 2)
        await connections.disconnect(one)
        #expect(changes.all.count == 2)

        _ = try await connections.session(for: one, password: secret)
        _ = try await connections.session(for: two, password: secret)
        #expect(changes.all.count == 4)
        await connections.disconnectAll()
        #expect(changes.all.count == 5)
        #expect(await connections.openedEndpoints.isEmpty)
        #expect(await connections.connected.isEmpty)
    }
}
