// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// How the mouse marks items (`specs/024-mouse-selection`).
public enum MouseSelectionMode: Sendable {
    /// Windows standard: a plain click starts over, ⌃/⌘ toggles one item, ⇧ marks a range.
    case standard
    /// Norton Commander style: the right button marks, a plain left click only moves the cursor.
    case rightButtonMarks
}

/// The keys held during a left click, as the marking rules see them.
public struct MouseModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// ⌃ or ⌘: toggle one item.
    public static let toggle = MouseModifiers(rawValue: 1)
    /// ⇧: a range from the cursor (with `toggle`: added to the marks).
    public static let range = MouseModifiers(rawValue: 2)
}

/// A selection rectangle being dragged: the marks it started from and the items it covered last.
public struct RubberBand: Sendable {
    public enum Operation: Sendable { case replace, add, toggle }

    public let operation: Operation
    let start: Set<String>
    var covered = IndexSet()
}

extension PanelModel {
    /// Left press on the item at `index`. Returns whether drag & drop may start from it: only a plain
    /// press does, so that ⌃, ⌘ and ⇧ clicks only mark.
    @discardableResult
    public func mousePressed(at index: Int, modifiers: MouseModifiers, mode: MouseSelectionMode) -> Bool {
        guard items.indices.contains(index) else { return false }
        let anchor = cursor
        switch (modifiers.contains(.toggle), modifiers.contains(.range)) {
        case (false, false):
            // A marked item keeps the marks until the release, so a drag from it carries them all.
            if mode == .standard, !isSelected(items[index]) { clearMarks() }
            moveCursor(to: index)
            return true
        case (true, false):
            toggleSelection(at: index)
        case (false, true):
            clearMarks()
            mark(min(anchor, index)...max(anchor, index), true)
        case (true, true):
            mark(min(anchor, index)...max(anchor, index), true)
        }
        moveCursor(to: index)
        return false
    }

    /// Left release on the item of a plain press that did not become a drag: a marked item becomes the
    /// only marked one.
    public func mouseReleased(at index: Int, mode: MouseSelectionMode) {
        guard mode == .standard, items.indices.contains(index), isSelected(items[index]) else { return }
        let only: Set = [rules.key(items[index].name)]
        guard selection != only else { return }
        rememberMarks()
        selection = only
    }

    /// Left press in the empty space below the items: clears the marks, the cursor stays.
    public func mousePressedOnEmptySpace(mode: MouseSelectionMode) {
        if mode == .standard { clearMarks() }
    }

    // MARK: Rubber band

    /// Starts a rectangle: alone it replaces the marks, with ⇧ it adds, with ⌃/⌘ it toggles.
    public func beginRubberBand(modifiers: MouseModifiers) -> RubberBand {
        let operation: RubberBand.Operation = modifiers.contains(.toggle) ? .toggle
            : modifiers.contains(.range) ? .add : .replace
        if operation == .replace { clearMarks() }
        return RubberBand(operation: operation, start: selection)
    }

    /// Applies the rectangle to the items it now covers. Only items that came in or went out change:
    /// those that went out get their state from the start of the drag back.
    public func updateRubberBand(_ band: inout RubberBand, covering: IndexSet) {
        let entered = covering.subtracting(band.covered)
        let left = band.covered.subtracting(covering)
        let start = band.start, toggles = band.operation == .toggle
        updateMarks { marks in
            for i in left {
                guard let key = markKey(at: i) else { continue }
                if start.contains(key) { marks.insert(key) } else { marks.remove(key) }
            }
            for i in entered {
                guard let key = markKey(at: i) else { continue }
                if toggles, start.contains(key) { marks.remove(key) } else { marks.insert(key) }
            }
        }
        band.covered = covering
    }

    // MARK: Right button (Norton style)

    /// A short right click: toggles the mark of the item and moves the cursor to it.
    public func toggleMarkByRightClick(at index: Int) {
        guard items.indices.contains(index) else { return }
        toggleSelection(at: index)
        moveCursor(to: index)
    }

    /// The start of a right drag: an unmarked first item means marking, a marked one unmarking. The
    /// first item gets that state; returns it for the rest of the drag.
    public func beginRightDrag(at index: Int) -> Bool {
        guard items.indices.contains(index) else { return true }
        let marking = !isSelected(items[index])
        rightDrag(from: index, to: index, marking: marking)
        return marking
    }

    /// The right drag moved from the row `from` to the row `to`: every item in between gets the state,
    /// so a fast move skips none. The cursor follows.
    public func rightDrag(from: Int, to: Int, marking: Bool) {
        guard !items.isEmpty else { return }
        mark(min(from, to)...max(from, to), marking)
        moveCursor(to: to)
    }

    // MARK: Helpers

    /// Before a gesture removes marks: ⌃W brings back what was marked.
    private func rememberMarks() {
        if !selection.isEmpty { previousSelection = selection }
    }

    private func clearMarks() {
        guard !selection.isEmpty else { return }
        rememberMarks()
        selection = []
    }

    /// The mark key of the item at `index`, nil for ".." and indices outside the list.
    private func markKey(at index: Int) -> String? {
        guard items.indices.contains(index), selectable(items[index]) else { return nil }
        return rules.key(items[index].name)
    }

    private func mark(_ range: ClosedRange<Int>, _ on: Bool) {
        let lo = max(range.lowerBound, 0), hi = min(range.upperBound, items.count - 1)
        guard lo <= hi else { return }
        updateMarks { marks in
            for i in lo...hi {
                guard let key = markKey(at: i) else { continue }
                if on { marks.insert(key) } else { marks.remove(key) }
            }
        }
    }

    /// Changes the marks in one assignment, so a large range or rectangle notifies observers once.
    private func updateMarks(_ change: (inout Set<String>) -> Void) {
        var marks = selection
        change(&marks)
        if marks != selection { selection = marks }
    }
}
