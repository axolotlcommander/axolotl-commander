// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// One line of the input without its line end; `ending` is empty, LF or CR LF (spec 030, R1).
struct EncodedLine: Equatable {
    var bytes: [UInt8]
    var ending: [UInt8]

    /// The line without trailing spaces and tabs.
    var trimmed: ArraySlice<UInt8> {
        var end = bytes.endIndex
        while end > bytes.startIndex, bytes[end - 1] == 0x20 || bytes[end - 1] == 0x09 { end -= 1 }
        return bytes[..<end]
    }

    func hasPrefix(_ prefix: String) -> Bool { bytes.starts(with: prefix.utf8) }
}

/// Reads the lines of several files in order, as one input. A file that does not end with a line end ends
/// its last line there; a line longer than `maximumLine` is handed out in pieces without a line end.
final class LineReader {
    static let chunk = 1 << 20
    static let maximumLine = 1 << 20

    private let urls: [URL]
    private var index = -1
    private var fd: Int32 = -1
    private var buffer: [UInt8] = []
    private var start = 0
    private var atEnd = true
    private var pushedBack: [EncodedLine] = []
    private let progress: (Int64) -> Void
    private(set) var readBytes: Int64 = 0

    init(_ urls: [URL], progress: @escaping (Int64) -> Void = { _ in }) {
        self.urls = urls
        self.progress = progress
    }

    deinit { if fd >= 0 { close(fd) } }

    /// Size of all inputs; every input must be a regular file.
    static func totalSize(_ urls: [URL]) throws -> Int64 {
        try urls.reduce(0) { sum, url in
            var st = stat()
            let path = FileSplitter.path(url)
            guard stat(path, &st) == 0 else { throw SplitCombineError.cannotRead(FileSplitter.describe(path)) }
            guard st.st_mode & S_IFMT == S_IFREG else { throw SplitCombineError.notRegularFile(url.lastPathComponent) }
            return sum + Int64(st.st_size)
        }
    }

    func pushBack(_ line: EncodedLine) { pushedBack.append(line) }

    func next() throws -> EncodedLine? {
        if let line = pushedBack.popLast() { return line }
        while true {
            if let newline = buffer[start...].firstIndex(of: 0x0A) {
                var end = newline
                var ending: [UInt8] = [0x0A]
                if end > start, buffer[end - 1] == 0x0D {
                    end -= 1
                    ending = [0x0D, 0x0A]
                }
                let line = EncodedLine(bytes: Array(buffer[start..<end]), ending: ending)
                start = newline + 1
                return line
            }
            if buffer.count - start >= Self.maximumLine {
                let line = EncodedLine(bytes: Array(buffer[start..<start + Self.maximumLine]), ending: [])
                start += Self.maximumLine
                return line
            }
            if atEnd {
                if start < buffer.count {
                    let line = EncodedLine(bytes: Array(buffer[start...]), ending: [])
                    buffer.removeAll(keepingCapacity: true)
                    start = 0
                    return line
                }
                guard try openNext() else { return nil }
                continue
            }
            try fill()
        }
    }

    private func openNext() throws -> Bool {
        if fd >= 0 { close(fd); fd = -1 }
        index += 1
        guard index < urls.count else { return false }
        let path = FileSplitter.path(urls[index])
        fd = try FileSplitter.openForReading(path)
        _ = try FileSplitter.regularFileSize(fd, name: urls[index].lastPathComponent, path: path)
        buffer.removeAll(keepingCapacity: true)
        start = 0
        atEnd = false
        return true
    }

    private func fill() throws {
        if Task.isCancelled { throw CancellationError() }
        if start > 0 {
            buffer.removeSubrange(0..<start)
            start = 0
        }
        let old = buffer.count
        buffer.append(contentsOf: repeatElement(0, count: Self.chunk))
        let path = FileSplitter.path(urls[index])
        let n = try buffer.withUnsafeMutableBytes { raw in
            try FileSplitter.readSome(fd, UnsafeMutableRawBufferPointer(rebasing: raw[old...]), Self.chunk, path: path)
        }
        buffer.removeLast(Self.chunk - n)
        if n == 0 { atEnd = true }
        readBytes += Int64(n)
        progress(readBytes)
    }
}

