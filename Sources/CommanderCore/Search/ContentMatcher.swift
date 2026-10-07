import Foundation
import Darwin

extension ByteSearch {
    /// Search hex syntax: hex bytes (as in `parseHex`) mixed with double-quoted strings,
    /// e.g. `4A 6F "text" 00` → bytes. Strings are UTF-8. nil on empty input, bad hex or an
    /// unterminated quote.
    public static func parseSearchHex(_ text: String) -> [UInt8]? {
        enum Element { case bytes([UInt8]); case token(Substring) }
        var elements: [Element] = []
        var token = Substring()
        var rest = Substring(text)
        func flush() {
            if !token.isEmpty { elements.append(.token(token)); token = Substring() }
        }
        while let c = rest.first {
            if c == "\"" {
                flush()
                let afterQuote = rest.dropFirst()
                guard let close = afterQuote.firstIndex(of: "\"") else { return nil }
                elements.append(.bytes(Array(afterQuote[..<close].utf8)))
                rest = afterQuote[afterQuote.index(after: close)...]
                continue
            }
            if c == " " || c == "," || c == "\t" || c == "\n" || c == "\r" {
                flush()
            } else {
                token.append(c)
            }
            rest = rest.dropFirst()
        }
        flush()
        var out: [UInt8] = []
        for element in elements {
            switch element {
            case .bytes(let b):
                out += b
            case .token(let t):
                var digits = t
                if digits.hasPrefix("0x") || digits.hasPrefix("0X") { digits = digits.dropFirst(2) }
                let normalized = digits.count == 1 && elements.count > 1 ? "0" + digits : String(digits)
                guard let b = parseHex(normalized) else { return nil }
                out += b
            }
        }
        return out.isEmpty ? nil : out
    }
}

/// Searches a file's content for a text, hex byte sequence or regular expression,
/// reading the file in chunks.
public struct ContentMatcher: Sendable {
    private enum Mode: Sendable {
        case bytes([BytePattern], wholeWords: Bool)
        case regex(NSRegularExpression)
    }

    private let mode: Mode
    private let legacyEncoding: TextEncoding
    /// Bytes read per `read` call (tests lower it to exercise chunk boundaries).
    var chunkSize = 1 << 20
    static let regexReadLimit = 64 << 20

    public init(_ query: SearchCriteria.ContentQuery, legacyEncoding: TextEncoding) throws {
        self.legacyEncoding = legacyEncoding
        guard !query.text.isEmpty else { throw SearchError.invalidPattern("Empty search text") }
        if query.isHex {
            guard let bytes = ByteSearch.parseSearchHex(query.text) else {
                throw SearchError.invalidPattern("Invalid hexadecimal sequence")
            }
            mode = .bytes([BytePattern(encodings: [], units: [[bytes]], alignment: 1)], wholeWords: false)
        } else if query.isRegex {
            let source = query.wholeWords ? "\\b(?:\(query.text))\\b" : query.text
            var options: NSRegularExpression.Options = [.anchorsMatchLines]
            if !query.caseSensitive { options.insert(.caseInsensitive) }
            do {
                mode = .regex(try NSRegularExpression(pattern: source, options: options))
            } catch {
                throw SearchError.invalidPattern("Invalid regular expression")
            }
        } else {
            let patterns = Self.textPatterns(query, legacyEncoding: legacyEncoding)
            guard !patterns.isEmpty else { throw SearchError.invalidPattern("Text cannot be encoded") }
            mode = .bytes(patterns, wholeWords: query.wholeWords)
        }
    }

    /// True when the file contains a match. Throws `SearchError.cannotRead` for unreadable
    /// files and `CancellationError` when the current task is cancelled.
    public func matches(fileAt path: String) throws -> Bool {
        switch mode {
        case .bytes(let patterns, let wholeWords):
            return try matchBytes(path, patterns, wholeWords)
        case .regex(let regex):
            return try matchRegex(path, regex)
        }
    }

    // MARK: Pattern construction

