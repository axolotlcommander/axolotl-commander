// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
internal import CArchive
import Darwin

/// Dates of an archive entry as the disk takes them.
struct EntryTimes {
    var modified: timespec?
    var accessed: timespec?
    var created: timespec?

    init(_ e: OpaquePointer) {
        modified = archive_entry_mtime_is_set(e) != 0
            ? timespec(tv_sec: archive_entry_mtime(e), tv_nsec: archive_entry_mtime_nsec(e)) : nil
        accessed = archive_entry_atime_is_set(e) != 0
            ? timespec(tv_sec: archive_entry_atime(e), tv_nsec: archive_entry_atime_nsec(e)) : nil
        created = archive_entry_birthtime_is_set(e) != 0
            ? timespec(tv_sec: archive_entry_birthtime(e), tv_nsec: archive_entry_birthtime_nsec(e)) : nil
    }

    init(modified: timespec? = nil, accessed: timespec? = nil, created: timespec? = nil) {
        self.modified = modified
        self.accessed = accessed
        self.created = created
    }
}

/// Writes extracted entries below a root folder. It replaces libarchive's disk writer, whose
/// constructor sets the process umask to 0 for a moment, so files that other threads create
/// meanwhile get mode 0666/0777. Here modes go through `open`/`mkdir`, which apply the umask.
///
/// Paths are relative to the root and already sanitized (no "", "." or ".."). Every folder on
/// the way is opened with `O_NOFOLLOW`, so a symlink below the root (one the archive made, for
/// example) stops the entry instead of leading the write elsewhere. An existing item at the
/// target is replaced: a file or symlink is removed, an empty folder too.
final class DiskWriter {
    enum Kind {
        case directory(perm: Int)
        case file(perm: Int)
        case symlink(target: String)
        /// A hard link to an earlier entry, named by its path relative to the root.
        case hardlink(to: String)
    }

    private let rootFD: Int32
    /// The file being written: its folder, name and descriptor (opened late for a hard link).
    private var current: (parent: Int32, name: String, fd: Int32?, times: EntryTimes)?
    /// Folders made from entries; their dates are set at the end, after their contents.
    private var folderTimes: [(path: [String], times: EntryTimes)] = []

