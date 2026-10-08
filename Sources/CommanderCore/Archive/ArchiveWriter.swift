// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
internal import CArchive
import Darwin

/// Creates archives and rewrites existing ones (add, remove, rename members).
public enum ArchiveWriter {
    public struct Source: Hashable, Sendable {
        /// Local file or directory; directories are added recursively, symlinks stored as symlinks.
        public var file: URL
        /// Member path to store it under, e.g. "dir/name".
        public var path: String

        public init(file: URL, path: String) {
            self.file = file
            self.path = path
        }
    }

    /// Creates a new archive; fails with `alreadyExists` if `archive` exists.
    /// Written to a temporary file next to it, then moved into place.
    @concurrent
    public static func create(
        _ archive: URL,
        format: ArchiveFormat,
        adding: [Source],
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try withUTF8Locale {
            try createArchive(archive, format: format, adding: adding, progress: progress)
        }
    }

    /// Rewrites an existing archive: copies every old entry except those at/below `removing`
    /// and those whose (renamed) path equals a path being added, renames path prefixes per
    /// `renaming` [old: new], then appends `adding`. The original is replaced only after
    /// a complete write and is left untouched on any error or cancellation.
    @concurrent
    public static func update(
        _ archive: URL,
        removing: Set<String> = [],
        renaming: [String: String] = [:],
        adding: [Source] = [],
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try withUTF8Locale {
            try updateArchive(archive, removing: removing, renaming: renaming, adding: adding, progress: progress)
        }
    }

    // MARK: - Implementation

    private static func createArchive(
        _ archive: URL,
        format: ArchiveFormat,
        adding: [Source],
        progress: @escaping (Int64) -> Void
    ) throws {
        guard format.isWritable else { throw ArchiveError.readOnly }
        let target = archive.standardizedFileURL.path
        var st = stat()
        guard lstat(target, &st) != 0 else { throw ArchiveError.alreadyExists(target) }
        let items = try expand(adding)
        let temp = temporaryPath(for: target)
        do {
            let writer = try ArchiveWriteHandle(path: temp, format: format)
            let copier = Copier(progress: progress)
            for item in items { try copier.write(item, to: writer, format: format) }
            try writer.close()
            if renamex_np(temp, target, UInt32(RENAME_EXCL)) != 0 {
                throw errno == EEXIST ? ArchiveError.alreadyExists(target) : ArchiveError.library(posixMessage())
            }
        } catch {
            unlink(temp)
            throw error
        }
    }

