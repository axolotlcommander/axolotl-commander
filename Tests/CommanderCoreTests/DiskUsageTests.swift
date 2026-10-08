// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import Testing
import Foundation
import Darwin
@testable import CommanderCore

@Suite struct DiskUsageTests {
    /// Creates a UUID-named temp dir, runs `body`, removes it (restoring permissions first).
    private func withTree(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiskUsageTests-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { Self.cleanUp(dir) }
        try await body(dir)
    }

    /// Restores permissions of everything below `dir` (chmod 000 folders), then removes it.
    private static func cleanUp(_ dir: URL) {
        let fm = FileManager.default
        for sub in (try? fm.subpathsOfDirectory(atPath: dir.path)) ?? [] {
            let path = dir.appendingPathComponent(sub).path
            if (try? fm.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeDirectory {
                chmod(path, 0o755)
            }
        }
        try? fm.removeItem(at: dir)
    }

    private func write(_ url: URL, bytes: Int) throws {
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    @Test func scansSmallTree() async throws {
        try await withTree { dir in
            let fm = FileManager.default
            let sub = dir.appendingPathComponent("sub", isDirectory: true)
            let deep = sub.appendingPathComponent("deep", isDirectory: true)
            let locked = dir.appendingPathComponent("locked", isDirectory: true)
            try fm.createDirectory(at: deep, withIntermediateDirectories: true)
            try fm.createDirectory(at: locked, withIntermediateDirectories: true)
            try write(dir.appendingPathComponent("empty0"), bytes: 0)
            try write(dir.appendingPathComponent("one"), bytes: 1)
            try write(sub.appendingPathComponent("five"), bytes: 5000)
            try write(deep.appendingPathComponent("big"), bytes: 100_000)
            try write(dir.appendingPathComponent("hard1"), bytes: 5000)
            try fm.linkItem(at: dir.appendingPathComponent("hard1"), to: dir.appendingPathComponent("hard2"))
            try fm.createSymbolicLink(atPath: dir.appendingPathComponent("link_file").path, withDestinationPath: "sub/five")
            try fm.createSymbolicLink(atPath: dir.appendingPathComponent("link_dir").path, withDestinationPath: "sub")
            try write(locked.appendingPathComponent("hidden"), bytes: 1000)
            #expect(chmod(locked.path, 0o000) == 0)
            let lockedEffective = (try? fm.contentsOfDirectory(atPath: locked.path)) == nil

            let root = try await DiskUsage.scan(dir)

            // Symlinks count by their own (target string) size, the hard link only once.
            let expectedLogical: Int64 = 0 + 1 + 5000 + 100_000 + 5000 + Int64("sub/five".utf8.count) + Int64("sub".utf8.count)
                + (lockedEffective ? 0 : 1000)
            #expect(root.logicalSize == expectedLogical)
            #expect(root.isDirectory)
            #expect(root.name == dir.lastPathComponent)
            #expect(root.fileCount == 8 + (lockedEffective ? 0 : 1))
            #expect(root.allocatedSize >= 105_001 + 5000)

            func child(_ name: String, in node: DiskUsageNode) throws -> DiskUsageNode {
                try #require(node.children.first { $0.name == name })
            }
            let linkDir = try child("link_dir", in: root)
            #expect(!linkDir.isDirectory)
            #expect(linkDir.children.isEmpty)
            #expect(linkDir.logicalSize == Int64("sub".utf8.count))
            let linkFile = try child("link_file", in: root)
            #expect(!linkFile.isDirectory)
            #expect(linkFile.logicalSize == Int64("sub/five".utf8.count))

            let subNode = try child("sub", in: root)
            #expect(subNode.isDirectory)
            #expect(subNode.logicalSize == 105_000)
            #expect(subNode.fileCount == 2)
            #expect(subNode.allocatedSize >= 105_000)
            let big = try child("big", in: try child("deep", in: subNode))
            #expect(big.logicalSize == 100_000)
            #expect(big.allocatedSize >= 100_000 && big.allocatedSize % 512 == 0)
            #expect(big.fileCount == 1)

            let empty = try child("empty0", in: root)
            #expect(empty.logicalSize == 0)
            #expect(try child("one", in: root).logicalSize == 1)

            let hard1 = try child("hard1", in: root)
            let hard2 = try child("hard2", in: root)
            #expect(hard1.logicalSize + hard2.logicalSize == 5000)
            #expect((hard1.allocatedSize == 0) != (hard2.allocatedSize == 0))

            let lockedNode = try child("locked", in: root)
            #expect(lockedNode.isDirectory)
            if lockedEffective {
                #expect(lockedNode.isUnreadable)
                #expect(lockedNode.children.isEmpty)
            }
            #expect(!subNode.isUnreadable)

            // Unique ids, sorted children at every level.
            var ids = Set<Int>()
            func visit(_ node: DiskUsageNode) {
                #expect(ids.insert(node.id).inserted)
                for (a, b) in zip(node.children, node.children.dropFirst()) {
                    #expect(a.allocatedSize > b.allocatedSize
                        || (a.allocatedSize == b.allocatedSize && a.name.localizedStandardCompare(b.name) != .orderedDescending))
                }
                node.children.forEach(visit)
            }
            visit(root)
            #expect(root.children.first?.name == "sub")
        }
    }

    @Test func nodeAtPath() async throws {
        try await withTree { dir in
            let deep = dir.appendingPathComponent("a/b", isDirectory: true)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
            try write(deep.appendingPathComponent("f"), bytes: 10)
            let root = try await DiskUsage.scan(dir)
            #expect(DiskUsage.node(at: [], in: root)?.id == root.id)
            #expect(DiskUsage.node(at: [0, 0, 0], in: root)?.name == "f")
            #expect(DiskUsage.node(at: [0, 0], in: root)?.name == "b")
            #expect(DiskUsage.node(at: [1], in: root) == nil)
            #expect(DiskUsage.node(at: [0, 0, 0, 0], in: root) == nil)
            #expect(DiskUsage.node(at: [-1], in: root) == nil)
        }
    }

    @Test func rootFileAndMissingRoot() async throws {
        try await withTree { dir in
            let file = dir.appendingPathComponent("lonely")
            try write(file, bytes: 77)
            let node = try await DiskUsage.scan(file)
            #expect(!node.isDirectory)
            #expect(node.logicalSize == 77)
            await #expect(throws: (any Error).self) {
                _ = try await DiskUsage.scan(dir.appendingPathComponent("missing"))
            }
        }
    }

