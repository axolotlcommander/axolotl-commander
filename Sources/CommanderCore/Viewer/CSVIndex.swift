// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

// Reading separated values for the table preview. The file is never decoded as a whole: one pass
// records where each row starts and how many fields it has, and a row is split again from its
// bytes when it is shown. The rules follow RFC 4180 (quotes, doubled quotes, separators and line
// breaks inside quotes) and are lenient where files break them (see `CSVRow.fields`).

/// A quote that was still open at the end of the file; it is read as an ordinary character.
public struct CSVUnclosedQuote: Sendable, Equatable {
    /// File row (0-based) where the quote opened.
    public var row: Int
    /// Byte offset of the quote.
    public var offset: Int
}

/// Row positions and field counts of a file, complete or as far as it has been read.
public struct CSVIndex: Sendable {
    /// Byte offset of each row, plus the offset where the next (unread) row starts.
    public private(set) var rowStarts: [Int]
    public private(set) var fieldCounts: [UInt32] = []
    /// Field count → number of rows with it.
    public private(set) var histogram: [UInt32: Int] = [:]
    /// The widest row.
    public private(set) var maxFields = 0
    public internal(set) var unclosedQuotes: [CSVUnclosedQuote] = []
    public internal(set) var isComplete = false

    public init(start: Int = 0) {
        rowStarts = [start]
    }

    public var rowCount: Int { fieldCounts.count }

    /// Bytes of a row, including its line break.
    public func range(ofRow row: Int) -> Range<Int> { rowStarts[row]..<rowStarts[row + 1] }

    /// Quotes read as ordinary characters (unclosed ones).
    public var literalQuotes: Set<Int> { Set(unclosedQuotes.map(\.offset)) }

    /// The row holding `offset`, or the last row when the offset is past the rows read so far.
    public func row(containing offset: Int) -> Int {
        guard rowCount > 0 else { return 0 }
        var low = 0, high = rowCount - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if rowStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The most common field count (the larger one on a tie), leaving out the header row.
    public func expectedFields(excludingFirst: Bool) -> Int {
        var counts = histogram
        if excludingFirst, let first = fieldCounts.first {
            counts[first, default: 0] -= 1
        }
        var best = 0, bestRows = 0
        for (fields, rows) in counts where rows > bestRows || (rows == bestRows && Int(fields) > best) {
            guard rows > 0 else { continue }
            best = Int(fields)
            bestRows = rows
        }
        return best
    }

    /// File rows whose field count differs from the expected one, or that hold an unclosed quote, ascending.
    public func malformedRows(excludingFirst: Bool) -> [Int] {
        let expected = UInt32(expectedFields(excludingFirst: excludingFirst))
        let unclosed = Set(unclosedQuotes.map(\.row))
        var rows: [Int] = []
        for row in (excludingFirst ? 1 : 0)..<max(rowCount, excludingFirst ? 1 : 0)
        where fieldCounts[row] != expected || (!unclosed.isEmpty && unclosed.contains(row)) {
            rows.append(row)
        }
        return rows
    }

    mutating func appendRow(fields: Int, next: Int) {
        let count = UInt32(clamping: fields)
        fieldCounts.append(count)
        rowStarts.append(next)
        histogram[count, default: 0] += 1
        if fields > maxFields { maxFields = fields }
    }

    mutating func reserve(_ rows: Int) {
        rowStarts.reserveCapacity(rows + 1)
        fieldCounts.reserveCapacity(rows)
    }
}

// MARK: Code units

/// Reads the file as code units: bytes for UTF-8 and the single-byte encodings (all of them
/// ASCII-compatible, so separators, quotes and line breaks are single bytes), 16-bit units for UTF-16.
protocol CSVUnits {
    var width: Int { get }
    func unit(at offset: Int) -> UInt32
}

struct CSVByteUnits: CSVUnits {
    let base: UnsafePointer<UInt8>
    var width: Int { 1 }
    @inline(__always) func unit(at offset: Int) -> UInt32 { UInt32(base[offset]) }
}

struct CSVUTF16Units: CSVUnits {
    let base: UnsafePointer<UInt8>
    let bigEndian: Bool
    var width: Int { 2 }
    @inline(__always) func unit(at offset: Int) -> UInt32 {
        let a = UInt32(base[offset]), b = UInt32(base[offset + 1])
        return bigEndian ? a << 8 | b : b << 8 | a
    }
}

private let quote: UInt32 = 0x22
private let lineFeed: UInt32 = 0x0A
private let carriageReturn: UInt32 = 0x0D
/// Never equal to a code unit: the separator of a single-column file.
private let noSeparator: UInt32 = 0x1_0000

extension CSVDialect {
    var separatorUnit: UInt32 { separator?.unit ?? noSeparator }
    var unitWidth: Int { encoding == .utf16LE || encoding == .utf16BE ? 2 : 1 }
}

/// Calls `bytes` or `utf16` (so each is specialized for its unit type) with the file's code units,
/// the raw bytes and the end of the content (UTF-16 rounded down to whole units).
private func withUnits<R>(_ data: Data, _ dialect: CSVDialect,
                          bytes: (CSVByteUnits, UnsafeRawBufferPointer, Int) -> R,
                          utf16: (CSVUTF16Units, UnsafeRawBufferPointer, Int) -> R) -> R? {
    data.withUnsafeBytes { raw -> R? in
        guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
        switch dialect.encoding {
        case .utf16LE, .utf16BE:
            let start = dialect.contentStart
            let end = start + (max(raw.count - start, 0) / 2) * 2
            return utf16(CSVUTF16Units(base: base, bigEndian: dialect.encoding == .utf16BE), raw, end)
        default:
            return bytes(CSVByteUnits(base: base), raw, raw.count)
        }
    }
}

// MARK: Indexing

public enum CSVIndexer {
    /// Rows between progress callbacks.
    static let progressRows = 4_096

