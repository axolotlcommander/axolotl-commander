// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// The text formats of Encode File (spec 030).
public enum EncodeFormat: String, CaseIterable, Sendable {
    case base64, uue

    public static let key = "encode.format"

    public var fileExtension: String {
        switch self {
        case .base64: "b64"
        case .uue: "uue"
        }
    }
}

/// A file written by Decode File into the staging folder.
public struct DecodedFile: Equatable, Sendable {
    public enum Kind: String, Sendable { case mime, uue, xxe, binhex, base64 }
    public enum State: Equatable, Sendable {
        case complete
        /// The data ended before its end marker.
        case incomplete
        /// A checksum of the data did not match (BinHex).
        case damaged
    }

    public var name: String
    public var url: URL
    public var kind: Kind
    public var state: State
    public var size: Int64
}

/// Encode File and Decode File (spec 030): Base64 / UUE out, MIME, UUE, XXE, BinHex and Base64 in.
public enum FileCodec {
    /// A new hidden staging folder inside `folder` for the files of one run (spec 029, R7).
    public static func makeStaging(in folder: URL) throws -> URL {
        try FileSplitter.makeStaging(in: folder)
    }

    // MARK: Encoding

    /// 855 is a multiple of 57 (one Base64 line) and of 45 (one UUE line).
    static let encodeChunk = 855 * 1200

    /// The upper bound of the encoded file's size, for the free space check.
    public static func encodedSize(_ size: Int64, name: String, format: EncodeFormat) -> Int64 {
        let header = Int64(300 + 3 * name.utf8.count)
        switch format {
        case .base64:
            let characters = (size + 2) / 3 * 4
            return characters + (characters + 75) / 76 + header
        case .uue:
            return (size + 44) / 45 * 62 + header
        }
    }

