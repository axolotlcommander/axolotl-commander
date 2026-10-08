// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

internal import CArchive
import Foundation
import Darwin

// Thin wrappers over libarchive handles. Handles are not Sendable: create and
// use them inside one synchronous call chain.

func archiveMessage(_ a: OpaquePointer, _ fallback: String) -> String {
    archive_error_string(a).map { String(cString: $0) } ?? fallback
}

/// Owns a read handle for an archive file.
final class ArchiveReadHandle {
    let a: OpaquePointer

    /// `passphrases` are tried in turn for encrypted entries (zip only).
    init(path: String, passphrases: [String] = []) throws(ArchiveError) {
        guard let a = archive_read_new() else { throw .library("archive_read_new failed") }
        self.a = a
        archive_read_support_filter_all(a)
        archive_read_support_format_all(a)
        for passphrase in passphrases where !passphrase.isEmpty {
            archive_read_add_passphrase(a, passphrase)
        }
        let r = archive_read_open_filename(a, path, 64 * 1024)
        if r != ARCHIVE_OK && r != ARCHIVE_WARN { throw .library(archiveMessage(a, "Cannot open archive")) }
    }

    deinit { archive_read_free(a) }

    /// The next entry header, nil at the end of the archive.
    func next() throws(ArchiveError) -> OpaquePointer? {
        var entry: OpaquePointer?
        let r = archive_read_next_header(a, &entry)
        if r == ARCHIVE_EOF { return nil }
        if r != ARCHIVE_OK && r != ARCHIVE_WARN { throw .library(archiveMessage(a, "Cannot read archive header")) }
        return entry
    }

    func skip() throws(ArchiveError) {
        let r = archive_read_data_skip(a)
        if r != ARCHIVE_OK && r != ARCHIVE_WARN && r != ARCHIVE_EOF {
            throw .library(archiveMessage(a, "Cannot read archive"))
        }
    }

    /// Reads the next block of the current entry's data; 0 at its end.
    func read(into buffer: UnsafeMutableRawBufferPointer) throws(ArchiveError) -> Int {
        let n = archive_read_data(a, buffer.baseAddress, buffer.count)
        if n < 0 { throw .library(archiveMessage(a, "Cannot read archive data")) }
        return n
    }

    /// Error for a failed data read of the encrypted entry `path` after passphrases were given.
    /// libarchive tells only by its message ("Incorrect passphrase"); other failures (bad CRC,
    /// broken stream) also mean a wrong passphrase that slipped past the check bytes.
    static func passphraseError(for path: String, after error: ArchiveError) -> ArchiveError {
        guard case .library(let message) = error else { return error }
        let text = message.lowercased()
        if text.contains("not supported") || text.contains("unsupported") { return .encrypted(path) }
        return .wrongPassword(path)
    }

    /// Format of the open archive, from libarchive's detection (valid after the first `next()`).
    func detectedFormat() -> ArchiveFormat? {
        switch archive_format(a) & ARCHIVE_FORMAT_BASE_MASK {
        case ARCHIVE_FORMAT_ZIP: return .zip
        case ARCHIVE_FORMAT_7ZIP: return .sevenZip
        case ARCHIVE_FORMAT_RAR, ARCHIVE_FORMAT_RAR_V5: return .rar
        case ARCHIVE_FORMAT_TAR:
            var filters: [Int32] = []
            for i in 0..<archive_filter_count(a) {
                let code = archive_filter_code(a, i)
                if code != ARCHIVE_FILTER_NONE { filters.append(code) }
            }
            switch filters {
            case []: return .tar
            case [ARCHIVE_FILTER_GZIP]: return .tarGzip
            case [ARCHIVE_FILTER_BZIP2]: return .tarBzip2
            case [ARCHIVE_FILTER_XZ]: return .tarXz
            default: return nil
            }
        default: return nil
        }
    }
}

/// Owns an archive writer: an archive file, or the disk (extraction).
final class ArchiveWriteHandle {
    let a: OpaquePointer
    private var freed = false

    /// Writes entries to the file system; entry pathnames are the targets.
    init(diskFlags: Int32) throws(ArchiveError) {
        guard let a = archive_write_disk_new() else { throw .library("archive_write_disk_new failed") }
        self.a = a
        archive_write_disk_set_options(a, diskFlags)
    }

    init(path: String, format: ArchiveFormat) throws(ArchiveError) {
        guard let a = archive_write_new() else { throw .library("archive_write_new failed") }
        self.a = a
        var r: Int32
        switch format {
        case .zip:
            r = archive_write_set_format_zip(a)
            if r == ARCHIVE_OK { r = archive_write_set_options(a, "zip:hdrcharset=UTF-8") }
        case .sevenZip:
            r = archive_write_set_format_7zip(a)
        case .tar, .tarGzip, .tarBzip2, .tarXz:
            r = archive_write_set_format_pax_restricted(a)
            if r == ARCHIVE_OK {
                switch format {
                case .tarGzip: r = archive_write_add_filter_gzip(a)
                case .tarBzip2: r = archive_write_add_filter_bzip2(a)
                case .tarXz: r = archive_write_add_filter_xz(a)
                default: break
                }
            }
        case .rar:
            throw .readOnly
        }
        if r != ARCHIVE_OK && r != ARCHIVE_WARN { throw .library(archiveMessage(a, "Cannot set archive format")) }
        r = archive_write_open_filename(a, path)
        if r != ARCHIVE_OK && r != ARCHIVE_WARN { throw .library(archiveMessage(a, "Cannot create archive")) }
    }

