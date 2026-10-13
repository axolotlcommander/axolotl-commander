// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// The destination menu of the F5/F6 dialog.
public enum DestinationMenu {
    public enum Section: Equatable, Sendable { case otherPanel, tabs, hotPaths, recent }
    public struct Entry: Equatable, Sendable {
        public let section: Section
        public let title: String
        public let path: String
    }

    public static let recentCapacity = 10

    /// Sections in this order: the other panel's folder, the other panel's other tabs then this
    /// panel's tabs, hot paths, recent. A path is listed once (first occurrence wins, ignoring a
    /// trailing "/"); the source folder and paths for which `isExcluded` is true are left out.
    /// The title is the path, or for a hot path its name when not empty.
    public static func build(otherPanel: String?, otherTabs: [String], ownTabs: [String], source: String,
                             hotPaths: [HotPath], recent: [String],
                             isExcluded: (String) -> Bool) -> [Entry] {
        var seen: Set<String> = [PathText.trimmingTrailingSlashes(source)]
        var entries: [Entry] = []
        func add(_ section: Section, title: String?, path: String) {
            let key = PathText.trimmingTrailingSlashes(path)
            guard !path.isEmpty, !seen.contains(key), !isExcluded(path) else { return }
            seen.insert(key)
            let shown = title.flatMap { $0.isEmpty ? nil : $0 } ?? path
            entries.append(Entry(section: section, title: shown, path: path))
        }
        if let otherPanel { add(.otherPanel, title: nil, path: otherPanel) }
        for p in otherTabs + ownTabs { add(.tabs, title: nil, path: p) }
        for h in hotPaths { add(.hotPaths, title: h.name, path: h.path) }
        for p in recent { add(.recent, title: nil, path: p) }
        return entries
    }
}
