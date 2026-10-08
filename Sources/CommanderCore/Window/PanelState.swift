// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Everything needed to bring a panel back to a given moment: location, cursor,
/// sort, filter and navigation history. One tab holds one `PanelState`.
public struct PanelState: Codable, Hashable, Sendable {
    /// One history entry: a directory and the item the cursor stood on.
    public struct Place: Codable, Hashable, Sendable {
        public var url: URL
        public var cursorName: String?
        /// Find results shown at that moment. Not persisted: after a restart the root folder is shown.
        public var results: ResultsListing?

        public init(url: URL, cursorName: String? = nil, results: ResultsListing? = nil) {
            self.url = url
            self.cursorName = cursorName
            self.results = results
        }

        private enum CodingKeys: String, CodingKey { case url, cursorName }
    }

    public var location: URL
    /// Name of the item under the cursor; nil when the cursor is on ".." or unknown.
    public var cursorName: String?
    public var sort: SortSpec
    public var showHidden: Bool
    /// `WildcardMask.pattern` of the active filter.
    public var filterPattern: String?
    /// Oldest first, like in `PanelModel`.
    public var back: [Place]
    public var forward: [Place]
    /// Find results shown in the panel (in memory only, like `Place.results`).
    public var results: ResultsListing?
    /// Names of the selected items (in memory only: a tab keeps its selection while switching).
    public var selectedNames: [String]

    private enum CodingKeys: String, CodingKey {
        case location, cursorName, sort, showHidden, filterPattern, back, forward
    }

    public init(
        location: URL,
        cursorName: String? = nil,
        sort: SortSpec = .default,
        showHidden: Bool = false,
        filterPattern: String? = nil,
        back: [Place] = [],
        forward: [Place] = [],
        results: ResultsListing? = nil,
        selectedNames: [String] = []
    ) {
        self.location = location
        self.cursorName = cursorName
        self.sort = sort
        self.showHidden = showHidden
        self.filterPattern = filterPattern
        self.back = back
        self.forward = forward
        self.results = results
        self.selectedNames = selectedNames
    }

    /// Missing keys fall back to defaults; only `location` is required.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        location = try c.decode(URL.self, forKey: .location)
        cursorName = try c.decodeIfPresent(String.self, forKey: .cursorName)
        sort = try c.decodeIfPresent(SortSpec.self, forKey: .sort) ?? .default
        showHidden = try c.decodeIfPresent(Bool.self, forKey: .showHidden) ?? false
        filterPattern = try c.decodeIfPresent(String.self, forKey: .filterPattern)
        back = try c.decodeIfPresent([Place].self, forKey: .back) ?? []
        forward = try c.decodeIfPresent([Place].self, forKey: .forward) ?? []
        selectedNames = []
    }

    /// Short tab title: the last path component, "/" for the root.
    public var title: String {
        if let results { return results.title }
        let name = location.lastPathComponent
        return name.isEmpty ? "/" : name
    }

    /// The closest ancestor of `url` (including `url` itself) for which `exists` is true;
    /// "/" at worst. For a tab whose directory has disappeared.
    public static func nearestExisting(_ url: URL, exists: (URL) -> Bool) -> URL {
        var current = url.standardizedFileURL
        while !exists(current) {
            let parent = current.deletingLastPathComponent()
            if current.path == "/" || parent.path == current.path { break }
            current = parent
        }
        return exists(current) ? current : URL(filePath: "/")
    }
}
