// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// Where panels were on each server connection, so a server button returns there: the folder
/// this panel visited last, else the folder any panel visited last, else the login folder.
/// Kept in memory only.
public struct ConnectionPlaces<PanelID: Hashable> {
    private var byPanel: [RemoteEndpoint: [PanelID: String]] = [:]
    private var latest: [RemoteEndpoint: String] = [:]

    public init() {}

    /// Records `location` as this panel's and the connection's last folder. A location whose
    /// path is not known yet (the login folder before it is resolved) is ignored.
    public mutating func visit(_ location: RemoteLocation, panel: PanelID) {
        guard !location.path.isEmpty else { return }
        byPanel[location.endpoint, default: [:]][panel] = location.path
        latest[location.endpoint] = location.path
    }

    /// An empty path stands for the login folder.
    public func place(for endpoint: RemoteEndpoint, panel: PanelID) -> RemoteLocation {
        RemoteLocation(endpoint: endpoint, path: byPanel[endpoint]?[panel] ?? latest[endpoint] ?? "")
    }

    public mutating func forget(_ endpoint: RemoteEndpoint) {
        byPanel[endpoint] = nil
        latest[endpoint] = nil
    }
}

extension ConnectionPlaces: Sendable where PanelID: Sendable {}
