// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// A parsed checksum list (GNU coreutils, BSD tag or SFV format).
public struct ChecksumList: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        /// Path as written in the list ("/" separators after the Windows heuristic, escapes undone).
        public var path: String
        /// Lowercase hex.
        public var digest: String
        /// 1-based line number.
        public var line: Int

        public init(path: String, digest: String, line: Int) {
            self.path = path
            self.digest = digest
            self.line = line
        }
    }

    public var algorithm: ChecksumAlgorithm
    public var entries: [Entry]
    /// 1-based numbers of lines that are neither entries, comments nor blank.
    public var invalidLines: [Int]
    /// Encoding the list was decoded from.
    public var encoding: TextEncoding

    public init(algorithm: ChecksumAlgorithm, entries: [Entry], invalidLines: [Int], encoding: TextEncoding) {
        self.algorithm = algorithm
        self.entries = entries
        self.invalidLines = invalidLines
        self.encoding = encoding
    }
}

extension Checksums {
    /// Parses a list. The whole file is decoded once in its detected encoding (BOM, UTF-16 pattern,
    /// valid UTF-8, else `fallback`); undecodable bytes and NULs become U+FFFD.
    ///
    /// Algorithm: from the extension of `fileName`, else from the first BSD tag line, else from the
    /// digest length of the first parsable line.
    ///
    /// Windows heuristic: lists made on Windows use `\` as the separator, so in a line that is not
    /// GNU-escaped (no leading `\`) every `\` in the path becomes `/`. GNU tools always escape names
    /// containing `\`, so an unescaped `\` means a Windows separator.
    ///
    /// Throws `ChecksumError.unknownAlgorithm` or `.noEntries` when nothing parses.
    public static func parse(_ data: Data, fileName: String, fallback: TextEncoding = .windows1252) throws -> ChecksumList {
        let detection = EncodingDetector.detect(data, fallback: fallback)
        let text = TextDecoding.decode(data, as: detection.encoding, skip: detection.bomLength)
        let lines = ListLine.split(text)

        let algorithm: ChecksumAlgorithm
        if let byName = ChecksumAlgorithm.forListFile(named: fileName) {
            algorithm = byName
        } else if let guessed = ListLine.guessAlgorithm(lines) {
            algorithm = guessed
        } else {
            throw ChecksumError.unknownAlgorithm
        }

        var entries: [ChecksumList.Entry] = []
        var invalid: [Int] = []
        for (index, line) in lines.enumerated() {
            let number = index + 1
            if ListLine.isSkippable(line, algorithm: algorithm) { continue }
            if let (path, digest) = ListLine.parse(line, algorithm: algorithm) {
                entries.append(ChecksumList.Entry(path: path, digest: digest.lowercased(), line: number))
            } else {
                invalid.append(number)
            }
        }
        guard !entries.isEmpty else { throw ChecksumError.noEntries }
        return ChecksumList(algorithm: algorithm, entries: entries, invalidLines: invalid, encoding: detection.encoding)
    }
}