    private static func textPatterns(_ query: SearchCriteria.ContentQuery, legacyEncoding: TextEncoding) -> [BytePattern] {
        let nfc = query.text.precomposedStringWithCanonicalMapping
        let nfd = query.text.decomposedStringWithCanonicalMapping
        var variants: [(TextEncoding, String)] = []
        for e in [TextEncoding.utf8, .utf16LE, .utf16BE] {
            variants.append((e, nfc))
            if !nfd.unicodeScalars.elementsEqual(nfc.unicodeScalars) { variants.append((e, nfd)) }
        }
        variants.append((legacyEncoding, nfc))

        var patterns: [BytePattern] = []
        for (encoding, text) in variants {
            guard let units = units(text, encoding, caseSensitive: query.caseSensitive) else { continue }
            let alignment = (encoding == .utf16LE || encoding == .utf16BE) ? 2 : 1
            if let index = patterns.firstIndex(where: { $0.units == units && $0.alignment == alignment }) {
                if !patterns[index].encodings.contains(encoding) { patterns[index].encodings.append(encoding) }
            } else {
                patterns.append(BytePattern(encodings: [encoding], units: units, alignment: alignment))
            }
        }
        return patterns
    }

    /// Case-sensitive: one unit with one alternative. Otherwise one unit per scalar whose
    /// alternatives are its own, lowercase and uppercase single-scalar forms.
    private static func units(_ text: String, _ encoding: TextEncoding, caseSensitive: Bool) -> [[[UInt8]]]? {
        if caseSensitive {
            guard let bytes = encoding.encode(text), !bytes.isEmpty else { return nil }
            return [[bytes]]
        }
        var result: [[[UInt8]]] = []
        for scalar in text.unicodeScalars {
            let own = String(scalar)
            var forms = [own]
            for variant in [own.lowercased(), own.uppercased()] {
                // Compare scalars: String equality would treat canonically equivalent scalars as equal.
                guard variant.unicodeScalars.count == 1,
                      !forms.contains(where: { $0.unicodeScalars.elementsEqual(variant.unicodeScalars) }) else { continue }
                forms.append(variant)
            }
            var alternatives: [[UInt8]] = []
            for form in forms {
                if let bytes = encoding.encode(form), !bytes.isEmpty, !alternatives.contains(bytes) {
                    alternatives.append(bytes)
                }
            }
            if alternatives.isEmpty { return nil }
            result.append(alternatives)
        }
        return result.isEmpty ? nil : result
    }

    // MARK: Byte search

    private static func openFile(_ path: String) throws -> (fd: Int32, size: Int) {
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SearchError.cannotRead(String(cString: strerror(errno))) }
        var st = stat()
        guard fstat(fd, &st) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw SearchError.cannotRead(message)
        }
        guard (st.st_mode & S_IFMT) == S_IFREG else {
            close(fd)
            throw SearchError.cannotRead("Not a regular file")
        }
        return (fd, Int(st.st_size))
    }

    private func matchBytes(_ path: String, _ patterns: [BytePattern], _ wholeWords: Bool) throws -> Bool {
        let (fd, size) = try Self.openFile(path)
        defer { close(fd) }
        let maxLen = patterns.map(\.maxLen).max() ?? 1
        let overlap = maxLen + 8
        let chunk = max(chunkSize, 1)
        var buffer = [UInt8](repeating: 0, count: overlap + chunk)
        var carry = 0
        var absStart = 0
        while true {
            if Task.isCancelled { throw CancellationError() }
            let n = buffer.withUnsafeMutableBytes { raw -> Int in
                read(fd, raw.baseAddress! + carry, chunk)
            }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw SearchError.cannotRead(String(cString: strerror(errno)))
            }
            let count = carry + n
            let final = n == 0 || absStart + count >= size
            if count == 0 { return false }
            let hit = buffer.withUnsafeBufferPointer { buf -> Bool in
                for pattern in patterns where pattern.find(buf.baseAddress!, count, absStart, final, wholeWords) {
                    return true
                }
                return false
            }
            if hit { return true }
            if final { return false }
            let keep = min(overlap, count)
            if keep < count {
                buffer.withUnsafeMutableBytes { raw in
                    _ = memmove(raw.baseAddress!, raw.baseAddress! + (count - keep), keep)
                }
                absStart += count - keep
            }
            carry = keep
        }
    }

    // MARK: Regex

    private func matchRegex(_ path: String, _ regex: NSRegularExpression) throws -> Bool {
        let (fd, size) = try Self.openFile(path)
        defer { close(fd) }
        let limit = min(size, Self.regexReadLimit)
        var data = Data(count: limit)
        var total = 0
        while total < limit {
            if Task.isCancelled { throw CancellationError() }
            let n = data.withUnsafeMutableBytes { raw -> Int in
                read(fd, raw.baseAddress! + total, min(limit - total, 1 << 20))
            }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw SearchError.cannotRead(String(cString: strerror(errno)))
            }
            if n == 0 { break }
            total += n
        }
        data.count = total
        if Task.isCancelled { throw CancellationError() }
        let detection = EncodingDetector.detect(data, fallback: legacyEncoding)
        let text = TextDecoding.decode(data, as: detection.encoding, skip: detection.bomLength)
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }
}

