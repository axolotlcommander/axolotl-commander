// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin

/// Mount points of the mounted file systems, used to keep verification on one volume.
public struct MountTable: Sendable {
    public var mountPoints: [String]

    public init(mountPoints: [String]) {
        self.mountPoints = mountPoints
    }

    /// Mounted file systems now. Uses MNT_NOWAIT, which only reads the kernel's cached
    /// table and never blocks on (or contacts) network file systems. Empty on failure.
    public static func current() -> MountTable {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo_r_np(&buffer, MNT_NOWAIT)
        defer { free(buffer) }
        guard count > 0, let buffer else { return MountTable(mountPoints: []) }
        var points: [String] = []
        for i in 0..<Int(count) {
            var fs = buffer[i]
            let name = withUnsafeBytes(of: &fs.f_mntonname) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
            if !name.isEmpty { points.append(name) }
        }
        return MountTable(mountPoints: points)
    }

    /// The longest mount point that is a component-wise prefix of the lexically normalized
    /// absolute `path` ("/" matches everything). Matching ignores case and Unicode normalization,
    /// so a path that may reach another volume on a case-insensitive file system is attributed to it.
    /// "/" when nothing matches.
    public func mountPoint(for path: String) -> String {
        let key = Self.key(PathLexical.normalize(path))
        var best = "/"
        var bestLength = -1
        for point in mountPoints {
            let normalized = PathLexical.normalize(point)
            let pointKey = Self.key(normalized)
            let matches = pointKey == "/" || key == pointKey || key.hasPrefix(pointKey + "/")
            if matches, pointKey.count > bestLength {
                best = normalized
                bestLength = pointKey.count
            }
        }
        return best
    }

    private static func key(_ path: String) -> String {
        NameRules.apfsDefault.key(path)
    }
}

public enum VerifyStatus: Sendable, Equatable {
    case ok
    case mismatch(actual: String)
    /// Missing, or refused because it leads outside the list's volume.
    case missing
    case unreadable(String)
}

public struct VerifyResult: Sendable, Equatable {
    public var entry: ChecksumList.Entry
    public var status: VerifyStatus

    public init(entry: ChecksumList.Entry, status: VerifyStatus) {
        self.entry = entry
        self.status = status
    }
}

extension Checksums {
    static let maxSymlinks = 32

    /// Resolves a list path to a regular file on the volume of `listDirectory`, or nil.
    ///
    /// Security rule: a path that leads to another volume, device or server is never opened or
    /// stat'ed. Rejected without any file system access: control characters, U+FFFD, Windows drive
    /// paths (`C:`), UNC paths (`\\server`, `//server`), and paths whose lexically normalized form lies
    /// on another mount point. The remaining path is walked component by component from the volume's
    /// mount point; each prefix is checked lexically before `lstat`, symlinks are expanded with
    /// `readlink` and re-checked (at most 32). The result must be a regular file with the
    /// list directory's `st_dev`.
    public static func resolve(_ listPath: String, listDirectory: URL, mounts: MountTable) -> URL? {
        guard !mounts.mountPoints.isEmpty, isAcceptableListPath(listPath) else { return nil }
        let directory = PathLexical.normalize(listDirectory.path)
        let volume = mounts.mountPoint(for: directory)
        var path = PathLexical.normalize(listPath.hasPrefix("/") ? listPath : directory + "/" + listPath)
        guard mounts.mountPoint(for: path) == volume else { return nil }

        var directoryStat = stat()
        guard stat(directory, &directoryStat) == 0 else { return nil }
        let device = directoryStat.st_dev
        let volumeDepth = PathLexical.components(volume).count
        var links = 0

        walk: while true {
            let parts = PathLexical.components(path)
            guard parts.count > volumeDepth else { return nil }
            var current = volume
            for i in volumeDepth..<parts.count {
                let next = current == "/" ? "/" + parts[i] : current + "/" + parts[i]
                guard mounts.mountPoint(for: next) == volume else { return nil }
                var st = stat()
                guard lstat(next, &st) == 0 else { return nil }
                let isLast = i == parts.count - 1
                switch st.st_mode & S_IFMT {
                case S_IFLNK:
                    links += 1
                    guard links <= maxSymlinks, let target = readLink(next), !target.isEmpty else { return nil }
                    let base = target.hasPrefix("/") ? target : current + "/" + target
                    let rest = parts[(i + 1)...].joined(separator: "/")
                    path = PathLexical.normalize(rest.isEmpty ? base : base + "/" + rest)
                    guard mounts.mountPoint(for: path) == volume else { return nil }
                    continue walk
                case S_IFDIR where !isLast:
                    guard st.st_dev == device else { return nil }
                case S_IFREG where isLast:
                    guard st.st_dev == device else { return nil }
                    return URL(fileURLWithPath: next)
                default:
                    return nil
                }
                current = next
            }
            return nil
        }
    }

    /// Verifies every entry (case-insensitive digest compare). Entries that `resolve` refuses are
    /// `.missing` and never accessed. Throws `CancellationError` when the task is cancelled.
    public static func verify(
        _ list: ChecksumList,
        listDirectory: URL,
        mounts: MountTable = .current(),
        progress: @Sendable (_ done: Int, _ total: Int) -> Void = { _, _ in }
    ) async throws -> [VerifyResult] {
        var directoryStat = stat()
        let directoryDevice: dev_t? = stat(listDirectory.path, &directoryStat) == 0 ? directoryStat.st_dev : nil
        let total = list.entries.count
        var results: [VerifyResult] = []
        results.reserveCapacity(total)
        progress(0, total)
        for (index, entry) in list.entries.enumerated() {
            try Task.checkCancellation()
            let status: VerifyStatus
            if let device = directoryDevice,
               let url = resolve(entry.path, listDirectory: listDirectory, mounts: mounts) {
                do {
                    let digests = try digests(
                        of: url, algorithms: [list.algorithm], progress: { _ in }, expectedDevice: device
                    )
                    let actual = digests[list.algorithm] ?? ""
                    status = actual.lowercased() == entry.digest.lowercased() ? .ok : .mismatch(actual: actual)
                } catch is CancellationError {
                    throw CancellationError()
                } catch ChecksumError.cannotRead(let message) {
                    status = .unreadable(message)
                } catch {
                    status = .missing
                }
            } else {
                status = .missing
            }
            results.append(VerifyResult(entry: entry, status: status))
            progress(index + 1, total)
        }
        return results
    }

    /// No control characters, U+FFFD, Windows drive or UNC forms.
    static func isAcceptableListPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        for scalar in path.unicodeScalars {
            if scalar.value < 0x20 || scalar.value == 0x7F || scalar == "\u{FFFD}" { return false }
        }
        let scalars = Array(path.unicodeScalars.prefix(2))
        if scalars.count == 2, scalars[1] == ":", scalars[0].isASCII, scalars[0].properties.isAlphabetic {
            return false
        }
        if path.hasPrefix("//") || path.hasPrefix("\\\\") || path.hasPrefix("/\\") || path.hasPrefix("\\/") {
            return false
        }
        return true
    }

    private static func readLink(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let n = readlink(path, &buffer, buffer.count - 1)
        guard n > 0 else { return nil }
        return String(decoding: buffer[0..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
