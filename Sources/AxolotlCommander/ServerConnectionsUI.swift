// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The open server connections as the windows show them: the list in opening order with
/// labels (kept in step with `RemoteConnections`), the last folder of each panel on each
/// connection, and disconnecting with every panel on the closed connection going home.
@MainActor
final class ServerConnectionsUI {
    static let shared = ServerConnectionsUI()

    /// Posted on the main thread after `opened` changed.
    static let didChange = Notification.Name("ServerConnectionsUI.didChange")

    /// Open connections in opening order, including dropped ones until they are disconnected.
    private(set) var opened: [RemoteEndpoint] = []
    private(set) var labels: [RemoteEndpoint: String] = [:]
    private var places = ConnectionPlaces<ObjectIdentifier>()
    private var generation = 0
    private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: RemoteConnections.didChangeNotification, object: RemoteConnections.shared, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Fetches the list again; when several fetches overlap, only the newest one counts.
    private func refresh() {
        generation += 1
        let current = generation
        Task {
            let list = await RemoteConnections.shared.openedEndpoints
            guard current == generation, list != opened else { return }
            opened = list
            labels = ServerLabels.labels(for: list)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    func label(for endpoint: RemoteEndpoint) -> String { labels[endpoint] ?? endpoint.host }

    /// The full address without a password: `sftp://user@host:port`.
    func address(of endpoint: RemoteEndpoint) -> String {
        "\(endpoint.proto.rawValue)://\(RemoteURL.displayName(endpoint))"
    }

    func visit(_ location: RemoteLocation, panel: PanelViewController) {
        places.visit(location, panel: ObjectIdentifier(panel))
    }

    /// Where a server button takes `panel`: its last folder there, else any panel's, else the
    /// login folder (empty path).
    func place(for endpoint: RemoteEndpoint, panel: PanelViewController) -> RemoteLocation {
        places.place(for: endpoint, panel: ObjectIdentifier(panel))
    }

    /// Closes the connections without asking; every panel of every main window on one of
    /// them shows the home folder. Used by the Disconnect dialog and the server buttons.
    func disconnect(_ endpoints: Set<RemoteEndpoint>) async {
        for endpoint in endpoints {
            await RemoteConnections.shared.disconnect(endpoint)
            places.forget(endpoint)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        for controller in NSApp.windows.compactMap({ $0.windowController as? MainWindowController }) {
            for panel in [controller.left, controller.right] {
                guard let remote = RemoteURL.parse(panel.model.location), endpoints.contains(remote.endpoint) else { continue }
                panel.go(to: home)
            }
        }
    }
}
