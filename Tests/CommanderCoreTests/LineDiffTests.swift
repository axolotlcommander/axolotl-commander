// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

// File tests live inside a UUID-named directory under FileManager.default.temporaryDirectory,
// created and removed by the test itself.

private func withSandbox(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("icmd-linediff-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

private func diff(_ l: [String], _ r: [String], _ o: DiffOptions = .init()) throws -> LineDiff {
    try LineDiff.compute(left: l, right: r, options: o)
}

/// Every left and right index appears exactly once, in increasing order.
private func isValidAlignment(_ d: LineDiff, leftCount: Int, rightCount: Int) -> Bool {
    var nextL = 0, nextR = 0
    for row in d.rows {
        switch row.kind {
        case .same, .changed:
            guard row.left == nextL, row.right == nextR else { return false }
            nextL += 1; nextR += 1
        case .deleted:
            guard row.left == nextL, row.right == nil else { return false }
            nextL += 1
        case .inserted:
            guard row.left == nil, row.right == nextR else { return false }
            nextR += 1
        }
    }
    return nextL == leftCount && nextR == rightCount
}

private func lcsLength(_ a: [Int], _ b: [Int]) -> Int {
    var prev = [Int](repeating: 0, count: b.count + 1)
    for x in a {
        var cur = [Int](repeating: 0, count: b.count + 1)
        for (j, y) in b.enumerated() {
            cur[j + 1] = x == y ? prev[j] + 1 : max(prev[j + 1], cur[j])
        }
        prev = cur
    }
    return prev[b.count]
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct LineDiffTests {
    // MARK: lines(of:)

    @Test func splitsOnAllTerminators() {
        #expect(LineDiff.lines(of: "a\nb\nc") == ["a", "b", "c"])
        #expect(LineDiff.lines(of: "a\r\nb\r\nc") == ["a", "b", "c"])
        #expect(LineDiff.lines(of: "a\rb\rc") == ["a", "b", "c"])
        #expect(LineDiff.lines(of: "a\r\nb\nc\rd") == ["a", "b", "c", "d"])
    }

    @Test func finalTerminatorAddsNoLine() {
        #expect(LineDiff.lines(of: "a\nb\n") == ["a", "b"])
        #expect(LineDiff.lines(of: "a\r\n") == ["a"])
        #expect(LineDiff.lines(of: "a\n\n") == ["a", ""])
        #expect(LineDiff.lines(of: "\n") == [""])
        #expect(LineDiff.lines(of: "") == [])
    }

    // MARK: Alignment

    @Test func identicalArrays() throws {
        let d = try diff(["a", "b", "c"], ["a", "b", "c"])
        #expect(d.isIdentical)
        #expect(d.blocks.isEmpty)
        #expect(d.rows.count == 3)
        #expect(d.rows.allSatisfy { $0.kind == .same })
        #expect(try diff([], []).rows.isEmpty)
    }

    @Test func insertionAtStartMiddleEnd() throws {
        let start = try diff(["b", "c"], ["a", "b", "c"])
        #expect(start.rows.map(\.kind) == [.inserted, .same, .same])
        #expect(start.blocks == [0..<1])
        let middle = try diff(["a", "c"], ["a", "b", "c"])
        #expect(middle.rows.map(\.kind) == [.same, .inserted, .same])
        #expect(middle.rows[1].right == 1 && middle.rows[1].left == nil)
        let end = try diff(["a", "b"], ["a", "b", "c"])
        #expect(end.rows.map(\.kind) == [.same, .same, .inserted])
        #expect(end.blocks == [2..<3])
    }

    @Test func deletion() throws {
        let d = try diff(["a", "b", "c"], ["a", "c"])
        #expect(d.rows.map(\.kind) == [.same, .deleted, .same])
        #expect(d.rows[1].left == 1 && d.rows[1].right == nil)
        #expect(try diff(["a"], []).rows.map(\.kind) == [.deleted])
    }

    @Test func changePairing() throws {
        let d = try diff(["k", "d1", "d2", "z"], ["k", "i1", "i2", "i3", "z"])
        #expect(d.rows.map(\.kind) == [.same, .changed, .changed, .inserted, .same])
        #expect(d.rows[1].left == 1 && d.rows[1].right == 1)
        #expect(d.rows[2].left == 2 && d.rows[2].right == 2)
        #expect(d.rows[3].left == nil && d.rows[3].right == 3)
        let more = try diff(["k", "d1", "d2", "d3", "z"], ["k", "i1", "z"])
        #expect(more.rows.map(\.kind) == [.same, .changed, .deleted, .deleted, .same])
    }

    @Test func blockRanges() throws {
        let l = ["a", "x", "b", "c", "y", "z", "d", "e"]
        let r = ["a", "b", "c", "q", "d", "e", "w"]
        let d = try diff(l, r)
        // a | -x | b c | y z -> q | d e | +w
        #expect(d.rows.map(\.kind) == [.same, .deleted, .same, .same, .changed, .deleted, .same, .same, .inserted])
        #expect(d.blocks == [1..<2, 4..<6, 8..<9])
        #expect(!d.isIdentical)
        #expect(isValidAlignment(d, leftCount: l.count, rightCount: r.count))
    }

    // MARK: Options

    @Test func ignoreWhitespaceChanges() throws {
        let o = DiffOptions(whitespace: .ignoreChanges)
        #expect(try diff(["a  b"], ["a b"], o).isIdentical)
        #expect(try diff([" a"], ["a"], o).isIdentical)
        #expect(try diff(["a\t \tb  "], ["a b"], o).isIdentical)
        #expect(!(try diff(["a b"], ["ab"], o).isIdentical))
        #expect(!(try diff(["a  b"], ["a b"]).isIdentical))
    }

    @Test func ignoreAllWhitespace() throws {
        let o = DiffOptions(whitespace: .ignoreAll)
        #expect(try diff(["a b"], ["ab"], o).isIdentical)
        #expect(try diff([" a\t b "], ["ab"], o).isIdentical)
        #expect(!(try diff(["a b"], ["ac"], o).isIdentical))
    }

    @Test func ignoreCase() throws {
        #expect(try diff(["Hello"], ["hELLO"], DiffOptions(ignoreCase: true)).isIdentical)
        #expect(!(try diff(["Hello"], ["hELLO"]).isIdentical))
    }

    @Test func czechDiacritics() throws {
        let l = ["Příliš žluťoučký kůň", "úpěl ďábelské ódy", "konec"]
        let r = ["Příliš žluťoučký kůň", "úpěl ďábelské ody", "konec"]
        let d = try diff(l, r)
        #expect(d.rows.map(\.kind) == [.same, .changed, .same])
        #expect(try diff(["ŽLUŤOUČKÝ"], ["žluťoučký"], DiffOptions(ignoreCase: true)).isIdentical)
        #expect(!(try diff(["kun"], ["kůň"], DiffOptions(ignoreCase: true)).isIdentical))
    }

    // MARK: Larger inputs

    @Test func largeFilesWithScatteredDifferences() throws {
        let left = (0..<20_000).map { "line \($0)" }
        var right = left
        var rng = SplitMix(state: 42)
        for _ in 0..<70 { right[Int.random(in: 0..<right.count, using: &rng)] = "changed \(Int.random(in: 0..<1000, using: &rng))" }
        for _ in 0..<70 { right.remove(at: Int.random(in: 0..<right.count, using: &rng)) }
        for _ in 0..<70 { right.insert("added", at: Int.random(in: 0...right.count, using: &rng)) }
        let d = try diff(left, right)
        #expect(!d.isIdentical)
        #expect(d.blocks.count > 50)
        #expect(isValidAlignment(d, leftCount: left.count, rightCount: right.count))
    }

    @Test func completelyDifferentFilesUseFallback() throws {
        let left = (0..<5_000).map { "left \($0)" }
        let right = (0..<5_000).map { "right \($0)" }
        let d = try diff(left, right)
        #expect(isValidAlignment(d, leftCount: 5_000, rightCount: 5_000))
        #expect(d.blocks == [0..<5_000])
        #expect(d.rows.allSatisfy { $0.kind == .changed })
    }

    @Test func fallbackKeepsUniqueAnchors() throws {
        // Far more than the edit-distance cap apart, but with shared unique lines in order.
        var left = [String](), right = [String]()
        for i in 0..<40 {
            left.append("anchor \(i)")
            right.append("anchor \(i)")
            for j in 0..<150 { left.append("L \(i) \(j)"); right.append("R \(i) \(j)") }
        }
        let d = try diff(left, right)
        #expect(isValidAlignment(d, leftCount: left.count, rightCount: right.count))
        #expect(d.rows.filter { $0.kind == .same }.count == 40)
    }

    @Test func matchesLongestCommonSubsequence() throws {
        var rng = SplitMix(state: 7)
        for _ in 0..<300 {
            let l = (0..<Int.random(in: 0...25, using: &rng)).map { _ in Int.random(in: 0..<4, using: &rng) }
            let r = (0..<Int.random(in: 0...25, using: &rng)).map { _ in Int.random(in: 0..<4, using: &rng) }
            let d = try diff(l.map(String.init), r.map(String.init))
            #expect(isValidAlignment(d, leftCount: l.count, rightCount: r.count))
            #expect(d.rows.filter { $0.kind == .same }.count == lcsLength(l, r))
        }
    }

    @Test func cancellationThrows() async throws {
        let left = (0..<20_000).map { "a \($0)" }
        let right = (0..<20_000).map { "b \($0)" }
        let task = Task { () throws -> LineDiff in
            while !Task.isCancelled { await Task.yield() }
            return try LineDiff.compute(left: left, right: right)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // MARK: InlineDiff

    private func substrings(_ s: String, _ ranges: [NSRange]) -> [String] {
        ranges.map { (s as NSString).substring(with: $0) }
    }

    @Test func inlineMarksOnlyChangedWord() {
        let l = "let x = 1", r = "let y = 1"
        let ranges = InlineDiff.ranges(left: l, right: r)
        #expect(ranges.left == [NSRange(location: 4, length: 1)])
        #expect(ranges.right == [NSRange(location: 4, length: 1)])
        #expect(substrings(l, ranges.left) == ["x"])
        #expect(substrings(r, ranges.right) == ["y"])
    }

    @Test func inlineUsesUTF16OffsetsAfterEmoji() {
        let l = "😀 abc end", r = "😀 abd end"
        let ranges = InlineDiff.ranges(left: l, right: r)
        #expect(ranges.left == [NSRange(location: 3, length: 3)])
        #expect(substrings(l, ranges.left) == ["abc"])
        #expect(substrings(r, ranges.right) == ["abd"])
    }

    @Test func inlineHonorsOptions() {
        let ws = InlineDiff.ranges(left: "a  b", right: "a b", options: DiffOptions(whitespace: .ignoreChanges))
        #expect(ws.left.isEmpty && ws.right.isEmpty)
        let all = InlineDiff.ranges(left: "a  b c", right: "a b  d", options: DiffOptions(whitespace: .ignoreAll))
        #expect(substrings("a  b c", all.left) == ["c"])
        #expect(substrings("a b  d", all.right) == ["d"])
        let cs = InlineDiff.ranges(left: "Foo bar", right: "foo baz", options: DiffOptions(ignoreCase: true))
        #expect(substrings("Foo bar", cs.left) == ["bar"])
        #expect(!InlineDiff.ranges(left: "Foo", right: "foo").left.isEmpty)
    }

    @Test func inlineLongLinesMarkedWhole() {
        let l = String(repeating: "a", count: 4001), r = String(repeating: "b", count: 10)
        let ranges = InlineDiff.ranges(left: l, right: r)
        #expect(ranges.left == [NSRange(location: 0, length: 4001)])
        #expect(ranges.right == [NSRange(location: 0, length: 10)])
    }

    // MARK: FileComparison

    @Test func identicalFiles() throws {
        try withSandbox { dir in
            let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
            try Data("same\ntext\n".utf8).write(to: a)
            try Data("same\ntext\n".utf8).write(to: b)
            #expect(try FileComparison.compare(a, b, fallback: .windows1250) == .identical)
            #expect(try FileComparison.firstDifference(a, b) == nil)
        }
    }

    @Test func binaryPrefixDifference() throws {
        try withSandbox { dir in
            let a = dir.appendingPathComponent("a.bin"), b = dir.appendingPathComponent("b.bin")
            try Data([0, 1, 2, 3, 4]).write(to: a)
            try Data([0, 1, 2, 3, 4, 5, 6]).write(to: b)
            let result = try FileComparison.compare(a, b, fallback: .windows1250)
            #expect(result == .binaryDifferent(firstDifference: 5, leftSize: 5, rightSize: 7))
            #expect(try FileComparison.firstDifference(a, b) == 5)
        }
    }

    @Test func binaryDifferenceAcrossChunks() throws {
        try withSandbox { dir in
            let a = dir.appendingPathComponent("a.bin"), b = dir.appendingPathComponent("b.bin")
            var bytes = [UInt8](repeating: 0, count: (1 << 20) + 100)
            try Data(bytes).write(to: a)
            bytes[(1 << 20) + 50] = 9
            try Data(bytes).write(to: b)
            #expect(try FileComparison.firstDifference(a, b) == Int64((1 << 20) + 50))
            let result = try FileComparison.compare(a, b, fallback: .windows1250)
            #expect(result == .binaryDifferent(firstDifference: Int64((1 << 20) + 50), leftSize: Int64(bytes.count), rightSize: Int64(bytes.count)))
        }
    }

    @Test func differentEncodingsSameTextAreIdentical() throws {
        try withSandbox { dir in
            let text = "Příliš žluťoučký kůň\núpěl ďábelské ódy\n"
            let a = dir.appendingPathComponent("utf8.txt"), b = dir.appendingPathComponent("cp1250.txt")
            try Data(text.utf8).write(to: a)
            let legacy = try #require(TextEncoding.windows1250.encode(text))
            try Data(legacy).write(to: b)
            let result = try FileComparison.compare(a, b, fallback: .windows1250)
            guard case let .text(d, left, right, le, re) = result else {
                Issue.record("expected .text, got \(result)")
                return
            }
            #expect(d.isIdentical)
            #expect(left == right)
            #expect(left.count == 2)
            #expect(le == .utf8)
            #expect(re == .windows1250)
        }
    }

    @Test func textDifferenceAndTextLimit() throws {
        try withSandbox { dir in
            let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
            try Data("one\ntwo\nthree\n".utf8).write(to: a)
            try Data("one\n2\nthree\nfour\n".utf8).write(to: b)
            guard case let .text(d, left, right, _, _) = try FileComparison.compare(a, b, fallback: .utf8) else {
                Issue.record("expected .text")
                return
            }
            #expect(left.count == 3 && right.count == 4)
            #expect(d.rows.map(\.kind) == [.same, .changed, .same, .inserted])
            let small = try FileComparison.compare(a, b, fallback: .utf8, textLimit: 4)
            #expect(small == .binaryDifferent(firstDifference: 4, leftSize: 14, rightSize: 17))
        }
    }
}
