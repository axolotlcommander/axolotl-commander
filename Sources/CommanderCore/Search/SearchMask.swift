// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// File name mask with the semantics of the Salamander "Find files" dialog:
/// a part without `*`, `?` and `.` is a substring (`*part*`), a part with a single
/// trailing dot and no wildcards is the exact name without the dot (`dog.` → `dog`),
/// everything else is a plain `WildcardMask` part. Separators (`;`, `;;`, `|`) are
/// the same as in `WildcardMask`. An empty pattern matches everything.
public struct SearchMask: Sendable, Hashable {
    public let pattern: String
    private let mask: WildcardMask

    public init(_ pattern: String) {
        self.pattern = pattern
        let parts = WildcardMask(pattern).parts
        mask = WildcardMask(
            pattern: pattern,
            includes: parts.includes.map(Self.transform),
            excludes: parts.excludes.map(Self.transform)
        )
    }

    public func matches(_ name: String, rules: NameRules) -> Bool {
        mask.matches(name, rules: rules)
    }

    private static func transform(_ part: String) -> String {
        let hasWildcard = part.contains("*") || part.contains("?")
        if !hasWildcard {
            if !part.contains(".") { return "*" + part + "*" }
            if part.hasSuffix(".") { return String(part.dropLast()) }
        }
        return part
    }
}
