// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Network

/// Servers announced on the local network over Bonjour (SMB, AFP, SFTP). Browsing starts with the
/// first request and then runs while the app runs; it only listens to and sends the standard
/// discovery queries, it never connects to a server.
public final class NetworkDiscovery: @unchecked Sendable {
    public static let shared = NetworkDiscovery()

    /// Posted (on any thread) after the set of services changed.
    public static let didChangeNotification = Notification.Name("NetworkDiscoveryDidChange")

    private let lock = NSLock()
    private var browsers: [NWBrowser] = []
    private var found: [NetworkPlaces.Service.Kind: Set<NetworkPlaces.Service>] = [:]
    private let queue = DispatchQueue(label: "NetworkDiscovery")

    private init() {}

    /// The services found so far, sorted by name; starts browsing on the first call.
    public func services() -> [NetworkPlaces.Service] {
        start()
        lock.lock()
        defer { lock.unlock() }
        return found.values.flatMap(\.self).sorted { a, b in
            let order = a.name.localizedStandardCompare(b.name)
            return order == .orderedSame ? a.kind.rawValue < b.kind.rawValue : order == .orderedAscending
        }
    }

    /// The rows of the Network folder right now.
    public func items() -> [FileItem] {
        NetworkPlaces.items(services: services(), volumes: Volumes.mounted())
    }

    private func start() {
        lock.lock()
        defer { lock.unlock() }
        guard browsers.isEmpty else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        for kind in NetworkPlaces.Service.Kind.allCases {
            let browser = NWBrowser(for: .bonjour(type: kind.type, domain: "local."), using: parameters)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.update(kind, results)
            }
            browser.start(queue: queue)
            browsers.append(browser)
        }
    }

    private func update(_ kind: NetworkPlaces.Service.Kind, _ results: Set<NWBrowser.Result>) {
        var services = Set<NetworkPlaces.Service>()
        for result in results {
            if case .service(let name, _, let domain, _) = result.endpoint {
                services.insert(NetworkPlaces.Service(name: name, kind: kind, domain: domain.isEmpty ? "local." : domain))
            }
        }
        lock.lock()
        let changed = found[kind] != services
        found[kind] = services
        lock.unlock()
        if changed { NotificationCenter.default.post(name: Self.didChangeNotification, object: nil) }
    }
}
