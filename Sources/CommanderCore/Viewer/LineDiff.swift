// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// How lines are compared.
public struct DiffOptions: Sendable, Equatable {
    public enum Whitespace: String, Sendable, CaseIterable {
        case compare
        /// Runs of spaces/tabs equal one space; leading and trailing ones are ignored.
        case ignoreChanges
        /// Spaces and tabs are ignored completely.
        case ignoreAll
    }

    public var whitespace: Whitespace
    public var ignoreCase: Bool

    public init(whitespace: Whitespace = .compare, ignoreCase: Bool = false) {
        self.whitespace = whitespace
        self.ignoreCase = ignoreCase
    }

    /// The text that is compared instead of `line` (identity when nothing is ignored).
    func normalize(_ line: String) -> String {
        var s = line
        switch whitespace {
        case .compare:
            break
        case .ignoreChanges:
            var out = String.UnicodeScalarView()
            var pendingSpace = false
            for u in line.unicodeScalars {
                if u == " " || u == "\t" {
                    pendingSpace = !out.isEmpty
                } else {
                    if pendingSpace { out.append(" "); pendingSpace = false }
                    out.append(u)
                }
            }
            s = String(out)
        case .ignoreAll:
            var out = String.UnicodeScalarView()
            for u in line.unicodeScalars where u != " " && u != "\t" { out.append(u) }
            s = String(out)
        }
        return ignoreCase ? s.lowercased() : s
    }
}

/// One aligned row of a side-by-side comparison.
public struct DiffRow: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case same
        case changed
        /// Only on the left.
        case deleted
        /// Only on the right.
        case inserted
    }

    public let kind: Kind
    /// 0-based line index on the left; nil for `.inserted`.
    public let left: Int?
    /// 0-based line index on the right; nil for `.deleted`.
    public let right: Int?

    public init(kind: Kind, left: Int?, right: Int?) {
        self.kind = kind
        self.left = left
        self.right = right
    }
}

/// Line-based diff: aligned rows plus the blocks of consecutive differing rows.
public struct LineDiff: Sendable, Equatable {
    /// Aligned rows, top to bottom.
    public let rows: [DiffRow]
    /// Row ranges of consecutive non-`.same` rows, in order.
    public let blocks: [Range<Int>]

    public var isIdentical: Bool { blocks.isEmpty }

    /// Largest edit distance the exact (Myers) search explores before falling back.
    static let maxEditDistance = 4000
    /// Total work (diagonal steps) the exact search may spend before falling back.
    static let workBudget = 50_000_000

    /// Minimal diff of two line arrays. Myers O((N+M)·D) after trimming the common prefix and suffix;
    /// when the cost cap is hit the remaining section is aligned on lines unique to both sides
    /// (patience-like, recursively), and what is left is one replaced block.
    /// Throws `CancellationError` when the task is cancelled.
    public static func compute(left: [String], right: [String], options: DiffOptions = .init()) throws -> LineDiff {
        try Task.checkCancellation()
        let (a, b) = try intern(left, right, options)
        let matches = try align(a, b)

        var rows = [DiffRow]()
        rows.reserveCapacity(max(a.count, b.count) + 16)
        var blocks = [Range<Int>]()
        var blockStart: Int?
        var pi = 0, pj = 0

        func closeBlock() {
            if let s = blockStart { blocks.append(s..<rows.count); blockStart = nil }
        }
        func gap(to i: Int, _ j: Int) {
            let d = i - pi, n = j - pj
            if d == 0 && n == 0 { return }
            if blockStart == nil { blockStart = rows.count }
            let paired = min(d, n)
            for k in 0..<paired { rows.append(DiffRow(kind: .changed, left: pi + k, right: pj + k)) }
            for k in paired..<d { rows.append(DiffRow(kind: .deleted, left: pi + k, right: nil)) }
            for k in paired..<n { rows.append(DiffRow(kind: .inserted, left: nil, right: pj + k)) }
        }

        for (count, m) in matches.enumerated() {
            if count & 0xFFF == 0 { try Task.checkCancellation() }
            gap(to: m.0, m.1)
            closeBlock()
            rows.append(DiffRow(kind: .same, left: m.0, right: m.1))
            pi = m.0 + 1
            pj = m.1 + 1
        }
        gap(to: a.count, b.count)
        closeBlock()
        return LineDiff(rows: rows, blocks: blocks)
    }

