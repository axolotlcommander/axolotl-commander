// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Which extra items the volume bar shows (Settings → Appearance); volumes are always shown.
public struct VolumeBarSettings: Equatable, Sendable {
    public static let homeKey = "volumeBar.showHome"
    public static let iCloudKey = "volumeBar.showICloud"
    public static let networkKey = "volumeBar.showNetwork"
    public static let serversKey = "volumeBar.showServers"

    public var showHome = false
    public var showICloud = true
    public var showNetwork = true
    public var showServers = true

    public init(showHome: Bool = false, showICloud: Bool = true, showNetwork: Bool = true, showServers: Bool = true) {
        self.showHome = showHome
        self.showICloud = showICloud
        self.showNetwork = showNetwork
        self.showServers = showServers
    }

    /// Reads the saved choices; `value` is a defaults lookup by key (a missing key keeps the default).
    public init(value: (String) -> Any?) {
        self.init()
        showHome = value(Self.homeKey) as? Bool ?? showHome
        showICloud = value(Self.iCloudKey) as? Bool ?? showICloud
        showNetwork = value(Self.networkKey) as? Bool ?? showNetwork
        showServers = value(Self.serversKey) as? Bool ?? showServers
    }
}

/// What the volume bar above a panel shows, in order, and which item is pressed.
public enum VolumeBarModel {
    public enum Item: Equatable, Sendable {
        case volume(VolumeInfo)
        case home(URL)
        case iCloud(URL)
        case network
        case server(RemoteEndpoint, label: String)
    }

    /// Volumes, then Home, iCloud Drive, Network and the server connections, each when the
    /// settings show it. `iCloud` is nil when iCloud Drive is not set up.
    public static func items(volumes: [VolumeInfo], home: URL, iCloud: URL?,
                             servers: [RemoteEndpoint], settings: VolumeBarSettings) -> [Item] {
        var items = volumes.map(Item.volume)
        if settings.showHome { items.append(.home(home)) }
        if settings.showICloud, let iCloud { items.append(.iCloud(iCloud)) }
        if settings.showNetwork { items.append(.network) }
        if settings.showServers {
            let labels = ServerLabels.labels(for: servers)
            var seen = Set<RemoteEndpoint>()
            for endpoint in servers where seen.insert(endpoint).inserted {
                items.append(.server(endpoint, label: labels[endpoint] ?? endpoint.host))
            }
        }
        return items
    }

    /// The item to show pressed: a server location presses its server; a local one presses
    /// iCloud Drive when inside it, Home when exactly the home folder, otherwise its volume
    /// (`volumeRoot`, the mount point containing `local`).
    public static func pressed(local: URL?, remote: RemoteEndpoint?, volumeRoot: URL?, items: [Item]) -> Int? {
        if let remote {
            return items.firstIndex { if case .server(remote, _) = $0 { true } else { false } }
        }
        guard let local else { return nil }
        let path = normalized(local)
        if let index = items.firstIndex(where: {
            if case .iCloud(let url) = $0 { contains(normalized(url), path) } else { false }
        }) {
            return index
        }
        if let index = items.firstIndex(where: { if case .home(let url) = $0 { normalized(url) == path } else { false } }) {
            return index
        }
        guard let volumeRoot else { return nil }
        let root = normalized(volumeRoot)
        return items.firstIndex { if case .volume(let volume) = $0 { normalized(volume.url) == root } else { false } }
    }

    /// The path without a trailing slash ("/" stays).
    private static func normalized(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    private static func contains(_ folder: String, _ path: String) -> Bool {
        path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/")
    }
}