// MARK: Base64

/// Streaming Base64 decoder: characters outside the alphabet are ignored, `=` ends the data.
struct Base64Decoder {
    static let table: [Int8] = {
        var t = [Int8](repeating: -1, count: 256)
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8.enumerated() { t[Int(c)] = Int8(i) }
        return t
    }()

    private var accumulator: UInt32 = 0
    private var bits = 0
    private var characters = 0
    private(set) var ended = false

    /// True when the data ended on a group of four characters or with padding.
    var isComplete: Bool { ended || characters % 4 == 0 }

    mutating func feed(_ bytes: some Sequence<UInt8>, into out: inout [UInt8]) {
        guard !ended else { return }
        for c in bytes {
            if c == UInt8(ascii: "=") {
                ended = true
                return
            }
            let v = Self.table[Int(c)]
            guard v >= 0 else { continue }
            characters += 1
            accumulator = accumulator << 6 | UInt32(v)
            bits += 6
            if bits >= 8 {
                bits -= 8
                out.append(UInt8(truncatingIfNeeded: accumulator >> UInt32(bits)))
            }
        }
    }

    /// True when `line` holds only Base64 characters (and padding), ignoring spaces.
    static func isBase64Line(_ line: some Collection<UInt8>) -> Bool {
        var any = false
        for c in line where c != 0x20 && c != 0x09 {
            guard table[Int(c)] >= 0 || c == UInt8(ascii: "=") else { return false }
            any = true
        }
        return any
    }
}

// MARK: Quoted-printable

enum QuotedPrintable {
    private static func hex(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: c - 0x30
        case 0x41...0x46: c - 0x41 + 10
        case 0x61...0x66: c - 0x61 + 10
        default: nil
        }
    }

    /// Decodes one line without its ending; returns false for a soft line break (`=` at the end), after
    /// which the next line continues this one, true when the line's own ending belongs to the data.
    @discardableResult
    static func decode(_ line: EncodedLine, into out: inout [UInt8]) -> Bool {
        let bytes = line.trimmed
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let c = bytes[i]
            if c == UInt8(ascii: "=") {
                if i + 1 == bytes.endIndex { return false }  // soft line break
                if bytes.endIndex - i >= 3, let hi = hex(bytes[i + 1]), let lo = hex(bytes[i + 2]) {
                    out.append(hi << 4 | lo)
                    i += 3
                    continue
                }
            }
            out.append(c)
            i += 1
        }
        return true
    }
}

// MARK: UUE and XXE

/// Line decoder for UUE and XXE: the first character gives the byte count, four characters make three bytes.
struct UUDecoder {
    enum Alphabet { case uue, xxe }

    private static let xxeTable: [Int8] = {
        var t = [Int8](repeating: -1, count: 256)
        for (i, c) in "+-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8.enumerated() { t[Int(c)] = Int8(i) }
        return t
    }()

    static func value(_ c: UInt8, _ alphabet: Alphabet) -> Int? {
        switch alphabet {
        case .uue: (0x20...0x60).contains(c) ? Int((c - 0x20) & 0x3F) : nil
        case .xxe: xxeTable[Int(c)] >= 0 ? Int(xxeTable[Int(c)]) : nil
        }
    }

    /// The byte count of a valid data line: every character belongs to the alphabet and the line has the
    /// characters its count needs (up to two more are allowed, e.g. a checksum character).
    static func byteCount(_ line: ArraySlice<UInt8>, _ alphabet: Alphabet) -> Int? {
        guard let first = line.first, let count = value(first, alphabet) else { return nil }
        let needed = (count + 2) / 3 * 4
        let characters = line.count - 1
        guard characters >= needed, characters <= needed + 2 else { return nil }
        for c in line.dropFirst() where value(c, alphabet) == nil { return nil }
        return count
    }