    /// The MIME header of a `.b64` file: the name as a quoted string, or RFC 2231 when it is not plain ASCII.
    static func mimeHeader(name: String) -> String {
        let plain = name.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) && $0 != "\"" && $0 != "\\" }
        let nameParameter: String
        let fileParameter: String
        if plain {
            nameParameter = "name=\"\(name)\""
            fileParameter = "filename=\"\(name)\""
        } else {
            let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&+-.^_`|~".utf8)
            let encoded = name.utf8.map { allowed.contains($0) ? String(UnicodeScalar($0)) : String(format: "%%%02X", $0) }.joined()
            nameParameter = "name*=UTF-8''\(encoded)"
            fileParameter = "filename*=UTF-8''\(encoded)"
        }
        return """
            MIME-Version: 1.0
            Content-Type: application/octet-stream; \(nameParameter)
            Content-Transfer-Encoding: base64
            Content-Disposition: attachment; \(fileParameter)


            """
    }

    private static let uueCharacters: [UInt8] = (0..<64).map { $0 == 0 ? UInt8(ascii: "`") : UInt8(0x20 + $0) }

    static func uueLine(_ bytes: ArraySlice<UInt8>, into out: inout [UInt8]) {
        out.append(uueCharacters[bytes.count])
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let a = bytes[i]
            let b = i + 1 < bytes.endIndex ? bytes[i + 1] : 0
            let c = i + 2 < bytes.endIndex ? bytes[i + 2] : 0
            out.append(uueCharacters[Int(a >> 2)])
            out.append(uueCharacters[Int((a & 0x03) << 4 | b >> 4)])
            out.append(uueCharacters[Int((b & 0x0F) << 2 | c >> 6)])
            out.append(uueCharacters[Int(c & 0x3F)])
            i += 3
        }
        out.append(0x0A)
    }

    /// Writes `<name>.b64` or `<name>.uue` into `folder` (a staging folder) and returns it.
    public static func encode(source: URL, name: String, format: EncodeFormat, into folder: URL,
                              progress: @Sendable (Int64) -> Void = { _ in }) async throws -> URL {
        let sourcePath = FileSplitter.path(source)
        let input = try FileSplitter.openForReading(sourcePath)
        defer { close(input) }
        _ = try FileSplitter.regularFileSize(input, name: source.lastPathComponent, path: sourcePath)
        let url = folder.appending(path: NameAllocator.shortened(name + "." + format.fileExtension))
        let output = try OutputFile(url: url)
        switch format {
        case .base64: try output.write(Array(mimeHeader(name: name).utf8))
        case .uue:
            let safe = name.map { $0 == "\n" || $0 == "\r" ? "_" : String($0) }.joined()
            try output.write(Array("begin 644 \(safe)\n".utf8))
        }
        var buffer = [UInt8](repeating: 0, count: encodeChunk)
        var done: Int64 = 0
        while true {
            if Task.isCancelled { throw CancellationError() }
            var filled = 0
            while filled < encodeChunk {
                let n = try buffer.withUnsafeMutableBytes { raw in
                    try FileSplitter.readSome(input, UnsafeMutableRawBufferPointer(rebasing: raw[filled...]),
                                              encodeChunk - filled, path: sourcePath)
                }
                if n == 0 { break }
                filled += n
            }
            if filled == 0 { break }
            let chunk = buffer[..<filled]
            var out: [UInt8] = []
            switch format {
            case .base64:
                let text = Data(chunk).base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed])
                out = Array(text.utf8)
                out.append(0x0A)
            case .uue:
                out.reserveCapacity(filled / 45 * 62 + 62)
                var i = 0
                while i < filled {
                    uueLine(chunk[i..<min(i + 45, filled)], into: &out)
                    i += 45
                }
            }
            try output.write(out)
            done += Int64(filled)
            progress(done)
            if filled < encodeChunk { break }
        }
        if format == .uue { try output.write(Array("`\nend\n".utf8)) }
        try output.close()
        return url
    }

    // MARK: Decoding

    /// Decodes every encoded file found in `inputs` (read in this order as one text) into `staging`.
    /// Returns an empty list when nothing was found; throws `CancellationError` when cancelled (the caller
    /// removes the staging folder).
    public static func decode(_ inputs: [URL], into staging: URL,
                              progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws -> [DecodedFile] {
        let run = DecodeRun(staging: staging)
        defer { run.closeAll() }
        let reader = LineReader(inputs, progress: progress)
        try run.decode(reader)
        if run.results.isEmpty, run.plainBase64, let first = inputs.first {
            // The whole input is Base64 text without headers (R2): a second pass.
            var name = first.lastPathComponent
            let lower = name.lowercased()
            if let ext = [".b64", ".base64"].first(where: { lower.hasSuffix($0) }), name.count > ext.count {
                name.removeLast(ext.count)
            } else {
                name += ".bin"
            }
            try run.decodePlainBase64(LineReader(inputs, progress: progress), name: name)
        }
        return run.results
    }
}

/// A file being written: buffered `write`s, created with `O_EXCL`.
final class OutputFile {
    let url: URL
    private var fd: Int32
    private var buffer: [UInt8] = []
    private(set) var size: Int64 = 0

    init(url: URL) throws {
        self.url = url
        fd = try FileSplitter.createExclusive(FileSplitter.path(url))
    }

    deinit { if fd >= 0 { Darwin.close(fd) } }

    func write(_ bytes: [UInt8]) throws {
        buffer += bytes
        size += Int64(bytes.count)
        if buffer.count >= 1 << 20 { try flush() }
    }

    private func flush() throws {
        try buffer.withUnsafeBytes { try FileSplitter.writeAll(fd, $0, path: FileSplitter.path(url)) }
        buffer.removeAll(keepingCapacity: true)
    }

    func close() throws {
        guard fd >= 0 else { return }
        try flush()
        Darwin.close(fd)
        fd = -1
    }
}

/// One Decode File run: the outputs, names and results.
final class DecodeRun {
    let staging: URL
    private var names = NameAllocator()
    private(set) var results: [DecodedFile] = []
    private var open: [ObjectIdentifier: (OutputFile, String, DecodedFile.Kind)] = [:]
    /// Every non-empty line seen at the top level was Base64 text, and there was at least one.
    private(set) var plainBase64 = false

    init(staging: URL) { self.staging = staging }

    func begin(_ rawName: String, kind: DecodedFile.Kind, fallbackExtension: String? = nil) throws -> OutputFile {
        let name = names.unique(rawName, fallbackExtension: fallbackExtension)
        let file = try OutputFile(url: staging.appending(path: name))
        open[ObjectIdentifier(file)] = (file, name, kind)
        return file
    }

