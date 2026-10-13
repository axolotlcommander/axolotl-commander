// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

// MARK: - Public API

/// The type of a node in a parsed JSON document; `error` is a bad line of a JSON Lines file.
public enum JSONKind: Sendable, Equatable { case object, array, string, number, bool, null, error }

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

/// One value of the document. Ranges are byte offsets into `JSONDocument.bytes`.
public struct JSONNode: Sendable, Equatable {
    public var kind: JSONKind
    /// The key token including its quotes; members of objects only.
    public var key: Range<Int>?
    /// Position among siblings (array index, member index, line index in JSON Lines).
    public var index: Int
    /// The value text: the whole container for objects and arrays, the line for an error node.
    public var value: Range<Int>
    /// -1 for the root.
    public var parent: Int
    /// -1 when there are no children.
    public var firstChild: Int
    public var childCount: Int
    /// -1 for the last child.
    public var nextSibling: Int
    /// 1-based start of the value.
    public var line: Int
    public var column: Int
    /// A later member with the same decoded key in the same object.
    public var isDuplicate: Bool
    /// Only for `.error` nodes; line and column are absolute in the file.
    public var error: JSONParseError?
}

/// An order-preserving JSON (or JSON Lines) document: a flat pre-order node list over the file bytes.
public struct JSONDocument: Sendable {
    /// The file content without a UTF-8 BOM; node ranges point into it.
    public let bytes: [UInt8]
    /// File order (pre-order); `nodes[0]` is the root (a virtual array of the lines in JSON Lines).
    public let nodes: [JSONNode]
    public let isLines: Bool

    /// Parses `data` in one pass. Accepts `//` and `/* */` comments, trailing commas and a BOM.
    /// Throws `JSONParseError` for a broken document (never in lines mode, where a bad line becomes an
    /// `.error` node) and `CancellationError` once `isCancelled` returns true.
    public static func parse(_ data: Data, lines: Bool,
                             isCancelled: @Sendable () -> Bool = { false }) throws -> JSONDocument {
        let hasBOM = data.count >= 3 && data.starts(with: [0xEF, 0xBB, 0xBF])
        let bytes = hasBOM ? [UInt8](data.dropFirst(3)) : [UInt8](data)
        var nodes = try bytes.withUnsafeBufferPointer { buf in
            var scanner = JSONScanner(buf: buf)
            if lines {
                try scanner.parseLines(isCancelled: isCancelled)
            } else {
                try scanner.parseDocument(isCancelled: isCancelled)
            }
            return scanner.nodes
        }
        markDuplicates(&nodes, bytes: bytes)
        return JSONDocument(bytes: bytes, nodes: nodes, isLines: lines)
    }