    static func decode(_ line: ArraySlice<UInt8>, _ alphabet: Alphabet, into out: inout [UInt8]) {
        guard var count = byteCount(line, alphabet) else { return }
        var i = line.startIndex + 1
        while count > 0 {
            let a = value(line[i], alphabet) ?? 0, b = value(line[i + 1], alphabet) ?? 0
            let c = value(line[i + 2], alphabet) ?? 0, d = value(line[i + 3], alphabet) ?? 0
            let group = [UInt8(truncatingIfNeeded: a << 2 | b >> 4), UInt8(truncatingIfNeeded: b << 4 | c >> 2),
                         UInt8(truncatingIfNeeded: c << 6 | d)]
            out.append(contentsOf: group.prefix(count))
            count -= min(count, 3)
            i += 4
        }
    }
}

// MARK: BinHex 4.0

enum CRC16 {
    private static let table: [UInt16] = (0..<256).map { i in
        var crc = UInt16(i) << 8
        for _ in 0..<8 { crc = crc & 0x8000 != 0 ? crc << 1 ^ 0x1021 : crc << 1 }
        return crc
    }

    /// CRC-16/XMODEM (polynomial 0x1021, initial 0), as BinHex uses it.
    static func update(_ crc: UInt16, _ byte: UInt8) -> UInt16 {
        crc << 8 ^ table[Int(UInt8(truncatingIfNeeded: crc >> 8) ^ byte)]
    }

    static func xmodem(_ bytes: some Sequence<UInt8>) -> UInt16 { bytes.reduce(0, update) }
}

/// BinHex 4.0: 6-bit characters → run-length decoding → header, data fork and resource fork with CRCs.
/// Only the data fork is kept (`data`, drained by the caller).
struct BinHexDecoder {
    enum State: Equatable { case running, finished, damaged }

    private static let table: [Int8] = {
        var t = [Int8](repeating: -1, count: 256)
        for (i, c) in "!\"#$%&'()*+,-012345689@ABCDEFGHIJKLMNPQRSTUVXYZ[`abcdefhijklmpqr".utf8.enumerated() { t[Int(c)] = Int8(i) }
        return t
    }()

    private enum Stage { case header, data, dataCRC, resource, resourceCRC, done }

    private(set) var state = State.running
    private(set) var name: String?
    var data: [UInt8] = []
    private var accumulator: UInt32 = 0
    private var bits = 0
    private var runMarker = false
    private var last: UInt8 = 0
    private var stage = Stage.header
    private var header: [UInt8] = []
    private var crc: UInt16 = 0
    private var remaining = 0
    private var resourceLength = 0
    private var storedCRC: [UInt8] = []

    /// True when the end `:` was seen.
    private(set) var closed = false

    /// Feeds characters; returns false once the closing `:` was read (the rest of the line is not data).
    @discardableResult
    mutating func feed(_ characters: some Sequence<UInt8>) -> Bool {
        for c in characters {
            guard !closed else { return false }
            if c == UInt8(ascii: ":") {
                closed = true
                return false
            }
            if c == 0x20 || c == 0x09 || c == 0x0D || c == 0x0A { continue }
            let v = Self.table[Int(c)]
            guard v >= 0 else {
                if state == .running { state = .damaged }
                continue
            }
            accumulator = accumulator << 6 | UInt32(v)
            bits += 6
            if bits >= 8 {
                bits -= 8
                expand(UInt8(truncatingIfNeeded: accumulator >> UInt32(bits)))
            }
        }
        return true
    }

    private mutating func expand(_ byte: UInt8) {
        if runMarker {
            runMarker = false
            if byte == 0 {
                last = 0x90
                consume(0x90)
            } else if byte > 1 {
                for _ in 1..<byte { consume(last) }
            }
        } else if byte == 0x90 {
            runMarker = true
        } else {
            last = byte
            consume(byte)
        }
    }

    private static func int32(_ b: ArraySlice<UInt8>) -> Int {
        b.reduce(0) { $0 << 8 | Int($1) }
    }