    func finish(_ file: OutputFile, _ state: DecodedFile.State) throws {
        guard let (_, name, kind) = open.removeValue(forKey: ObjectIdentifier(file)) else { return }
        try file.close()
        results.append(DecodedFile(name: name, url: file.url, kind: kind, state: state, size: file.size))
    }

    func closeAll() {
        for (file, _, _) in open.values { try? file.close() }
        open = [:]
    }

    // MARK: Top level

    func decode(_ reader: LineReader) throws {
        // Leading empty lines and an mbox "From " line may precede the headers of a saved message.
        var first = try reader.next()
        while let line = first, line.bytes.isEmpty || line.hasPrefix("From ") { first = try reader.next() }
        guard let first else { return }
        reader.pushBack(first)
        if MIMEHeaders.isField(first) {
            let headers = try MIMEHeaders.read(from: reader.next, pushBack: reader.pushBack)
            if headers.isMIME {
                _ = try part(headers, reader: reader, boundaries: [])
                return
            }
        }
        let scanner = BlockScanner(run: self)
        var shape = Base64Shape()
        while let line = try reader.next() {
            shape.add(line.trimmed)
            try scanner.feed(line)
        }
        try scanner.finish()
        plainBase64 = shape.isBase64
    }

    func decodePlainBase64(_ reader: LineReader, name: String) throws {
        let file = try begin(name, kind: .base64)
        var decoder = Base64Decoder()
        var out: [UInt8] = []
        while let line = try reader.next() {
            decoder.feed(line.bytes, into: &out)
            if out.count >= 1 << 20 {
                try file.write(out)
                out.removeAll(keepingCapacity: true)
            }
        }
        try file.write(out)
        try finish(file, decoder.isComplete ? .complete : .incomplete)
    }

    // MARK: MIME

    /// How a part's body ended.
    enum End: Equatable {
        case eof
        /// A delimiter of `boundaries[index]`; `closing` for `--boundary--`.
        case boundary(index: Int, closing: Bool)
    }

    private static func boundary(_ line: EncodedLine, _ boundaries: [String]) -> End? {
        guard line.bytes.count >= 2, line.bytes[0] == 0x2D, line.bytes[1] == 0x2D else { return nil }
        let text = MIMEHeaders.text(line.trimmed.dropFirst(2))
        for (index, boundary) in boundaries.enumerated().reversed() {
            if text == boundary { return .boundary(index: index, closing: false) }
            if text == boundary + "--" { return .boundary(index: index, closing: true) }
        }
        return nil
    }

    /// Reads one part's body (after its headers) until a boundary of `boundaries` or the end of the input.
    func part(_ headers: MIMEHeaders, reader: LineReader, boundaries: [String]) throws -> End {
        let (type, parameters) = headers.contentType
        if type.hasPrefix("multipart/"), let boundary = parameters["boundary"], !boundary.isEmpty {
            return try multipart(boundary, reader: reader, boundaries: boundaries)
        }
        if type == "message/rfc822", !headers.isAttachment {
            let inner = try MIMEHeaders.read(from: reader.next, pushBack: reader.pushBack)
            return try part(inner, reader: reader, boundaries: boundaries)
        }
        if headers.isAttachment {
            return try attachment(headers, reader: reader, boundaries: boundaries)
        }
        return try text(headers, reader: reader, boundaries: boundaries)
    }

    private func multipart(_ boundary: String, reader: LineReader, boundaries: [String]) throws -> End {
        let stack = boundaries + [boundary]
        let own = stack.count - 1
        // The preamble.
        var end = End.eof
        while let line = try reader.next() {
            if let hit = Self.boundary(line, stack) {
                end = hit
                break
            }
        }
        while case .boundary(own, false) = end {
            let headers = try MIMEHeaders.read(from: reader.next, pushBack: reader.pushBack)
            end = try part(headers, reader: reader, boundaries: stack)
        }
        guard case .boundary(own, true) = end else { return end }
        // The epilogue, up to the enclosing boundary.
        while let line = try reader.next() {
            if let hit = Self.boundary(line, boundaries) { return hit }
        }
        return .eof
    }

