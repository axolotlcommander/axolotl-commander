// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// POSIX sh quoting.
public enum ShellQuote {
    private static let safe: Set<Character> = Set(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_./+:@%,=-")

    /// Unchanged when non-empty, made only of `[A-Za-z0-9_./+:@%,=-]` (non-ASCII letters are
    /// NOT safe) and not starting with `=` (zsh expands a leading `=word` to a command path).
    /// Otherwise wrapped in single quotes with `'` written as `'\''`. Empty → `''`.
    public static func quote(_ s: String) -> String {
        if !s.isEmpty && !s.hasPrefix("=") && s.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
