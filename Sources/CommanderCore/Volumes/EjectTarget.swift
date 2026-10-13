// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// What the Eject command acts on for a panel: a volume or a server connection.
public enum EjectTarget: Hashable, Sendable {
    case volume(VolumeInfo)
    case server(RemoteEndpoint)

    /// `archiveFile` is the archive being browsed, if any; `rootOf` maps a URL to its volume root.
    public static func resolve(
        location: URL, archiveFile: URL?, isNetwork: Bool, remoteEndpoint: RemoteEndpoint?,
        volumes: [VolumeInfo], rootOf: (URL) -> URL
    ) -> EjectTarget? {
        if isNetwork { return nil }
        if let remoteEndpoint { return .server(remoteEndpoint) }
        let root = rootOf(archiveFile ?? location).standardizedFileURL.path
        guard let v = volumes.first(where: { $0.url.standardizedFileURL.path == root }), Ejectability.canEject(v)
        else { return nil }
        return .volume(v)
    }

    /// Menu title for the command.
    public static func title(for target: EjectTarget?) -> String {
        switch target {
        case .volume(let v): String(localized: "Eject “\(v.name)”")
        case .server(let e): String(localized: "Disconnect “\(RemoteURL.displayName(e))”")
        case nil: String(localized: "Eject Volume")
        }
    }
}