    private func attachment(_ headers: MIMEHeaders, reader: LineReader, boundaries: [String]) throws -> End {
        let file = try begin(headers.fileName ?? "", kind: .mime,
                             fallbackExtension: headers.fileName == nil ? headers.preferredExtension : nil)
        let encoding = headers.transferEncoding
        var base64 = Base64Decoder()
        var out: [UInt8] = []
        var pendingEnding: [UInt8] = []
        var end = End.eof
        while let line = try reader.next() {
            if let hit = Self.boundary(line, boundaries) {
                end = hit
                break
            }
            switch encoding {
            case "base64": base64.feed(line.bytes, into: &out)
            case "quoted-printable":
                out += pendingEnding
                pendingEnding = QuotedPrintable.decode(line, into: &out) ? line.ending : []
            default:
                // The line end before a delimiter belongs to the delimiter: written only with the next line.
                out += pendingEnding
                out += line.bytes
                pendingEnding = line.ending
            }
            if out.count >= 1 << 20 {
                try file.write(out)
                out.removeAll(keepingCapacity: true)
            }
        }
        if case .eof = end, boundaries.isEmpty { out += pendingEnding }
        try file.write(out)
        let complete = (end != .eof || boundaries.isEmpty) && (encoding != "base64" || base64.isComplete)
        try finish(file, complete ? .complete : .incomplete)
        return end
    }

    /// A text part: decoded and scanned for UUE / XXE / BinHex blocks (old mails carried files in the body).
    private func text(_ headers: MIMEHeaders, reader: LineReader, boundaries: [String]) throws -> End {
        let scanner = BlockScanner(run: self)
        let encoding = headers.transferEncoding
        var base64 = Base64Decoder()
        var decoded: [UInt8] = []
        var end = End.eof
        func feedDecoded(final: Bool) throws {
            while let newline = decoded.firstIndex(of: 0x0A) {
                var bytes = Array(decoded[..<newline])
                if bytes.last == 0x0D { bytes.removeLast() }
                try scanner.feed(EncodedLine(bytes: bytes, ending: [0x0A]))
                decoded.removeSubrange(...newline)
            }
            if final, !decoded.isEmpty {
                try scanner.feed(EncodedLine(bytes: decoded, ending: []))
                decoded = []
            }
        }
        while let line = try reader.next() {
            if let hit = Self.boundary(line, boundaries) {
                end = hit
                break
            }
            switch encoding {
            case "base64":
                base64.feed(line.bytes, into: &decoded)
                try feedDecoded(final: false)
            case "quoted-printable":
                if QuotedPrintable.decode(line, into: &decoded) { decoded += line.ending.isEmpty ? [0x0A] : line.ending }
                try feedDecoded(final: false)
            default:
                try scanner.feed(line)
            }
        }
        try feedDecoded(final: true)
        try scanner.finish()
        return end
    }
}

/// Whether a whole input looks like Base64 text without headers (R2): only Base64 lines, all as long as the
/// first (at least 16 characters when there are more lines), the last not longer; a single line needs at
/// least 8 characters. Ordinary words do not pass.
struct Base64Shape {
    private var lines = 0
    private var first = 0
    private var previousShorter = false
    private var characters = 0
    private var valid = true

    mutating func add(_ line: ArraySlice<UInt8>) {
        guard valid, !line.isEmpty else { return }
        guard !previousShorter, Base64Decoder.isBase64Line(line), !line.contains(0x20) else {
            valid = false
            return
        }
        lines += 1
        characters += line.count
        if lines == 1 { first = line.count }
        else if line.count > first { valid = false }
        else if line.count < first { previousShorter = true }
    }

    var isBase64: Bool {
        guard valid, lines > 0, characters % 4 != 1 else { return false }
        return lines == 1 ? first >= 8 : first >= 16
    }
}

/// Finds UUE, XXE, `begin-base64` and BinHex blocks in lines of text (spec 030, R2).
final class BlockScanner {
    private enum State {
        case idle
        /// After `begin`: the kind is decided by the first data line.
        case uu(name: String, file: OutputFile?, alphabet: UUDecoder.Alphabet?)
        case base64(file: OutputFile, decoder: Base64Decoder)
        case binhexStart
        case binhex(decoder: BinHexDecoder, file: OutputFile?)
    }

