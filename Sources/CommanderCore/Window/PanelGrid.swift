// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import CoreGraphics

/// A key that moves the panel cursor.
public enum MoveKey: Sendable {
    case up, down, left, right, home, end, pageUp, pageDown
}

/// How a panel view arranges its items, for moving the cursor with the keyboard.
public enum PanelGrid: Sendable, Equatable {
    /// Detailed: one item per row; ← and → do not move.
    case list(pageRows: Int)
    /// Brief: columns filled top to bottom, then left to right.
    case columns(rowsPerColumn: Int, visibleColumns: Int)
    /// Thumbnails: rows filled left to right, then down.
    case rows(columnsPerRow: Int, visibleRows: Int)

    /// The item the key moves the cursor to, clamped to the items; nil when the key does not move in this
    /// arrangement (← and → in a list).
    public func target(from: Int, count: Int, key: MoveKey) -> Int? {
        guard count > 0 else { return nil }
        let step: Int
        switch (self, key) {
        case (_, .home): return 0
        case (_, .end): return count - 1
        case (.list, .left), (.list, .right): return nil
        case (.list, .up), (.columns, .up), (.rows, .left): step = -1
        case (.list, .down), (.columns, .down), (.rows, .right): step = 1
        case (.columns(let rows, _), .left): step = -max(1, rows)
        case (.columns(let rows, _), .right): step = max(1, rows)
        case (.rows(let columns, _), .up): step = -max(1, columns)
        case (.rows(let columns, _), .down): step = max(1, columns)
        case (.list(let page), .pageUp), (.list(let page), .pageDown):
            step = (key == .pageUp ? -1 : 1) * max(1, page)
        case (.columns(let rows, let columns), .pageUp), (.columns(let rows, let columns), .pageDown),
             (.rows(let columns, let rows), .pageUp), (.rows(let columns, let rows), .pageDown):
            step = (key == .pageUp ? -1 : 1) * max(1, rows) * max(1, columns)
        }
        return min(max(from + step, 0), count - 1)
    }
}

/// The cells of a grid view laid out with equal cells, for finding the cells under a rectangle (the rubber
/// band) by arithmetic instead of asking the layout for every cell.
public struct GridGeometry: Sendable, Equatable {
    public enum Order: Sendable, Equatable {
        /// Brief: `perLine` cells top to bottom form a column, columns go left to right.
        case columnsFirst
        /// Thumbnails: `perLine` cells left to right form a row, rows go down.
        case rowsFirst
    }

    public var origin: CGPoint
    public var cell: CGSize
    /// The distance between the origins of neighboring cells: horizontally (width) and vertically (height).
    public var stride: CGSize
    public var perLine: Int
    public var order: Order
    public var count: Int

    public init(origin: CGPoint, cell: CGSize, stride: CGSize, perLine: Int, order: Order, count: Int) {
        self.origin = origin
        self.cell = cell
        self.stride = stride
        self.perLine = perLine
        self.order = order
        self.count = count
    }

    /// The cells the rectangle touches (a rectangle only in the gaps touches none). Coordinates grow
    /// rightwards and downwards, as in a flipped view.
    public func indices(in rect: CGRect) -> IndexSet {
        guard count > 0, perLine > 0, cell.width > 0, cell.height > 0, stride.width > 0, stride.height > 0 else {
            return []
        }
        guard let columns = touched(rect.minX - origin.x, rect.maxX - origin.x, size: cell.width, stride: stride.width),
              let rows = touched(rect.minY - origin.y, rect.maxY - origin.y, size: cell.height, stride: stride.height)
        else { return [] }
        // Along a line only `perLine` cells exist; across lines the count ends the grid.
        let (lines, along) = order == .columnsFirst ? (columns, rows) : (rows, columns)
        guard along.lowerBound < perLine else { return [] }
        let first = along.lowerBound, last = min(along.upperBound, perLine - 1)
        var result = IndexSet()
        for line in lines {
            let low = line * perLine + first
            guard low < count else { break }
            result.insert(integersIn: low..<min(line * perLine + last + 1, count))
        }
        return result
    }

    /// The line numbers whose cells (not the gaps after them) overlap `low...high` along one axis; empty
    /// when the span lies in a gap or before the first line.
    private func touched(_ low: CGFloat, _ high: CGFloat, size: CGFloat, stride: CGFloat) -> ClosedRange<Int>? {
        guard high >= 0, high >= low else { return nil }
        let start = max(low, 0)
        var first = Int(floor(start / stride))
        // The span starts in the gap after line `first`: that line is not touched.
        if start - CGFloat(first) * stride >= size { first += 1 }
        let last = Int(floor(high / stride))
        return first <= last ? first...last : nil
    }
}
