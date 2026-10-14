// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// The size of the cells in the Thumbnails view (spec 025), one setting for the whole app.
public enum ThumbnailSize: String, CaseIterable, Sendable {
    case small, medium, large

    public static let key = "panel.thumbnailSize"
    public static let `default` = ThumbnailSize.medium

    /// The side of the square the picture is fitted into.
    public var points: Int {
        switch self {
        case .small: 64
        case .medium: 128
        case .large: 256
        }
    }

    /// The next size up or down; nil at the ends.
    public var larger: ThumbnailSize? { Self.allCases.firstIndex(of: self).flatMap { Self.allCases[safe: $0 + 1] } }
    public var smaller: ThumbnailSize? { Self.allCases.firstIndex(of: self).flatMap { Self.allCases[safe: $0 - 1] } }

    public init(storage: String?) { self = storage.flatMap(Self.init(rawValue:)) ?? .default }

    public static func saved(_ defaults: UserDefaults = .standard) -> ThumbnailSize {
        ThumbnailSize(storage: defaults.string(forKey: key))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// One picture made for an item: a changed file (another date) or another size is another picture.
public struct ThumbnailKey: Hashable, Sendable {
    public let path: String
    public let modified: Date?
    public let size: ThumbnailSize

    public init(path: String, modified: Date?, size: ThumbnailSize) {
        self.path = path
        self.modified = modified
        self.size = size
    }
}

/// Which items get previews: only files the system can read directly, never members of archives, server
/// files or the Network folder, so nothing is extracted or downloaded for a preview.
public enum ThumbnailPolicy {
    public static func allowsPreviews(inArchive: Bool, onServer: Bool, isNetwork: Bool) -> Bool {
        !inArchive && !onServer && !isNetwork
    }

    /// A file URL that is not a path inside an archive (search results and branch view list items from
    /// several places).
    public static func allowsPreview(of url: URL,
                                     isRegularFile: (URL) -> Bool = ArchivePath.defaultIsRegularFile) -> Bool {
        url.isFileURL && ArchivePath.split(url, isRegularFile: isRegularFile).map { $0.inner.isEmpty } ?? true
    }
}

/// Pictures kept in memory up to a total cost; the least recently used go first. Nothing is written to disk.
public struct ThumbnailCache<Value> {
    private struct Entry {
        var value: Value
        var cost: Int
        var older: ThumbnailKey?
        var newer: ThumbnailKey?
    }

    public let costLimit: Int
    public private(set) var totalCost = 0
    private var entries: [ThumbnailKey: Entry] = [:]
    private var oldest: ThumbnailKey?
    private var newest: ThumbnailKey?

    public init(costLimit: Int) { self.costLimit = costLimit }

    public var count: Int { entries.count }

    /// The picture for the key, which becomes the most recently used one.
    public mutating func value(for key: ThumbnailKey) -> Value? {
        guard let entry = entries[key] else { return nil }
        unlink(key)
        link(key)
        return entry.value
    }

    public func contains(_ key: ThumbnailKey) -> Bool { entries[key] != nil }

    /// Stores the picture as the most recently used one and drops the oldest ones while over the limit. A
    /// picture larger than the whole limit is not kept.
    public mutating func insert(_ value: Value, for key: ThumbnailKey, cost: Int) {
        remove(key)
        guard cost <= costLimit else { return }
        entries[key] = Entry(value: value, cost: cost)
        totalCost += cost
        link(key)
        while totalCost > costLimit, let first = oldest { remove(first) }
    }

    public mutating func removeAll() {
        entries = [:]
        oldest = nil
        newest = nil
        totalCost = 0
    }

    private mutating func remove(_ key: ThumbnailKey) {
        guard let entry = entries[key] else { return }
        unlink(key)
        totalCost -= entry.cost
        entries[key] = nil
    }

    private mutating func unlink(_ key: ThumbnailKey) {
        guard let entry = entries[key] else { return }
        if let older = entry.older { entries[older]?.newer = entry.newer } else { oldest = entry.newer }
        if let newer = entry.newer { entries[newer]?.older = entry.older } else { newest = entry.older }
        entries[key]?.older = nil
        entries[key]?.newer = nil
    }

    private mutating func link(_ key: ThumbnailKey) {
        entries[key]?.older = newest
        entries[key]?.newer = nil
        if let newest { entries[newest]?.newer = key } else { oldest = key }
        newest = key
    }
}

/// Decides which preview requests run: at most `limit` at once, the most wanted first (the visible cells
/// before the margin around them), and a request whose cell is no longer wanted is cancelled.
public struct ThumbnailQueue: Sendable {
    public let limit: Int
    public private(set) var running: [ThumbnailKey] = []
    private var wanted: [ThumbnailKey] = []

    public init(limit: Int) { self.limit = max(1, limit) }

    /// The keys wanted now, most important first (keys already made are left out by the caller). Returns
    /// the requests to start and those to cancel.
    public mutating func want(_ keys: [ThumbnailKey]) -> (start: [ThumbnailKey], cancel: [ThumbnailKey]) {
        var seen = Set<ThumbnailKey>()
        wanted = keys.filter { seen.insert($0).inserted }
        let cancel = running.filter { !seen.contains($0) }
        running.removeAll { !seen.contains($0) }
        return (fill(), cancel)
    }

    /// A request ended (made or failed): it is not asked again, and the next wanted ones start.
    public mutating func finished(_ key: ThumbnailKey) -> [ThumbnailKey] {
        running.removeAll { $0 == key }
        wanted.removeAll { $0 == key }
        return fill()
    }

    private mutating func fill() -> [ThumbnailKey] {
        var start: [ThumbnailKey] = []
        for key in wanted where running.count < limit && !running.contains(key) {
            running.append(key)
            start.append(key)
        }
        return start
    }
}
