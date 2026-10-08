// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin

/// Identity of a file system object: device + inode. Two paths name the same
/// object exactly when their identities are equal; the path text is irrelevant.
public struct FileIdentity: Hashable, Sendable {
    public let device: Int64
    public let inode: UInt64

    public init(device: Int64, inode: UInt64) {
        self.device = device
        self.inode = inode
    }

    /// nil when the path does not exist or its identity cannot be determined.
    /// Callers must treat nil on an existing path as "maybe the same file".
    public static func of(_ url: URL, followingLinks: Bool = true) -> FileIdentity? {
        if case .exists(let info) = FileProbe.probe(url.path, followingLinks: followingLinks) {
            return info.identity
        }
        return nil
    }
}

/// The subset of `stat` the operations need.
struct FileStat: Sendable {
    /// nil when the volume does not provide file ids.
    let identity: FileIdentity?
    let device: Int64
    let mode: mode_t
    let size: Int64
    let modificationDate: Date

    init(_ st: Darwin.stat) {
        device = Int64(st.st_dev)
        identity = st.st_ino == 0 ? nil : FileIdentity(device: Int64(st.st_dev), inode: UInt64(st.st_ino))
        mode = st.st_mode
        size = Int64(st.st_size)
        modificationDate = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)
            + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000)
    }

    var type: mode_t { mode & S_IFMT }
    var isDirectory: Bool { type == S_IFDIR }
    var isSymlink: Bool { type == S_IFLNK }
    var isRegular: Bool { type == S_IFREG }
}

/// Result of stat/lstat that distinguishes "does not exist" from "cannot tell".
enum FileProbe {
    case missing
    case unknown(Int32)
    case exists(FileStat)

    static func probe(_ path: String, followingLinks: Bool) -> FileProbe {
        var st = Darwin.stat()
        let rc = followingLinks ? stat(path, &st) : lstat(path, &st)
        if rc == 0 { return .exists(FileStat(st)) }
        let err = errno
        if err == ENOENT || err == ENOTDIR { return .missing }
        return .unknown(err)
    }
}

/// String path helpers that never touch the file system.
enum FSPath {
    static func join(_ dir: String, _ name: String) -> String {
        dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }

    static func parent(_ path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    static func name(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    static func errorText(_ code: Int32, _ what: String, _ path: String) -> String {
        "\(what) \(path): \(String(cString: strerror(code)))"
    }
}