    /// Lines split on `\n`, `\r\n` and `\r`; a final terminator does not create an extra empty line; "" gives [].
    public static func lines(of text: String) -> [String] {
        var result = [String]()
        var text = text
        text.withUTF8 { bytes in
            let n = bytes.count
            var start = 0, i = 0
            while i < n {
                let c = bytes[i]
                if c == 10 || c == 13 {
                    result.append(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<i]), as: UTF8.self))
                    if c == 13, i + 1 < n, bytes[i + 1] == 10 { i += 1 }
                    start = i + 1
                }
                i += 1
            }
            if start < n {
                result.append(String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<n]), as: UTF8.self))
            }
        }
        return result
    }

    // MARK: - Internals

    /// Equal normalized lines get equal ids.
    private static func intern(_ left: [String], _ right: [String], _ options: DiffOptions) throws -> ([Int], [Int]) {
        var table = [String: Int]()
        let plain = options == DiffOptions()
        func ids(_ lines: [String]) throws -> [Int] {
            var out = [Int]()
            out.reserveCapacity(lines.count)
            for (n, line) in lines.enumerated() {
                if n & 0xFFF == 0 { try Task.checkCancellation() }
                let key = plain ? line : options.normalize(line)
                if let id = table[key] {
                    out.append(id)
                } else {
                    let id = table.count
                    table[key] = id
                    out.append(id)
                }
            }
            return out
        }
        let a = try ids(left)
        let b = try ids(right)
        return (a, b)
    }

    /// Matched (left, right) index pairs, increasing in both.
    private static func align(_ a: [Int], _ b: [Int]) throws -> [(Int, Int)] {
        var matches = [(Int, Int)]()
        var budget = workBudget
        var stack = [(alo: Int, ahi: Int, blo: Int, bhi: Int)]()
        stack.append((0, a.count, 0, b.count))

        while var s = stack.popLast() {
            try Task.checkCancellation()
            while s.alo < s.ahi, s.blo < s.bhi, a[s.alo] == b[s.blo] {
                matches.append((s.alo, s.blo))
                s.alo += 1
                s.blo += 1
            }
            while s.alo < s.ahi, s.blo < s.bhi, a[s.ahi - 1] == b[s.bhi - 1] {
                s.ahi -= 1
                s.bhi -= 1
                matches.append((s.ahi, s.bhi))
            }
            if s.alo == s.ahi || s.blo == s.bhi { continue }

            if budget > 0,
               let found = try Myers.matches(a, s.alo..<s.ahi, b, s.blo..<s.bhi, maxD: maxEditDistance, budget: &budget) {
                matches.append(contentsOf: found)
                continue
            }

            // Fallback: anchor on lines unique in both sections, align what lies between recursively.
            let anchors = patienceAnchors(a, s.alo..<s.ahi, b, s.blo..<s.bhi)
            var pa = s.alo, pb = s.blo
            for (i, j) in anchors {
                stack.append((pa, i, pb, j))
                matches.append((i, j))
                pa = i + 1
                pb = j + 1
            }
            if !anchors.isEmpty { stack.append((pa, s.ahi, pb, s.bhi)) }
        }
        matches.sort { $0.0 < $1.0 }
        return matches
    }

    /// Longest increasing run of the lines that occur exactly once on both sides.
    private static func patienceAnchors(_ a: [Int], _ ar: Range<Int>, _ b: [Int], _ br: Range<Int>) -> [(Int, Int)] {
        struct Entry { var ca = 0, cb = 0, pb = 0 }
        var table = [Int: Entry]()
        for i in ar { table[a[i], default: Entry()].ca += 1 }
        for j in br {
            guard var e = table[b[j]] else { continue }
            e.cb += 1
            e.pb = j
            table[b[j]] = e
        }
        var cand = [(i: Int, j: Int)]()
        for i in ar {
            if let e = table[a[i]], e.ca == 1, e.cb == 1 { cand.append((i, e.pb)) }
        }
        if cand.isEmpty { return [] }

        // Patience LIS over the right positions.
        var tails = [Int]()          // indexes into cand
        var prev = [Int](repeating: -1, count: cand.count)
        for (c, item) in cand.enumerated() {
            var lo = 0, hi = tails.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if cand[tails[mid]].j < item.j { lo = mid + 1 } else { hi = mid }
            }
            if lo > 0 { prev[c] = tails[lo - 1] }
            if lo == tails.count { tails.append(c) } else { tails[lo] = c }
        }
        var out = [(Int, Int)]()
        var c = tails.last ?? -1
        while c >= 0 {
            out.append((cand[c].i, cand[c].j))
            c = prev[c]
        }
        out.reverse()
        return out
    }
}

