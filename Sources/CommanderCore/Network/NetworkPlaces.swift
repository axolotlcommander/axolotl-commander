// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// The virtual Network folder of a panel: servers announced on the local network (Bonjour) and the
/// network volumes mounted in macOS. It is a place to look and to open from, never a folder on disk.
public enum NetworkPlaces {
    /// The panel location of the Network folder.
    public static let location = URL(string: "network:/")!

    public static func isNetwork(_ url: URL) -> Bool { url.scheme == "network" }

    /// An announced server.
    public struct Service: Hashable, Sendable {
        public enum Kind: String, CaseIterable, Sendable {
            case smb, afp, sftp

            /// The Bonjour service type.
            public var type: String {
                switch self {
                case .smb: "_smb._tcp"
                case .afp: "_afpovertcp._tcp"
                case .sftp: "_sftp-ssh._tcp"
                }
            }

            public init?(type: String) {
                let bare = type.hasSuffix(".") ? String(type.dropLast()) : type
                guard let kind = Self.allCases.first(where: { $0.type == bare }) else { return nil }
                self = kind
            }
        }

        public let name: String
        public let kind: Kind
        public let domain: String

        public init(name: String, kind: Kind, domain: String = "local.") {
            self.name = name
            self.kind = kind
            self.domain = domain
        }

        /// The row's URL: `network:/smb/<name>` (domain kept in the query when not `local.`).
        public var url: URL {
            var components = URLComponents()
            components.scheme = "network"
            components.path = "/\(kind.rawValue)/\(name)"
            if domain != "local." { components.queryItems = [URLQueryItem(name: "domain", value: domain)] }
            return components.url ?? NetworkPlaces.location
        }
    }

    /// The rows of the Network folder: one per server and protocol (several interfaces merged), named
    /// `<name>.<protocol>` so the extension column shows the protocol, then one folder row per mounted
    /// network volume.
    public static func items(services: some Sequence<Service>, volumes: [VolumeInfo]) -> [FileItem] {
        var seen = Set<Service>()
        var rows: [FileItem] = []
        for service in services where seen.insert(service).inserted {
            rows.append(FileItem(url: service.url, name: "\(service.name).\(service.kind.rawValue)"))
        }
        for volume in volumes where volume.isNetwork {
            rows.append(FileItem(url: volume.url, name: volume.name, isDirectory: true))
        }
        return rows
    }

    /// The server a row stands for; nil for volume rows and other URLs.
    public static func service(of url: URL) -> Service? {
        guard isNetwork(url), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let parts = components.path.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, let kind = Service.Kind(rawValue: String(parts[0])) else { return nil }
        let domain = components.queryItems?.first { $0.name == "domain" }?.value ?? "local."
        return Service(name: String(parts[1]), kind: kind, domain: domain)
    }
}
