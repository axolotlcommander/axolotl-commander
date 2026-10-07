public import Foundation
import CryptoKit
import Darwin

/// Checksum algorithms offered for calculation and verification.
public enum ChecksumAlgorithm: String, CaseIterable, Codable, Sendable {
    case crc32, md5, sha1, sha256, sha512

    public var title: String {
        switch self {
        case .crc32: "CRC32 (SFV)"
        case .md5: "MD5"
        case .sha1: "SHA-1"
        case .sha256: "SHA-256"
        case .sha512: "SHA-512"
        }
    }

    /// Extension of the list file this algorithm writes.
    public var listExtension: String {
        switch self {
        case .crc32: "sfv"
        case .md5: "md5"
        case .sha1: "sha1"
        case .sha256: "sha256"
        case .sha512: "sha512"
        }
    }

    /// Number of hex digits of one digest.
    public var hexLength: Int {
        switch self {
        case .crc32: 8
        case .md5: 32
        case .sha1: 40
        case .sha256: 64
        case .sha512: 128
        }
    }

    /// Algorithm of a list file by its extension (case-insensitive); nil when unknown.
    public static func forListFile(named name: String) -> ChecksumAlgorithm? {
        let ext = (name as NSString).pathExtension.lowercased()
        return allCases.first { $0.listExtension == ext }
    }

    /// Algorithm whose digest has `length` hex digits.
    static func forHexLength(_ length: Int) -> ChecksumAlgorithm? {
        allCases.first { $0.hexLength == length }
    }
}

public enum ChecksumError: Error, Equatable, Sendable {
    case cannotRead(String)
    case notRegularFile
    /// The list's algorithm cannot be determined from its name or contents.
    case unknownAlgorithm
    /// No line of the list could be parsed.
    case noEntries
}

/// Checksum calculation, list files and verification.
public enum Checksums {
    static let chunkSize = 1 << 20

    // MARK: Digests

    /// Computes all `algorithms` in one read pass. Digests are lowercase hex, CRC32 is 8 uppercase hex digits.
    /// `progress` gets the number of bytes read so far. Throws `CancellationError` when the task is cancelled.
    public static func digests(
        of file: URL,
        algorithms: Set<ChecksumAlgorithm>,
        progress: (Int64) -> Void = { _ in }
    ) throws -> [ChecksumAlgorithm: String] {
        try digests(of: file, algorithms: algorithms, progress: progress, expectedDevice: nil)
    }

    /// `expectedDevice` (verification): the final component must not be a symlink and the opened
    /// file must lie on that device.
    static func digests(
        of file: URL,
        algorithms: Set<ChecksumAlgorithm>,
        progress: (Int64) -> Void,
        expectedDevice: dev_t?
    ) throws -> [ChecksumAlgorithm: String] {
        let path = file.path
        // O_NONBLOCK: a FIFO swapped in for the file must not block the open; fstat rejects it below.
        var flags = O_RDONLY | O_CLOEXEC | O_NONBLOCK
        if expectedDevice != nil { flags |= O_NOFOLLOW }
        var fd: Int32
        repeat { fd = open(path, flags) } while fd < 0 && errno == EINTR
        guard fd >= 0 else { throw ChecksumError.cannotRead("\(path): \(String(cString: strerror(errno)))") }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0 else {
            throw ChecksumError.cannotRead("\(path): \(String(cString: strerror(errno)))")
        }
        guard st.st_mode & S_IFMT == S_IFREG else { throw ChecksumError.notRegularFile }
        if let expectedDevice, st.st_dev != expectedDevice { throw ChecksumError.notRegularFile }

        var hashers = Hashers(algorithms)
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 16)
        defer { buffer.deallocate() }
        var total: Int64 = 0
        while true {
            try Task.checkCancellation()
            let n = read(fd, buffer.baseAddress, chunkSize)
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw ChecksumError.cannotRead("\(path): \(String(cString: strerror(errno)))")
            }
            if n == 0 { break }
            hashers.update(UnsafeRawBufferPointer(rebasing: buffer[0..<n]))
            total += Int64(n)
            progress(total)
        }
        return hashers.finish()
    }

    // MARK: Collecting files

    /// Regular files among `items` plus all regular files inside directory items, sorted by path.
    /// Symlinks (to files or directories) are skipped. `path` is relative to `base` with "/" separators,
    /// or absolute for items outside `base`.
    public static func files(in items: [URL], relativeTo base: URL) throws -> [(url: URL, path: String)] {
        let basePath = PathLexical.normalize(base.path)
        var result: [(url: URL, path: String)] = []

        func relative(_ path: String) -> String {
            if basePath == "/" { return String(path.dropFirst()) }
            if path.hasPrefix(basePath + "/") { return String(path.dropFirst(basePath.count + 1)) }
            return path
        }

        func visit(_ path: String) throws {
            var st = stat()
            guard lstat(path, &st) == 0 else {
                throw ChecksumError.cannotRead("\(path): \(String(cString: strerror(errno)))")
            }
            switch st.st_mode & S_IFMT {
            case S_IFREG:
                result.append((URL(fileURLWithPath: path), relative(path)))
            case S_IFDIR:
                try Task.checkCancellation()
                let names: [String]
                do {
                    names = try FileManager.default.contentsOfDirectory(atPath: path)
                } catch {
                    throw ChecksumError.cannotRead("\(path): \(error.localizedDescription)")
                }
                for name in names {
                    try visit(path == "/" ? "/" + name : path + "/" + name)
                }
            default:
                break
            }
        }

        for item in items {
            try visit(PathLexical.normalize(item.path))
        }
        let rules = NameRules.apfsDefault
        result.sort { rules.order($0.path, $1.path) == .orderedAscending }
        return result
    }

    // MARK: Writing lists

    /// Serializes a list. md5/sha*: GNU coreutils format (`hex  path`, escaped when the path contains
    /// `\`, LF or CR). crc32: SFV (`path HEX8`); paths with LF, CR or `\` cannot be represented in SFV
    /// (a `\` would be read back as a Windows separator) and are returned in `skipped`.
    public static func listData(
        _ entries: [(path: String, digest: String)],
        algorithm: ChecksumAlgorithm
    ) -> (data: Data, skipped: [String]) {
        var text = ""
        var skipped: [String] = []
        for (path, digest) in entries {
            let special = path.unicodeScalars.contains { $0 == "\\" || $0 == "\n" || $0 == "\r" }
            if algorithm == .crc32 {
                if special {
                    skipped.append(path)
                    continue
                }
                text += path + " " + digest.uppercased() + "\n"
            } else if special {
                var escaped = ""
                for scalar in path.unicodeScalars {
                    switch scalar {
                    case "\\": escaped += "\\\\"
                    case "\n": escaped += "\\n"
                    case "\r": escaped += "\\r"
                    default: escaped.unicodeScalars.append(scalar)
                    }
                }
                text += "\\" + digest.lowercased() + "  " + escaped + "\n"
            } else {
                text += digest.lowercased() + "  " + path + "\n"
            }
        }
        return (Data(text.utf8), skipped)
    }
}