// MARK: - Byte pattern

/// A pattern as a sequence of units, each a set of alternative byte sequences.
private struct BytePattern: Sendable {
    var encodings: [TextEncoding]
    let units: [[[UInt8]]]
    let alignment: Int
    /// Set when every unit has exactly one alternative.
    let flat: [UInt8]?
    let minLen: Int
    let maxLen: Int
    let firstBytes: [Bool]
    let firstSingle: UInt8?

    init(encodings: [TextEncoding], units: [[[UInt8]]], alignment: Int) {
        self.encodings = encodings
        self.units = units
        self.alignment = alignment
        if units.allSatisfy({ $0.count == 1 }) {
            flat = units.flatMap { $0[0] }
        } else {
            flat = nil
        }
        minLen = units.reduce(0) { $0 + ($1.map(\.count).min() ?? 0) }
        maxLen = units.reduce(0) { $0 + ($1.map(\.count).max() ?? 0) }
        var table = [Bool](repeating: false, count: 256)
        for alternative in units[0] { table[Int(alternative[0])] = true }
        firstBytes = table
        let set = table.indices.filter { table[$0] }
        firstSingle = set.count == 1 ? UInt8(set[0]) : nil
    }

    /// Searches `buf[0..<count]`. `absStart` is the file offset of `buf[0]`; `final` means the
    /// buffer ends at the end of the file. Matches whose word context is not fully inside the
    /// buffer are left to the next (overlapping) buffer.
    func find(_ buf: UnsafePointer<UInt8>, _ count: Int, _ absStart: Int, _ final: Bool, _ wholeWords: Bool) -> Bool {
        let last = count - minLen
        var i = 0
        while i <= last {
            if wholeWords {
                if absStart > 0 && i < 4 { i = 4; continue }
                if !final && i + maxLen + 4 > count { return false }
            }
            guard let candidate = nextCandidate(buf, count, i) else { return false }
            i = candidate
            if i > last { return false }
            if wholeWords {
                if absStart > 0 && i < 4 { i += 1; continue }
                if !final && i + maxLen + 4 > count { return false }
            }
            if alignment == 2 && (absStart + i) & 1 != 0 { i += 1; continue }
            if matchUnits(buf, count, 0, i, { end in
                !wholeWords || boundariesOK(buf, count, absStart, i, end, final)
            }) {
                return true
            }
            i += 1
        }
        return false
    }

    private func nextCandidate(_ buf: UnsafePointer<UInt8>, _ count: Int, _ from: Int) -> Int? {
        if let flat {
            guard from + flat.count <= count else { return nil }
            let hit = flat.withUnsafeBufferPointer { memmem(buf + from, count - from, $0.baseAddress!, flat.count) }
            guard let hit else { return nil }
            return UnsafeRawPointer(hit) - UnsafeRawPointer(buf)
        }
        if let single = firstSingle {
            guard from < count, let hit = memchr(buf + from, Int32(single), count - from) else { return nil }
            return UnsafeRawPointer(hit) - UnsafeRawPointer(buf)
        }
        var i = from
        while i < count {
            if firstBytes[Int(buf[i])] { return i }
            i += 1
        }
        return nil
    }

