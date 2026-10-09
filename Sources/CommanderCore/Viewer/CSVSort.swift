// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Orders table rows by one column; only the view changes, never the file.
public enum CSVSort {
    /// Above this many distinct texts, they are sorted in chunks on all cores and merged.
    static let parallelThreshold = 50_000

    /// File rows of `rows` ordered by `column`:
    /// - numbers by value when `numeric` (cells that are not numbers after them, in file order);
    /// - text by the locale's comparison ignoring case;
    /// - empty cells last in both directions;
    /// - equal values in file order.
    /// Throws when the task is cancelled.
    public static func order(_ data: Data, index: CSVIndex, dialect: CSVDialect, rows: Range<Int>, column: Int,
                             numeric: Bool, ascending: Bool, locale: Locale = .current,
                             progress: @Sendable (Double) -> Void = { _ in }) async throws -> [Int32] {
        let cells = try extract(data, index: index, dialect: dialect, rows: rows, column: column, progress: progress)
        try Task.checkCancellation()
        // Group: 0 = sorted value, 1 = a text cell in a numeric column, 2 = empty.
        var group = [UInt8](repeating: 0, count: cells.count)
        var keys = [Double](repeating: 0, count: cells.count)
        if numeric {
            let allowComma = dialect.separator != .comma
            for (i, cell) in cells.enumerated() {
                if cell.isEmpty { group[i] = 2 } else if let value = CSVNumber.parse(cell, allowComma: allowComma) {
                    keys[i] = value
                } else { group[i] = 1 }
            }
        } else {
            let ranks = try await textRanks(cells, locale: locale)
            for (i, cell) in cells.enumerated() {
                if cell.isEmpty { group[i] = 2 } else { keys[i] = Double(ranks[i]) }
            }
        }
        try Task.checkCancellation()
        var positions = Array(0..<Int32(cells.count))
        positions.sort { a, b in
            let ga = group[Int(a)], gb = group[Int(b)]
            if ga != gb { return ga < gb }
            if ga == 0 {
                let ka = keys[Int(a)], kb = keys[Int(b)]
                if ka != kb { return ascending ? ka < kb : ka > kb }
            }
            return a < b
        }
        let first = Int32(rows.lowerBound)
        return positions.map { $0 + first }
    }

    /// The cell of `column` in every row (empty when a row is shorter).
    private static func extract(_ data: Data, index: CSVIndex, dialect: CSVDialect, rows: Range<Int>,
                                column: Int, progress: (Double) -> Void) throws -> [String] {
        let literal = index.literalQuotes
        var cells: [String] = []
        cells.reserveCapacity(rows.count)
        for row in rows {
            if (row - rows.lowerBound) % 8_192 == 0 {
                try Task.checkCancellation()
                progress(0.5 * Double(row - rows.lowerBound) / Double(max(rows.count, 1)))
            }
            let fields = CSVRow.fields(in: data, range: index.range(ofRow: row), dialect: dialect,
                                       literalQuotes: literal, limit: column + 1)
            cells.append(column < fields.count ? fields[column] : "")
        }
        return cells
    }

    /// Compares texts by a locale's rules, ignoring case. A CoreFoundation locale made once is safe
    /// to share and lets comparisons run in parallel (measured: comparing through `Locale` serializes
    /// on a lock, so parallel chunks were slower than one thread).
    struct Collator: @unchecked Sendable {
        private let locale: CFLocale

        init(_ locale: Locale) {
            self.locale = CFLocaleCreate(nil, CFLocaleIdentifier(rawValue: locale.identifier as CFString))
        }

        func order(_ a: String, _ b: String) -> CFComparisonResult {
            CFStringCompareWithOptionsAndLocale(a as CFString, b as CFString, CFRange(location: 0, length: a.utf16.count),
                                                [.compareCaseInsensitive, .compareLocalized], locale)
        }
    }

    /// The rank of each cell's text among the distinct texts, in the locale's order.
    static func textRanks(_ cells: [String], locale: Locale) async throws -> [Int32] {
        var ids: [String: Int32] = [:]
        var distinct: [String] = []
        var cellIDs = [Int32](repeating: 0, count: cells.count)
        for (i, cell) in cells.enumerated() {
            if let id = ids[cell] {
                cellIDs[i] = id
            } else {
                let id = Int32(distinct.count)
                ids[cell] = id
                distinct.append(cell)
                cellIDs[i] = id
            }
        }
        ids = [:]
        let collator = Collator(locale)
        let sorted = try await sortedIDs(distinct, collator: collator)
        // Texts the comparison finds equal ("Praha", "praha") share a rank, so they keep file order.
        var rankOfID = [Int32](repeating: 0, count: distinct.count)
        var rank: Int32 = 0
        for (k, id) in sorted.enumerated() {
            if k > 0, collator.order(distinct[Int(sorted[k - 1])], distinct[Int(id)]) != .compareEqualTo { rank += 1 }
            rankOfID[Int(id)] = rank
        }
        return cellIDs.map { rankOfID[Int($0)] }
    }

    /// Indices of `texts` in the locale's order; large inputs are sorted in chunks on all cores and
    /// merged pairwise, also in parallel.
    private static func sortedIDs(_ texts: [String], collator: Collator) async throws -> [Int32] {
        @Sendable func less(_ a: Int32, _ b: Int32) -> Bool {
            // A cancelled sort finishes fast with any order; the caller throws afterwards.
            if Task.isCancelled { return false }
            return collator.order(texts[Int(a)], texts[Int(b)]) == .compareLessThan
        }
        let all = Array(0..<Int32(texts.count))
        guard texts.count > parallelThreshold else {
            let result = all.sorted(by: less)
            try Task.checkCancellation()
            return result
        }
        let parts = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let size = (texts.count + parts - 1) / parts
        var chunks = try await withThrowingTaskGroup(of: (Int, [Int32]).self) { group in
            for part in 0..<parts {
                let slice = Array(all[min(part * size, all.count)..<min((part + 1) * size, all.count)])
                group.addTask { (part, slice.sorted(by: less)) }
            }
            var result = [[Int32]](repeating: [], count: parts)
            for try await (part, chunk) in group { result[part] = chunk }
            return result
        }
        try Task.checkCancellation()
        while chunks.count > 1 {
            let round = chunks
            chunks = try await withThrowingTaskGroup(of: (Int, [Int32]).self) { group in
                for pair in stride(from: 0, to: round.count, by: 2) {
                    group.addTask {
                        (pair / 2, pair + 1 < round.count ? merge(round[pair], round[pair + 1], by: less) : round[pair])
                    }
                }
                var result = [[Int32]](repeating: [], count: (round.count + 1) / 2)
                for try await (slot, merged) in group { result[slot] = merged }
                return result
            }
            try Task.checkCancellation()
        }
        return chunks.first ?? []
    }

    private static func merge(_ a: [Int32], _ b: [Int32], by less: (Int32, Int32) -> Bool) -> [Int32] {
        var result: [Int32] = []
        result.reserveCapacity(a.count + b.count)
        var i = 0, j = 0
        while i < a.count, j < b.count {
            // `b` wins only when strictly smaller, so equal texts keep their index order.
            if less(b[j], a[i]) {
                result.append(b[j])
                j += 1
            } else {
                result.append(a[i])
                i += 1
            }
        }
        result.append(contentsOf: a[i...])
        result.append(contentsOf: b[j...])
        return result
    }
}