    private mutating func consume(_ byte: UInt8) {
        switch stage {
        case .header:
            header.append(byte)
            let nameLength = Int(header[0])
            // length, name, version, type (4), creator (4), flags (2), data length (4), resource length (4), CRC (2)
            guard header.count == 1 + nameLength + 1 + 4 + 4 + 2 + 4 + 4 + 2 else { return }
            let body = header.dropLast(2)
            let stored = UInt16(header[header.count - 2]) << 8 | UInt16(header[header.count - 1])
            if CRC16.xmodem(body) != stored { state = .damaged }
            let nameBytes = header[1..<1 + nameLength]
            name = String(bytes: nameBytes, encoding: .macOSRoman) ?? String(decoding: nameBytes, as: UTF8.self)
            let lengths = 1 + nameLength + 1 + 4 + 4 + 2
            remaining = Self.int32(header[lengths..<lengths + 4])
            resourceLength = Self.int32(header[lengths + 4..<lengths + 8])
            crc = 0
            stage = remaining > 0 ? .data : .dataCRC
        case .data:
            data.append(byte)
            crc = CRC16.update(crc, byte)
            remaining -= 1
            if remaining == 0 { stage = .dataCRC }
        case .dataCRC, .resourceCRC:
            storedCRC.append(byte)
            guard storedCRC.count == 2 else { return }
            if UInt16(storedCRC[0]) << 8 | UInt16(storedCRC[1]) != crc { state = .damaged }
            storedCRC = []
            crc = 0
            if stage == .dataCRC {
                remaining = resourceLength
                stage = remaining > 0 ? .resource : .resourceCRC
            } else {
                stage = .done
                if state == .running { state = .finished }
            }
        case .resource:
            crc = CRC16.update(crc, byte)
            remaining -= 1
            if remaining == 0 { stage = .resourceCRC }
        case .done:
            break
        }
    }

    /// True once the header was read (the name is known).
    var hasHeader: Bool { stage != .header }

    /// True when the data stopped before the resource fork's CRC.
    var isTruncated: Bool { stage != .done }

    /// The result for a closed stream.
    var result: DecodedFile.State {
        if state == .damaged { return isTruncated ? .incomplete : .damaged }
        return isTruncated ? .incomplete : .complete
    }
}

// MARK: Names

/// Safe names for decoded files (spec 030, R5): one component inside the target, unique within a run.
struct NameAllocator {
    static let fallback = "decoded"
    private var used: Set<String> = []

    static func safe(_ raw: String, fallbackExtension: String? = nil) -> String {
        let last = raw.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var scalars = String.UnicodeScalarView()
        for s in last.unicodeScalars {
            let control = s.value < 0x20 || (0x7F...0x9F).contains(s.value)
            scalars.append(control || s == ":" ? "_" : s)
        }
        var name = String(scalars).trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name == "." || name == ".." {
            name = fallback + (fallbackExtension.map { "." + $0 } ?? "")
        }
        return shortened(name)
    }

    /// At most 255 UTF-8 bytes, keeping a short extension.
    static func shortened(_ name: String, limit: Int = 255) -> String {
        guard name.utf8.count > limit else { return name }
        let (base, ext) = split(name)
        var shortBase = base
        while !shortBase.isEmpty, shortBase.utf8.count + ext.utf8.count > limit { shortBase.removeLast() }
        return shortBase + ext
    }

    /// The name and its extension (with the dot); a leading dot is not an extension.
    static func split(_ name: String) -> (String, String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        let ext = String(name[dot...])
        guard ext.count <= 16 else { return (name, "") }
        return (String(name[..<dot]), ext)
    }

    /// The safe form of `raw`, with " 2", " 3", … before the extension when this run already used it.
    mutating func unique(_ raw: String, fallbackExtension: String? = nil) -> String {
        let safe = Self.safe(raw, fallbackExtension: fallbackExtension)
        var candidate = safe
        var number = 2
        while used.contains(candidate.lowercased()) {
            let (base, ext) = Self.split(safe)
            candidate = Self.shortened("\(base) \(number)\(ext)")
            number += 1
        }
        used.insert(candidate.lowercased())
        return candidate
    }
}
