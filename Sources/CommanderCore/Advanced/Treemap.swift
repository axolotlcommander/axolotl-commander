// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

/// Axis-aligned rectangle; own type so the core stays free of CoreGraphics.
/// Coordinates are plain numbers; "top" below means the smaller `y`.
public struct TreemapRect: Sendable, Equatable {
    public var x, y, width, height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// Half-open containment: left/top edges inside, right/bottom edges outside.
    public func contains(x px: Double, y py: Double) -> Bool {
        px >= x && px < maxX && py >= y && py < maxY
    }
}

/// Squarified treemap layout (Bruls, Huizing, van Wijk).
public enum Treemap {
    /// Squarified layout of `sizes` (any order; zero/negative/non-finite sizes get empty rects)
    /// inside `rect`. Returns one rect per size, in the input order. Rect areas are proportional
    /// to the sizes and add up to the area of `rect`.
    public static func squarify(_ sizes: [Double], in rect: TreemapRect) -> [TreemapRect] {
        var result = Array(repeating: TreemapRect(x: rect.x, y: rect.y, width: 0, height: 0), count: sizes.count)
        let order = sizes.indices
            .filter { sizes[$0].isFinite && sizes[$0] > 0 }
            .sorted { sizes[$0] != sizes[$1] ? sizes[$0] > sizes[$1] : $0 < $1 }
        let total = order.reduce(0) { $0 + sizes[$1] }
        guard !order.isEmpty, total > 0, rect.width > 0, rect.height > 0 else { return result }

        let scale = rect.width * rect.height / total
        let areas = order.map { sizes[$0] * scale }
        var free = rect
        var start = 0
        while start < order.count {
            let side = min(free.width, free.height)
            var end = start + 1
            var rowSum = areas[start]
            var best = worst(rowSum, areas[start], areas[start], side)
            while end < order.count {
                let area = areas[end]
                // Areas are sorted descending: the first is the row's largest, the new one its smallest.
                let candidate = worst(rowSum + area, areas[start], area, side)
                if candidate > best { break }
                best = candidate
                rowSum += area
                end += 1
            }

            let last = end == order.count
            if free.width >= free.height {
                // Row is a column on the left, items stacked vertically.
                let thickness = last ? free.width : min(free.width, rowSum / free.height)
                var y = free.y
                for k in start..<end {
                    let h = last && k == end - 1 ? free.maxY - y : areas[k] / rowSum * free.height
                    result[order[k]] = TreemapRect(x: free.x, y: y, width: thickness, height: h)
                    y += h
                }
                free.x += thickness
                free.width -= thickness
            } else {
                // Row is a strip at the top, items side by side.
                let thickness = last ? free.height : min(free.height, rowSum / free.width)
                var x = free.x
                for k in start..<end {
                    let w = last && k == end - 1 ? free.maxX - x : areas[k] / rowSum * free.width
                    result[order[k]] = TreemapRect(x: x, y: free.y, width: w, height: thickness)
                    x += w
                }
                free.y += thickness
                free.height -= thickness
            }
            start = end
        }
        return result
    }

    /// Worst aspect ratio of a row with total area `sum`, largest item `big`, smallest `small`, laid along `side`.
    private static func worst(_ sum: Double, _ big: Double, _ small: Double, _ side: Double) -> Double {
        let s2 = side * side
        return max(s2 * big / (sum * sum), sum * sum / (s2 * small))
    }

    /// One laid out node; `path` indexes `children` from the root, `depth` 0 is the root's children.
    public struct Cell: Sendable, Equatable {
        public var path: [Int]
        public var rect: TreemapRect
        public var depth: Int

        public init(path: [Int], rect: TreemapRect, depth: Int) {
            self.path = path
            self.rect = rect
            self.depth = depth
        }
    }

    /// Nested layout by `allocatedSize`: cells for the node's children, recursively down to `maxDepth`
    /// levels. A folder's children are laid out in its rect inset by `inset` on all sides with an extra
    /// `header` at the top (smaller `y`) for a title; folders are not descended when that inner rect
    /// is narrower or lower than `minSide`. Cells for nodes of size 0 are omitted. Parents precede
    /// their children in the result. Packages are laid out like any other folder.
    public static func cells(
        for root: DiskUsageNode, in rect: TreemapRect,
        maxDepth: Int, inset: Double, header: Double, minSide: Double
    ) -> [Cell] {
        var cells: [Cell] = []
        layout(root, path: [], in: rect, depth: 0, maxDepth: maxDepth, inset: inset, header: header,
               minSide: minSide, into: &cells)
        return cells
    }

