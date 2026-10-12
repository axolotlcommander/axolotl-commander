// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// The folder history list (Go → Folder History…): the panel's Back / Forward history around the
/// current folder, then the recent paths typed in Go to Folder.
public enum FolderHistory {
    public enum Target: Hashable, Sendable {
        /// A place from the panel's history; opened like Back opens it.
        case location(URL)
        /// A path typed in Go to Folder; opened the way Go to Folder opens it.
        case typed(String)
    }

    public struct Entry: Hashable, Sendable {
        public var target: Target
        public var text: String
        public var isCurrent: Bool

        public init(target: Target, text: String, isCurrent: Bool = false) {
            self.target = target
            self.text = text
            self.isCurrent = isCurrent
        }
    }

    /// Forward places (furthest first), the current folder, Back places (newest first), then the
    /// recent paths not listed yet. A folder that appears more than once stays where it is closest
    /// to the current folder. `back` and `forward` are as the model keeps them (the next step last).
    public static func entries(back: [PanelState.Place], current: URL, forward: [PanelState.Place],
                               recent: [String], display: (URL) -> String) -> [Entry] {
        // Time order with the distance from the current folder.
        var timeline: [(entry: Entry, distance: Int)] = forward.enumerated().map { i, place in
            (Entry(target: .location(place.url), text: display(place.url)), forward.count - i)
        }
        timeline.append((Entry(target: .location(current), text: display(current), isCurrent: true), 0))
        timeline += back.reversed().enumerated().map { i, place in
            (Entry(target: .location(place.url), text: display(place.url)), i + 1)
        }
        var nearest: [String: Int] = [:]
        for (entry, distance) in timeline {
            let key = Self.key(entry.text)
            nearest[key] = min(nearest[key] ?? .max, distance)
        }
        var seen = Set<String>()
        var result: [Entry] = []
        for (entry, distance) in timeline {
            let key = Self.key(entry.text)
            guard nearest[key] == distance, seen.insert(key).inserted else { continue }
            result.append(entry)
        }
        for path in recent where seen.insert(Self.key(path)).inserted {
            result.append(Entry(target: .typed(path), text: path))
        }
        return result
    }

    /// The entry below the current folder (where Back leads), or the current folder itself.
    public static func initialSelection(in entries: [Entry]) -> Int? {
        guard let current = entries.firstIndex(where: \.isCurrent) else { return entries.isEmpty ? nil : 0 }
        let below = current + 1
        if entries.indices.contains(below), case .location = entries[below].target { return below }
        return current
    }

    private static func key(_ text: String) -> String { PathText.trimmingTrailingSlashes(text) }
}

/// Filtering of the history lists: every space-separated word must appear, ignoring case and
/// diacritics.
public enum HistoryFilter {
    public static func matches(_ text: String, query: String) -> Bool {
        query.split(separator: " ").allSatisfy {
            text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}
