public import Foundation
internal import CArchive
import Darwin

public struct ExtractReport: Sendable, Equatable {
    /// Files, directories and symlinks written (nested ones included).
    public var written: [URL] = []
    /// Member paths left alone because the target already existed.
    public var skipped: [String] = []

    public init(written: [URL] = [], skipped: [String] = []) {
        self.written = written
        self.skipped = skipped
    }
}

public enum ArchiveExtractor {
    /// Makes a member path safe to write below a target folder: drops "", ".", "..",
    /// a leading drive letter ("C:"); splits on "/" and "\". nil when nothing remains.
    public static func sanitize(_ memberPath: String) -> String? {
        var parts = memberPath.split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .filter { $0 != "." && $0 != ".." }
        if let first = parts.first, first.count == 2, first.last == ":", first.first?.isASCII == true,
           first.first?.isLetter == true {
            parts.removeFirst()
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    /// Extracts `members` (directories recursively; "" means everything) into the existing
    /// directory `destination`, stripping the `base` folder prefix from member paths.
    /// Existing files are replaced only when `overwrite` is true, otherwise reported as skipped.
    /// `progress` gets cumulative bytes written, from any thread.
    @concurrent
    public static func extract(
        archive: URL,
        members: [String],
        base: String,
        to destination: URL,
        overwrite: Bool,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> ExtractReport {
        try withUTF8Locale {
            try run(archive: archive, members: members, base: base, to: destination, overwrite: overwrite, progress: progress)
        }
    }

    private static func run(
        archive: URL,
        members: [String],
        base: String,
        to destination: URL,
        overwrite: Bool,
        progress: (Int64) -> Void
    ) throws -> ExtractReport {
        // libarchive checks every component of the absolute target for symlinks,
        // so the destination itself must be symlink-free.
        guard let resolved = realpath(destination.path, nil) else { throw ArchiveError.notFound(destination.path) }
        let root = String(cString: resolved)
        free(resolved)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            throw ArchiveError.notFound(destination.path)
        }

        let base = normalizeMemberPath(base)
        let members = members.map(normalizeMemberPath)
        let reader = try ArchiveReadHandle(path: archive.path)
        let disk = try ArchiveWriteHandle(
            diskFlags: ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_SECURE_SYMLINKS | ARCHIVE_EXTRACT_SECURE_NODOTDOT
        )
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 64 * 1024, alignment: 16)
        defer { buffer.deallocate() }

        var report = ExtractReport()
        var writtenTargets: Set<String> = []
        var total: Int64 = 0
        var count = 0

        func targetPath(for memberPath: String) -> String? {
            var relative = memberPath
            if !base.isEmpty, memberPath.hasPrefix(base + "/") {
                relative = String(memberPath.dropFirst(base.count + 1))
            }
            return sanitize(relative).map { root + "/" + $0 }
        }

        while let e = try reader.next() {
            count += 1
            if count % 256 == 0, Task.isCancelled { throw ArchiveError.cancelled }
            let info = RawEntryInfo(e)
            let path = normalizeMemberPath(info.path)
            guard !path.isEmpty, members.contains(where: { memberPath(path, isAtOrBelow: $0) }),
                  let target = targetPath(for: path)
            else {
                try reader.skip()
                continue
            }
            if info.isEncrypted { throw ArchiveError.encrypted(path) }

            var st = stat()
            if lstat(target, &st) == 0, !writtenTargets.contains(target) {
                // An existing folder is merged into, without touching it.
                let existingIsDir = (st.st_mode & S_IFMT) == S_IFDIR
                if info.isDirectory && existingIsDir {
                    try reader.skip()
                    continue
                }
                if !overwrite {
                    report.skipped.append(path)
                    try reader.skip()
                    continue
                }
            }

            let entry = ArchiveEntryHandle(cloning: e)
            archive_entry_set_pathname_utf8(entry.e, target)
            if let link = info.hardlink {
                guard let linkTarget = targetPath(for: normalizeMemberPath(link)), writtenTargets.contains(linkTarget) else {
                    report.skipped.append(path)
                    try reader.skip()
                    continue
                }
                archive_entry_set_hardlink_utf8(entry.e, linkTarget)
            }
            let perm = info.perm & 0o777
            if info.isDirectory {
                archive_entry_set_perm(entry.e, mode_t(perm == 0 ? 0o755 : perm | 0o700))
            } else if !info.isSymlink {
                archive_entry_set_perm(entry.e, mode_t(perm == 0 ? 0o644 : perm | 0o600))
            }

            try disk.header(entry.e)
            writtenTargets.insert(target)
            report.written.append(URL(filePath: target, directoryHint: info.isDirectory ? .isDirectory : .notDirectory))

            if !info.isDirectory && !info.isSymlink {
                do {
                    while true {
                        if Task.isCancelled { throw ArchiveError.cancelled }
                        let n = try reader.read(into: buffer)
                        if n == 0 { break }
                        try disk.write(UnsafeRawBufferPointer(rebasing: buffer[..<n]))
                        total += Int64(n)
                        progress(total)
                    }
                } catch {
                    // Leave no half-written file behind.
                    disk.abandon()
                    unlink(target)
                    throw error
                }
            }
            try disk.finishEntry()
        }
        try disk.close()
        return report
    }
}