    private static func updateArchive(
        _ archive: URL,
        removing: Set<String>,
        renaming: [String: String],
        adding: [Source],
        progress: @escaping (Int64) -> Void
    ) throws {
        guard let named = ArchiveFormat.detect(fileName: archive.lastPathComponent) else {
            throw ArchiveError.unsupportedFormat
        }
        guard named.isWritable else { throw ArchiveError.readOnly }
        guard let resolved = realpath(archive.path, nil) else { throw ArchiveError.notFound(archive.path) }
        let target = String(cString: resolved)
        free(resolved)
        var original = stat()
        guard stat(target, &original) == 0 else { throw ArchiveError.notFound(archive.path) }

        let items = try expand(adding)
        let added = Set(items.map(\.member))
        let removing = Set(removing.map(normalizeMemberPath))
        var renames: [String: String] = [:]
        for (old, new) in renaming { renames[normalizeMemberPath(old)] = normalizeMemberPath(new) }
        // Longest prefix first, so nested renames win over their parents.
        let renameKeys = renames.keys.sorted { $0.count > $1.count }
        var removeHits: Set<String> = []
        var renameHits: Set<String> = []

        func renamed(_ path: String) -> String {
            guard let key = renameKeys.first(where: { memberPath(path, isAtOrBelow: $0) }) else { return path }
            renameHits.insert(key)
            return normalizeMemberPath(renames[key]! + "/" + path.dropFirst(key.count))
        }

        let reader = try ArchiveReadHandle(path: target)
        var current = try reader.next()
        let format = reader.detectedFormat() ?? named
        guard format.isWritable else { throw ArchiveError.readOnly }

        let temp = temporaryPath(for: target)
        do {
            let writer = try ArchiveWriteHandle(path: temp, format: format)
            let copier = Copier(progress: progress)
            while let e = current {
                if Task.isCancelled { throw ArchiveError.cancelled }
                let info = RawEntryInfo(e)
                let path = normalizeMemberPath(info.path)
                if let hit = removing.first(where: { memberPath(path, isAtOrBelow: $0) }) {
                    removeHits.insert(hit)
                    try reader.skip()
                    current = try reader.next()
                    continue
                }
                let newPath = renamed(path)
                if added.contains(newPath) || (newPath.isEmpty && !path.isEmpty) {
                    try reader.skip()
                    current = try reader.next()
                    continue
                }
                if info.isEncrypted { throw ArchiveError.readOnly }

                let entry = ArchiveEntryHandle(cloning: e)
                if newPath != path {
                    archive_entry_set_pathname_utf8(entry.e, memberName(newPath, isDirectory: info.isDirectory, format: format))
                }
                if let link = info.hardlink {
                    let old = normalizeMemberPath(link)
                    let new = renamed(old)
                    if new != old { archive_entry_set_hardlink_utf8(entry.e, new) }
                }
                try writer.header(entry.e)
                if !info.isDirectory && !info.isSymlink {
                    try copier.copyData(from: reader, to: writer)
                }
                try writer.finishEntry()
                current = try reader.next()
            }
            if let missing = removing.subtracting(removeHits).sorted().first { throw ArchiveError.notFound(missing) }
            if let missing = Set(renames.keys).subtracting(renameHits).sorted().first { throw ArchiveError.notFound(missing) }
            for item in items { try copier.write(item, to: writer, format: format) }
            try writer.close()
            if chmod(temp, original.st_mode & 0o7777) != 0 || rename(temp, target) != 0 {
                throw ArchiveError.library(posixMessage())
            }
        } catch {
            unlink(temp)
            throw error
        }
    }

    /// Hidden temporary file in the same directory as `path`.
    private static func temporaryPath(for path: String) -> String {
        let url = URL(filePath: path)
        return url.deletingLastPathComponent().path + "/.\(url.lastPathComponent).axolotl-\(UUID().uuidString).tmp"
    }

    /// Zip marks directory entries with a trailing "/".
    fileprivate static func memberName(_ path: String, isDirectory: Bool, format: ArchiveFormat) -> String {
        isDirectory && format == .zip ? path + "/" : path
    }

    // MARK: - Local sources

    fileprivate enum Kind { case directory, file, symlink }

    fileprivate struct Item {
        var file: String
        var member: String
        var kind: Kind
        var size: Int64
        var modified: timespec
        var perm: mode_t
        var uid: uid_t
        var gid: gid_t
        var linkTarget: String?
    }

