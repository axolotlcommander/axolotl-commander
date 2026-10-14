// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

/// A listing that exists only in memory: nothing on disk is read or written.
private struct MemorySource: FileSource {
    let names: [String]
    var folders: [String] = []

    func list(_ directory: URL, includeHidden: Bool) async throws -> [FileItem] {
        folders.map { FileItem(url: directory.appendingPathComponent($0), isDirectory: true) }
            + names.map { FileItem(url: directory.appendingPathComponent($0), size: 1) }
    }
}

@MainActor
@Suite struct PanelMouseTests {
    /// Items: "..", "dir", a…j (indices 0, 1, 2…11).
    func model(_ names: [String] = (0..<10).map { String(UnicodeScalar(97 + $0)!) }) async -> PanelModel {
        let m = PanelModel(location: URL(fileURLWithPath: "/virtual/folder"),
                           source: MemorySource(names: names, folders: ["dir"]))
        await m.refresh()
        return m
    }

    func marked(_ m: PanelModel) -> [String] { m.selectedItems.map(\.name) }
    func index(_ m: PanelModel, _ name: String) -> Int { m.items.firstIndex { $0.name == name }! }

    @Test func listing() async {
        let m = await model()
        #expect(m.items.map(\.name) == ["..", "dir", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j"])
    }

    // MARK: Default mode

    @Test func plainPressOnUnmarkedClearsAllMarks() async {
        let m = await model()
        m.toggleSelection(at: index(m, "b"))   // a keyboard mark
        m.toggleSelection(at: index(m, "c"))
        let canDrag = m.mousePressed(at: index(m, "f"), modifiers: [], mode: .standard)
        #expect(canDrag)
        #expect(marked(m).isEmpty)
        #expect(m.cursor == index(m, "f"))
        m.restorePreviousSelection()
        #expect(marked(m) == ["b", "c"])
    }

    @Test func plainPressOnMarkedKeepsMarksUntilRelease() async {
        let m = await model()
        m.setSelected(true, range: index(m, "b")...index(m, "d"))
        #expect(m.mousePressed(at: index(m, "c"), modifiers: [], mode: .standard))
        #expect(marked(m) == ["b", "c", "d"])       // a drag from here carries all three
        m.mouseReleased(at: index(m, "c"), mode: .standard)
        #expect(marked(m) == ["c"])
        #expect(m.cursor == index(m, "c"))
        m.restorePreviousSelection()
        #expect(marked(m) == ["b", "c", "d"])
    }

    @Test func shiftClickStartsANewRange() async {
        let m = await model()
        m.toggleSelection(at: index(m, "g"))
        m.moveCursor(to: index(m, "e"))
        #expect(!m.mousePressed(at: index(m, "c"), modifiers: .range, mode: .standard))
        #expect(marked(m) == ["c", "d", "e"])
        #expect(m.cursor == index(m, "c"))
        m.mousePressed(at: index(m, "f"), modifiers: .range, mode: .standard)
        #expect(marked(m) == ["c", "d", "e", "f"])   // from the cursor (c) down to f
        m.restorePreviousSelection()
        #expect(marked(m) == ["c", "d", "e", "f"])
    }

    @Test func shiftClickOnTheCursorItemMarksJustIt() async {
        let m = await model()
        m.moveCursor(to: index(m, "d"))
        m.mousePressed(at: index(m, "d"), modifiers: .range, mode: .standard)
        #expect(marked(m) == ["d"])
    }

    @Test func controlShiftClickAddsARange() async {
        let m = await model()
        m.moveCursor(to: index(m, "b"))
        m.mousePressed(at: index(m, "d"), modifiers: .range, mode: .standard)
        m.mousePressed(at: index(m, "g"), modifiers: .toggle, mode: .standard)
        m.mousePressed(at: index(m, "i"), modifiers: [.toggle, .range], mode: .standard)
        #expect(marked(m) == ["b", "c", "d", "g", "h", "i"])
        #expect(m.cursor == index(m, "i"))
    }