    /// Indexes the whole file. `progress` is called every few thousand rows with the index so far;
    /// returning false stops (the result is then nil).
    public static func build(_ data: Data, dialect: CSVDialect, progress: (CSVIndex) -> Bool = { _ in true }) -> CSVIndex? {
        var index = CSVIndex(start: min(dialect.contentStart, data.count))
        guard data.count > dialect.contentStart else {
            index.isComplete = true
            return index
        }
        // About one row per 64 bytes saves most reallocations; untouched capacity costs no memory.
        index.reserve(min(data.count / 64, 1 << 22))
        var literal = Set<Int>()
        let start = dialect.contentStart, separator = dialect.separatorUnit
        let finished = withUnits(data, dialect, bytes: { units, _, end in
            scan(units, from: start, to: end, separator: separator, recover: true, finishLastRow: true,
                 rowLimit: .max, literal: &literal, index: &index, progress: progress)
        }, utf16: { units, _, end in
            scan(units, from: start, to: end, separator: separator, recover: true, finishLastRow: true,
                 rowLimit: .max, literal: &literal, index: &index, progress: progress)
        }) ?? true
        guard finished else { return nil }
        index.isComplete = true
        return index
    }

    /// Indexes the file in the background, yielding the index soon after the first rows, then
    /// about every 100 ms, and finally the complete one. Cancelling the consumer stops the work.
    public static func stream(_ data: Data, dialect: CSVDialect) -> AsyncStream<CSVIndex> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let clock = ContinuousClock()
                var last = clock.now
                var yielded = false
                let result = build(data, dialect: dialect) { index in
                    if Task.isCancelled { return false }
                    let now = clock.now
                    if !yielded || now - last >= .milliseconds(100) {
                        continuation.yield(index)
                        yielded = true
                        last = now
                    }
                    return true
                }
                if let result, !Task.isCancelled { continuation.yield(result) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The rows of the detection sample: up to `CSVSample.byteLimit` bytes or `rowLimit` rows; a
    /// row cut by the sample's end (or inside an open quote) is left out.
    static func sampleIndex(_ data: Data, dialect: CSVDialect) -> CSVIndex {
        var index = CSVIndex(start: min(dialect.contentStart, data.count))
        guard data.count > dialect.contentStart else { return index }
        var literal = Set<Int>()
        let start = dialect.contentStart, separator = dialect.separatorUnit
        _ = withUnits(data, dialect, bytes: { units, _, end in
            let sampleEnd = min(end, start + CSVSample.byteLimit)
            return scan(units, from: start, to: sampleEnd, separator: separator, recover: false,
                        finishLastRow: sampleEnd == end, rowLimit: CSVSample.rowLimit,
                        literal: &literal, index: &index, progress: { _ in true })
        }, utf16: { units, _, end in
            let sampleEnd = min(end, start + CSVSample.byteLimit)
            return scan(units, from: start, to: sampleEnd, separator: separator, recover: false,
                        finishLastRow: sampleEnd == end, rowLimit: CSVSample.rowLimit,
                        literal: &literal, index: &index, progress: { _ in true })
        })
        return index
    }

    /// The row scanner. Returns false when `progress` asked to stop.
    private static func scan<U: CSVUnits>(_ units: U, from start: Int, to end: Int, separator: UInt32,
                                          recover: Bool, finishLastRow: Bool, rowLimit: Int,
                                          literal: inout Set<Int>, index: inout CSVIndex,
                                          progress: (CSVIndex) -> Bool) -> Bool {
        let w = units.width
        var rowStart = start
        while true {
            var i = rowStart
            var fields = 1
            var atFieldStart = true
            var inQuote = false
            var quoteAt = -1
            while i < end {
                let c = units.unit(at: i)
                if inQuote {
                    if c == quote {
                        if i + w < end, units.unit(at: i + w) == quote {
                            i += 2 * w
                            continue
                        }
                        inQuote = false
                    }
                    i += w
                    continue
                }
                if c == separator {
                    fields += 1
                    atFieldStart = true
                    i += w
                    continue
                }
                if c == lineFeed || c == carriageReturn {
                    var next = i + w
                    if c == carriageReturn, next < end, units.unit(at: next) == lineFeed { next += w }
                    index.appendRow(fields: fields, next: next)
                    if index.rowCount >= rowLimit { return true }
                    if index.rowCount % progressRows == 0, !progress(index) { return false }
                    rowStart = next
                    fields = 1
                    atFieldStart = true
                    i = next
                    continue
                }
                if c == quote, atFieldStart, literal.isEmpty || !literal.contains(i) {
                    inQuote = true
                    quoteAt = i
                }
                atFieldStart = false
                i += w
            }
            if inQuote {
                guard recover else { return true }
                // No row was recorded inside the quote: read its row again with the quote as text.
                literal.insert(quoteAt)
                index.unclosedQuotes.append(CSVUnclosedQuote(row: index.rowCount, offset: quoteAt))
                continue
            }
            if rowStart < end, finishLastRow { index.appendRow(fields: fields, next: end) }
            return true
        }
    }
}

// MARK: Splitting a row

public enum CSVRow {
    /// The fields of one indexed row (at most `limit`).
    public static func fields(in data: Data, index: CSVIndex, row: Int, dialect: CSVDialect,
                              limit: Int = .max) -> [String] {
        guard row >= 0, row < index.rowCount else { return [] }
        return fields(in: data, range: index.range(ofRow: row), dialect: dialect,
                      literalQuotes: index.literalQuotes, limit: limit)
    }

