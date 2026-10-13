// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// The content of the Disconnect sheet: servers, network volumes and ejectable disks.
public enum DisconnectList {
    public struct Item: Identifiable, Hashable, Sendable {
        public enum Kind: Hashable, Sendable {
            case server(RemoteEndpoint)
            case volume(VolumeInfo)
        }

        public var kind: Kind
        public var name: String
        public var detail: String

        public var id: String {
            switch kind {
            case .server(let e): "server:\(e.proto.rawValue)://\(RemoteURL.displayName(e))"
            case .volume(let v): "volume:\(v.url.standardizedFileURL.path)"
            }
        }
    }

    public struct Section: Identifiable, Hashable, Sendable {
        public enum Title: Hashable, Sendable { case servers, networkVolumes, disks }
        public var title: Title
        public var items: [Item]
        public var id: Title { title }
    }

    public static func sections(servers: [RemoteEndpoint], volumes: [VolumeInfo]) -> [Section] {
        let serverItems = servers.map {
            Item(kind: .server($0), name: RemoteURL.displayName($0), detail: "\($0.proto.rawValue)://\(RemoteURL.displayName($0))")
        }
        let ejectable = volumes.filter(Ejectability.canEject)
        let net = ejectable.filter(\.isNetwork).map {
            Item(kind: .volume($0), name: $0.name, detail: String(localized: "Network Volume"))
        }
        let disks = ejectable.filter { !$0.isNetwork }.map {
            Item(kind: .volume($0), name: $0.name, detail: String(localized: "External Disk"))
        }
        return [
            Section(title: .servers, items: serverItems),
            Section(title: .networkVolumes, items: net),
            Section(title: .disks, items: disks),
        ].filter { !$0.items.isEmpty }
    }

    /// The item matching the panel's eject target, if listed.
    public static func preChecked(_ target: EjectTarget?, in sections: [Section]) -> Item.ID? {
        guard let target else { return nil }
        return sections.lazy.flatMap(\.items).first {
            switch (target, $0.kind) {
            case (.server(let a), .server(let b)): a == b
            case (.volume(let a), .volume(let b)): a.url == b.url
            default: false
            }
        }?.id
    }

    /// "Disconnect" when every checked item is a server, otherwise "Eject".
    public static func confirmTitle(checked: [Item]) -> String {
        let allServers = !checked.isEmpty && checked.allSatisfy { if case .server = $0.kind { true } else { false } }
        return allServers ? String(localized: "Disconnect") : String(localized: "Eject")
    }

    public static func isEnabled(servers: [RemoteEndpoint], volumes: [VolumeInfo]) -> Bool {
        !servers.isEmpty || volumes.contains(where: Ejectability.canEject)
    }
}
