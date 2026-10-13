// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin

/// Refuses folder pairs that cannot be synchronized.
public enum SyncGuard {
    public enum Refusal: Equatable, Sendable {
        /// Both sides are the same folder.
        case same
        /// One folder is inside the other.
        case nested
    }

    /// Compares the resolved paths (symbolic links followed) component by component.
    public static func check(left: URL, right: URL) -> Refusal? {
        let rules = SyncRulesForPair.rules(left: left, right: right)
        let a = components(left).map(rules.key)
        let b = components(right).map(rules.key)
        if a == b { return .same }
        let shorter = min(a.count, b.count)
        if Array(a.prefix(shorter)) == Array(b.prefix(shorter)) { return .nested }
        return nil
    }

    private static func components(_ url: URL) -> [String] {
        let path = resolved(url.standardizedFileURL.path)
        return path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func resolved(_ path: String) -> String {
        guard let real = realpath(path, nil) else {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        }
        defer { free(real) }
        return String(cString: real)
    }
}

/// Name rules for two folders: case-sensitive only when both volumes are.
enum SyncRulesForPair {
    static func rules(left: URL, right: URL) -> NameRules {
        let l = NameRules.forVolume(containing: left)
        let r = NameRules.forVolume(containing: right)
        return l.caseSensitive && r.caseSensitive ? NameRules(caseSensitive: true) : .apfsDefault
    }
}
