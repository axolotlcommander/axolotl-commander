// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// One row of a panel listing. `name` is exactly what the filesystem returned
/// (no Unicode normalization); compare names through `NameRules`.
public struct FileItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    /// The synthetic ".." row.
    public let isParent: Bool
    /// True for directories and for symlinks that resolve to directories.
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    /// nil for directories.
    public let size: Int64?
    public let modificationDate: Date?

    public var id: String { name }

    public init(
        url: URL,
        name: String? = nil,
        isParent: Bool = false,
        isDirectory: Bool = false,
        isSymlink: Bool = false,
        isPackage: Bool = false,
        isHidden: Bool = false,
        size: Int64? = nil,
        modificationDate: Date? = nil
    ) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.isParent = isParent
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.size = size
        self.modificationDate = modificationDate
    }

    /// The ".." row for `directory`; its URL is the parent directory.
    public static func parent(of directory: URL) -> FileItem {
        FileItem(
            url: directory.deletingLastPathComponent(),
            name: "..",
            isParent: true,
            isDirectory: true
        )
    }

    /// Text after the last dot (files only, and only when the dot is not the
    /// first character). Empty for directories and the parent row.
    public var fileExtension: String {
        guard !isDirectory || isPackage, !isParent, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...])
    }

    /// Name without ".ext" for files and packages (“Mail” of “Mail.app”); the full name for folders.
    public var baseName: String {
        guard !isDirectory || isPackage, !isParent, let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
}