// MARK: - Hashing

private struct Hashers {
    var crc: CRC32?
    var md5: Insecure.MD5?
    var sha1: Insecure.SHA1?
    var sha256: SHA256?
    var sha512: SHA512?

    init(_ algorithms: Set<ChecksumAlgorithm>) {
        if algorithms.contains(.crc32) { crc = CRC32() }
        if algorithms.contains(.md5) { md5 = Insecure.MD5() }
        if algorithms.contains(.sha1) { sha1 = Insecure.SHA1() }
        if algorithms.contains(.sha256) { sha256 = SHA256() }
        if algorithms.contains(.sha512) { sha512 = SHA512() }
    }

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        crc?.update(bytes)
        md5?.update(bufferPointer: bytes)
        sha1?.update(bufferPointer: bytes)
        sha256?.update(bufferPointer: bytes)
        sha512?.update(bufferPointer: bytes)
    }

    func finish() -> [ChecksumAlgorithm: String] {
        var result: [ChecksumAlgorithm: String] = [:]
        if let crc { result[.crc32] = crc.hex }
        if let md5 { result[.md5] = Hex.lower(md5.finalize()) }
        if let sha1 { result[.sha1] = Hex.lower(sha1.finalize()) }
        if let sha256 { result[.sha256] = Hex.lower(sha256.finalize()) }
        if let sha512 { result[.sha512] = Hex.lower(sha512.finalize()) }
        return result
    }
}

enum Hex {
    private static let digits = Array("0123456789abcdef".utf8)

    static func lower(_ bytes: some Sequence<UInt8>) -> String {
        var out: [UInt8] = []
        for b in bytes {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0F)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func isHex(_ s: some StringProtocol) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 | 0x20 >= 0x61 && $0 | 0x20 <= 0x66) }
    }
}

/// CRC-32 (IEEE 802.3, reflected, polynomial 0xEDB88320), slicing-by-8.
struct CRC32 {
    private static let tables: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 8 * 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            t[i] = c
        }
        for k in 1..<8 {
            for i in 0..<256 {
                let prev = t[(k - 1) * 256 + i]
                t[k * 256 + i] = (prev >> 8) ^ t[Int(prev & 0xFF)]
            }
        }
        return t
    }()

    private var crc: UInt32 = 0xFFFF_FFFF

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        let b = bytes.bindMemory(to: UInt8.self)
        let n = b.count
        var c = crc
        Self.tables.withUnsafeBufferPointer { t in
            var i = 0
            while n - i >= 8 {
                var a = UInt32(b[i])
                a |= UInt32(b[i + 1]) << 8
                a |= UInt32(b[i + 2]) << 16
                a |= UInt32(b[i + 3]) << 24
                a ^= c
                var x: UInt32 = t[7 * 256 + Int(a & 0xFF)]
                x ^= t[6 * 256 + Int((a >> 8) & 0xFF)]
                x ^= t[5 * 256 + Int((a >> 16) & 0xFF)]
                x ^= t[4 * 256 + Int(a >> 24)]
                x ^= t[3 * 256 + Int(b[i + 4])]
                x ^= t[2 * 256 + Int(b[i + 5])]
                x ^= t[256 + Int(b[i + 6])]
                x ^= t[Int(b[i + 7])]
                c = x
                i += 8
            }
            while i < n {
                c = t[Int((c ^ UInt32(b[i])) & 0xFF)] ^ (c >> 8)
                i += 1
            }
        }
        crc = c
    }

    var value: UInt32 { crc ^ 0xFFFF_FFFF }

    /// 8 uppercase hex digits (SFV convention).
    var hex: String {
        let s = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: 8 - s.count) + s
    }
}

// MARK: - Lexical paths

enum PathLexical {
    /// Absolute path with `.`, `..` and duplicate slashes resolved without touching the file system.
    /// A relative path is treated as relative to "/".
    static func normalize(_ path: String) -> String {
        var parts: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
                continue
            }
            parts.append(part)
        }
        return "/" + parts.joined(separator: "/")
    }

    static func components(_ normalized: String) -> [String] {
        normalized.split(separator: "/").map(String.init)
    }
}
