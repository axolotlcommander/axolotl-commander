// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// The tabs of one panel. Never empty; the last tab cannot be closed.
public struct TabList: Codable, Hashable, Sendable {
    public private(set) var tabs: [PanelState]
    public private(set) var active: Int

    public init(_ first: PanelState) {
        tabs = [first]
        active = 0
    }

    /// Empty `tabs` is a decoding error; an out-of-range `active` is clamped.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try c.decode([PanelState].self, forKey: .tabs)
        guard !decoded.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .tabs, in: c, debugDescription: "No tabs")
        }
        tabs = decoded
        active = max(0, min(try c.decodeIfPresent(Int.self, forKey: .active) ?? 0, decoded.count - 1))
    }

    public var current: PanelState { tabs[active] }

    /// Stores the state of the active tab; call before every switch and before saving.
    public mutating func updateCurrent(_ state: PanelState) {
        tabs[active] = state
    }

    /// Inserts `state` right after the active tab and activates it.
    public mutating func open(_ state: PanelState) {
        tabs.insert(state, at: active + 1)
        active += 1
    }

    /// Closes the active tab; returns false (changing nothing) for the only tab.
    /// The tab to the right becomes active, or the one to the left when the last tab was closed.
    @discardableResult
    public mutating func closeCurrent() -> Bool {
        close(at: active)
    }

    @discardableResult
    public mutating func close(at index: Int) -> Bool {
        guard tabs.count > 1, tabs.indices.contains(index) else { return false }
        tabs.remove(at: index)
        if index < active { active -= 1 } else if active >= tabs.count { active = tabs.count - 1 }
        return true
    }

    /// Out-of-range indices are ignored.
    public mutating func select(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        active = index
    }

    /// Cycles to the next tab.
    public mutating func next() {
        active = (active + 1) % tabs.count
    }

    /// Cycles to the previous tab.
    public mutating func previous() {
        active = (active - 1 + tabs.count) % tabs.count
    }

    /// Drag-and-drop reorder: the tab at `from` ends up at index `to`. The active tab stays active.
    public mutating func move(from: Int, to: Int) {
        guard tabs.indices.contains(from) else { return }
        let target = max(0, min(to, tabs.count - 1))
        guard target != from else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: target)
        if active == from {
            active = target
        } else {
            var a = from < active ? active - 1 : active
            if target <= a { a += 1 }
            active = a
        }
    }
}
