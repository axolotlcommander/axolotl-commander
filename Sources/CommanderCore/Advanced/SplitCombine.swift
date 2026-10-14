// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Errors of Split File and Combine Files (spec 029).
public enum SplitCombineError: Error, Equatable, Sendable {
    case cannotRead(String)
    case cannotWrite(String)
    case notRegularFile(String)
    /// The source file's size changed while it was split.
    case sourceChanged(String)
    /// Nothing to join (no part found, or only a checksum file marked).
    case noParts
    /// Names of the parts missing from a numbered set (at most ten).
    case missingParts([String])
    /// A folder has the name a part or the checksum file needs.
    case folderInTheWay(String)
    /// A file appeared under a name that was free when the user was asked.
    case alreadyExists(String)
}

// MARK: - Part size

/// The size of the parts Split File makes (R1, R2).
public enum PartSize {
    public static let mebibyte: Int64 = 1 << 20
    /// Split never makes more parts than this (three-digit names).
    public static let maximumParts = 999
    public static let defaultSize: Int64 = 100 * mebibyte

    public enum Preset: CaseIterable, Sendable {
        case email, hundred, cd, dvd, fat32

        public var bytes: Int64 {
            switch self {
            case .email: 25 * mebibyte
            case .hundred: 100 * mebibyte
            case .cd: 700 * mebibyte
            // A single-layer DVD holds 4 700 372 992 bytes; the rest leaves room for its file system.
            case .dvd: 4_480 * mebibyte
            case .fat32: 4_294_967_295
            }
        }

        public static func matching(_ bytes: Int64) -> Preset? {
            allCases.first { $0.bytes == bytes }
        }
    }

    public enum Problem: Equatable, Sendable {
        case invalid
        /// The file is not larger than one part.
        case notLarger
        case tooManyParts
    }

    /// A typed size: a number with an optional unit k, M or G (powers of 1024, also with a trailing B),
    /// bytes without a unit; a decimal comma or point; spaces anywhere. Rounded down to whole bytes; nil
    /// when it cannot be read or is below one byte.
    public static func parse(_ text: String) -> Int64? {
        var s = text.filter { !$0.isWhitespace }.lowercased()
        if s.hasSuffix("b") { s.removeLast() }
        var multiplier: Double = 1
        if let last = s.last, let unit = ["k": 1024.0, "m": 1024.0 * 1024, "g": 1024.0 * 1024 * 1024][String(last)] {
            multiplier = unit
            s.removeLast()
        }
        s = s.replacingOccurrences(of: ",", with: ".")
        guard s.contains(where: \.isNumber),
              s.allSatisfy({ ("0"..."9").contains($0) || $0 == "." }),
              s.filter({ $0 == "." }).count <= 1,
              let value = Double(s) else { return nil }
        let bytes = (value * multiplier).rounded(.down)
        guard bytes >= 1, bytes < 9.0e18 else { return nil }
        return Int64(bytes)
    }

    /// Number of parts of `partSize` bytes a file of `fileSize` bytes needs.
    public static func count(fileSize: Int64, partSize: Int64) -> Int {
        guard fileSize > 0, partSize > 0 else { return 0 }
        let whole = fileSize / partSize
        return Int(whole) + (fileSize % partSize == 0 ? 0 : 1)
    }

    /// Why a file cannot be split into parts of `partSize` (nil: it can).
    public static func problem(fileSize: Int64, partSize: Int64?) -> Problem? {
        guard let partSize, partSize > 0 else { return .invalid }
        if fileSize <= partSize { return .notLarger }
        if count(fileSize: fileSize, partSize: partSize) > maximumParts { return .tooManyParts }
        return nil
    }
}

// MARK: - Names

public enum PartName {
    /// `<base>.001`, `<base>.002`, … (at least three digits).
    public static func name(base: String, index: Int) -> String {
        let digits = String(index)
        return base + "." + String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    }

    /// `<base>.<3 or more digits>` with a number of at least 1 → base, number and digit count.
    public static func parse(_ name: String) -> (base: String, number: Int, width: Int)? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let base = name[..<dot]
        let digits = name[name.index(after: dot)...]
        guard !base.isEmpty, (3...9).contains(digits.count), digits.allSatisfy({ ("0"..."9").contains($0) }),
              let number = Int(digits), number >= 1 else { return nil }
        return (String(base), number, digits.count)
    }

    public static func checksumName(base: String) -> String { base + ".crc" }

    public static func isChecksumFile(_ name: String) -> Bool {
        name.count > 4 && name.lowercased().hasSuffix(".crc")
    }

    /// The name without its last extension (the whole name when it has none).
    static func withoutExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return name }
        return String(name[..<dot])
    }
}

// MARK: - Checksum file

/// The small text file next to the parts: original name, size and CRC32 (R4).
public struct SplitChecksum: Equatable, Sendable {
    public var name: String?
    public var size: Int64?
    public var crc32: UInt32?

    public init(name: String?, size: Int64?, crc32: UInt32?) {
        self.name = name
        self.size = size
        self.crc32 = crc32
    }

    /// The text Split writes: `filename=`, `size=`, `crc32=` lines ending with CR LF.
    public static func text(name: String, size: Int64, crc32: UInt32) -> Data {
        Data("filename=\(name)\r\nsize=\(size)\r\ncrc32=\(hex(crc32))\r\n".utf8)
    }