    private func matchUnits(_ buf: UnsafePointer<UInt8>, _ count: Int, _ unit: Int, _ pos: Int,
                            _ accept: (Int) -> Bool) -> Bool {
        if unit == units.count { return accept(pos) }
        for alternative in units[unit] {
            let n = alternative.count
            guard pos + n <= count else { continue }
            let equal = alternative.withUnsafeBufferPointer { memcmp(buf + pos, $0.baseAddress!, n) == 0 }
            if equal && matchUnits(buf, count, unit + 1, pos + n, accept) { return true }
        }
        return false
    }

    // MARK: Whole words

    private func boundariesOK(_ buf: UnsafePointer<UInt8>, _ count: Int, _ absStart: Int,
                              _ start: Int, _ end: Int, _ final: Bool) -> Bool {
        let atFileStart = absStart + start == 0
        let atFileEnd = final && end == count
        for encoding in encodings {
            let before = atFileStart ? nil : Self.scalarBefore(encoding, buf, start)
            let after = atFileEnd ? nil : Self.scalarAfter(encoding, buf, count, end)
            if !Self.isWord(before) && !Self.isWord(after) { return true }
        }
        return false
    }

    private static func isWord(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        if scalar == "_" { return true }
        let p = scalar.properties
        if p.isAlphabetic || p.numericType != nil { return true }
        switch p.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    private static func single(_ string: String) -> Unicode.Scalar? {
        let scalars = string.unicodeScalars
        guard scalars.count == 1, let s = scalars.first, s != "\u{FFFD}" else { return nil }
        return s
    }

    private static func unit16(_ encoding: TextEncoding, _ b: UnsafePointer<UInt8>, _ i: Int) -> UInt16 {
        encoding == .utf16BE ? UInt16(b[i]) << 8 | UInt16(b[i + 1]) : UInt16(b[i + 1]) << 8 | UInt16(b[i])
    }

    private static func scalarBefore(_ encoding: TextEncoding, _ b: UnsafePointer<UInt8>, _ i: Int) -> Unicode.Scalar? {
        switch encoding {
        case .utf8:
            guard i > 0 else { return nil }
            var j = i - 1
            while j > 0 && i - j < 4 && (b[j] & 0xC0) == 0x80 { j -= 1 }
            return single(String(decoding: UnsafeBufferPointer(start: b + j, count: i - j), as: UTF8.self))
        case .utf16LE, .utf16BE:
            guard i >= 2 else { return nil }
            let last = unit16(encoding, b, i - 2)
            var units = [last]
            if (0xDC00...0xDFFF).contains(last), i >= 4 {
                let first = unit16(encoding, b, i - 4)
                if (0xD800...0xDBFF).contains(first) { units.insert(first, at: 0) }
            }
            return single(String(decoding: units, as: UTF16.self))
        default:
            guard i > 0, let table = encoding.byteTable, let c = table[Int(b[i - 1])] else { return nil }
            return c.unicodeScalars.first
        }
    }

    private static func scalarAfter(_ encoding: TextEncoding, _ b: UnsafePointer<UInt8>, _ count: Int,
                                    _ i: Int) -> Unicode.Scalar? {
        switch encoding {
        case .utf8:
            guard i < count else { return nil }
            let lead = b[i]
            let length = lead < 0x80 ? 1 : lead >= 0xF0 ? 4 : lead >= 0xE0 ? 3 : lead >= 0xC0 ? 2 : 0
            guard length > 0, i + length <= count else { return nil }
            return single(String(decoding: UnsafeBufferPointer(start: b + i, count: length), as: UTF8.self))
        case .utf16LE, .utf16BE:
            guard i + 2 <= count else { return nil }
            let first = unit16(encoding, b, i)
            var units = [first]
            if (0xD800...0xDBFF).contains(first), i + 4 <= count { units.append(unit16(encoding, b, i + 2)) }
            return single(String(decoding: units, as: UTF16.self))
        default:
            guard i < count, let table = encoding.byteTable, let c = table[Int(b[i])] else { return nil }
            return c.unicodeScalars.first
        }
    }
}