    /// Walks the sources (directories recursively, symlinks not followed).
    private static func expand(_ sources: [Source]) throws -> [Item] {
        var items: [Item] = []
        func visit(_ file: String, _ member: String) throws {
            if Task.isCancelled { throw ArchiveError.cancelled }
            var st = stat()
            guard lstat(file, &st) == 0 else { throw ArchiveError.notFound(file) }
            var item = Item(
                file: file, member: member, kind: .file, size: 0,
                modified: st.st_mtimespec, perm: st.st_mode & 0o777, uid: st.st_uid, gid: st.st_gid, linkTarget: nil
            )
            switch st.st_mode & S_IFMT {
            case S_IFDIR:
                item.kind = .directory
                items.append(item)
                let names = try FileManager.default.contentsOfDirectory(atPath: file).sorted()
                for name in names { try visit(file + "/" + name, member + "/" + name) }
            case S_IFLNK:
                var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
                let n = readlink(file, &buffer, Int(PATH_MAX))
                guard n >= 0 else { throw ArchiveError.library(posixMessage(file)) }
                item.kind = .symlink
                item.linkTarget = String(decoding: buffer[..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self)
                items.append(item)
            case S_IFREG:
                item.size = Int64(st.st_size)
                items.append(item)
            default:
                break // fifos, sockets, devices are not archived
            }
        }
        for source in sources {
            let member = normalizeMemberPath(source.path)
            guard !member.isEmpty else { throw ArchiveError.notFound(source.path) }
            try visit(source.file.standardizedFileURL.path, member)
        }
        return items
    }

    /// Streams entry data and reports cumulative progress.
    fileprivate final class Copier {
        let progress: (Int64) -> Void
        var total: Int64 = 0
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 64 * 1024, alignment: 16)
        private var userNames: [uid_t: String?] = [:]
        private var groupNames: [gid_t: String?] = [:]

        init(progress: @escaping (Int64) -> Void) {
            self.progress = progress
        }

        deinit { buffer.deallocate() }

        func copyData(from reader: ArchiveReadHandle, to writer: ArchiveWriteHandle) throws {
            while true {
                if Task.isCancelled { throw ArchiveError.cancelled }
                let n = try reader.read(into: buffer)
                if n == 0 { return }
                try writer.write(UnsafeRawBufferPointer(rebasing: buffer[..<n]))
                advance(n)
            }
        }

        func write(_ item: Item, to writer: ArchiveWriteHandle, format: ArchiveFormat) throws {
            if Task.isCancelled { throw ArchiveError.cancelled }
            let entry = ArchiveEntryHandle()
            let e = entry.e
            archive_entry_set_pathname_utf8(e, ArchiveWriter.memberName(item.member, isDirectory: item.kind == .directory, format: format))
            archive_entry_set_mtime(e, item.modified.tv_sec, item.modified.tv_nsec)
            archive_entry_set_perm(e, item.perm)
            // Owner of the source file, so tar listings show the real user, not root.
            archive_entry_set_uid(e, Int64(item.uid))
            archive_entry_set_gid(e, Int64(item.gid))
            if let name = userName(item.uid) { archive_entry_set_uname_utf8(e, name) }
            if let name = groupName(item.gid) { archive_entry_set_gname_utf8(e, name) }
            switch item.kind {
            case .directory:
                archive_entry_set_filetype(e, UInt32(AE_IFDIR))
                try writer.header(e)
            case .symlink:
                archive_entry_set_filetype(e, UInt32(AE_IFLNK))
                archive_entry_set_symlink_utf8(e, item.linkTarget ?? "")
                archive_entry_set_size(e, 0)
                try writer.header(e)
            case .file:
                let fd = open(item.file, O_RDONLY)
                guard fd >= 0 else { throw ArchiveError.library(posixMessage(item.file)) }
                defer { close(fd) }
                archive_entry_set_filetype(e, UInt32(AE_IFREG))
                archive_entry_set_size(e, item.size)
                try writer.header(e)
                var remaining = item.size
                while remaining > 0 {
                    if Task.isCancelled { throw ArchiveError.cancelled }
                    let n = Darwin.read(fd, buffer.baseAddress, min(buffer.count, Int(remaining)))
                    if n < 0 { throw ArchiveError.library(posixMessage(item.file)) }
                    if n == 0 { break }
                    try writer.write(UnsafeRawBufferPointer(rebasing: buffer[..<n]))
                    remaining -= Int64(n)
                    advance(n)
                }
            }
            try writer.finishEntry()
        }

        private func userName(_ uid: uid_t) -> String? {
            if let cached = userNames[uid] { return cached }
            var record = passwd()
            var result: UnsafeMutablePointer<passwd>?
            var storage = [CChar](repeating: 0, count: 4096)
            let name = getpwuid_r(uid, &record, &storage, storage.count, &result) == 0 && result != nil
                ? String(cString: record.pw_name) : nil
            userNames[uid] = name
            return name
        }

        private func groupName(_ gid: gid_t) -> String? {
            if let cached = groupNames[gid] { return cached }
            var record = group()
            var result: UnsafeMutablePointer<group>?
            var storage = [CChar](repeating: 0, count: 4096)
            let name = getgrgid_r(gid, &record, &storage, storage.count, &result) == 0 && result != nil
                ? String(cString: record.gr_name) : nil
            groupNames[gid] = name
            return name
        }

        private func advance(_ n: Int) {
            total += Int64(n)
            progress(total)
        }
    }
}

private func posixMessage(_ path: String? = nil) -> String {
    let message = String(cString: strerror(errno))
    return path.map { "\($0): \(message)" } ?? message
}
