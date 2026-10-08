// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

public enum OperationError: Error, Equatable {
    /// Copy/move onto itself (hard link, symlink, /tmp vs /private/tmp, …).
    case sameFile(URL)
    /// Folder into itself or one of its descendants.
    case intoItself(URL)
    /// Identity cannot be proven different; the destructive part is refused.
    case identityUnknown(URL)
    /// Move would delete through a directory symlink or after an incomplete traversal.
    case sourceKeptBecauseOfLink(URL)
    /// Target name already used by a different file (makeDirectory, rename).
    case alreadyExists(URL)
    /// Name contains "/" or NUL, or is "." / "..".
    case invalidName(String)
    case path(PathError)
    case io(String)
    case cancelled

    static func wrap(_ error: any Error) -> OperationError {
        if let e = error as? OperationError { return e }
        if let e = error as? PathError { return .path(e) }
        if error is CancellationError { return .cancelled }
        return .io(String(describing: error))
    }
}

public enum ConflictResolution: Sendable, Equatable {
    case overwrite, overwriteAll, skip, skipAll, rename(String), cancel
}

/// What a conflict dialog shows about one side.
public struct FileItemInfo: Sendable, Hashable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    /// nil for directories.
    public let size: Int64?
    public let modificationDate: Date?

    public init(url: URL, name: String? = nil, isDirectory: Bool, size: Int64?, modificationDate: Date?) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.isDirectory = isDirectory
        self.size = size
        self.modificationDate = modificationDate
    }

    init(path: String, stat: FileStat) {
        self.init(
            url: FSPath.url(path),
            name: FSPath.name(path),
            isDirectory: stat.isDirectory,
            size: stat.isDirectory ? nil : stat.size,
            modificationDate: stat.modificationDate
        )
    }
}

public struct Conflict: Sendable {
    public let source: FileItemInfo
    public let destination: FileItemInfo

    public init(source: FileItemInfo, destination: FileItemInfo) {
        self.source = source
        self.destination = destination
    }
}

public struct OperationProgress: Sendable, Equatable {
    public var totalBytes: Int64
    public var doneBytes: Int64
    public var totalItems: Int
    public var doneItems: Int
    public var currentName: String

    public init(totalBytes: Int64, doneBytes: Int64, totalItems: Int, doneItems: Int, currentName: String) {
        self.totalBytes = totalBytes
        self.doneBytes = doneBytes
        self.totalItems = totalItems
        self.doneItems = doneItems
        self.currentName = currentName
    }
}

public enum TransferKind: Sendable {
    case copy, move
}

public struct TransferRequest: Sendable {
    public var kind: TransferKind
    public var sources: [URL]
    public var destinationDirectory: URL
    /// Windows-style target mask applied to file names (not directory names), see `NameMask`.
    public var nameMask: String

    public init(kind: TransferKind, sources: [URL], destinationDirectory: URL, nameMask: String = "*.*") {
        self.kind = kind
        self.sources = sources
        self.destinationDirectory = destinationDirectory
        self.nameMask = nameMask
    }
}

public struct TransferReport: Sendable, Equatable {
    /// Files and symlinks placed at the destination.
    public let copied: Int
    /// Source items skipped (conflict skip, unsupported type, unreadable).
    public let skipped: [URL]
    /// Move sources that were not deleted (directory symlink inside, something
    /// skipped, incomplete traversal, or content left behind).
    public let keptSources: [URL]

    public init(copied: Int, skipped: [URL], keptSources: [URL]) {
        self.copied = copied
        self.skipped = skipped
        self.keptSources = keptSources
    }
}

/// Validates a single file name (not a path).
enum NameCheck {
    static func validate(_ name: String) throws(OperationError) {
        if name.isEmpty { throw .path(.empty) }
        if name == "." || name == ".." || name.contains("/") || name.utf8.contains(0) {
            throw .invalidName(name)
        }
        if name.utf8.count > PathRules.maxNameBytes { throw .path(.nameTooLong(name)) }
    }

    static func validate(path: String) throws(OperationError) {
        do { try PathRules.validate(path) } catch { throw .path(error) }
    }
}
