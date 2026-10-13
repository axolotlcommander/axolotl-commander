// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Darwin

/// What a run will do: every item with an effect (excluded and `none` items left out).
public struct SyncPlan: Sendable {
    public struct Step: Hashable, Sendable {
        public var item: SyncItem
        public var effect: SyncEffect
        public var target: Side

        public init(item: SyncItem, effect: SyncEffect, target: Side) {
            self.item = item
            self.effect = effect
            self.target = target
        }

        /// The side copied from (or, for a deletion, the side lacking the item).
        public var source: Side { target.other }
    }

    public var steps: [Step]

    public init(_ comparison: SyncComparison) {
        steps = comparison.items.compactMap { item in
            let (effect, target) = SyncRules.effect(of: item)
            guard effect != .nothing, let target else { return nil }
            return Step(item: item, effect: effect, target: target)
        }
    }

    public var isEmpty: Bool { steps.isEmpty }

    private func copies(to side: Side) -> [Step] {
        steps.filter { $0.target == side && [.copy, .overwrite, .replace].contains($0.effect) }
    }

    /// Files copied to `side` (a folder counts the files inside).
    public func files(to side: Side) -> Int {
        copies(to: side).reduce(0) { $0 + ($1.item.side($1.source)?.fileCount ?? 0) }
    }

    /// Bytes copied to `side` (source sizes, a folder by its total).
    public func bytes(to side: Side) -> Int64 {
        copies(to: side).reduce(0) { $0 + ($1.item.side($1.source)?.size ?? 0) }
    }

    /// Items going to the Trash on `side`: deletions and the targets of replacements.
    public func deletions(on side: Side) -> Int {
        steps.filter { $0.target == side && ($0.effect == .delete || $0.effect == .replace) }.count
    }

    public var deletionCount: Int { deletions(on: .left) + deletions(on: .right) }

    /// "Copy 12 files (340 MB) to the right, 3 files (1 kB) to the left", or nil when nothing is copied.
    public var copyLine: String? {
        func amount(_ side: Side) -> String? {
            guard !copies(to: side).isEmpty else { return nil }
            let files = String(localized: "\(files(to: side)) files")
            let bytes = SizeFormat.rounded(bytes(to: side), units: .decimal)
            return String(localized: "\(files) (\(bytes))")
        }
        switch (amount(.right), amount(.left)) {
        case let (r?, l?): return String(localized: "Copy \(r) to the right, \(l) to the left")
        case let (r?, nil): return String(localized: "Copy \(r) to the right")
        case let (nil, l?): return String(localized: "Copy \(l) to the left")
        case (nil, nil): return nil
        }
    }

    /// "Move 3 items to the Trash", or nil when nothing is deleted.
    public var trashLine: String? {
        guard deletionCount > 0 else { return nil }
        return String(localized: "Move \(String(localized: "\(deletionCount) items")) to the Trash")
    }

    /// One line for the summary: copies and deletions, or "Nothing to do".
    public var summary: String {
        switch (copyLine, trashLine) {
        case let (copy?, _?):
            String(localized: "\(copy), \(String(localized: "\(deletionCount) items")) to the Trash")
        case let (copy?, nil): copy
        case let (nil, trash?): trash
        case (nil, nil): String(localized: "Nothing to do")
        }
    }
}

/// The changed-since-comparing test of a run.
public enum SyncCheck {
    /// Both sides still look as compared (existence, kind, size for files, date within 1 ms, link target).
    public static func unchanged(_ item: SyncItem, in comparison: SyncComparison) -> Bool {
        matches(item.left, comparison.url(of: item, on: .left))
            && matches(item.right, comparison.url(of: item, on: .right))
    }

    static func matches(_ side: SyncSide?, _ url: URL) -> Bool {
        var st = Darwin.stat()
        guard lstat(url.path, &st) == 0 else { return side == nil && errno == ENOENT }
        guard let side else { return false }
        switch st.st_mode & S_IFMT {
        case S_IFDIR:
            // A folder's own date changes whenever an entry is added inside (also .DS_Store).
            return side.kind == .folder
        case S_IFLNK:
            guard case .link(let target) = side.kind else { return false }
            return (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == target
                && sameDate(st, side.modified)
        default:
            return side.kind == .file && Int64(st.st_size) == side.size && sameDate(st, side.modified)
        }
    }

    private static func sameDate(_ st: Darwin.stat, _ date: Date?) -> Bool {
        guard let date else { return true }
        let t = st.st_mtimespec
        let modified = Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1_000_000_000)
        return abs(modified.timeIntervalSince(date)) <= 0.001
    }
}
