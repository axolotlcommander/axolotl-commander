// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Something that is using files: a localized operation name and the folders and files it touches.
public struct VolumeUser: Sendable, Hashable {
    public var title: String
    public var urls: [URL]

    public init(title: String, urls: [URL]) {
        self.title = title
        self.urls = urls
    }
}

public enum VolumeUse {
    /// True when `url` is the volume root or lies inside it (compared by standardized path).
    public static func isOnVolume(_ url: URL, root: URL) -> Bool {
        let r = root.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        if r == "/" { return false }
        return p == r || p.hasPrefix(r + "/")
    }

    /// The first user with any URL on the volume.
    public static func blocking(_ root: URL, users: [VolumeUser]) -> VolumeUser? {
        users.first { u in u.urls.contains { isOnVolume($0, root: root) } }
    }
}
