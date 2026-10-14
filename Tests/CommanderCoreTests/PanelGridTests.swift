// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import CoreGraphics
@testable import CommanderCore

@Suite struct PanelGridTests {
    // MARK: Cursor movement

    @Test func listMoves() {
        let grid = PanelGrid.list(pageRows: 10)
        #expect(grid.target(from: 5, count: 50, key: .down) == 6)
        #expect(grid.target(from: 5, count: 50, key: .up) == 4)
        #expect(grid.target(from: 5, count: 50, key: .pageDown) == 15)
        #expect(grid.target(from: 5, count: 50, key: .pageUp) == 0)
        #expect(grid.target(from: 5, count: 50, key: .home) == 0)
        #expect(grid.target(from: 5, count: 50, key: .end) == 49)
        #expect(grid.target(from: 49, count: 50, key: .down) == 49)
        #expect(grid.target(from: 5, count: 50, key: .left) == nil)
        #expect(grid.target(from: 5, count: 50, key: .right) == nil)
    }

    @Test func columnsMoves() {
        // Brief: 8 rows per column, 3 columns visible.
        let grid = PanelGrid.columns(rowsPerColumn: 8, visibleColumns: 3)
        #expect(grid.target(from: 3, count: 30, key: .down) == 4)
        #expect(grid.target(from: 3, count: 30, key: .right) == 11)
        #expect(grid.target(from: 11, count: 30, key: .left) == 3)
        #expect(grid.target(from: 3, count: 30, key: .left) == 0)
        #expect(grid.target(from: 27, count: 30, key: .right) == 29)
        #expect(grid.target(from: 3, count: 30, key: .pageDown) == 27)
        #expect(grid.target(from: 3, count: 100, key: .pageDown) == 27)
    }

    @Test func rowsMoves() {
        // Thumbnails: 4 cells per row, 3 rows visible; 10 items: rows 0–3, 4–7, 8–9.
        let grid = PanelGrid.rows(columnsPerRow: 4, visibleRows: 3)
        #expect(grid.target(from: 1, count: 10, key: .right) == 2)
        #expect(grid.target(from: 1, count: 10, key: .left) == 0)
        #expect(grid.target(from: 1, count: 10, key: .down) == 5)
        #expect(grid.target(from: 5, count: 10, key: .up) == 1)
        // From the first row up: the first item; down above the shorter last row: the last item.
        #expect(grid.target(from: 2, count: 10, key: .up) == 0)
        #expect(grid.target(from: 7, count: 10, key: .down) == 9)
        #expect(grid.target(from: 6, count: 10, key: .down) == 9)
        #expect(grid.target(from: 5, count: 10, key: .down) == 9)
        #expect(grid.target(from: 4, count: 10, key: .down) == 8)
        #expect(grid.target(from: 0, count: 100, key: .pageDown) == 12)
        #expect(grid.target(from: 30, count: 100, key: .pageUp) == 18)
        #expect(grid.target(from: 3, count: 10, key: .end) == 9)
        #expect(grid.target(from: 3, count: 10, key: .home) == 0)
    }

    @Test func singleItemAndEmpty() {
        let grid = PanelGrid.rows(columnsPerRow: 4, visibleRows: 3)
        for key in [MoveKey.up, .down, .left, .right, .home, .end, .pageUp, .pageDown] {
            #expect(grid.target(from: 0, count: 1, key: key) == 0)
            #expect(grid.target(from: 0, count: 0, key: key) == nil)
        }
        // A zero column count (a panel not laid out yet) still moves by one.
        #expect(PanelGrid.rows(columnsPerRow: 0, visibleRows: 0).target(from: 2, count: 10, key: .down) == 3)
    }

    // MARK: Cells under a rectangle

    /// Thumbnails: cells 100 × 120 with 10 points between them, 4 per row, starting at (5, 5).
    let thumbs = GridGeometry(origin: CGPoint(x: 5, y: 5), cell: CGSize(width: 100, height: 120),
                              stride: CGSize(width: 110, height: 130), perLine: 4, order: .rowsFirst, count: 10)

    @Test func rowsFirstRectangles() {
        // Inside cell 0 only.
        #expect(thumbs.indices(in: CGRect(x: 20, y: 20, width: 10, height: 10)) == IndexSet([0]))
        // From cell 1 to cell 6 (second row, third column): columns 1–2 of rows 0–1.
        #expect(thumbs.indices(in: CGRect(x: 120, y: 20, width: 120, height: 140)) == IndexSet([1, 2, 5, 6]))
        // Only in the gap between columns 0 and 1.
        #expect(thumbs.indices(in: CGRect(x: 106, y: 20, width: 8, height: 300)).isEmpty)
        // Over the whole grid and beyond: every item, the short last row included.
        #expect(thumbs.indices(in: CGRect(x: -50, y: -50, width: 2000, height: 2000)) == IndexSet(0..<10))
        // Right of the last column of the short last row: nothing there.
        #expect(thumbs.indices(in: CGRect(x: 340, y: 270, width: 50, height: 50)).isEmpty)
        // Below the last row.
        #expect(thumbs.indices(in: CGRect(x: 0, y: 400, width: 500, height: 50)).isEmpty)
        // Starting in the gap below row 0 reaches row 1.
        #expect(thumbs.indices(in: CGRect(x: 20, y: 127, width: 10, height: 20)) == IndexSet([4]))
    }

    @Test func columnsFirstRectangles() {
        // Brief: cells 150 × 18, 8 points between columns, 5 rows per column, 12 items.
        let brief = GridGeometry(origin: CGPoint(x: 2, y: 2), cell: CGSize(width: 150, height: 18),
                                 stride: CGSize(width: 158, height: 18), perLine: 5, order: .columnsFirst, count: 12)
        // Rows 1–2 of columns 0 and 1.
        #expect(brief.indices(in: CGRect(x: 10, y: 25, width: 160, height: 20)) == IndexSet([1, 2, 6, 7]))
        // The gap between the columns only.
        #expect(brief.indices(in: CGRect(x: 153, y: 0, width: 5, height: 100)).isEmpty)
        // Below the last row of a column: nothing (5 rows only).
        #expect(brief.indices(in: CGRect(x: 10, y: 100, width: 10, height: 30)).isEmpty)
        // Everything.
        #expect(brief.indices(in: CGRect(x: 0, y: 0, width: 1000, height: 1000)) == IndexSet(0..<12))
    }
}