/// Myers' greedy forward O((N+M)·D) shortest edit script, with the V snapshots kept for backtracking.
enum Myers {
    /// Matched index pairs (absolute indexes) of a longest common subsequence of `a[ar]` and `b[br]`;
    /// nil when the edit distance exceeds `maxD` or the work exceeds `budget` (which is decremented).
    static func matches(
        _ a: [Int], _ ar: Range<Int>, _ b: [Int], _ br: Range<Int>, maxD: Int, budget: inout Int
    ) throws -> [(Int, Int)]? {
        let n = ar.count, m = br.count
        if n == 0 || m == 0 { return [] }
        let limit = min(maxD, n + m)
        let off = limit + 1
        let aBase = ar.lowerBound, bBase = br.lowerBound
        var v = [Int](repeating: 0, count: 2 * limit + 3)
        // Snapshot d (V after step d) holds diagonals -d, -d+2 … d at base d(d+1)/2, index (k+d)/2.
        var trace = [Int32]()
        var found = -1

        search: for d in 0...limit {
            try Task.checkCancellation()
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[off + k - 1] < v[off + k + 1]) {
                    x = v[off + k + 1]
                } else {
                    x = v[off + k - 1] + 1
                }
                var y = x - k
                let startX = x
                while x < n && y < m && a[aBase + x] == b[bBase + y] { x += 1; y += 1 }
                budget -= 1 + (x - startX)
                v[off + k] = x
                if x >= n && y >= m { found = d; break search }
                k += 2
            }
            if budget < 0 { return nil }
            k = -d
            while k <= d { trace.append(Int32(truncatingIfNeeded: v[off + k])); k += 2 }
        }
        if found < 0 { return nil }

        var pairs = [(Int, Int)]()
        var x = n, y = m
        var d = found
        while d > 0 {
            let k = x - y
            let base = (d - 1) * d / 2
            func prevV(_ kk: Int) -> Int { Int(trace[base + (kk + d - 1) / 2]) }
            let down = k == -d || (k != d && prevV(k - 1) < prevV(k + 1))
            let prevK = down ? k + 1 : k - 1
            let prevX = prevV(prevK)
            let prevY = prevX - prevK
            let midX = down ? prevX : prevX + 1
            while x > midX {
                x -= 1
                y -= 1
                pairs.append((aBase + x, bBase + y))
            }
            x = prevX
            y = prevY
            d -= 1
        }
        while x > 0 {
            x -= 1
            y -= 1
            pairs.append((aBase + x, bBase + y))
        }
        pairs.reverse()
        return pairs
    }
}