    init(root: String) throws(ArchiveError) {
        rootFD = open(root, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if rootFD < 0 { throw Self.failure("Cannot open", root) }
    }

    deinit {
        abandon()
        Darwin.close(rootFD)
    }

    /// Creates the item at `path`; a file then takes `write` calls until `finish`.
    func begin(_ path: String, kind: Kind, times: EntryTimes) throws(ArchiveError) {
        let parts = path.split(separator: "/").map(String.init)
        guard let name = parts.last else { throw .library("Empty path") }
        let parent = try openFolder(parts.dropLast(), creating: true, for: path)
        var keepParent = false
        defer { if !keepParent { Darwin.close(parent) } }

        var st = stat()
        let exists = fstatat(parent, name, &st, AT_SYMLINK_NOFOLLOW) == 0
        let existingIsDir = exists && (st.st_mode & S_IFMT) == S_IFDIR
        if exists {
            if case .directory = kind, existingIsDir {
                // Merged into as it is.
            } else if unlinkat(parent, name, existingIsDir ? AT_REMOVEDIR : 0) != 0 {
                throw Self.failure("Cannot replace", path)
            }
        }

        switch kind {
        case .directory(let perm):
            if !existingIsDir, mkdirat(parent, name, mode_t(perm)) != 0 { throw Self.failure("Cannot create folder", path) }
            folderTimes.append((parts, times))
        case .file(let perm):
            let fd = openat(parent, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(perm))
            if fd < 0 { throw Self.failure("Cannot create", path) }
            current = (parent, name, fd, times)
            keepParent = true
        case .symlink(let target):
            if symlinkat(target, parent, name) != 0 { throw Self.failure("Cannot create symbolic link", path) }
            Self.setTimes(times) { utimensat(parent, name, $0, AT_SYMLINK_NOFOLLOW) }
        case .hardlink(let linked):
            let linkedParts = linked.split(separator: "/").map(String.init)
            guard let linkedName = linkedParts.last else { throw .library("Empty path") }
            let source = try openFolder(linkedParts.dropLast(), creating: false, for: linked)
            defer { Darwin.close(source) }
            if linkat(source, linkedName, parent, name, 0) != 0 { throw Self.failure("Cannot create hard link", path) }
            current = (parent, name, nil, times)
            keepParent = true
        }
    }

    /// Appends data to the file begun last (for a hard link: replaces the shared data).
    func write(_ bytes: UnsafeRawBufferPointer) throws(ArchiveError) {
        guard var entry = current else { return }
        if entry.fd == nil {
            let fd = openat(entry.parent, entry.name, O_WRONLY | O_TRUNC | O_NOFOLLOW | O_CLOEXEC)
            if fd < 0 { throw Self.failure("Cannot write", entry.name) }
            entry.fd = fd
            current = entry
        }
        guard let fd = entry.fd else { return }
        var offset = 0
        while offset < bytes.count {
            let n = Darwin.write(fd, bytes.baseAddress! + offset, bytes.count - offset)
            if n < 0 {
                if errno == EINTR { continue }
                throw Self.failure("Cannot write", entry.name)
            }
            offset += n
        }
    }

    /// Finishes the current file: dates, then close.
    func finish() throws(ArchiveError) {
        guard let entry = current else { return }
        current = nil
        defer { Darwin.close(entry.parent) }
        if let fd = entry.fd {
            Self.setTimes(entry.times) { futimens(fd, $0) }
            if Darwin.close(fd) != 0 { throw Self.failure("Cannot write", entry.name) }
        } else {
            Self.setTimes(entry.times) { utimensat(entry.parent, entry.name, $0, AT_SYMLINK_NOFOLLOW) }
        }
    }

    /// Drops the current file, leaving nothing half-written behind.
    func abandon() {
        guard let entry = current else { return }
        current = nil
        if let fd = entry.fd {
            Darwin.close(fd)
            unlinkat(entry.parent, entry.name, 0)
        }
        Darwin.close(entry.parent)
    }

    /// Sets the dates of the folders made from entries, deepest first.
    func close() {
        for folder in folderTimes.sorted(by: { $0.path.count > $1.path.count }) {
            guard let name = folder.path.last,
                  let parent = try? openFolder(folder.path.dropLast(), creating: false, for: name) else { continue }
            Self.setTimes(folder.times) { utimensat(parent, name, $0, AT_SYMLINK_NOFOLLOW) }
            Darwin.close(parent)
        }
        folderTimes = []
    }

    /// Opens the folder `parts` below the root, never through a symlink; missing folders are
    /// created when `creating`.
    private func openFolder(_ parts: ArraySlice<String>, creating: Bool, for path: String) throws(ArchiveError) -> Int32 {
        var fd = dup(rootFD)
        if fd < 0 { throw Self.failure("Cannot open", path) }
        for part in parts {
            var next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if next < 0, errno == ENOENT, creating {
                if mkdirat(fd, part, 0o777) != 0, errno != EEXIST {
                    let failure = Self.failure("Cannot create folder", path)
                    Darwin.close(fd)
                    throw failure
                }
                next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            if next < 0 {
                // ELOOP: a symlink is in the way; ENOTDIR: a file.
                let failure = Self.failure("Cannot write into", path)
                Darwin.close(fd)
                throw failure
            }
            Darwin.close(fd)
            fd = next
        }
        return fd
    }

    /// Sets the modification (and access) date; a creation date is set first, as setting
    /// an earlier modification date moves the creation date back to it.
    private static func setTimes(_ times: EntryTimes, _ apply: (UnsafePointer<timespec>) -> Int32) {
        guard let modified = times.modified else { return }
        let accessed = times.accessed ?? timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT))
        if let created = times.created, created.tv_sec < modified.tv_sec
            || (created.tv_sec == modified.tv_sec && created.tv_nsec < modified.tv_nsec) {
            _ = [accessed, created].withUnsafeBufferPointer { apply($0.baseAddress!) }
        }
        _ = [accessed, modified].withUnsafeBufferPointer { apply($0.baseAddress!) }
    }

    private static func failure(_ action: String, _ path: String) -> ArchiveError {
        .library("\(action) “\(path)”: \(String(cString: strerror(errno)))")
    }
}
