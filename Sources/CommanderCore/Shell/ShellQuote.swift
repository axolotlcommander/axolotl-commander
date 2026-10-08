// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// POSIX sh quoting.
public enum ShellQuote {
    private static let safe: Set<Character> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./+:@%,=-")

    /// Unchanged when non-empty and made only of `[A-Za-z0-9_./+:@%,=-]` (non-ASCII letters are
    /// NOT safe). Otherwise wrapped in single quotes with `'` written as `'\''`. Empty → `''`.
    public static func quote(_ s: String) -> String {
        if !s.isEmpty && s.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