/// Character-level highlighting inside a `.changed` row.
public enum InlineDiff {
    /// Lines longer than this (UTF-16 units) are marked as a whole.
    static let maxLength = 4000

    private enum TokenKind { case word, space, other }
    private struct Token {
        var kind: TokenKind
        var text: String
        var range: NSRange
    }

    /// UTF-16 ranges of the characters that differ between two lines, honoring `options`
    /// (text that differs only by ignored whitespace or case is not marked).
    /// Tokens are words (letters/digits/_ runs), whitespace runs and single other characters.
    public static func ranges(left: String, right: String, options: DiffOptions = .init()) -> (left: [NSRange], right: [NSRange]) {
        func whole(_ s: String) -> [NSRange] {
            let n = s.utf16.count
            return n == 0 ? [] : [NSRange(location: 0, length: n)]
        }
        if left.utf16.count > maxLength || right.utf16.count > maxLength {
            return (whole(left), whole(right))
        }
        let lt = tokens(left, options), rt = tokens(right, options)
        var table = [String: Int]()
        func key(_ t: Token) -> Int {
            let s: String
            switch t.kind {
            case .space: s = options.whitespace == .ignoreChanges ? " " : t.text
            default: s = options.ignoreCase ? t.text.lowercased() : t.text
            }
            let tag = (t.kind == .space ? "s" : "t") + s
            if let id = table[tag] { return id }
            let id = table.count
            table[tag] = id
            return id
        }
        let a = lt.map(key), b = rt.map(key)
        var budget = Int.max
        guard let pairs = (try? Myers.matches(a, 0..<a.count, b, 0..<b.count, maxD: 1000, budget: &budget)) else {
            return (whole(left), whole(right))
        }
        var matchedL = [Bool](repeating: false, count: lt.count)
        var matchedR = [Bool](repeating: false, count: rt.count)
        for (i, j) in pairs { matchedL[i] = true; matchedR[j] = true }
        return (marked(lt, matchedL), marked(rt, matchedR))
    }

    private static func marked(_ tokens: [Token], _ matched: [Bool]) -> [NSRange] {
        var out = [NSRange]()
        for (i, t) in tokens.enumerated() where !matched[i] {
            if let last = out.last, last.location + last.length == t.range.location {
                out[out.count - 1].length += t.range.length
            } else {
                out.append(t.range)
            }
        }
        return out
    }

    private static func isWordScalar(_ u: Unicode.Scalar) -> Bool {
        if u == "_" { return true }
        let p = u.properties
        if p.isAlphabetic || p.numericType != nil { return true }
        switch p.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// Tokens with their UTF-16 ranges; whitespace tokens that the options ignore are left out.
    private static func tokens(_ s: String, _ options: DiffOptions) -> [Token] {
        var out = [Token]()
        var offset = 0
        var current: (kind: TokenKind, text: String, start: Int)?
        func flush(end: Int) {
            if let c = current {
                out.append(Token(kind: c.kind, text: c.text, range: NSRange(location: c.start, length: end - c.start)))
                current = nil
            }
        }
        for u in s.unicodeScalars {
            let len = u.value > 0xFFFF ? 2 : 1
            let kind: TokenKind = isWordScalar(u) ? .word : (u.properties.isWhitespace ? .space : .other)
            if kind != .other, let c = current, c.kind == kind {
                current!.text.unicodeScalars.append(u)
            } else {
                flush(end: offset)
                current = (kind, String(u), offset)
            }
            offset += len
            if kind == .other { flush(end: offset) }
        }
        flush(end: offset)

        switch options.whitespace {
        case .compare:
            break
        case .ignoreChanges:
            if out.first?.kind == .space { out.removeFirst() }
            if out.last?.kind == .space { out.removeLast() }
        case .ignoreAll:
            out.removeAll { $0.kind == .space }
        }
        return out
    }
}
