// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// What one side of a sync item holds.
public struct SyncSide: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case file, folder
        case link(target: String)
    }

    public var kind: Kind
    /// File size; a folder facing nothing (or a non-folder): the total of the files inside, else 0.
    public var size: Int64
    /// 1 for a file or link; a folder facing nothing (or a non-folder): the files inside, else 0.
    public var fileCount: Int
    public var modified: Date?

    public init(kind: Kind, size: Int64, fileCount: Int, modified: Date?) {
        self.kind = kind
        self.size = size
        self.fileCount = fileCount
        self.modified = modified
    }

    public var isFolder: Bool { kind == .folder }

    /// File, folder or link, ignoring the link target.
    func sameKind(as other: SyncSide) -> Bool {
        switch (kind, other.kind) {
        case (.file, .file), (.folder, .folder), (.link, .link): true
        default: false
        }
    }
}

public enum SyncState: Hashable, Sendable {
    case onlyLeft, onlyRight, equal, leftNewer, rightNewer
    /// No newer side: size or content differs, the date is not compared, or the kinds differ.
    case different
    /// Unreadable folder, unreadable file or a name clash; never touched.
    case error(String)
}

/// What the run does with an item.
public enum SyncAction: Hashable, Sendable {
    case none
    /// Make the right side like the left.
    case toRight
    /// Make the left side like the right.
    case toLeft
}

/// What an action does on disk.
public enum SyncEffect: Hashable, Sendable {
    case nothing, copy, overwrite
    /// The target has another kind: it goes to the Trash first, then the copy.
    case replace
    /// The source lacks the item: the target goes to the Trash.
    case delete
}

public struct SyncItem: Hashable, Sendable, Identifiable {
    /// Relative, "/"-separated; the left spelling when the left side has it.
    public var path: String
    public var id: String { path }
    public var name: String
    /// 0 for the top level.
    public var depth: Int
    public var left: SyncSide?
    public var right: SyncSide?
    public var state: SyncState
    public var defaultAction: SyncAction
    public var action: SyncAction
    public var excluded: Bool
    /// The relative path as spelled on each side. The side lacking the item uses its own spelling
    /// of the parent folders and the other side's name.
    public var leftPath: String
    public var rightPath: String

    public init(path: String, left: SyncSide?, right: SyncSide?, state: SyncState,
                defaultAction: SyncAction = .none, action: SyncAction? = nil, excluded: Bool = false,
                leftPath: String? = nil, rightPath: String? = nil) {
        self.path = path
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        name = parts.last.map(String.init) ?? path
        depth = max(parts.count - 1, 0)
        self.left = left
        self.right = right
        self.state = state
        self.defaultAction = defaultAction
        self.action = action ?? defaultAction
        self.excluded = excluded
        self.leftPath = leftPath ?? path
        self.rightPath = rightPath ?? path
    }

    public func side(_ s: Side) -> SyncSide? {
        s == .left ? left : right
    }

    public func path(on s: Side) -> String {
        s == .left ? leftPath : rightPath
    }

    public var isError: Bool {
        if case .error = state { return true }
        return false
    }
}

/// The result of comparing two folder trees.
public struct SyncComparison: Sendable {
    public var left: URL
    public var right: URL
    public var options: SyncOptions
    public var rules: NameRules
    /// Whether hidden items were compared (Show Hidden Files at the time).
    public var includeHidden: Bool
    /// Sorted by path (`NameRules.order` per component), a folder before its contents.
    public var items: [SyncItem]

    public init(left: URL, right: URL, options: SyncOptions, rules: NameRules, includeHidden: Bool = false,
                items: [SyncItem]) {
        self.left = left
        self.right = right
        self.options = options
        self.rules = rules
        self.includeHidden = includeHidden
        self.items = items
    }

    public func root(_ side: Side) -> URL {
        side == .left ? left : right
    }

    /// Where the item is (or would be) on `side`.
    public func url(of item: SyncItem, on side: Side) -> URL {
        root(side).appending(path: item.path(on: side), directoryHint: .notDirectory)
    }
}

/// How far comparing is.
public struct SyncProgress: Sendable, Equatable {
    /// Items listed so far on both sides.
    public var scanned: Int
    /// The folder being read, relative to the compared folders ("" for the top).
    public var folder: String
    /// Bytes read by the content comparison.
    public var bytesRead: Int64

    public init(scanned: Int, folder: String, bytesRead: Int64) {
        self.scanned = scanned
        self.folder = folder
        self.bytesRead = bytesRead
    }
}
