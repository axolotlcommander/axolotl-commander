// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// What the quick view panel previews for the active panel's cursor item.
public enum QuickViewSubject: Equatable, Sendable {
    /// A file, package or folder on disk.
    case item(URL)
    /// Items in archives, on servers and in the Network folder have no preview.
    case unavailable
    /// An empty panel.
    case nothing

    /// ".." previews the panel's own folder.
    public static func subject(cursor: FileItem?, location: URL, inArchive: Bool, onServer: Bool,
                               isNetwork: Bool) -> QuickViewSubject {
        guard let cursor else { return .nothing }
        if inArchive || onServer || isNetwork { return .unavailable }
        return .item(cursor.isParent ? location : cursor.url)
    }
}
