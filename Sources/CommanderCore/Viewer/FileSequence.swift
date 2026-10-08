// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation

/// Snapshot of the panel's files for viewer "next/previous file" navigation.
public struct FileSequence: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let url: URL
        public let isSelected: Bool
        public init(url: URL, isSelected: Bool) {
            self.url = url
            self.isSelected = isSelected
        }
    }

    public enum Step: Sendable { case next, previous, first, last, nextSelected, previousSelected }

    public let entries: [Entry]
    public private(set) var index: Int

    /// nil when `current` is not among `entries` (URLs compared by standardized file path).
    public init?(entries: [Entry], current: URL) {
        let key = current.standardizedFileURL.path
        guard let i = entries.firstIndex(where: { $0.url.standardizedFileURL.path == key }) else { return nil }
        self.entries = entries
        self.index = i
    }

    public var current: URL { entries[index].url }

    /// Moves and returns the new current URL; nil (index unchanged) when there is no such file.
    public mutating func move(_ step: Step) -> URL? {
        let target: Int?
        switch step {
        case .next: target = index + 1 < entries.count ? index + 1 : nil
        case .previous: target = index > 0 ? index - 1 : nil
        case .first: target = index != 0 ? 0 : nil
        case .last: target = index != entries.count - 1 ? entries.count - 1 : nil
        case .nextSelected: target = entries[(index + 1)...].firstIndex(where: \.isSelected)
        case .previousSelected: target = entries[..<index].lastIndex(where: \.isSelected)
        }
        guard let target else { return nil }
        index = target
        return entries[target].url
    }

    /// Like `move(_:)`, but only lands on entries `accept` takes (e.g. pictures in the image viewer).
    public mutating func move(_ step: Step, where accept: (Entry) -> Bool) -> URL? {
        let candidates: [Int]
        switch step {
        case .next: candidates = Array(entries.indices.dropFirst(index + 1))
        case .previous: candidates = entries.indices.prefix(index).reversed()
        case .first: candidates = Array(entries.indices.prefix(index))
        case .last: candidates = entries.indices.dropFirst(index + 1).reversed()
        case .nextSelected: candidates = entries.indices.dropFirst(index + 1).filter { entries[$0].isSelected }
        case .previousSelected: candidates = entries.indices.prefix(index).reversed().filter { entries[$0].isSelected }
        }
        guard let target = candidates.first(where: { accept(entries[$0]) }) else { return nil }
        index = target
        return entries[target].url
    }
}