    @Test func reportsProgress() async throws {
        try await withTree { dir in
            try write(dir.appendingPathComponent("f"), bytes: 10)
            let calls = Counter()
            _ = try await DiskUsage.scan(dir) { _ in calls.increment() }
            // The first entry always reports (throttle starts open); never more than once per entry.
            #expect(calls.value >= 1 && calls.value <= 3)
        }
    }

    @Test func cancellation() async throws {
        try await withTree { dir in
            for i in 0..<20 { try write(dir.appendingPathComponent("f\(i)"), bytes: 1) }
            let task = Task {
                while !Task.isCancelled { await Task.yield() }
                return try await DiskUsage.scan(dir)
            }
            task.cancel()
            await #expect(throws: CancellationError.self) { _ = try await task.value }
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@Suite struct TreemapTests {
    private let bounds = TreemapRect(x: 0, y: 0, width: 6, height: 4)

    private func worstAspect(_ rects: [TreemapRect]) -> Double {
        rects.filter { !$0.isEmpty }.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
    }

    private func area(_ r: TreemapRect) -> Double { r.width * r.height }

    private func inside(_ r: TreemapRect, _ outer: TreemapRect, tol: Double = 1e-9) -> Bool {
        r.x >= outer.x - tol && r.y >= outer.y - tol && r.maxX <= outer.maxX + tol && r.maxY <= outer.maxY + tol
    }

    private func overlap(_ a: TreemapRect, _ b: TreemapRect) -> Double {
        let w = min(a.maxX, b.maxX) - max(a.x, b.x)
        let h = min(a.maxY, b.maxY) - max(a.y, b.y)
        return w > 0 && h > 0 ? w * h : 0
    }

    @Test func paperExample() {
        let sizes: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let rects = Treemap.squarify(sizes, in: bounds)
        #expect(rects.count == sizes.count)
        #expect(rects.allSatisfy { inside($0, bounds) })
        for i in rects.indices {
            #expect(abs(area(rects[i]) - sizes[i]) < 1e-9)
            for j in rects.indices where j > i {
                #expect(overlap(rects[i], rects[j]) < 1e-9)
            }
        }
        #expect(worstAspect(rects) <= 3)

        // Slice-and-dice: vertical strips of the full height are much worse.
        let strips = sizes.map { TreemapRect(x: 0, y: 0, width: $0 / 24 * 6, height: 4) }
        #expect(worstAspect(rects) < worstAspect(strips))
    }

    @Test func proportionalAndComplete() {
        let sizes: [Double] = [1_000_000, 123_456, 98_765, 5000, 777, 42, 42, 1]
        let outer = TreemapRect(x: 10, y: 20, width: 800, height: 500)
        let rects = Treemap.squarify(sizes, in: outer)
        let total = sizes.reduce(0, +)
        for (size, rect) in zip(sizes, rects) {
            let expected = outer.width * outer.height * size / total
            #expect(abs(area(rect) - expected) / expected < 1e-6)
            #expect(inside(rect, outer))
        }
        #expect(abs(rects.map(area).reduce(0, +) - outer.width * outer.height) < 1e-6)
        for i in rects.indices {
            for j in rects.indices where j > i {
                #expect(overlap(rects[i], rects[j]) < 1e-6)
            }
        }
    }

    @Test func keepsInputOrderAndHandlesUnsortedInput() {
        let rects = Treemap.squarify([1, 5, 3], in: bounds)
        #expect(area(rects[1]) > area(rects[2]))
        #expect(area(rects[2]) > area(rects[0]))
    }

    @Test func zeroAndNegativeSizes() {
        let rects = Treemap.squarify([0, 5, -3, 5, .nan], in: bounds)
        #expect(rects.count == 5)
        for i in [0, 2, 4] { #expect(area(rects[i]) == 0) }
        #expect(abs(area(rects[1]) - 12) < 1e-9)
        #expect(abs(area(rects[3]) - 12) < 1e-9)

        #expect(Treemap.squarify([], in: bounds).isEmpty)
        #expect(Treemap.squarify([0, 0], in: bounds).allSatisfy { area($0) == 0 })
        #expect(Treemap.squarify([1, 2], in: TreemapRect(x: 0, y: 0, width: 0, height: 5)).allSatisfy { area($0) == 0 })
        let single = Treemap.squarify([7], in: bounds)
        #expect(single == [bounds])
    }

    // MARK: nested cells

    private func leaf(_ id: Int, _ name: String, _ size: Int64) -> DiskUsageNode {
        DiskUsageNode(id: id, name: name, url: URL(fileURLWithPath: "/x/\(name)"), isDirectory: false,
                      allocatedSize: size, logicalSize: size, fileCount: 1)
    }

    private func folder(_ id: Int, _ name: String, _ children: [DiskUsageNode]) -> DiskUsageNode {
        let size = children.reduce(0) { $0 + $1.allocatedSize }
        return DiskUsageNode(id: id, name: name, url: URL(fileURLWithPath: "/x/\(name)"), isDirectory: true,
                             allocatedSize: size, logicalSize: size, fileCount: children.count, children: children)
    }

    private var sample: DiskUsageNode {
        folder(0, "root", [
            folder(1, "big", [leaf(2, "a", 600), leaf(3, "b", 300), leaf(4, "c", 100), leaf(5, "zero", 0)]),
            leaf(6, "mid", 500),
            folder(7, "small", [leaf(8, "tiny", 60)]),
            leaf(9, "empty", 0),
        ])
    }

    @Test func nestedCellsRespectInsetAndHeader() {
        let outer = TreemapRect(x: 0, y: 0, width: 400, height: 300)
        let cells = Treemap.cells(for: sample, in: outer, maxDepth: 3, inset: 4, header: 16, minSide: 2)
        let byPath = Dictionary(uniqueKeysWithValues: cells.map { ($0.path, $0) })

        #expect(byPath[[3]] == nil, "zero-size node omitted")
        #expect(byPath[[0, 3]] == nil)
        #expect(byPath[[0]]?.depth == 0)
        #expect(byPath[[0, 0]]?.depth == 1)
        #expect(cells.count == 7)

        let big = byPath[[0]]!.rect
        for path in [[0, 0], [0, 1], [0, 2]] {
            let r = byPath[path]!.rect
            #expect(r.x >= big.x + 4 - 1e-9)
            #expect(r.y >= big.y + 4 + 16 - 1e-9)
            #expect(r.maxX <= big.maxX - 4 + 1e-9)
            #expect(r.maxY <= big.maxY - 4 + 1e-9)
        }
        // Children fill the inner rect.
        let innerArea = (big.width - 8) * (big.height - 8 - 16)
        let childArea = [[0, 0], [0, 1], [0, 2]].map { byPath[$0]!.rect }.map(area).reduce(0, +)
        #expect(abs(innerArea - childArea) < 1e-6)

        // Parents come before their children.
        let indexOf = Dictionary(uniqueKeysWithValues: cells.enumerated().map { ($1.path, $0) })
        #expect(indexOf[[0]]! < indexOf[[0, 0]]!)
    }

    @Test func depthAndMinSideLimitDescent() {
        let outer = TreemapRect(x: 0, y: 0, width: 400, height: 300)
        let shallow = Treemap.cells(for: sample, in: outer, maxDepth: 1, inset: 4, header: 16, minSide: 2)
        #expect(shallow.allSatisfy { $0.depth == 0 })
        #expect(shallow.count == 3)
        #expect(Treemap.cells(for: sample, in: outer, maxDepth: 0, inset: 4, header: 16, minSide: 2).isEmpty)

        let strict = Treemap.cells(for: sample, in: outer, maxDepth: 3, inset: 4, header: 16, minSide: 10_000)
        #expect(strict.allSatisfy { $0.depth == 0 })
        // "small" is tiny: its inner rect is below minSide, so "tiny" is not laid out at a moderate minSide.
        let moderate = Treemap.cells(for: sample, in: outer, maxDepth: 3, inset: 4, header: 16, minSide: 50)
        #expect(!moderate.contains { $0.path == [2, 0] })
        #expect(moderate.contains { $0.path == [0, 0] })
    }

    @Test func hitReturnsDeepest() {
        let outer = TreemapRect(x: 0, y: 0, width: 400, height: 300)
        let cells = Treemap.cells(for: sample, in: outer, maxDepth: 3, inset: 4, header: 16, minSide: 2)
        let inner = cells.first { $0.path == [0, 0] }!
        let cx = inner.rect.x + inner.rect.width / 2
        let cy = inner.rect.y + inner.rect.height / 2
        #expect(Treemap.hit(cells, x: cx, y: cy)?.path == [0, 0])

        // Folder header area belongs to the folder itself.
        let big = cells.first { $0.path == [0] }!
        #expect(Treemap.hit(cells, x: big.rect.x + 1, y: big.rect.y + 1)?.path == [0])

        let mid = cells.first { $0.path == [1] }!
        #expect(Treemap.hit(cells, x: mid.rect.x + 1, y: mid.rect.y + 1)?.path == [1])

        #expect(Treemap.hit(cells, x: -5, y: -5) == nil)
        #expect(Treemap.hit([], x: 1, y: 1) == nil)
    }

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> TreemapRect {
        TreemapRect(x: x, y: y, width: w, height: h)
    }

    @Test func neighborInGrid() {
        // 0 1 2
        // 3 4 5
        let grid = (0..<6).map { rect(Double($0 % 3) * 10, Double($0 / 3) * 10, 10, 10) }
        #expect(Treemap.neighbor(of: 4, in: grid, toward: .left) == 3)
        #expect(Treemap.neighbor(of: 4, in: grid, toward: .right) == 5)
        #expect(Treemap.neighbor(of: 4, in: grid, toward: .up) == 1)
        #expect(Treemap.neighbor(of: 0, in: grid, toward: .right) == 1)
        #expect(Treemap.neighbor(of: 0, in: grid, toward: .down) == 3)
        // Edges: nothing beyond.
        #expect(Treemap.neighbor(of: 0, in: grid, toward: .left) == nil)
        #expect(Treemap.neighbor(of: 0, in: grid, toward: .up) == nil)
        #expect(Treemap.neighbor(of: 5, in: grid, toward: .right) == nil)
        #expect(Treemap.neighbor(of: 5, in: grid, toward: .down) == nil)
        // Invalid index.
        #expect(Treemap.neighbor(of: 6, in: grid, toward: .left) == nil)
        #expect(Treemap.neighbor(of: 0, in: [], toward: .left) == nil)
        #expect(Treemap.neighbor(of: 0, in: [rect(0, 0, 10, 10)], toward: .right) == nil)
    }

    @Test func neighborInUnevenLayout() {
        // A tall cell on the left, a column of two on the right (the lower one larger), a strip below.
        let rects = [rect(0, 0, 50, 100), rect(50, 0, 50, 30), rect(50, 30, 50, 70), rect(0, 100, 100, 20)]
        #expect(Treemap.neighbor(of: 0, in: rects, toward: .right) == 2) // greater overlap
        #expect(Treemap.neighbor(of: 1, in: rects, toward: .left) == 0)
        #expect(Treemap.neighbor(of: 2, in: rects, toward: .left) == 0)
        #expect(Treemap.neighbor(of: 1, in: rects, toward: .down) == 2) // nearest edge before the strip
        #expect(Treemap.neighbor(of: 2, in: rects, toward: .up) == 1)
        #expect(Treemap.neighbor(of: 0, in: rects, toward: .down) == 3)
        #expect(Treemap.neighbor(of: 3, in: rects, toward: .up) == 0) // equal overlap: first one wins
        #expect(Treemap.neighbor(of: 3, in: rects, toward: .down) == nil)
        // An adjacent cell wins over a farther one with full overlap.
        let row = [rect(0, 0, 10, 40), rect(10, 0, 10, 10), rect(20, 0, 10, 40)]
        #expect(Treemap.neighbor(of: 0, in: row, toward: .right) == 1)
        #expect(Treemap.neighbor(of: 2, in: row, toward: .left) == 1)
    }

    @Test func neighborFallsBackToNearestCenter() {
        // No cell overlaps 0's span: the nearest center beyond it is taken.
        let rects = [rect(0, 0, 10, 10), rect(20, 20, 10, 10), rect(20, 60, 10, 10), rect(-30, 30, 10, 10)]
        #expect(Treemap.neighbor(of: 0, in: rects, toward: .right) == 1)
        #expect(Treemap.neighbor(of: 0, in: rects, toward: .down) == 1)
        #expect(Treemap.neighbor(of: 0, in: rects, toward: .left) == 3)
        #expect(Treemap.neighbor(of: 0, in: rects, toward: .up) == nil)
        // Empty rects are skipped.
        #expect(Treemap.neighbor(of: 0, in: [rect(0, 0, 10, 10), rect(10, 0, 0, 10)], toward: .right) == nil)
    }

    @Test func neighborInSquarifiedLayoutIsAdjacent() {
        let sizes: [Double] = [500, 300, 200, 120, 80, 60, 40, 25, 10, 5]
        let rects = Treemap.squarify(sizes, in: rect(0, 0, 400, 300))
        for index in rects.indices {
            for direction in Treemap.Direction.allCases {
                guard let next = Treemap.neighbor(of: index, in: rects, toward: direction) else { continue }
                let a = rects[index], b = rects[next]
                // Cells tile the rect, so the neighbor shares the edge.
                let gap = switch direction {
                case .right: b.x - a.maxX
                case .left: a.x - b.maxX
                case .down: b.y - a.maxY
                case .up: a.y - b.maxY
                }
                #expect(abs(gap) < 1e-6)
            }
            // Only cells touching the outer edge have no neighbor that way.
            if Treemap.neighbor(of: index, in: rects, toward: .left) == nil { #expect(abs(rects[index].x) < 1e-6) }
            if Treemap.neighbor(of: index, in: rects, toward: .right) == nil { #expect(abs(rects[index].maxX - 400) < 1e-6) }
            if Treemap.neighbor(of: index, in: rects, toward: .up) == nil { #expect(abs(rects[index].y) < 1e-6) }
            if Treemap.neighbor(of: index, in: rects, toward: .down) == nil { #expect(abs(rects[index].maxY - 300) < 1e-6) }
        }
    }
}