    public func children(of node: Int) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(nodes[node].childCount)
        var child = nodes[node].firstChild
        while child >= 0 {
            result.append(child)
            child = nodes[child].nextSibling
        }
        return result
    }

    /// Parent first, root last.
    public func ancestors(of node: Int) -> [Int] {
        var result: [Int] = []
        var parent = nodes[node].parent
        while parent >= 0 {
            result.append(parent)
            parent = nodes[parent].parent
        }
        return result
    }

    /// The decoded key; nil for array elements, lines and the root.
    public func keyText(_ node: Int) -> String? {
        guard let key = nodes[node].key else { return nil }
        return decodedString(key, maxBytes: .max).text
    }

    /// Short display text: strings decoded without quotes, other scalars as written, an error node's
    /// line; cut to `limit` characters with "…". Containers give "".
    public func valueText(_ node: Int, limit: Int = 200) -> String {
        let n = nodes[node]
        let maxBytes = limit > Int.max / 8 ? Int.max : limit * 4 + 16
        let text: String
        let truncated: Bool
        switch n.kind {
        case .object, .array:
            return ""
        case .string:
            (text, truncated) = decodedString(n.value, maxBytes: maxBytes)
        case .number, .bool, .null, .error:
            let end = n.value.count > maxBytes ? leadBoundary(n.value.lowerBound + maxBytes) : n.value.upperBound
            text = String(decoding: bytes[n.value.lowerBound..<end], as: UTF8.self)
            truncated = end < n.value.upperBound
        }
        if text.count > limit { return String(text.prefix(limit)) + "…" }
        return truncated ? text + "…" : text
    }

    /// `items[3].name`, `["two words"]`, `[4].name` for a JSON Lines line; `$` for the root.
    public func path(of node: Int) -> String {
        guard nodes[node].parent >= 0 else { return "$" }
        var chain = [node]
        var parent = nodes[node].parent
        while parent >= 0, nodes[parent].parent >= 0 {
            chain.append(parent)
            parent = nodes[parent].parent
        }
        var path = ""
        for n in chain.reversed() {
            if nodes[nodes[n].parent].kind == .object, let key = keyText(n) {
                if Self.isIdentifier(key) {
                    path += path.isEmpty ? key : "." + key
                } else {
                    var quoted: [UInt8] = []
                    Self.appendQuoted(Array(key.utf8), to: &quoted)
                    path += "[" + String(decoding: quoted, as: UTF8.self) + "]"
                }
            } else {
                path += "[\(nodes[n].index)]"
            }
        }
        return path
    }

    /// A string decoded without quotes, other scalars as written, a container as indented JSON in file
    /// order (comments dropped), an error node's raw line.
    public func copyValue(of node: Int) -> String {
        let n = nodes[node]
        switch n.kind {
        case .string: return decodedString(n.value, maxBytes: .max).text
        case .number, .bool, .null, .error: return String(decoding: bytes[n.value], as: UTF8.self)
        case .object, .array: return String(decoding: prettyPrinted(node), as: UTF8.self)
        }
    }

    /// The next node after `from` (before it when `backward`) in file order whose key or scalar value
    /// contains `text`, wrapping around; `from` itself is checked last. nil when nothing matches.
    public func search(_ text: String, from node: Int, backward: Bool, ignoreCase: Bool) -> Int? {
        guard !text.isEmpty, !nodes.isEmpty else { return nil }
        let needle = Needle(text, ignoreCase: ignoreCase)
        let count = nodes.count
        let start = min(max(node, 0), count - 1)
        for step in 1...count {
            let i = backward ? ((start - step) % count + count) % count : (start + step) % count
            if isLines && i == 0 { continue }
            if matches(i, needle) { return i }
        }
        return nil
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
        var node: Int
        var isObject: Bool
        var lastChild: Int
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
    var nodes: [JSONNode] = []
    var stack: [Frame] = []

    init(buf: UnsafeBufferPointer<UInt8>) {
        self.buf = buf
        self.end = buf.count
        nodes.reserveCapacity(max(16, buf.count / 32))
    }

    // MARK: Entry points

    mutating func parseDocument(isCancelled: () -> Bool) throws {
        try skipTrivia()
        guard pos < end else { throw JSONParseError(line: 1, column: 1, reason: .emptyDocument) }
        _ = try parseValue(parent: -1, index: 0, isCancelled: isCancelled)
        try skipTrivia()
        if pos < end { throw fail(.trailingData, at: pos) }
    }

    mutating func parseLines(isCancelled: () -> Bool) throws {
        let total = buf.count
        nodes.append(JSONNode(kind: .array, key: nil, index: 0, value: 0..<total, parent: -1, firstChild: -1,
                              childCount: 0, nextSibling: -1, line: 1, column: 1, isDuplicate: false, error: nil))
        var start = 0
        var line = 1
        var lastChild = -1
        var count = 0
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
            let mark = nodes.count
            var child = -1
            do {
                try skipTrivia()
                if pos < end {
                    child = try parseValue(parent: 0, index: count, isCancelled: isCancelled)
                    try skipTrivia()
                    if pos < end { throw fail(.trailingData, at: pos) }
                }
            } catch let error as JSONParseError {
                nodes.removeSubrange(mark...)
                child = nodes.count
                nodes.append(JSONNode(kind: .error, key: nil, index: count, value: start..<contentEnd, parent: 0,
                                      firstChild: -1, childCount: 0, nextSibling: -1, line: line, column: 1,
                                      isDuplicate: false, error: error))
            }
            if child >= 0 {
                if lastChild < 0 { nodes[0].firstChild = child } else { nodes[lastChild].nextSibling = child }
                lastChild = child
                count += 1
            }
            if lineEnd >= total { break }
            start = lineEnd + 1
            line += 1
        }
        nodes[0].childCount = count
    }

    // MARK: Values

    /// Parses one value at `pos` and appends its subtree; returns the index of its node.
    mutating func parseValue(parent: Int, index: Int, isCancelled: () -> Bool) throws -> Int {
        var root = -1
        var pendingKey: Range<Int>?
        valueLoop: while true {
            try skipTrivia()
            if pos >= nextCheck {
                nextCheck = pos + 65_536
                if isCancelled() { throw CancellationError() }
            }
            guard pos < end else { throw fail(.unexpectedEnd, at: end) }
            let start = pos
            let kind: JSONKind
            switch buf[pos] {
            case Byte.openBrace: kind = .object
            case Byte.openBracket: kind = .array
            case Byte.quote: kind = .string
            case Byte.minus, Byte.zero...Byte.nine: kind = .number
            case 0x74, 0x66: kind = .bool // t f
            case 0x6E: kind = .null // n
            default: throw badValueStart()
            }

            let idx = nodes.count
            var parentIndex = parent
            var childIndex = index
            if !stack.isEmpty {
                let t = stack.count - 1
                parentIndex = stack[t].node
                childIndex = stack[t].count
                if stack[t].lastChild < 0 {
                    nodes[parentIndex].firstChild = idx
                } else {
                    nodes[stack[t].lastChild].nextSibling = idx
                }
                stack[t].lastChild = idx
                stack[t].count += 1
            } else {
                root = idx
            }
            nodes.append(JSONNode(kind: kind, key: pendingKey, index: childIndex, value: start..<start,
                                  parent: parentIndex, firstChild: -1, childCount: 0, nextSibling: -1,
                                  line: lineNo, column: column(at: start), isDuplicate: false, error: nil))
            pendingKey = nil

            switch kind {
            case .object, .array:
                let isObject = kind == .object
                pos += 1
                stack.append(Frame(node: idx, isObject: isObject, lastChild: -1, count: 0))
                try skipTrivia()
                guard pos < end else { throw fail(.unexpectedEnd, at: end) }
                if buf[pos] == (isObject ? Byte.closeBrace : Byte.closeBracket) {
                    closeContainer()
                } else {
                    if isObject { pendingKey = try parseKey() }
                    continue valueLoop
                }
            case .string:
                try scanString()
            case .number:
                try scanNumber()
            case .bool, .null, .error:
                let literal = buf[pos] == 0x74 ? trueBytes : buf[pos] == 0x66 ? falseBytes : nullBytes
                guard matches(literal, at: pos) else { throw fail(.unexpectedCharacter, at: pos) }
                pos += literal.count
            }
            if kind != .object && kind != .array { nodes[idx].value = start..<pos }

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
                    if top.isObject { pendingKey = try parseKey() }
                    continue valueLoop
                } else if b == close {
                    closeContainer()
                } else {
                    throw fail(.unexpectedCharacter, at: pos)
                }
            }
            return root
        }
    }

    mutating func closeContainer() {
        let frame = stack.removeLast()
        nodes[frame.node].value = nodes[frame.node].value.lowerBound..<(pos + 1)
        nodes[frame.node].childCount = frame.count
        pos += 1
    }

    /// Reads `"key"` and the colon after it; returns the key token range.
    mutating func parseKey() throws -> Range<Int> {
        guard pos < end else { throw fail(.unexpectedEnd, at: end) }
        let b = buf[pos]
        guard b == Byte.quote else {
            if b == Byte.apostrophe || isIdentifierStart(b) { throw fail(.unsupportedJSON5, at: pos) }
            throw fail(.unexpectedCharacter, at: pos)
        }
        let start = pos
        try scanString()
        let key = start..<pos
        try skipTrivia()
        guard pos < end else { throw fail(.unexpectedEnd, at: end) }
        guard buf[pos] == Byte.colon else { throw fail(.unexpectedCharacter, at: pos) }
        pos += 1
        return key
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

// MARK: - Helpers

extension JSONDocument {
    /// Marks later members whose decoded key repeats an earlier one in the same object.
    fileprivate static func markDuplicates(_ nodes: inout [JSONNode], bytes: [UInt8]) {
        for i in nodes.indices where nodes[i].kind == .object && nodes[i].childCount > 1 {
            var keys: [ArraySlice<UInt8>] = []
            var seen: Set<ArraySlice<UInt8>> = []
            let useSet = nodes[i].childCount > 8
            var child = nodes[i].firstChild
            while child >= 0 {
                if let range = nodes[child].key {
                    let key = keyBytes(range, in: bytes)
                    let repeated = useSet ? !seen.insert(key).inserted : keys.contains(key)
                    if repeated { nodes[child].isDuplicate = true } else if !useSet { keys.append(key) }
                }
                child = nodes[child].nextSibling
            }
        }
    }

    /// The decoded UTF-8 of a key token; a slice of `bytes` when it has no escapes.
    private static func keyBytes(_ range: Range<Int>, in bytes: [UInt8]) -> ArraySlice<UInt8> {
        let inner = bytes[(range.lowerBound + 1)..<(range.upperBound - 1)]
        guard inner.contains(Byte.backslash) else { return inner }
        return ArraySlice(decode(inner, maxBytes: .max).bytes)
    }

    /// Resolves the escapes of a string token's content, stopping at a scalar boundary after `maxBytes`.
    fileprivate static func decode(_ inner: ArraySlice<UInt8>, maxBytes: Int) -> (bytes: [UInt8], truncated: Bool) {
        var out: [UInt8] = []
        out.reserveCapacity(min(inner.count, maxBytes))
        var i = inner.startIndex
        let end = inner.endIndex
        while i < end {
            let b = inner[i]
            if out.count >= maxBytes && b & 0xC0 != 0x80 { return (out, true) }
            guard b == Byte.backslash, i + 1 < end else {
                out.append(b)
                i += 1
                continue
            }
            let e = inner[i + 1]
            i += 2
            switch e {
            case 0x62: out.append(0x08)
            case 0x66: out.append(0x0C)
            case 0x6E: out.append(0x0A)
            case 0x72: out.append(0x0D)
            case 0x74: out.append(0x09)
            case 0x75:
                var scalar = hex4(inner, at: i) ?? 0xFFFD
                i += 4
                if scalar >= 0xD800 && scalar <= 0xDBFF {
                    if i + 6 <= end, inner[i] == Byte.backslash, inner[i + 1] == 0x75,
                       let low = hex4(inner, at: i + 2), low >= 0xDC00 && low <= 0xDFFF {
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        i += 6
                    } else {
                        scalar = 0xFFFD
                    }
                } else if scalar >= 0xDC00 && scalar <= 0xDFFF {
                    scalar = 0xFFFD
                }
                appendUTF8(scalar, to: &out)
            default: out.append(e) // \" \\ \/
            }
        }
        return (out, false)
    }

    private static func appendUTF8(_ v: UInt32, to out: inout [UInt8]) {
        switch v {
        case 0..<0x80:
            out.append(UInt8(v))
        case 0x80..<0x800:
            out.append(contentsOf: [UInt8(0xC0 | v >> 6), UInt8(0x80 | v & 0x3F)])
        case 0x800..<0x10000:
            out.append(contentsOf: [UInt8(0xE0 | v >> 12), UInt8(0x80 | v >> 6 & 0x3F), UInt8(0x80 | v & 0x3F)])
        default:
            out.append(contentsOf: [UInt8(0xF0 | v >> 18), UInt8(0x80 | v >> 12 & 0x3F),
                                    UInt8(0x80 | v >> 6 & 0x3F), UInt8(0x80 | v & 0x3F)])
        }
    }

    private static func hex4(_ s: ArraySlice<UInt8>, at i: Int) -> UInt32? {
        guard i + 4 <= s.endIndex else { return nil }
        var v: UInt32 = 0
        for j in i..<(i + 4) {
            let b = s[j]
            let d: UInt8
            switch b {
            case 0x30...0x39: d = b - 0x30
            case 0x41...0x46: d = b - 0x41 + 10
            case 0x61...0x66: d = b - 0x61 + 10
            default: return nil
            }
            v = v << 4 | UInt32(d)
        }
        return v
    }

    /// The text of a string token (`range` includes the quotes).
    fileprivate func decodedString(_ range: Range<Int>, maxBytes: Int) -> (text: String, truncated: Bool) {
        let inner = bytes[(range.lowerBound + 1)..<(range.upperBound - 1)]
        if !inner.contains(Byte.backslash) {
            let end = inner.count > maxBytes ? leadBoundary(inner.startIndex + maxBytes) : inner.endIndex
            return (String(decoding: inner[inner.startIndex..<end], as: UTF8.self), end < inner.endIndex)
        }
        let (out, truncated) = Self.decode(inner, maxBytes: maxBytes)
        return (String(decoding: out, as: UTF8.self), truncated)
    }

    /// The first UTF-8 lead byte at or before `p`.
    fileprivate func leadBoundary(_ p: Int) -> Int {
        var p = p
        while p > 0 && p < bytes.count && bytes[p] & 0xC0 == 0x80 { p -= 1 }
        return p
    }

    fileprivate static func isIdentifier(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard let first = u.first, first < 0x80, isIdentifierStart(first) else { return false }
        return u.dropFirst().allSatisfy { $0 < 0x80 && (isIdentifierStart($0) || isDigit($0)) }
    }

    /// Writes `utf8` as a JSON string literal, escaping only `"`, `\` and control characters.
    fileprivate static func appendQuoted(_ utf8: some Collection<UInt8>, to out: inout [UInt8]) {
        let hex = Array("0123456789abcdef".utf8)
        out.append(Byte.quote)
        for b in utf8 {
            switch b {
            case Byte.quote: out.append(contentsOf: [Byte.backslash, Byte.quote])
            case Byte.backslash: out.append(contentsOf: [Byte.backslash, Byte.backslash])
            case 0x0A: out.append(contentsOf: [Byte.backslash, 0x6E])
            case 0x0D: out.append(contentsOf: [Byte.backslash, 0x72])
            case 0x09: out.append(contentsOf: [Byte.backslash, 0x74])
            case 0x08: out.append(contentsOf: [Byte.backslash, 0x62])
            case 0x0C: out.append(contentsOf: [Byte.backslash, 0x66])
            case 0..<0x20: out.append(contentsOf: [Byte.backslash, 0x75, 0x30, 0x30, hex[Int(b >> 4)], hex[Int(b & 0xF)]])
            default: out.append(b)
            }
        }
        out.append(Byte.quote)
    }

    /// Appends a string token re-escaped minimally.
    private func appendString(_ range: Range<Int>, to out: inout [UInt8]) {
        let inner = bytes[(range.lowerBound + 1)..<(range.upperBound - 1)]
        if inner.contains(Byte.backslash) {
            Self.appendQuoted(Self.decode(inner, maxBytes: .max).bytes, to: &out)
        } else {
            out.append(Byte.quote)
            out.append(contentsOf: inner)
            out.append(Byte.quote)
        }
    }

    /// Indented JSON (2 spaces) of a container, members in file order.
    fileprivate func prettyPrinted(_ node: Int) -> [UInt8] {
        struct Frame { var next: Int; var depth: Int; var isObject: Bool; var first: Bool }
        var out: [UInt8] = []
        var stack: [Frame] = []

        func indent(_ depth: Int) { out.append(contentsOf: repeatElement(0x20, count: depth * 2)) }

        func emit(_ i: Int, depth: Int) {
            let n = nodes[i]
            switch n.kind {
            case .object, .array:
                let isObject = n.kind == .object
                if n.firstChild < 0 {
                    out.append(contentsOf: isObject ? [Byte.openBrace, Byte.closeBrace] : [Byte.openBracket, Byte.closeBracket])
                } else {
                    out.append(isObject ? Byte.openBrace : Byte.openBracket)
                    stack.append(Frame(next: n.firstChild, depth: depth + 1, isObject: isObject, first: true))
                }
            case .string: appendString(n.value, to: &out)
            case .number, .bool, .null, .error: out.append(contentsOf: bytes[n.value])
            }
        }

        emit(node, depth: 0)
        while let top = stack.last {
            let t = stack.count - 1
            guard top.next >= 0 else {
                stack.removeLast()
                out.append(Byte.newline)
                indent(top.depth - 1)
                out.append(top.isObject ? Byte.closeBrace : Byte.closeBracket)
                continue
            }
            if !top.first { out.append(Byte.comma) }
            out.append(Byte.newline)
            indent(top.depth)
            stack[t].first = false
            stack[t].next = nodes[top.next].nextSibling
            if top.isObject, let key = nodes[top.next].key {
                appendString(key, to: &out)
                out.append(contentsOf: [Byte.colon, 0x20])
            }
            emit(top.next, depth: top.depth)
        }
        return out
    }

    // MARK: Search

    fileprivate struct Needle {
        let text: String
        let ignoreCase: Bool
        /// ASCII needle bytes (lowercased when ignoring case); nil for a non-ASCII needle.
        let ascii: [UInt8]?

        init(_ text: String, ignoreCase: Bool) {
            self.text = text
            self.ignoreCase = ignoreCase
            let u = Array(text.utf8)
            ascii = u.allSatisfy { $0 < 0x80 } ? (ignoreCase ? u.map(Needle.lower) : u) : nil
        }

        static func lower(_ b: UInt8) -> UInt8 { b >= 0x41 && b <= 0x5A ? b + 0x20 : b }
    }

    fileprivate func matches(_ i: Int, _ needle: Needle) -> Bool {
        let n = nodes[i]
        if let key = n.key, contains(stringToken: key, needle) { return true }
        switch n.kind {
        case .object, .array: return false
        case .string: return contains(stringToken: n.value, needle)
        case .number, .bool, .null, .error: return contains(raw: n.value, needle)
        }
    }

    private func contains(stringToken range: Range<Int>, _ needle: Needle) -> Bool {
        let inner = (range.lowerBound + 1)..<(range.upperBound - 1)
        if !bytes[inner].contains(Byte.backslash) { return contains(raw: inner, needle) }
        return contains(decodedString(range, maxBytes: .max).text, needle)
    }

    /// Byte comparison when both sides are ASCII (same result as Foundation there), else Foundation.
    private func contains(raw range: Range<Int>, _ needle: Needle) -> Bool {
        if let ascii = needle.ascii, !bytes[range].contains(where: { $0 >= 0x80 }) {
            guard ascii.count <= range.count else { return false }
            let last = range.upperBound - ascii.count
            var p = range.lowerBound
            while p <= last {
                var j = 0
                while j < ascii.count {
                    let b = needle.ignoreCase ? Needle.lower(bytes[p + j]) : bytes[p + j]
                    if b != ascii[j] { break }
                    j += 1
                }
                if j == ascii.count { return true }
                p += 1
            }
            return false
        }
        return contains(String(decoding: bytes[range], as: UTF8.self), needle)
    }

    private func contains(_ text: String, _ needle: Needle) -> Bool {
        text.range(of: needle.text, options: needle.ignoreCase ? [.caseInsensitive] : []) != nil
    }
}