    @Test func controlClickTogglesOneItem() async {
        let m = await model()
        #expect(!m.mousePressed(at: index(m, "c"), modifiers: .toggle, mode: .standard))
        m.mousePressed(at: index(m, "e"), modifiers: .toggle, mode: .standard)
        #expect(marked(m) == ["c", "e"])
        #expect(m.cursor == index(m, "e"))
        m.mousePressed(at: index(m, "c"), modifiers: .toggle, mode: .standard)
        #expect(marked(m) == ["e"])
        #expect(m.cursor == index(m, "c"))
    }

    @Test func parentRowIsNeverMarked() async {
        let m = await model()
        m.mousePressed(at: 0, modifiers: .toggle, mode: .standard)
        #expect(marked(m).isEmpty)
        #expect(m.cursor == 0)
        m.mousePressed(at: index(m, "b"), modifiers: .range, mode: .standard)   // from ".."
        #expect(marked(m) == ["dir", "a", "b"])
        m.mousePressed(at: 0, modifiers: [.toggle, .range], mode: .standard)
        #expect(!m.isSelected(m.items[0]))
    }

    @Test func pressOnEmptySpaceClearsMarksAndKeepsCursor() async {
        let m = await model()
        m.setSelected(true, range: 2...5)
        m.moveCursor(to: 4)
        m.mousePressedOnEmptySpace(mode: .standard)
        #expect(marked(m).isEmpty)
        #expect(m.cursor == 4)
        m.restorePreviousSelection()
        #expect(marked(m).count == 4)
    }

    @Test func outOfRangeIndexDoesNothing() async {
        let m = await model()
        m.toggleSelection(at: 3)
        #expect(!m.mousePressed(at: 99, modifiers: [], mode: .standard))
        #expect(marked(m) == ["b"])
    }

    // MARK: Right button mode

    @Test func plainLeftPressOnlyMovesTheCursorInRightButtonMode() async {
        let m = await model()
        m.setSelected(true, range: 3...5)
        #expect(m.mousePressed(at: 8, modifiers: [], mode: .rightButtonMarks))
        m.mouseReleased(at: 8, mode: .rightButtonMarks)
        #expect(marked(m) == ["b", "c", "d"])
        #expect(m.cursor == 8)
        m.mousePressed(at: 4, modifiers: [], mode: .rightButtonMarks)
        m.mouseReleased(at: 4, mode: .rightButtonMarks)
        #expect(marked(m) == ["b", "c", "d"])
        m.mousePressedOnEmptySpace(mode: .rightButtonMarks)
        #expect(marked(m) == ["b", "c", "d"])
        m.mousePressed(at: 9, modifiers: .toggle, mode: .rightButtonMarks)   // modifier clicks still mark
        #expect(marked(m) == ["b", "c", "d", "h"])
    }

    @Test func rightClickToggles() async {
        let m = await model()
        m.toggleMarkByRightClick(at: index(m, "c"))
        #expect(marked(m) == ["c"])
        #expect(m.cursor == index(m, "c"))
        m.toggleMarkByRightClick(at: index(m, "c"))
        #expect(marked(m).isEmpty)
        m.toggleMarkByRightClick(at: 0)
        #expect(marked(m).isEmpty)
    }

    @Test func rightDragTheFirstItemDecides() async {
        let m = await model()
        let b = index(m, "b"), f = index(m, "f")
        let marking = m.beginRightDrag(at: b)
        #expect(marking)
        m.rightDrag(from: b, to: b + 1, marking: marking)
        m.rightDrag(from: b + 1, to: f, marking: marking)   // a fast move skips rows
        #expect(marked(m) == ["b", "c", "d", "e", "f"])
        #expect(m.cursor == f)
        let unmarking = m.beginRightDrag(at: index(m, "c"))
        #expect(!unmarking)
        m.rightDrag(from: index(m, "c"), to: index(m, "e"), marking: unmarking)
        #expect(marked(m) == ["b", "f"])
        let up = m.beginRightDrag(at: index(m, "a"))
        m.rightDrag(from: index(m, "a"), to: 0, marking: up)
        #expect(marked(m) == ["dir", "a", "b", "f"])
    }

