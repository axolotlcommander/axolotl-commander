// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import Foundation

/// History of the "Go to folder" dialog, newest first.
public struct RecentPaths: Codable, Hashable, Sendable {
    public static let limit = 20

    public private(set) var paths: [String]

    public init(paths: [String] = []) {
        self.paths = Array(paths.prefix(Self.limit))
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(paths: try c.decodeIfPresent([String].self, forKey: .paths) ?? [])
    }

    /// Trims whitespace, ignores empty input, strips any password (`Credentials.scrub`) and moves
    /// an equal path (ignoring a trailing "/", except for "/" itself) to the front.
    public mutating func add(_ path: String) {
        let clean = Credentials.scrub(path.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !clean.isEmpty else { return }
        let key = PathText.trimmingTrailingSlashes(clean)
        paths.removeAll { PathText.trimmingTrailingSlashes($0) == key }
        paths.insert(clean, at: 0)
        if paths.count > Self.limit { paths.removeLast(paths.count - Self.limit) }
    }
}
