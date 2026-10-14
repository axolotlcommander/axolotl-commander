// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import UniformTypeIdentifiers

/// The header block of a MIME message or part (spec 030, R3).
struct MIMEHeaders {
    /// Lowercased field names with their unfolded values, in order.
    private(set) var fields: [(name: String, value: String)] = []

    /// True for a line that starts a header field ("Name: value").
    static func isField(_ line: EncodedLine) -> Bool {
        guard let colon = line.bytes.firstIndex(of: UInt8(ascii: ":")), colon > 0 else { return false }
        return line.bytes[..<colon].allSatisfy { $0 > 0x20 && $0 < 0x7F }
    }

    static func text(_ bytes: some Collection<UInt8>) -> String {
        String(bytes: Array(bytes), encoding: .utf8) ?? String(bytes: Array(bytes), encoding: .isoLatin1) ?? ""
    }

    /// Reads header lines until the empty line (which is consumed) or a line that is not a header.
    static func read(from next: () throws -> EncodedLine?, pushBack: (EncodedLine) -> Void) rethrows -> MIMEHeaders {
        var headers = MIMEHeaders()
        while let line = try next() {
            if line.bytes.isEmpty { break }
            if let first = line.bytes.first, first == 0x20 || first == 0x09, !headers.fields.isEmpty {
                headers.fields[headers.fields.count - 1].value += " " + text(line.bytes).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard isField(line) else {
                pushBack(line)
                break
            }
            let colon = line.bytes.firstIndex(of: UInt8(ascii: ":"))!
            headers.fields.append((text(line.bytes[..<colon]).lowercased(),
                                   text(line.bytes[(colon + 1)...]).trimmingCharacters(in: .whitespaces)))
        }
        return headers
    }

    subscript(name: String) -> String? { fields.first { $0.name == name }?.value }

    var isMIME: Bool { self["mime-version"] != nil || self["content-type"] != nil }

    /// Type/subtype (lowercased, `text/plain` when missing) and the parameters.
    var contentType: (type: String, parameters: [String: String]) {
        guard let value = self["content-type"] else { return ("text/plain", [:]) }
        let parsed = HeaderValue.parse(value)
        return (parsed.value.contains("/") ? parsed.value.lowercased() : "text/plain", parsed.parameters)
    }

    var disposition: (value: String, parameters: [String: String])? {
        self["content-disposition"].map { HeaderValue.parse($0) }.map { ($0.value.lowercased(), $0.parameters) }
    }

    var transferEncoding: String {
        (self["content-transfer-encoding"] ?? "7bit").trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// `filename` of Content-Disposition, else `name` of Content-Type, decoded.
    var fileName: String? {
        let name = disposition?.parameters["filename"] ?? contentType.parameters["name"]
        return name.map(EncodedWords.decode).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A part that is written as a file: it has a name, is marked as an attachment, or is not text.
    var isAttachment: Bool {
        let type = contentType.type
        if type.hasPrefix("multipart/") { return false }
        if type == "message/rfc822" { return fileName != nil }
        return fileName != nil || disposition?.value == "attachment" || !type.hasPrefix("text/")
    }

    /// The extension the system knows for the part's type (for an unnamed attachment).
    var preferredExtension: String? {
        UTType(mimeType: contentType.type)?.preferredFilenameExtension
    }
}

/// A header value with `; name=value` parameters, including RFC 2231 extended and continued parameters.
enum HeaderValue {
    static func parse(_ text: String) -> (value: String, parameters: [String: String]) {
        let pieces = split(text)
        let value = pieces.first?.trimmingCharacters(in: .whitespaces) ?? ""
        var plain: [String: String] = [:]
        // name → [(section, extended, raw value)]
        var sections: [String: [(Int, Bool, String)]] = [:]
        for piece in pieces.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            var key = piece[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let raw = unquote(piece[piece.index(after: equals)...].trimmingCharacters(in: .whitespaces))
            let extended = key.hasSuffix("*")
            if extended { key.removeLast() }
            if let star = key.firstIndex(of: "*"), let number = Int(key[key.index(after: star)...]) {
                sections[String(key[..<star]), default: []].append((number, extended, raw))
            } else if extended {
                sections[key, default: []].append((0, true, raw))
            } else {
                plain[key] = raw
            }
        }
        var parameters = plain
        for (key, parts) in sections {
            var charset = "utf-8"
            var bytes: [UInt8] = []
            for (index, (_, extended, raw)) in parts.sorted(by: { $0.0 < $1.0 }).enumerated() {
                var raw = Substring(raw)
                if extended, index == 0 {
                    let fields = raw.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                    if fields.count == 3 {
                        if !fields[0].isEmpty { charset = String(fields[0]) }
                        raw = fields[2]
                    }
                }
                bytes += extended ? percentDecoded(raw) : Array(raw.utf8)
            }
            parameters[key] = EncodedWords.string(bytes, charset: charset)
        }
        return (value, parameters)
    }

    /// Splits at `;` outside quoted strings.
    private static func split(_ text: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var quoted = false
        var escaped = false
        for c in text {
            if escaped {
                current.append(c)
                escaped = false
            } else if c == "\\", quoted {
                current.append(c)
                escaped = true
            } else if c == "\"" {
                quoted.toggle()
                current.append(c)
            } else if c == ";", !quoted {
                pieces.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        pieces.append(current)
        return pieces
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        var result = ""
        var escaped = false
        for c in text.dropFirst().dropLast() {
            if escaped {
                result.append(c)
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                result.append(c)
            }
        }
        return result
    }

    private static func percentDecoded(_ text: Substring) -> [UInt8] {
        var bytes: [UInt8] = []
        let utf8 = Array(text.utf8)
        var i = 0
        while i < utf8.count {
            if utf8[i] == UInt8(ascii: "%"), i + 2 < utf8.count,
               let value = UInt8(String(decoding: utf8[i + 1...i + 2], as: UTF8.self), radix: 16) {
                bytes.append(value)
                i += 3
            } else {
                bytes.append(utf8[i])
                i += 1
            }
        }
        return bytes
    }
}

/// RFC 2047 encoded words (`=?charset?B?…?=`, `=?charset?Q?…?=`).
enum EncodedWords {
    static func decode(_ text: String) -> String {
        guard text.contains("=?") else { return text }
        let pattern = /=\?([^?\s]+)\?([BbQq])\?([^?\s]*)\?=/
        var result = ""
        var rest = Substring(text)
        var lastWasWord = false
        while let match = rest.firstMatch(of: pattern) {
            let between = rest[..<match.range.lowerBound]
            // Whitespace between two encoded words is dropped.
            if !(lastWasWord && between.allSatisfy(\.isWhitespace)) { result += between }
            let charset = String(match.output.1)
            let data = String(match.output.3)
            let bytes = match.output.2.lowercased() == "b" ? base64(data) : q(data)
            result += string(bytes, charset: charset)
            rest = rest[match.range.upperBound...]
            lastWasWord = true
        }
        return result + rest
    }

    static func string(_ bytes: [UInt8], charset: String) -> String {
        let name = charset.split(separator: "*").first.map(String.init) ?? charset
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        if cf != kCFStringEncodingInvalidId {
            let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            if let text = String(bytes: bytes, encoding: encoding) { return text }
        }
        return MIMEHeaders.text(bytes)
    }

    private static func base64(_ text: String) -> [UInt8] {
        var decoder = Base64Decoder()
        var out: [UInt8] = []
        decoder.feed(text.utf8, into: &out)
        return out
    }

    private static func q(_ text: String) -> [UInt8] {
        var out: [UInt8] = []
        let line = EncodedLine(bytes: Array(text.utf8).map { $0 == UInt8(ascii: "_") ? 0x20 : $0 }, ending: [])
        _ = QuotedPrintable.decode(line, into: &out)
        return out
    }
}