    deinit { abandon() }

    /// Frees the handle without the caller relying on a complete result.
    func abandon() {
        guard !freed else { return }
        freed = true
        archive_write_free(a)
    }

    func header(_ entry: OpaquePointer) throws(ArchiveError) {
        let r = archive_write_header(a, entry)
        if r != ARCHIVE_OK && r != ARCHIVE_WARN { throw .library(archiveMessage(a, "Cannot write archive entry")) }
    }

    func write(_ bytes: UnsafeRawBufferPointer) throws(ArchiveError) {
        var offset = 0
        while offset < bytes.count {
            let n = archive_write_data(a, bytes.baseAddress! + offset, bytes.count - offset)
            if n <= 0 { throw .library(archiveMessage(a, "Cannot write archive data")) }
            offset += n
        }
    }

    func finishEntry() throws(ArchiveError) {
        let r = archive_write_finish_entry(a)
        if r != ARCHIVE_OK && r != ARCHIVE_WARN { throw .library(archiveMessage(a, "Cannot write archive entry")) }
    }

    /// Flushes everything; the archive is complete only after this succeeds.
    func close() throws(ArchiveError) {
        let r = archive_write_close(a)
        if r != ARCHIVE_OK && r != ARCHIVE_WARN { throw .library(archiveMessage(a, "Cannot finish archive")) }
    }
}

/// Owns an archive_entry.
final class ArchiveEntryHandle {
    let e: OpaquePointer

    init() { e = archive_entry_new() }
    init(cloning other: OpaquePointer) { e = archive_entry_clone(other) }
    deinit { archive_entry_free(e) }
}

/// Header fields of an entry as Swift values.
struct RawEntryInfo {
    var path: String
    var isDirectory: Bool
    var isSymlink: Bool
    var linkTarget: String?
    var hardlink: String?
    var size: Int64?
    var modificationDate: Date?
    var isEncrypted: Bool
    var perm: Int

    init(_ e: OpaquePointer) {
        let raw = Self.string(archive_entry_pathname_utf8(e)) ?? Self.string(archive_entry_pathname(e)) ?? ""
        let type = Int32(archive_entry_filetype(e)) & AE_IFMT
        isDirectory = type == AE_IFDIR || raw.hasSuffix("/")
        isSymlink = !isDirectory && type == AE_IFLNK
        path = raw
        linkTarget = isSymlink
            ? Self.string(archive_entry_symlink_utf8(e)) ?? Self.string(archive_entry_symlink(e))
            : nil
        hardlink = Self.string(archive_entry_hardlink_utf8(e)) ?? Self.string(archive_entry_hardlink(e))
        size = isDirectory || archive_entry_size_is_set(e) == 0 ? nil : archive_entry_size(e)
        modificationDate = archive_entry_mtime_is_set(e) != 0
            ? Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(e)) + TimeInterval(archive_entry_mtime_nsec(e)) / 1e9)
            : nil
        isEncrypted = archive_entry_is_encrypted(e) != 0
        perm = Int(archive_entry_perm(e)) & 0o7777
    }

    private static func string(_ p: UnsafePointer<CChar>?) -> String? {
        p.map { String(cString: $0) }
    }
}

/// Member path as the index shows it: "/"-separated, no leading "/" or "./", no trailing "/".
/// ".." components stay; extraction sanitizes them.
func normalizeMemberPath(_ raw: String) -> String {
    raw.split(separator: "/", omittingEmptySubsequences: true)
        .filter { $0 != "." }
        .joined(separator: "/")
}

/// True when `path` equals `prefix` or lies below it ("" contains everything).
func memberPath(_ path: String, isAtOrBelow prefix: String) -> Bool {
    if prefix.isEmpty { return true }
    guard path.hasPrefix(prefix) else { return false }
    return path.count == prefix.count || path[path.index(path.startIndex, offsetBy: prefix.count)] == "/"
}

/// Runs `body` with a UTF-8 C locale on this thread, so libarchive converts
/// names between UTF-8 and the "multibyte" form without loss.
func withUTF8Locale<T>(_ body: () throws -> T) rethrows -> T {
    guard let utf8 = newlocale(LC_CTYPE_MASK, "UTF-8", nil) else { return try body() }
    let previous = uselocale(utf8)
    defer {
        uselocale(previous)
        freelocale(utf8)
    }
    return try body()
}