/// Line-level parsing of checksum lists.
enum ListLine {
    /// Splits on LF (never on NUL); removes one trailing CR; NUL becomes U+FFFD.
    static func split(_ text: String) -> [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        func flush() {
            if current.last == "\r" { current.removeLast() }
            lines.append(String(current))
            current = String.UnicodeScalarView()
        }
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n": flush()
            case "\u{0}": current.append("\u{FFFD}")
            default: current.append(scalar)
            }
        }
        if !current.isEmpty { flush() }
        return lines
    }

    static func isBlank(_ line: String) -> Bool {
        line.unicodeScalars.allSatisfy { $0 == " " || $0 == "\t" }
    }

    static func isSkippable(_ line: String, algorithm: ChecksumAlgorithm) -> Bool {
        if isBlank(line) { return true }
        return line.hasPrefix(algorithm == .crc32 ? ";" : "#")
    }

    static func guessAlgorithm(_ lines: [String]) -> ChecksumAlgorithm? {
        for line in lines where !isBlank(line) && !line.hasPrefix("#") && !line.hasPrefix(";") {
            let (body, _) = unescapePrefix(line)
            if let tag = bsd(body)?.algorithm { return tag }
            if let gnu = gnu(body), let algorithm = ChecksumAlgorithm.forHexLength(gnu.digest.count),
               algorithm != .crc32 {
                return algorithm
            }
            if sfv(line) != nil { return .crc32 }
        }
        return nil
    }

    /// (path, digest) or nil for an invalid line.
    static func parse(_ line: String, algorithm: ChecksumAlgorithm) -> (String, String)? {
        if algorithm == .crc32 {
            guard let (path, digest) = sfv(line) else { return nil }
            return (windowsSeparators(path), digest)
        }
        let (body, escaped) = unescapePrefix(line)
        var found: (path: String, digest: String)?
        if let tagged = bsd(body) {
            guard tagged.algorithm == algorithm else { return nil }
            found = (tagged.path, tagged.digest)
        } else if let plain = gnu(body) {
            found = plain
        }
        guard let found, found.digest.count == algorithm.hexLength else { return nil }
        let path: String
        if escaped {
            guard let unescaped = unescape(found.path) else { return nil }
            path = unescaped
        } else {
            path = windowsSeparators(found.path)
        }
        guard !path.isEmpty else { return nil }
        return (path, found.digest)
    }

    // MARK: Forms

    private static let bsdTags: [(String, ChecksumAlgorithm)] = [
        ("MD5", .md5), ("SHA1", .sha1), ("SHA-1", .sha1), ("SHA256", .sha256), ("SHA-256", .sha256),
        ("SHA512", .sha512), ("SHA-512", .sha512),
    ]

    /// `TAG (path) = hex`.
    static func bsd(_ line: String) -> (algorithm: ChecksumAlgorithm, path: String, digest: String)? {
        let scalars = line.unicodeScalars
        for (tag, algorithm) in bsdTags where line.hasPrefix(tag) {
            var rest = scalars.dropFirst(tag.unicodeScalars.count)
            if rest.first == " " { rest = rest.dropFirst() }
            guard rest.first == "(" else { continue }
            rest = rest.dropFirst()
            guard let close = rest.lastIndex(of: ")") else { return nil }
            let path = rest[..<close]
            var tail = rest[rest.index(after: close)...]
            while tail.first == " " { tail = tail.dropFirst() }
            guard tail.first == "=" else { return nil }
            tail = tail.dropFirst()
            while tail.first == " " { tail = tail.dropFirst() }
            let digest = string(tail)
            guard Hex.isHex(digest) else { return nil }
            return (algorithm, string(path), digest)
        }
        return nil
    }

    /// `hex  path`, `hex *path` or (lenient) `hex path`.
    static func gnu(_ line: String) -> (path: String, digest: String)? {
        let scalars = line.unicodeScalars
        guard let space = scalars.firstIndex(of: " ") else { return nil }
        let digest = string(scalars[..<space])
        guard Hex.isHex(digest) else { return nil }
        var rest = scalars[scalars.index(after: space)...]
        if rest.first == " " || rest.first == "*" { rest = rest.dropFirst() }
        guard !rest.isEmpty else { return nil }
        return (string(rest), digest)
    }

    /// `path HEX8`: the last space separates the CRC.
    static func sfv(_ line: String) -> (path: String, digest: String)? {
        let scalars = line.unicodeScalars
        guard let space = scalars.lastIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        let digest = string(scalars[scalars.index(after: space)...])
        guard digest.utf8.count == 8, Hex.isHex(digest) else { return nil }
        var path = scalars[..<space]
        while let last = path.last, last == " " || last == "\t" { path = path.dropLast() }
        guard !path.isEmpty else { return nil }
        return (string(path), digest)
    }

    private static func string(_ scalars: Substring.UnicodeScalarView) -> String {
        String(String.UnicodeScalarView(scalars))
    }

    // MARK: Escapes

    /// Drops the GNU escape marker (leading `\`).
    static func unescapePrefix(_ line: String) -> (String, Bool) {
        line.hasPrefix("\\") ? (String(line.dropFirst()), true) : (line, false)
    }

    /// GNU escapes: `\\`, `\n`, `\r`; any other escape makes the line invalid.
    static func unescape(_ path: String) -> String? {
        var out = String.UnicodeScalarView()
        var iterator = path.unicodeScalars.makeIterator()
        while let scalar = iterator.next() {
            guard scalar == "\\" else {
                out.append(scalar)
                continue
            }
            switch iterator.next() {
            case "\\": out.append("\\")
            case "n": out.append("\n")
            case "r": out.append("\r")
            default: return nil
            }
        }
        return String(out)
    }

    static func windowsSeparators(_ path: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in path.unicodeScalars { out.append(scalar == "\\" ? "/" : scalar) }
        return String(out)
    }
}
