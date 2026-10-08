// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// File mask in Open Salamander syntax: `*` any sequence, `?` any single
/// character, masks separated by `;` (`;;` is a literal semicolon), and an
/// optional exclusion list after `|` (e.g. `*.txt;*.doc|backup*`).
/// `*.*` matches names without an extension; so does any mask ending in `.*`
/// (`readme.*` matches `readme`). A mask without wildcards must match the
/// whole name. An empty include list matches everything.
public struct WildcardMask: Sendable, Hashable {
    public let pattern: String
    private let includes: [String]
    private let excludes: [String]

    public init(_ pattern: String) {
        self.pattern = pattern
        let (inc, exc) = Self.split(pattern)
        includes = inc
        excludes = exc
    }

    /// Mask built from already split parts (used by `SearchMask`).
    init(pattern: String, includes: [String], excludes: [String]) {
        self.pattern = pattern
        self.includes = includes
        self.excludes = excludes
    }

    /// The parsed include and exclude parts (without `|`, `;` separators).
    var parts: (includes: [String], excludes: [String]) { (includes, excludes) }

    public func matches(_ name: String, rules: NameRules = .apfsDefault) -> Bool {
        let n = Array(rules.key(name))
        if !includes.isEmpty && !includes.contains(where: { Self.matchPart($0, n, rules) }) { return false }
        return !excludes.contains(where: { Self.matchPart($0, n, rules) })
    }

    // MARK: Parsing

    private static func split(_ pattern: String) -> (include: [String], exclude: [String]) {
        var lists: [[String]] = [[]]
        var current = ""
        let chars = Array(pattern)
        var i = 0
        func flush() {
            let part = current.trimmingCharacters(in: .whitespaces)
            if !part.isEmpty { lists[lists.count - 1].append(part) }
            current = ""
        }
        while i < chars.count {
            let c = chars[i]
            if c == ";" {
                if i + 1 < chars.count, chars[i + 1] == ";" { current.append(";"); i += 2; continue }
                flush()
            } else if c == "|" && lists.count == 1 {
                flush()
                lists.append([])
            } else {
                current.append(c)
            }
            i += 1
        }
        flush()
        return (lists[0], lists.count > 1 ? lists[1] : [])
    }

    // MARK: Matching

    private static func matchPart(_ part: String, _ name: [Character], _ rules: NameRules) -> Bool {
        let p = Array(rules.key(part))
        if glob(p, name) { return true }
        // Windows semantics: a trailing ".*" also matches names without extension.
        if p.count >= 2, p[p.count - 2] == ".", p[p.count - 1] == "*" {
            return glob(Array(p.dropLast(2)), name)
        }
        return false
    }

    private static func glob(_ p: [Character], _ s: [Character]) -> Bool {
        var pi = 0, si = 0
        var star = -1, mark = 0
        while si < s.count {
            if pi < p.count, p[pi] == "*" {
                star = pi; mark = si; pi += 1
            } else if pi < p.count, p[pi] == "?" || p[pi] == s[si] {
                pi += 1; si += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; si = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
