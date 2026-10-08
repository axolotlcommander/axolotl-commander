// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

/// Text helpers for user-entered paths (no filesystem access).
enum PathText {
    /// Removes trailing slashes, except that "/" stays "/".
    static func trimmingTrailingSlashes(_ path: String) -> String {
        var p = Substring(path)
        while p.count > 1, p.hasSuffix("/") { p = p.dropLast() }
        return String(p)
    }

    /// Last path component; "/" for the root.
    static func lastComponent(_ path: String) -> String {
        let p = trimmingTrailingSlashes(path)
        if p == "/" { return "/" }
        if let slash = p.lastIndex(of: "/") { return String(p[p.index(after: slash)...]) }
        return p
    }
}