    /// Reads any line ends, case of keys and hex digits, spaces around values and extra lines; nil when
    /// none of the three keys is there. An unsafe name (empty, a slash, NUL, "." or "..") is dropped.
    public init?(data: Data) {
        // Names written by other programs may not be UTF-8.
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        var name: String?
        var size: Int64?
        var crc: UInt32?
        var found = false
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" || $0 == "\r\n" }) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "filename":
                found = true
                name = Self.isSafe(value) ? value : nil
            case "size":
                found = true
                size = Int64(value).flatMap { $0 >= 0 ? $0 : nil }
            case "crc32":
                found = true
                crc = value.count <= 8 ? UInt32(value, radix: 16) : nil
            default:
                continue
            }
        }
        guard found else { return nil }
        self.init(name: name, size: size, crc32: crc)
    }

    static func isSafe(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }

    public static func hex(_ crc: UInt32) -> String {
        let s = String(crc, radix: 16, uppercase: true)
        return String(repeating: "0", count: 8 - s.count) + s
    }
}

// MARK: - Part sets

/// The parts Combine Files joins, in order, with the checksum file used for the check (R5).
public struct PartSet: Equatable, Sendable {
    public var parts: [URL]
    public var checksumFile: URL?
    public var checksum: SplitChecksum?
    /// Proposed name of the joined file.
    public var defaultName: String

    /// The numbered set `<base>.001`, `<base>.002`, … that `name` (a part or the checksum file) belongs to.
    public static func find(around name: String, in folder: URL) throws -> PartSet {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        } catch {
            throw SplitCombineError.cannotRead(folder.path(percentEncoded: false))
        }
        return try find(around: name, among: names, in: folder)
    }

    static func find(around name: String, among names: [String], in folder: URL) throws -> PartSet {
        let cursor = PartName.parse(name)
        let base: String
        if PartName.isChecksumFile(name) {
            base = String(name.dropLast(4))
        } else if let cursor {
            base = cursor.base
        } else {
            throw SplitCombineError.noParts
        }
        var byWidth: [Int: [Int: String]] = [:]
        for candidate in names {
            guard let part = PartName.parse(candidate), part.base == base else { continue }
            byWidth[part.width, default: [:]][part.number] = candidate
        }
        // Names of one width only (`x.001` and `x.0001` would both be part 1): the cursor's, else the
        // narrowest.
        let width = cursor.flatMap { byWidth[$0.width] == nil ? nil : $0.width } ?? byWidth.keys.min() ?? 3
        let numbered = byWidth[width] ?? [:]
        let checksumName = PartName.checksumName(base: base).lowercased()
        let checksumFile = names.first { $0.lowercased() == checksumName }.map { folder.appending(path: $0) }
        guard let last = numbered.keys.max() else {
            throw SplitCombineError.missingParts([PartName.name(base: base, index: 1)])
        }
        let missing = (1...last).filter { numbered[$0] == nil }
        if !missing.isEmpty {
            throw SplitCombineError.missingParts(missing.prefix(10).map { number in
                let digits = String(number)
                return base + "." + String(repeating: "0", count: max(0, width - digits.count)) + digits
            })
        }
        let checksum = checksumFile.flatMap(Self.readChecksum)
        return PartSet(parts: (1...last).map { folder.appending(path: numbered[$0]!) }, checksumFile: checksumFile,
                       checksum: checksum, defaultName: checksum?.name ?? base)
    }

    /// Exactly the marked files in natural name order; the first marked `.crc` file is the checksum file.
    public static func marked(_ urls: [URL]) throws -> PartSet {
        let checksumFile = urls.first { PartName.isChecksumFile($0.lastPathComponent) }
        let rules = NameRules(caseSensitive: false)
        let parts = urls.filter { $0 != checksumFile }
            .sorted { rules.order($0.lastPathComponent, $1.lastPathComponent) == .orderedAscending }
        guard let first = parts.first else { throw SplitCombineError.noParts }
        let checksum = checksumFile.flatMap(Self.readChecksum)
        let name = first.lastPathComponent
        let fallback = PartName.parse(name)?.base ?? PartName.withoutExtension(name)
        return PartSet(parts: parts, checksumFile: checksumFile, checksum: checksum,
                       defaultName: checksum?.name ?? fallback)
    }

    /// Sum of the part sizes (links followed).
    public func totalSize() throws -> Int64 {
        try partSizes().reduce(0, +)
    }

    /// The size of each part, in order; every part must be a regular file.
    public func partSizes() throws -> [Int64] {
        try parts.map { url in
            var st = stat()
            guard stat(url.path(percentEncoded: false), &st) == 0 else {
                throw SplitCombineError.cannotRead(url.path(percentEncoded: false))
            }
            guard st.st_mode & S_IFMT == S_IFREG else { throw SplitCombineError.notRegularFile(url.lastPathComponent) }
            return Int64(st.st_size)
        }
    }

    static func readChecksum(_ url: URL) -> SplitChecksum? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // A real checksum file has three short lines.
        guard let data = try? handle.read(upToCount: 64 * 1024) else { return nil }
        return SplitChecksum(data: data)
    }
}

// MARK: - Free space

public enum FreeSpace {
    /// Bytes available on the volume of `url` (or of its nearest existing parent); nil when unknown.
    public static func available(at url: URL) -> Int64? {
        var folder = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
            let parent = folder.deletingLastPathComponent()
            if parent.path == folder.path { return nil }
            folder = parent
        }
        guard let capacity = try? folder.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity
        else { return nil }
        return Int64(capacity)
    }
}
