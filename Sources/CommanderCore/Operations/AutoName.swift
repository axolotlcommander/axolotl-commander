// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// Finder-style free names for "rename automatically".
public enum AutoName {
    /// "base N.ext", or "base N" for folders and names without an extension; `attempt` >= 2.
    /// The result fits 255 bytes of UTF-8: the base is shortened, never the suffix or extension.
    public static func name(for original: String, isDirectory: Bool, attempt: Int) -> String {
        var base = original
        var ext = ""
        if !isDirectory, let dot = original.lastIndex(of: "."),
           dot != original.startIndex, original.index(after: dot) != original.endIndex {
            base = String(original[..<dot])
            ext = String(original[dot...])
        }
        let tail = " \(max(attempt, 2))" + ext
        let room = PathRules.maxNameBytes - tail.utf8.count
        while base.utf8.count > room, !base.isEmpty { base.removeLast() }
        return base + tail
    }
}
