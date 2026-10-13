// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// Quick filter matching (`specs/013-quick-filter`): text without wildcards matches names that
/// contain it; text with `*`, `?`, `;` or `|` is a mask with the syntax of Filter….
public enum QuickFilter {
    public static func matches(_ name: String, text: String, rules: NameRules) -> Bool {
        if text.contains(where: { "*?;|".contains($0) }) { return WildcardMask(text).matches(name, rules: rules) }
        return rules.key(name).contains(rules.key(text))
    }
}
