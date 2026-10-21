// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

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

    /// Stores the state of the active tab; call before every switch and before saving. The tab keeps its
    /// lock: the panel's snapshots know nothing about locks.
    public mutating func updateCurrent(_ state: PanelState) {
        var state = state
        state.lock = tabs[active].lock
        tabs[active] = state
    }

    /// Adds `state` as the last tab (or right after the active one, `nextToCurrent`) and activates it.
    public mutating func open(_ state: PanelState, nextToCurrent: Bool = false) {
        open(state, activate: true, nextToCurrent: nextToCurrent)
    }

    /// Adds `state` as the last tab, or right after the active one with `nextToCurrent` (the setting
    /// "Open new tabs next to the current tab"); a background tab leaves the active one active.
    public mutating func open(_ state: PanelState, activate: Bool, nextToCurrent: Bool = false) {
        let index = nextToCurrent ? active + 1 : tabs.count
        tabs.insert(state, at: index)
        if activate { active = index }
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

    /// Sends every tab except the active one whose location matches to `location`, with an empty
    /// cursor and selection; history is kept. Returns how many tabs changed.
    @discardableResult
    public mutating func redirect(where match: (URL) -> Bool, to location: URL) -> Int {
        var changed = 0
        for i in tabs.indices where i != active && match(tabs[i].location) {
            tabs[i].lock = nil
            tabs[i].location = location
            tabs[i].cursorName = nil
            tabs[i].selectedNames = []
            tabs[i].results = nil
            tabs[i].branch = nil
            changed += 1
        }
        return changed
    }

    // MARK: Locks (spec 028)

    /// Locks the tab at `index` on the folder it shows now (nil unlocks).
    public mutating func setLock(_ mode: TabLock.Mode?, at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].lock = mode.map { TabLock(mode: $0, state: tabs[index]) }
    }

    /// A folder change in the active locked tab: the tab gets `keeping` back (its lock stays) and `opened`
    /// becomes a new unlocked tab right after it, active.
    public mutating func split(keeping: PanelState, opened: PanelState, nextToCurrent: Bool = false) {
        var kept = keeping
        kept.lock = tabs[active].lock
        tabs[active] = kept
        var new = opened
        new.lock = nil
        open(new, activate: true, nextToCurrent: nextToCurrent)
    }

    /// The active tab, when locked with folder changes allowed, shows its locked folder again.
    public mutating func returnCurrentToLock() {
        guard let lock = tabs[active].lock, lock.mode == .allowsChanges else { return }
        tabs[active] = lock.returning(tabs[active])
    }

    /// Every tab locked with folder changes allowed shows its locked folder (at start).
    public mutating func returnAllToLocks() {
        for i in tabs.indices {
            if let lock = tabs[i].lock, lock.mode == .allowsChanges { tabs[i] = lock.returning(tabs[i]) }
        }
    }

    /// Close Other Tabs: every unlocked tab except the one at `index` goes; returns the closed ones.
    @discardableResult
    public mutating func closeOthers(keeping index: Int) -> [PanelState] {
        guard tabs.indices.contains(index) else { return [] }
        return remove(fallback: index) { $0 != index && $1.lock == nil }
    }

    /// Close Tabs to the Right: every unlocked tab after the one at `index` goes; returns the closed ones.
    @discardableResult
    public mutating func closeToTheRight(of index: Int) -> [PanelState] {
        guard tabs.indices.contains(index) else { return [] }
        return remove(fallback: index) { $0 > index && $1.lock == nil }
    }

    /// Removes the matching tabs. The active tab stays active when kept; otherwise the tab at `fallback`
    /// (which is always kept) becomes active.
    private mutating func remove(fallback: Int, _ match: (Int, PanelState) -> Bool) -> [PanelState] {
        let all = tabs
        let doomed = Set(all.indices.filter { match($0, all[$0]) })
        guard !doomed.isEmpty, !doomed.contains(fallback) else { return [] }
        let target = doomed.contains(active) ? fallback : active
        tabs = all.indices.filter { !doomed.contains($0) }.map { all[$0] }
        active = all.indices.filter { $0 < target && !doomed.contains($0) }.count
        return all.indices.filter(doomed.contains).map { all[$0] }
    }

    /// Duplicate Tab: an unlocked copy of the tab at `index` as the last tab (or right after it,
    /// `nextToCurrent`), active.
    public mutating func duplicate(at index: Int, nextToCurrent: Bool = false) {
        guard tabs.indices.contains(index) else { return }
        var copy = tabs[index]
        copy.lock = nil
        let target = nextToCurrent ? index + 1 : tabs.count
        tabs.insert(copy, at: target)
        active = target
    }

    /// Removes the locks of the tabs whose location or locked folder matches (an ejected volume, a
    /// disconnected server).
    public mutating func unlock(where match: (URL) -> Bool) {
        for i in tabs.indices {
            if match(tabs[i].location) || tabs[i].lock.map({ match($0.folder) }) == true { tabs[i].lock = nil }
        }
    }

    /// The locked folder of the tab at `index` is gone: the lock moves to `folder`.
    public mutating func relock(at index: Int, to folder: URL) {
        guard tabs.indices.contains(index), tabs[index].lock != nil else { return }
        tabs[index].lock?.folder = folder
        tabs[index].lock?.cursorName = nil
    }

    /// Cycles to the next tab.
    public mutating func next() {
        active = (active + 1) % tabs.count
    }

    /// Cycles to the previous tab.
    public mutating func previous() {
        active = (active - 1 + tabs.count) % tabs.count
    }

    /// Whether the tab at `index` can move `offset` places (Move Tab Left / Right, spec 036).
    public func canMove(_ index: Int, by offset: Int) -> Bool {
        tabs.indices.contains(index) && tabs.indices.contains(index + offset) && offset != 0
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

/// The tabs a panel closed, newest first, for Reopen Closed Tab and the tab list. Kept in memory.
public struct ClosedTabs: Hashable, Sendable {
    public static let limit = 10

    public private(set) var items: [PanelState] = []

    public init() {}

    public var isEmpty: Bool { items.isEmpty }

    public mutating func push(_ state: PanelState) {
        items.insert(state, at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
    }

    public mutating func popNewest() -> PanelState? {
        items.isEmpty ? nil : items.removeFirst()
    }

    public mutating func remove(at index: Int) -> PanelState? {
        items.indices.contains(index) ? items.remove(at: index) : nil
    }
}
