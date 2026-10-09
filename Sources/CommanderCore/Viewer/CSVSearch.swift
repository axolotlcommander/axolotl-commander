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

    /// Finds the next cell (in display order, wrapping around) containing `query`. The search starts
    /// after cell `column` of the row at `position` (before it when `backward`): the rest of that
    /// row first, then the following rows, and that row's remaining cells last. A nil `column`
    /// starts after (before) the whole row; a `position` outside the rows starts at the first (last)
    /// row. Diacritics are always ignored, case when `ignoreCase`. Throws when the task is cancelled.
    public static func find(_ query: String, ignoreCase: Bool, locale: Locale = .current,
                            in data: Data, index: CSVIndex, dialect: CSVDialect, rows: CSVRowList,
                            from position: Int, column: Int? = nil, backward: Bool,
                            progress: (Double) -> Void = { _ in }) throws -> Match? {
        let count = rows.count
        guard !query.isEmpty, count > 0 else { return nil }
        var options: String.CompareOptions = [.diacriticInsensitive]
        if ignoreCase { options.insert(.caseInsensitive) }
        let literal = index.literalQuotes

        /// The first (last, backward) cell of a row that matches and passes `allowed`.
        func cell(at position: Int, where allowed: (Int) -> Bool) -> Int? {
            let range = index.range(ofRow: rows[position])
            // The whole row first; only a hit is split to find its cell (a match across a separator is none).
            let line = data.withUnsafeBytes { bytes in
                TextDecoding.decode(UnsafeBufferPointer(rebasing: bytes.bindMemory(to: UInt8.self)[range]),
                                    as: dialect.encoding)
            }
            guard line.range(of: query, options: options, locale: locale) != nil else { return nil }
            let fields = CSVRow.fields(in: data, range: range, dialect: dialect, literalQuotes: literal)
            let columns = backward ? Array(fields.indices.reversed()) : Array(fields.indices)
            return columns.first { allowed($0) && fields[$0].range(of: query, options: options, locale: locale) != nil }
        }

        let valid = position >= 0 && position < count
        let origin = valid ? position : (backward ? count : -1)
        if valid, let column, let found = cell(at: origin, where: { backward ? $0 < column : $0 > column }) {
            return Match(position: origin, column: found)
        }
        let steps = valid ? count - 1 : count
        for step in stride(from: 1, through: steps, by: 1) {
            if step % 1_024 == 0 {
                try Task.checkCancellation()
                progress(Double(step) / Double(count))
            }
            let raw = backward ? origin - step : origin + step
            let at = (raw % count + count) % count
            if let found = cell(at: at, where: { _ in true }) { return Match(position: at, column: found) }
        }
        if valid, let found = cell(at: origin, where: { candidate in
            guard let column else { return true }
            return backward ? candidate >= column : candidate <= column
        }) {
            return Match(position: origin, column: found)
        }
        return nil
    }
}
