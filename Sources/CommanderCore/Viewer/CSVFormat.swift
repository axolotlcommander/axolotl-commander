// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// The field separators the table preview recognizes.
public enum CSVSeparator: String, CaseIterable, Sendable, Codable {
    case semicolon, comma, tab, bar

    /// The separator as a code unit (the same in bytes and in UTF-16).
    public var unit: UInt32 {
        switch self {
        case .semicolon: 0x3B
        case .comma: 0x2C
        case .tab: 0x09
        case .bar: 0x7C
        }
    }
}

/// How a file is read as a table.
public struct CSVDialect: Sendable, Equatable {
    /// nil: the file is a single column.
    public var separator: CSVSeparator?
    public var encoding: TextEncoding
    /// Byte offset where the content starts (after a byte order mark).
    public var contentStart: Int

    public init(separator: CSVSeparator?, encoding: TextEncoding, contentStart: Int = 0) {
        self.separator = separator
        self.encoding = encoding
        self.contentStart = contentStart
    }
}

/// The number rule used for alignment, sorting and header detection: an optional sign, digits,
/// and at most one decimal point or comma followed by more digits.
public enum CSVNumber {
    /// `allowComma` is false when the comma separates fields.
    public static func parse(_ cell: String, allowComma: Bool = true) -> Double? {
        var digitsBefore = 0, digitsAfter = 0, sawDecimal = false, first = true
        var normalized = ""
        normalized.reserveCapacity(cell.utf8.count)
        for byte in cell.utf8 {
            defer { first = false }
            switch byte {
            case UInt8(ascii: "+"), UInt8(ascii: "-"):
                guard first else { return nil }
                normalized.append(Character(UnicodeScalar(byte)))
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                if sawDecimal { digitsAfter += 1 } else { digitsBefore += 1 }
                normalized.append(Character(UnicodeScalar(byte)))
            case UInt8(ascii: "."), UInt8(ascii: ","):
                guard !sawDecimal, digitsBefore > 0, byte == UInt8(ascii: ".") || allowComma else { return nil }
                sawDecimal = true
                normalized.append(".")
            default:
                return nil
            }
        }
        guard digitsBefore > 0, !sawDecimal || digitsAfter > 0 else { return nil }
        return Double(normalized)
    }

    public static func isNumber(_ cell: String, allowComma: Bool = true) -> Bool {
        parse(cell, allowComma: allowComma) != nil
    }
}

/// What the beginning of a file says about it: the separator, whether the first row is a header,
/// which columns hold numbers, and the sampled rows (for column widths).
public struct CSVSample: Sendable, Equatable {
    public var separator: CSVSeparator?
    public var hasHeader: Bool
    public var numericColumns: Set<Int>
    public var rows: [[String]]

    /// The sample ends after this many bytes or rows, whichever comes first.
    public static let byteLimit = 65_536
    public static let rowLimit = 1_000
    /// Share of non-empty cells that must be numbers for a numeric column.
    public static let numericShare = 0.9

    /// Picks the separator that gives the most rows with the same field count above 1. Ties go to
    /// tab first when `preferTab` (.tsv, .tab), otherwise semicolon, comma, tab, vertical bar.
    public static func detect(_ data: Data, encoding: TextEncoding, contentStart: Int, preferTab: Bool) -> CSVSample {
        let order: [CSVSeparator] = preferTab ? [.tab, .semicolon, .comma, .bar] : [.semicolon, .comma, .tab, .bar]
        var best: CSVSeparator?
        var bestScore = 0
        for candidate in order {
            let dialect = CSVDialect(separator: candidate, encoding: encoding, contentStart: contentStart)
            let score = Self.score(CSVIndexer.sampleIndex(data, dialect: dialect))
            if score > bestScore {
                best = candidate
                bestScore = score
            }
        }
        return make(data, dialect: CSVDialect(separator: best, encoding: encoding, contentStart: contentStart))
    }

    /// The sample read with a fixed separator (detected or chosen by the user).
    public static func make(_ data: Data, dialect: CSVDialect) -> CSVSample {
        let index = CSVIndexer.sampleIndex(data, dialect: dialect)
        let rows = (0..<index.rowCount).map { CSVRow.fields(in: data, index: index, row: $0, dialect: dialect) }
        return CSVSample(rows: rows, separator: dialect.separator)
    }

    init(rows: [[String]], separator: CSVSeparator?) {
        self.separator = separator
        self.rows = rows
        let allowComma = separator != .comma
        let body = rows.count >= 2 ? rows.dropFirst() : rows[...]
        let width = rows.map(\.count).max() ?? 0
        var numeric = Set<Int>()
        for column in 0..<width {
            var filled = 0, numbers = 0
            for row in body where column < row.count && !row[column].isEmpty {
                filled += 1
                if CSVNumber.isNumber(row[column], allowComma: allowComma) { numbers += 1 }
            }
            if filled > 0, Double(numbers) >= Double(filled) * Self.numericShare { numeric.insert(column) }
        }
        numericColumns = numeric
        hasHeader = Self.looksLikeHeader(rows, numeric: numeric, allowComma: allowComma)
    }

    /// The first row is a header when every cell is non-empty text, and either some column holds
    /// numbers below it or none of its values appears again in its own column.
    private static func looksLikeHeader(_ rows: [[String]], numeric: Set<Int>, allowComma: Bool) -> Bool {
        guard rows.count >= 2, let first = rows.first, !first.isEmpty else { return false }
        guard first.allSatisfy({ !$0.isEmpty && !CSVNumber.isNumber($0, allowComma: allowComma) }) else { return false }
        if !numeric.isEmpty { return true }
        for (column, title) in first.enumerated() {
            if rows.dropFirst().contains(where: { column < $0.count && $0[column] == title }) { return false }
        }
        return true
    }

    private static func score(_ index: CSVIndex) -> Int {
        let expected = index.expectedFields(excludingFirst: false)
        guard expected > 1 else { return 0 }
        return index.histogram[UInt32(expected)] ?? 0
    }
}
