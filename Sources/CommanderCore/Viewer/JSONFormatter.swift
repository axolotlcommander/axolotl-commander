// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

// MARK: - Public API

/// Where and why parsing stopped.
public struct JSONParseError: Error, Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case unexpectedEnd, unexpectedCharacter, unterminatedString, invalidEscape, invalidNumber,
             controlCharacter, unsupportedJSON5, trailingData, emptyDocument
    }

    /// 1-based.
    public let line: Int
    /// 1-based, counted in Unicode scalars of the line.
    public let column: Int
    public let reason: Reason

    public init(line: Int, column: Int, reason: Reason) {
        self.line = line
        self.column = column
        self.reason = reason
    }
}

/// Checks and indents JSON (or JSON Lines) in one pass over the bytes, without building a tree, so a
/// file of tens of megabytes needs little more memory than its formatted text.
public enum JSONFormatter {
    /// Deeper levels share this indentation, so a deeply nested file cannot blow up the formatted text.
    public static let maxIndentDepth = 64

    public struct Output: Sendable, Equatable {
        public let text: String
        /// The first bad line of a JSON Lines file; that line is kept as written.
        public let firstLineError: JSONParseError?
    }

    /// The document indented by two spaces per level with members in file order. Keys, strings and
    /// numbers stay exactly as written; `//` and `/* */` comments, trailing commas and a UTF-8 BOM are
    /// dropped. JSON Lines give one record after another, each indented, a bad line as written and
    /// empty lines left out. Throws `JSONParseError` for a broken document (never in lines mode) and
    /// `CancellationError` once `isCancelled` returns true.
    public static func format(_ data: Data, lines: Bool,
                              isCancelled: @Sendable () -> Bool = { false }) throws -> Output {
        try data.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self)
            var scanner = JSONScanner(buf: buf)
            if lines {
                try scanner.formatLines(isCancelled: isCancelled)
            } else {
                try scanner.formatDocument(isCancelled: isCancelled)
            }
            return Output(text: String(decoding: scanner.out, as: UTF8.self), firstLineError: scanner.firstLineError)
        }
    }
}

// MARK: - Scanner

private enum Byte {
    static let quote: UInt8 = 0x22, backslash: UInt8 = 0x5C, slash: UInt8 = 0x2F, star: UInt8 = 0x2A
    static let comma: UInt8 = 0x2C, colon: UInt8 = 0x3A, minus: UInt8 = 0x2D, plus: UInt8 = 0x2B
    static let dot: UInt8 = 0x2E, apostrophe: UInt8 = 0x27, newline: UInt8 = 0x0A, cr: UInt8 = 0x0D
    static let openBrace: UInt8 = 0x7B, closeBrace: UInt8 = 0x7D
    static let openBracket: UInt8 = 0x5B, closeBracket: UInt8 = 0x5D
    static let zero: UInt8 = 0x30, nine: UInt8 = 0x39
}

private let trueBytes = Array("true".utf8), falseBytes = Array("false".utf8), nullBytes = Array("null".utf8)
private let infinityBytes = Array("Infinity".utf8), nanBytes = Array("NaN".utf8)

private func isDigit(_ b: UInt8) -> Bool { b >= Byte.zero && b <= Byte.nine }

private func isHex(_ b: UInt8) -> Bool {
    isDigit(b) || (b >= 0x41 && b <= 0x46) || (b >= 0x61 && b <= 0x66)
}

