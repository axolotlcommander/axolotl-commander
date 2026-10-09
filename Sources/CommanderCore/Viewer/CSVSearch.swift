// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// The rows a table shows, in display order: a range of file rows, or a list (sorted or filtered).
public enum CSVRowList: Sendable, Equatable {
    case range(Range<Int>)
    case list([Int])

    public var count: Int {
        switch self {
        case .range(let range): range.count
        case .list(let rows): rows.count
        }
    }

    /// File row at a display position.
    public subscript(position: Int) -> Int {
        switch self {
        case .range(let range): range.lowerBound + position
        case .list(let rows): rows[position]
        }
    }

    /// Display position of a file row, if it is shown.
    public func position(of row: Int) -> Int? {
        switch self {
        case .range(let range): range.contains(row) ? row - range.lowerBound : nil
        case .list(let rows): rows.firstIndex(of: row)
        }
    }
}

public enum CSVSearch {
    public struct Match: Sendable, Equatable {
        /// Display position of the row.
        public var position: Int
        public var column: Int

        public init(position: Int, column: Int) {
            self.position = position
            self.column = column
        }
    }

    /// Finds the next row (in display order, wrapping around) with a cell containing `query`,
    /// starting after `position` (before it when `backward`; -1 = from the start or the end).
    /// Diacritics are always ignored, case when `ignoreCase`. Throws when the task is cancelled.
    public static func find(_ query: String, ignoreCase: Bool, locale: Locale = .current,
                            in data: Data, index: CSVIndex, dialect: CSVDialect, rows: CSVRowList,
                            from position: Int, backward: Bool,
                            progress: (Double) -> Void = { _ in }) throws -> Match? {
        let count = rows.count
        guard !query.isEmpty, count > 0 else { return nil }
        var options: String.CompareOptions = [.diacriticInsensitive]
        if ignoreCase { options.insert(.caseInsensitive) }
        let literal = index.literalQuotes
        let origin = position < 0 || position >= count ? (backward ? count : -1) : position
        for step in 0..<count {
            if step % 1_024 == 0 {
                try Task.checkCancellation()
                progress(Double(step) / Double(count))
            }
            let raw = backward ? origin - 1 - step : origin + 1 + step
            let at = (raw % count + count) % count
            let range = index.range(ofRow: rows[at])
            // The whole row first; only a hit is split to find its cell (a match across a separator is none).
            let line = data.withUnsafeBytes { bytes in
                TextDecoding.decode(UnsafeBufferPointer(rebasing: bytes.bindMemory(to: UInt8.self)[range]),
                                    as: dialect.encoding)
            }
            guard line.range(of: query, options: options, locale: locale) != nil else { continue }
            let fields = CSVRow.fields(in: data, range: range, dialect: dialect, literalQuotes: literal)
            if let column = fields.firstIndex(where: { $0.range(of: query, options: options, locale: locale) != nil }) {
                return Match(position: at, column: column)
            }
        }
        return nil
    }
}
