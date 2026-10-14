// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// How many tabs fit in a panel's tab strip and which of them it shows (spec 028: "+" and "»").
public enum TabStripLayout {
    /// The number of tabs of at least `tabWidth` that fit in `width` next to the "+" button, and next to "»"
    /// too when not all `count` tabs fit; at least one.
    public static func capacity(width: CGFloat, count: Int, tabWidth: CGFloat, spacing: CGFloat, button: CGFloat) -> Int {
        func fit(_ room: CGFloat) -> Int { max(1, Int(((room + spacing) / (tabWidth + spacing)).rounded(.down))) }
        let all = fit(width - button - spacing)
        return all >= count ? count : fit(width - 2 * (button + spacing))
    }

    /// The indices shown: the first `capacity` tabs; when the active tab is not among them it takes the last
    /// place.
    public static func visible(count: Int, active: Int, capacity: Int) -> [Int] {
        let shown = Array(0..<min(count, max(1, capacity)))
        guard !shown.contains(active) else { return shown }
        return shown.dropLast() + [active]
    }
}