    /// Splits the bytes of one row. A quote opens a quoted field only at the start of a field;
    /// elsewhere, and at the offsets in `literalQuotes`, it is an ordinary character. Text after a
    /// closing quote is kept as part of the field. An unquoted CR or LF ends the row.
    public static func fields(in data: Data, range: Range<Int>, dialect: CSVDialect,
                              literalQuotes: Set<Int> = [], limit: Int = .max) -> [String] {
        let separator = dialect.separatorUnit, encoding = dialect.encoding
        return withUnits(data, dialect, bytes: { units, raw, end in
            split(units, raw: raw, from: range.lowerBound, to: min(range.upperBound, end),
                  separator: separator, encoding: encoding, literal: literalQuotes, limit: limit)
        }, utf16: { units, raw, end in
            split(units, raw: raw, from: range.lowerBound, to: min(range.upperBound, end),
                  separator: separator, encoding: encoding, literal: literalQuotes, limit: limit)
        }) ?? []
    }

    private static func split<U: CSVUnits>(_ units: U, raw: UnsafeRawBufferPointer, from start: Int, to end: Int,
                                           separator: UInt32, encoding: TextEncoding, literal: Set<Int>,
                                           limit: Int) -> [String] {
        let w = units.width
        let bytes = raw.bindMemory(to: UInt8.self)
        var fields: [String] = []
        var i = start
        var fieldStart = start
        var atFieldStart = true
        var quoted = false
        var inQuote = false
        var buffer: [UInt8] = []

        func take(_ offset: Int) { buffer.append(contentsOf: bytes[offset..<(offset + w)]) }
        func finish(at offset: Int) {
            if quoted {
                fields.append(buffer.withUnsafeBufferPointer { TextDecoding.decode($0, as: encoding) })
            } else {
                fields.append(TextDecoding.decode(UnsafeBufferPointer(rebasing: bytes[fieldStart..<offset]), as: encoding))
            }
            buffer.removeAll(keepingCapacity: true)
            quoted = false
            atFieldStart = true
        }

        while i < end {
            let c = units.unit(at: i)
            if inQuote {
                if c == quote {
                    if i + w < end, units.unit(at: i + w) == quote {
                        take(i)
                        i += 2 * w
                        continue
                    }
                    inQuote = false
                } else {
                    take(i)
                }
                i += w
                continue
            }
            if c == separator {
                finish(at: i)
                if fields.count >= limit { return fields }
                i += w
                fieldStart = i
                continue
            }
            if c == lineFeed || c == carriageReturn { break }
            if c == quote, atFieldStart, literal.isEmpty || !literal.contains(i) {
                quoted = true
                inQuote = true
            } else if quoted {
                take(i)
            }
            atFieldStart = false
            i += w
        }
        finish(at: i)
        return fields
    }
}