    // MARK: Rubber band

    @Test func plainRubberBandReplacesTheMarks() async {
        let m = await model()
        m.toggleSelection(at: index(m, "a"))
        var band = m.beginRubberBand(modifiers: [])
        #expect(marked(m).isEmpty)
        m.updateRubberBand(&band, covering: IndexSet(5...7))
        #expect(marked(m) == ["d", "e", "f"])
        m.updateRubberBand(&band, covering: IndexSet(5...9))
        #expect(marked(m) == ["d", "e", "f", "g", "h"])
        m.updateRubberBand(&band, covering: IndexSet(6...6))   // shrinking undoes
        #expect(marked(m) == ["e"])
        m.restorePreviousSelection()
        #expect(marked(m) == ["a", "e"])
    }

    @Test func shiftRubberBandAdds() async {
        let m = await model()
        m.setSelected(true, range: 2...3)
        var band = m.beginRubberBand(modifiers: .range)
        m.updateRubberBand(&band, covering: IndexSet(3...6))
        #expect(marked(m) == ["a", "b", "c", "d", "e"])
        m.updateRubberBand(&band, covering: IndexSet(5...6))   // b was marked before: it stays
        #expect(marked(m) == ["a", "b", "d", "e"])
    }

    @Test func controlRubberBandToggles() async {
        let m = await model()
        m.setSelected(true, range: index(m, "c")...index(m, "e"))
        var band = m.beginRubberBand(modifiers: .toggle)
        m.updateRubberBand(&band, covering: IndexSet(index(m, "d")...index(m, "g")))
        #expect(marked(m) == ["c", "f", "g"])
        m.updateRubberBand(&band, covering: IndexSet())
        #expect(marked(m) == ["c", "d", "e"])
    }

    @Test func rubberBandSkipsTheParentRow() async {
        let m = await model()
        var band = m.beginRubberBand(modifiers: [])
        m.updateRubberBand(&band, covering: IndexSet(0...2))
        #expect(marked(m) == ["dir", "a"])
        #expect(!m.isSelected(m.items[0]))
    }

    @Test func largeRubberBandAndRangeStayFast() async {
        let m = await model((0..<100_000).map { "file\($0)" })
        #expect(m.items.count == 100_002)
        var band = m.beginRubberBand(modifiers: [])
        let clock = ContinuousClock()
        let bandTime = clock.measure { m.updateRubberBand(&band, covering: IndexSet(0..<m.items.count)) }
        #expect(m.selection.count == 100_001)
        m.moveCursor(to: 1)
        let rangeTime = clock.measure {
            m.mousePressed(at: m.items.count - 1, modifiers: .range, mode: .standard)
        }
        #expect(m.selection.count == 100_001)
        // The release build takes about 30 ms for each (SC-003: under 0.1 s); a debug build under the load
        // of the parallel test run is many times slower, so this only catches a gross regression.
        #expect(bandTime < .seconds(5) && rangeTime < .seconds(5), "band \(bandTime), range \(rangeTime)")
    }

    // MARK: Setting

    @Test func rightButtonSetting() {
        #expect(PanelBehavior().rightButtonMarks == false)
        #expect(PanelBehavior().mouseSelectionMode == .standard)
        let suite = "PanelMouseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: PanelBehavior.rightButtonKey)
        #expect(PanelBehavior(defaults: defaults).mouseSelectionMode == .rightButtonMarks)
        #expect(PanelBehavior.rightButtonKey == "panel.rightButtonMarks")
    }
}
