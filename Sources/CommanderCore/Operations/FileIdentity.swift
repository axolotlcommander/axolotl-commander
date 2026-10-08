// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin

/// Identity of a file system object: device + inode. Two paths name the same
/// object exactly when their identities are equal; the path text is irrelevant.
///
/// Valid only while the volume stays mounted (`st_dev` changes across mounts) and only
/// on volumes whose file ids are real (see `VolumeTraits.identityReliable`). Never store
/// it across launches; use `PersistentFileStamp` for that.
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
    /// Number of hard links (`st_nlink`).
    let linkCount: Int

    init(_ st: Darwin.stat) {
        device = Int64(st.st_dev)
        linkCount = Int(st.st_nlink)
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

/// What a volume promises about its file ids.
public struct VolumeTraits: Sendable, Equatable {
    /// True when (`st_dev`, `st_ino`) reliably names one object: equal ids mean the same
    /// file and different ids mean different files. Only APFS and HFS+ are trusted; FAT,
    /// exFAT, NTFS, network and FUSE file systems may synthesize or reuse ids.
    public var identityReliable: Bool
    /// Volume UUID, stable across mounts when the file system has one.
    public var uuid: String?

    public init(identityReliable: Bool, uuid: String?) {
        self.identityReliable = identityReliable
        self.uuid = uuid
    }

    static let reliableTypes: Set<String> = ["apfs", "hfs"]

    /// Traits of the volume holding `url` (the nearest existing ancestor when `url` does
    /// not exist yet). Unknown volumes are unreliable.
    public static func of(_ url: URL) -> VolumeTraits {
        var path = url.path
        var fs = statfs()
        while statfs(path, &fs) != 0 {
            let parent = FSPath.parent(path)
            if parent == path || parent.isEmpty { return VolumeTraits(identityReliable: false, uuid: nil) }
            path = parent
        }
        let type = withUnsafeBytes(of: fs.f_fstypename) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let uuid = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
        return VolumeTraits(identityReliable: reliableTypes.contains(type), uuid: uuid)
    }
}

/// A file's state that can be stored across launches and remounts: volume UUID + file id
/// + size + modification time. Equal stamps mean "the file has not changed since".
public struct PersistentFileStamp: Codable, Sendable, Equatable {
    public var volumeUUID: String?
    public var fileID: UInt64
    public var size: Int64
    /// Modification time in nanoseconds since 1970.
    public var modified: Int64

    public init(volumeUUID: String?, fileID: UInt64, size: Int64, modified: Int64) {
        self.volumeUUID = volumeUUID
        self.fileID = fileID
        self.size = size
        self.modified = modified
    }

    /// nil when the file does not exist or cannot be examined. Follows symlinks.
    public init?(_ url: URL) {
        var st = Darwin.stat()
        guard stat(url.path, &st) == 0 else { return nil }
        volumeUUID = (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
        fileID = UInt64(st.st_ino)
        size = Int64(st.st_size)
        modified = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
    }
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
