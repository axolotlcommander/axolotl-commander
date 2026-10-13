// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// Which F-key positions the function key bar shows (spec 017). Hiding a position hides its button
/// in every modifier layer; the key itself keeps working.
public struct FunctionKeyChoice: Equatable, Sendable {
    /// The hidden positions as text, e.g. "5,6,8"; missing or empty = all twelve shown.
    public static let key = "functionKeyBar.hidden"

    /// Hidden positions (1…12); never all of them.
    public private(set) var hidden: Set<Int>

    public init(hidden: Set<Int> = []) {
        let valid = hidden.filter { (1...FunctionKeyBar.count).contains($0) }
        self.hidden = valid.count == FunctionKeyBar.count ? [] : valid
    }

    /// Reads the stored text; unknown parts are ignored, and hiding everything shows everything.
    public init(storage: String?) {
        let numbers = (storage ?? "").split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        self.init(hidden: Set(numbers))
    }

    public var storage: String { hidden.sorted().map(String.init).joined(separator: ",") }

    /// The shown positions in F-key order; never empty.
    public var visible: [Int] { (1...FunctionKeyBar.count).filter { !hidden.contains($0) } }

    public func isVisible(_ number: Int) -> Bool { !hidden.contains(number) }

    /// The last shown position cannot be hidden: hiding the whole bar is a separate setting.
    public func canHide(_ number: Int) -> Bool { !isVisible(number) || visible.count > 1 }

    public mutating func set(_ number: Int, visible: Bool) {
        guard (1...FunctionKeyBar.count).contains(number) else { return }
        if visible {
            hidden.remove(number)
        } else if canHide(number) {
            hidden.insert(number)
        }
    }
}

/// Where the shown buttons stand in the bar: side by side from the left edge, each at most
/// `maxWidth` wide; when there is less room they share the bar evenly and the last one ends at the edge.
public enum FunctionKeyBarLayout {
    public static let maxButtonWidth = 140.0

    /// x and width of each of `count` buttons in a bar `width` wide: `edge` free at both ends of the
    /// bar, `gap` between the buttons.
    public static func frames(count: Int, width: Double, edge: Double, gap: Double,
                              maxWidth: Double = maxButtonWidth) -> [(x: Double, width: Double)] {
        guard count > 0 else { return [] }
        let shared = ((width - 2 * edge - gap * Double(count - 1)) / Double(count)).rounded(.down)
        let capped = shared >= maxWidth
        let buttonWidth = min(shared, maxWidth)
        var x = edge
        return (0..<count).map { index in
            // Evenly shared, the last button takes the rounding remainder so the row ends at the edge.
            let w = !capped && index == count - 1 ? width - edge - x : buttonWidth
            defer { x += buttonWidth + gap }
            return (x, max(w, 0))
        }
    }
}