/// A JSON5 identifier start: ASCII letter, `_`, `$` or any non-ASCII byte.
private func isIdentifierStart(_ b: UInt8) -> Bool {
    (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b == 0x24 || b >= 0x80
}

private struct JSONScanner {
    struct Frame {
        var isObject: Bool
        var count: Int
    }

    let buf: UnsafeBufferPointer<UInt8>
    var pos = 0
    var end: Int
    var lineNo = 1
    var lineStart = 0
    // Column cache: `colCount` lead bytes lie in lineStart..<colPos.
    var colPos = 0
    var colCount = 0
    var nextCheck = 0
    var out: [UInt8] = []
    var stack: [Frame] = []
    var firstLineError: JSONParseError?

    init(buf: UnsafeBufferPointer<UInt8>) {
        self.buf = buf
        self.end = buf.count
        if buf.count >= 3 && buf[0] == 0xEF && buf[1] == 0xBB && buf[2] == 0xBF {
            pos = 3
            lineStart = 3
            colPos = 3
        }
        out.reserveCapacity(buf.count + buf.count / 2)
    }

    // MARK: Entry points

    mutating func formatDocument(isCancelled: () -> Bool) throws {
        try skipTrivia()
        guard pos < end else { throw JSONParseError(line: 1, column: 1, reason: .emptyDocument) }
        try formatValue(isCancelled: isCancelled)
        try skipTrivia()
        if pos < end { throw fail(.trailingData, at: pos) }
    }

    mutating func formatLines(isCancelled: () -> Bool) throws {
        let total = buf.count
        var start = pos
        var line = 1
        while start <= total {
            var lineEnd = start
            while lineEnd < total && buf[lineEnd] != Byte.newline { lineEnd += 1 }
            var contentEnd = lineEnd
            if contentEnd > start && buf[contentEnd - 1] == Byte.cr { contentEnd -= 1 }

            pos = start
            end = contentEnd
            lineNo = line
            lineStart = start
            colPos = start
            colCount = 0
            stack.removeAll(keepingCapacity: true)
            if pos >= nextCheck {
                nextCheck = pos + 65_536
                if isCancelled() { throw CancellationError() }
            }
            var mark = -1
            do {
                try skipTrivia()
                if pos < end {
                    if !out.isEmpty { out.append(Byte.newline) }
                    mark = out.count
                    try formatValue(isCancelled: isCancelled)
                    try skipTrivia()
                    if pos < end { throw fail(.trailingData, at: pos) }
                }
            } catch let error as JSONParseError {
                // A bad line stays as written.
                if mark < 0 {
                    if !out.isEmpty { out.append(Byte.newline) }
                } else {
                    out.removeSubrange(mark...)
                }
                out += buf[start..<contentEnd]
                if firstLineError == nil { firstLineError = error }
            }
            if lineEnd >= total { break }
            start = lineEnd + 1
            line += 1
        }
    }

    // MARK: Values

    mutating func indent(_ depth: Int) {
        out.append(Byte.newline)
        out.append(contentsOf: repeatElement(0x20, count: min(depth, JSONFormatter.maxIndentDepth) * 2))
    }

    /// Before a member or element: a comma after the previous one, a new line and the indentation.
    mutating func startItem() {
        let t = stack.count - 1
        if stack[t].count > 0 { out.append(Byte.comma) }
        stack[t].count += 1
        indent(stack.count)
    }

    /// Writes one value at `pos` with everything inside it.
    mutating func formatValue(isCancelled: () -> Bool) throws {
        valueLoop: while true {
            try skipTrivia()
            if pos >= nextCheck {
                nextCheck = pos + 65_536
                if isCancelled() { throw CancellationError() }
            }
            guard pos < end else { throw fail(.unexpectedEnd, at: end) }
            let start = pos
            switch buf[pos] {
            case Byte.openBrace, Byte.openBracket:
                let isObject = buf[pos] == Byte.openBrace
                pos += 1
                try skipTrivia()
                guard pos < end else { throw fail(.unexpectedEnd, at: end) }
                if buf[pos] == (isObject ? Byte.closeBrace : Byte.closeBracket) {
                    pos += 1
                    out.append(contentsOf: isObject ? [Byte.openBrace, Byte.closeBrace] : [Byte.openBracket, Byte.closeBracket])
                } else {
                    out.append(isObject ? Byte.openBrace : Byte.openBracket)
                    stack.append(Frame(isObject: isObject, count: 0))
                    startItem()
                    if isObject { try formatKey() }
                    continue valueLoop
                }
            case Byte.quote:
                try scanString()
                out += buf[start..<pos]
            case Byte.minus, Byte.zero...Byte.nine:
                try scanNumber()
                out += buf[start..<pos]
            case 0x74, 0x66, 0x6E: // t f n
                let literal = buf[pos] == 0x74 ? trueBytes : buf[pos] == 0x66 ? falseBytes : nullBytes
                guard matches(literal, at: pos) else { throw fail(.unexpectedCharacter, at: pos) }
                pos += literal.count
                out += literal
            default:
                throw badValueStart()
            }

            // After a value: a comma moves on, a closing bracket ends the container.
            while let top = stack.last {
                try skipTrivia()
                guard pos < end else { throw fail(.unexpectedEnd, at: end) }
                let close = top.isObject ? Byte.closeBrace : Byte.closeBracket
                let b = buf[pos]
                if b == Byte.comma {
                    pos += 1
                    try skipTrivia()
                    guard pos < end else { throw fail(.unexpectedEnd, at: end) }
                    if buf[pos] == close {
                        closeContainer()
                        continue
                    }
                    startItem()
                    if top.isObject { try formatKey() }
                    continue valueLoop
                } else if b == close {
                    closeContainer()
                } else {
                    throw fail(.unexpectedCharacter, at: pos)
                }
            }
            return
        }
    }

    mutating func closeContainer() {
        let frame = stack.removeLast()
        indent(stack.count)
        out.append(frame.isObject ? Byte.closeBrace : Byte.closeBracket)
        pos += 1
    }

    /// Reads `"key"` and the colon after it and writes `"key": `.
    mutating func formatKey() throws {
        try skipTrivia()
        guard pos < end else { throw fail(.unexpectedEnd, at: end) }
        let b = buf[pos]
        guard b == Byte.quote else {
            if b == Byte.apostrophe || isIdentifierStart(b) { throw fail(.unsupportedJSON5, at: pos) }
            throw fail(.unexpectedCharacter, at: pos)
        }
        let start = pos
        try scanString()
        out += buf[start..<pos]
        out.append(contentsOf: [Byte.colon, 0x20])
        try skipTrivia()
        guard pos < end else { throw fail(.unexpectedEnd, at: end) }
        guard buf[pos] == Byte.colon else { throw fail(.unexpectedCharacter, at: pos) }
        pos += 1
    }

    /// The error for a byte that cannot start a value.
    mutating func badValueStart() -> JSONParseError {
        switch buf[pos] {
        case Byte.apostrophe, Byte.plus, Byte.dot:
            return fail(.unsupportedJSON5, at: pos)
        case 0x49 where matches(infinityBytes, at: pos), 0x4E where matches(nanBytes, at: pos): // I N
            return fail(.unsupportedJSON5, at: pos)
        default:
            return fail(.unexpectedCharacter, at: pos)
        }
    }

    mutating func scanString() throws {
        let open = pos
        pos += 1
        while pos < end {
            let b = buf[pos]
            if b == Byte.quote {
                pos += 1
                return
            } else if b == Byte.backslash {
                guard pos + 1 < end else { throw fail(.unterminatedString, at: open) }
                switch buf[pos + 1] {
                case Byte.quote, Byte.backslash, Byte.slash, 0x62, 0x66, 0x6E, 0x72, 0x74: // b f n r t
                    pos += 2
                case 0x75: // u
                    guard pos + 5 < end, isHex(buf[pos + 2]), isHex(buf[pos + 3]), isHex(buf[pos + 4]),
                          isHex(buf[pos + 5]) else { throw fail(.invalidEscape, at: pos) }
                    pos += 6
                default:
                    throw fail(.invalidEscape, at: pos)
                }
            } else if b < 0x20 {
                if b == Byte.newline || b == Byte.cr { throw fail(.unterminatedString, at: open) }
                throw fail(.controlCharacter, at: pos)
            } else {
                pos += 1
            }
        }
        throw fail(.unterminatedString, at: open)
    }

    /// RFC 8259 number grammar; JSON5 forms (hex, `-Infinity`, `.5`, `5.`) are reported as such.
    mutating func scanNumber() throws {
        let start = pos
        if buf[pos] == Byte.minus {
            pos += 1
            guard pos < end else { throw fail(.invalidNumber, at: pos) }
            if buf[pos] == Byte.dot { throw fail(.unsupportedJSON5, at: pos) }
            if matches(infinityBytes, at: pos) { throw fail(.unsupportedJSON5, at: start) }
        }
        guard pos < end, isDigit(buf[pos]) else { throw fail(.invalidNumber, at: pos) }
        if buf[pos] == Byte.zero {
            pos += 1
            if pos < end {
                let b = buf[pos]
                if b == 0x78 || b == 0x58 { throw fail(.unsupportedJSON5, at: start) } // x X
                if isDigit(b) { throw fail(.invalidNumber, at: pos) }
            }
        } else {
            while pos < end && isDigit(buf[pos]) { pos += 1 }
        }
        if pos < end && buf[pos] == Byte.dot {
            let dot = pos
            pos += 1
            guard pos < end, isDigit(buf[pos]) else { throw fail(.unsupportedJSON5, at: dot) }
            while pos < end && isDigit(buf[pos]) { pos += 1 }
        }
        if pos < end && (buf[pos] == 0x65 || buf[pos] == 0x45) { // e E
            pos += 1
            if pos < end && (buf[pos] == Byte.plus || buf[pos] == Byte.minus) { pos += 1 }
            guard pos < end, isDigit(buf[pos]) else { throw fail(.invalidNumber, at: pos) }
            while pos < end && isDigit(buf[pos]) { pos += 1 }
        }
    }

    func matches(_ literal: [UInt8], at p: Int) -> Bool {
        guard p + literal.count <= end else { return false }
        for (i, b) in literal.enumerated() where buf[p + i] != b { return false }
        return true
    }

    // MARK: Trivia and positions

    /// Skips whitespace and comments, counting lines.
    mutating func skipTrivia() throws {
        while pos < end {
            let b = buf[pos]
            if b == 0x20 || b == 0x09 || b == Byte.cr {
                pos += 1
            } else if b == Byte.newline {
                pos += 1
                newLine()
            } else if b == Byte.slash {
                guard pos + 1 < end else { throw fail(.unexpectedCharacter, at: pos) }
                let next = buf[pos + 1]
                if next == Byte.slash {
                    pos += 2
                    while pos < end && buf[pos] != Byte.newline { pos += 1 }
                } else if next == Byte.star {
                    pos += 2
                    while true {
                        guard pos < end else { throw fail(.unexpectedEnd, at: end) }
                        let c = buf[pos]
                        if c == Byte.star && pos + 1 < end && buf[pos + 1] == Byte.slash {
                            pos += 2
                            break
                        }
                        pos += 1
                        if c == Byte.newline { newLine() }
                    }
                } else {
                    throw fail(.unexpectedCharacter, at: pos)
                }
            } else {
                return
            }
        }
    }

    mutating func newLine() {
        lineNo += 1
        lineStart = pos
        colPos = pos
        colCount = 0
    }

    /// 1-based column of `p` on the current line (amortized: positions mostly grow).
    mutating func column(at p: Int) -> Int {
        if p < colPos {
            colPos = lineStart
            colCount = 0
        }
        var i = colPos
        var c = colCount
        while i < p {
            if buf[i] & 0xC0 != 0x80 { c += 1 }
            i += 1
        }
        colPos = p
        colCount = c
        return c + 1
    }

    mutating func fail(_ reason: JSONParseError.Reason, at p: Int) -> JSONParseError {
        JSONParseError(line: lineNo, column: column(at: p), reason: reason)
    }
}
