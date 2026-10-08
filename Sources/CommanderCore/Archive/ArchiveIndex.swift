// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation

/// One member of an archive as the panels show it.
public struct ArchiveEntry: Hashable, Sendable {
    /// Normalized member path: "/"-separated, no leading "./" or "/", no trailing "/".
    public var path: String
    public var name: String
    public var isDirectory: Bool
    public var isSymlink: Bool
    public var linkTarget: String?
    /// nil for directories.
    public var size: Int64?
    public var modificationDate: Date?
    public var isEncrypted: Bool
    /// Directory synthesized because members exist below it but the archive has no entry for it.
    public var isImplicit: Bool

    public init(
        path: String,
        isDirectory: Bool,
        isSymlink: Bool = false,
        linkTarget: String? = nil,
        size: Int64? = nil,
        modificationDate: Date? = nil,
        isEncrypted: Bool = false,
        isImplicit: Bool = false
    ) {
        self.path = path
        name = path.split(separator: "/").last.map(String.init) ?? path
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.linkTarget = linkTarget
        self.size = isDirectory ? nil : size
        self.modificationDate = modificationDate
        self.isEncrypted = isEncrypted
        self.isImplicit = isImplicit
    }
}

/// The member list of an archive with folder lookups.
public struct ArchiveIndex: Sendable {
    public let format: ArchiveFormat
    /// One entry per path, implicit directories included; a path stored twice keeps the last one.
    public let entries: [ArchiveEntry]
    public let hasEncryptedEntries: Bool
    private let byPath: [String: Int]
    private let childrenByParent: [String: [Int]]

    /// Builds the index from entries in archive order (paths already normalized).
    public init(format: ArchiveFormat, entries raw: [ArchiveEntry]) {
        var entries: [ArchiveEntry] = []
        var byPath: [String: Int] = [:]
        for entry in raw where !entry.path.isEmpty {
            var parent = Substring(entry.path)
            while let slash = parent.lastIndex(of: "/") {
                parent = parent[..<slash]
                let dir = String(parent)
                if byPath[dir] != nil { continue }
                byPath[dir] = entries.count
                entries.append(ArchiveEntry(path: dir, isDirectory: true, isImplicit: true))
            }
            if let existing = byPath[entry.path] {
                entries[existing] = entry
            } else {
                byPath[entry.path] = entries.count
                entries.append(entry)
            }
        }
        var children: [String: [Int]] = [:]
        for (i, entry) in entries.enumerated() {
            let parent = entry.path.lastIndex(of: "/").map { String(entry.path[..<$0]) } ?? ""
            children[parent, default: []].append(i)
        }
        self.format = format
        self.entries = entries
        self.byPath = byPath
        childrenByParent = children
        hasEncryptedEntries = entries.contains { $0.isEncrypted }
    }

    /// Direct children of a folder; [] for an unknown one.
    public func children(of inner: String) -> [ArchiveEntry] {
        (childrenByParent[inner] ?? []).map { entries[$0] }
    }

    /// "" (the root) always exists.
    public func contains(directory inner: String) -> Bool {
        inner.isEmpty || byPath[inner].map { entries[$0].isDirectory } == true
    }

    public func entry(at path: String) -> ArchiveEntry? {
        byPath[path].map { entries[$0] }
    }

    /// Every entry at or below each of `paths` (directories recursive), deduplicated, in archive order.
    public func entries(under paths: [String]) -> [ArchiveEntry] {
        entries.filter { entry in paths.contains { memberPath(entry.path, isAtOrBelow: $0) } }
    }

    /// Total uncompressed size of the files in `entries(under:)`.
    public func totalSize(under paths: [String]) -> Int64 {
        entries(under: paths).reduce(0) { $0 + ($1.isDirectory ? 0 : $1.size ?? 0) }
    }

    /// Reads the member list without decompressing data where the format allows it.
    static func read(_ archive: URL, format: ArchiveFormat) throws -> ArchiveIndex {
        try withUTF8Locale {
            let reader = try ArchiveReadHandle(path: archive.path)
            var raw: [ArchiveEntry] = []
            var count = 0
            while let e = try reader.next() {
                count += 1
                if count % 256 == 0 { try Task.checkCancellation() }
                let info = RawEntryInfo(e)
                let path = normalizeMemberPath(info.path)
                if !path.isEmpty {
                    raw.append(ArchiveEntry(
                        path: path,
                        isDirectory: info.isDirectory,
                        isSymlink: info.isSymlink,
                        linkTarget: info.linkTarget,
                        size: info.size,
                        modificationDate: info.modificationDate,
                        isEncrypted: info.isEncrypted
                    ))
                }
                try reader.skip()
            }
            return ArchiveIndex(format: reader.detectedFormat() ?? format, entries: raw)
        }
    }
}

/// Reads and caches archive indexes; a cached index is reused while the
/// archive's size and modification date are unchanged.
public actor ArchiveCatalog {
    public static let shared = ArchiveCatalog()

    private struct Stamp: Equatable {
        var size: Int64
        var modified: timespec

        static func == (a: Stamp, b: Stamp) -> Bool {
            a.size == b.size && a.modified.tv_sec == b.modified.tv_sec && a.modified.tv_nsec == b.modified.tv_nsec
        }
    }

    private var cache: [String: (stamp: Stamp, index: ArchiveIndex)] = [:]

    public init() {}

    public func index(of archive: URL) async throws -> ArchiveIndex {
        let key = archive.standardizedFileURL.path
        guard let format = ArchiveFormat.detect(fileName: archive.lastPathComponent) else {
            throw ArchiveError.unsupportedFormat
        }
        let stamp = try Self.stamp(key)
        if let cached = cache[key], cached.stamp == stamp { return cached.index }
        let index = try await Self.readIndex(URL(filePath: key), format: format)
        // Keep it only if the file did not change while it was read.
        if (try? Self.stamp(key)) == stamp { cache[key] = (stamp, index) }
        return index
    }

    public func invalidate(_ archive: URL) {
        cache[archive.standardizedFileURL.path] = nil
    }

    /// Lists `path.inner` as panel items; throws `notFound` when the folder is not in the archive.
    public func list(_ path: ArchivePath, includeHidden: Bool) async throws -> [FileItem] {
        let index = try await index(of: path.archive)
        guard index.contains(directory: path.inner) else { throw ArchiveError.notFound(path.inner) }
        let base = path.url
        return index.children(of: path.inner).compactMap { entry in
            // "../x" stays in the index for extraction (as "x") but has no folder to show.
            if entry.name == ".." || entry.name == "." { return nil }
            let hidden = entry.name.hasPrefix(".")
            if hidden && !includeHidden { return nil }
            return FileItem(
                url: base.appending(path: entry.name, directoryHint: entry.isDirectory ? .isDirectory : .notDirectory),
                name: entry.name,
                isDirectory: entry.isDirectory,
                isSymlink: entry.isSymlink,
                isPackage: false,
                isHidden: hidden,
                size: entry.size,
                modificationDate: entry.modificationDate
            )
        }
    }

    @concurrent
    private static func readIndex(_ archive: URL, format: ArchiveFormat) async throws -> ArchiveIndex {
        try ArchiveIndex.read(archive, format: format)
    }

    private static func stamp(_ path: String) throws -> Stamp {
        var st = stat()
        guard stat(path, &st) == 0 else { throw ArchiveError.notFound(path) }
        return Stamp(size: Int64(st.st_size), modified: st.st_mtimespec)
    }
}