    private let run: DecodeRun
    private var state = State.idle

    init(run: DecodeRun) { self.run = run }

    /// `begin <octal mode> <name>` (or `begin-base64 …`): the name, or nil.
    private static func beginName(_ line: EncodedLine, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        let rest = MIMEHeaders.text(line.bytes.dropFirst(prefix.utf8.count))
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, (1...4).contains(parts[0].count), parts[0].allSatisfy({ ("0"..."7").contains($0) }) else { return nil }
        return String(parts[1])
    }

    private static func isEnd(_ line: EncodedLine) -> Bool { line.trimmed.elementsEqual("end".utf8) }

    func feed(_ line: EncodedLine) throws {
        switch state {
        case .idle:
            try start(line)
        case .uu(let name, var file, var alphabet):
            if Self.isEnd(line) {
                let output = try file ?? run.begin(name, kind: .uue)
                try run.finish(output, .complete)
                state = .idle
                return
            }
            if Self.beginName(line, prefix: "begin ") != nil || Self.beginName(line, prefix: "begin-base64 ") != nil {
                if let file { try run.finish(file, .incomplete) } else { try run.finish(run.begin(name, kind: .uue), .incomplete) }
                state = .idle
                try start(line)
                return
            }
            let data = line.trimmed
            if alphabet == nil {
                if UUDecoder.byteCount(data, .uue) != nil { alphabet = .uue }
                else if UUDecoder.byteCount(data, .xxe) != nil { alphabet = .xxe }
                else { return }
                file = try run.begin(name, kind: alphabet == .uue ? .uue : .xxe)
            }
            guard let alphabet, let output = file, UUDecoder.byteCount(data, alphabet) != nil else { return }
            var out: [UInt8] = []
            UUDecoder.decode(data, alphabet, into: &out)
            try output.write(out)
            state = .uu(name: name, file: output, alphabet: alphabet)
        case .base64(let file, var decoder):
            if line.trimmed.elementsEqual("====".utf8) {
                try run.finish(file, .complete)
                state = .idle
                return
            }
            var out: [UInt8] = []
            decoder.feed(line.bytes, into: &out)
            try file.write(out)
            state = .base64(file: file, decoder: decoder)
        case .binhexStart:
            guard let colon = line.bytes.firstIndex(of: UInt8(ascii: ":")) else { return }
            state = .binhex(decoder: BinHexDecoder(), file: nil)
            try binhex(line.bytes[(colon + 1)...])
        case .binhex:
            try binhex(line.bytes[...])
        }
    }

    private func start(_ line: EncodedLine) throws {
        if let name = Self.beginName(line, prefix: "begin-base64 ") {
            state = .base64(file: try run.begin(name, kind: .base64), decoder: Base64Decoder())
        } else if let name = Self.beginName(line, prefix: "begin ") {
            state = .uu(name: name, file: nil, alphabet: nil)
        } else if line.hasPrefix("(This file must be converted with BinHex") {
            state = .binhexStart
        }
    }

    private func binhex(_ characters: ArraySlice<UInt8>) throws {
        guard case .binhex(var decoder, var file) = state else { return }
        decoder.feed(characters)
        if file == nil, decoder.hasHeader {
            file = try run.begin(decoder.name ?? NameAllocator.fallback, kind: .binhex)
        }
        if let file, !decoder.data.isEmpty {
            try file.write(decoder.data)
            decoder.data.removeAll(keepingCapacity: true)
        }
        if decoder.closed {
            let output = try file ?? run.begin(NameAllocator.fallback, kind: .binhex)
            try run.finish(output, decoder.result)
            state = .idle
        } else {
            state = .binhex(decoder: decoder, file: file)
        }
    }

    /// The end of the input closes an open block as incomplete.
    func finish() throws {
        switch state {
        case .idle, .binhexStart: break
        case .uu(let name, let file, _):
            try run.finish(file ?? run.begin(name, kind: .uue), .incomplete)
        case .base64(let file, _):
            try run.finish(file, .incomplete)
        case .binhex(_, let file):
            if let file { try run.finish(file, .incomplete) }
        }
        state = .idle
    }
}