    private static func layout(
        _ node: DiskUsageNode, path: [Int], in rect: TreemapRect, depth: Int, maxDepth: Int,
        inset: Double, header: Double, minSide: Double, into cells: inout [Cell]
    ) {
        guard depth < maxDepth, !node.children.isEmpty else { return }
        let rects = squarify(node.children.map { Double($0.allocatedSize) }, in: rect)
        for (index, child) in node.children.enumerated() where child.allocatedSize > 0 {
            let childRect = rects[index]
            guard !childRect.isEmpty else { continue }
            let childPath = path + [index]
            cells.append(Cell(path: childPath, rect: childRect, depth: depth))
            guard child.isDirectory else { continue }
            let inner = TreemapRect(
                x: childRect.x + inset, y: childRect.y + inset + header,
                width: childRect.width - 2 * inset, height: childRect.height - 2 * inset - header)
            guard inner.width >= minSide, inner.height >= minSide, !inner.isEmpty else { continue }
            layout(child, path: childPath, in: inner, depth: depth + 1, maxDepth: maxDepth,
                   inset: inset, header: header, minSide: minSide, into: &cells)
        }
    }

    /// The deepest cell containing the point (the last one among equally deep cells).
    public static func hit(_ cells: [Cell], x: Double, y: Double) -> Cell? {
        var best: Cell?
        for cell in cells where cell.rect.contains(x: x, y: y) {
            if let current = best, cell.depth < current.depth { continue }
            best = cell
        }
        return best
    }

    /// Direction of keyboard movement between cells; `up` is towards the smaller `y`.
    public enum Direction: Sendable, CaseIterable {
        case left, right, up, down
    }

    /// The cell next to `rects[index]` in `direction`, for arrow key navigation (empty rects are skipped).
    /// Prefers cells lying wholly beyond the current cell's edge that overlap its span on the other axis:
    /// the nearest edge first, then the greatest overlap. Without such a cell, the cell beyond that edge
    /// whose center is nearest. nil if nothing lies beyond the edge (the cell is at the border).
    public static func neighbor(of index: Int, in rects: [TreemapRect], toward direction: Direction) -> Int? {
        guard rects.indices.contains(index) else { return nil }
        let current = rects[index]
        let tolerance = 1e-6
        let horizontal = direction == .left || direction == .right
        // Distance from the current cell's edge to the candidate's near edge; negative when not wholly beyond.
        func gap(_ r: TreemapRect) -> Double {
            switch direction {
            case .right: r.x - current.maxX
            case .left: current.x - r.maxX
            case .down: r.y - current.maxY
            case .up: current.y - r.maxY
            }
        }
        func overlap(_ r: TreemapRect) -> Double {
            horizontal ? min(r.maxY, current.maxY) - max(r.y, current.y)
                : min(r.maxX, current.maxX) - max(r.x, current.x)
        }

        var best: (index: Int, gap: Double, overlap: Double)?
        for (i, r) in rects.enumerated() where i != index && !r.isEmpty {
            let g = gap(r), o = overlap(r)
            guard g >= -tolerance, o > tolerance else { continue }
            if let b = best, !(g < b.gap - tolerance || (abs(g - b.gap) <= tolerance && o > b.overlap + tolerance)) {
                continue
            }
            best = (i, g, o)
        }
        if let best { return best.index }

        let cx = current.x + current.width / 2, cy = current.y + current.height / 2
        var nearest: (index: Int, distance: Double)?
        for (i, r) in rects.enumerated() where i != index && !r.isEmpty && gap(r) >= -tolerance {
            let dx = r.x + r.width / 2 - cx, dy = r.y + r.height / 2 - cy
            let distance = dx * dx + dy * dy
            if nearest == nil || distance < nearest!.distance { nearest = (i, distance) }
        }
        return nearest?.index
    }
}
