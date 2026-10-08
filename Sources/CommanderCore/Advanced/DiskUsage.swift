// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin

/// One folder or file in a disk usage tree. Built by `DiskUsage.scan`.
public struct DiskUsageNode: Sendable, Identifiable {
    /// Unique within one scan.
    public var id: Int
    public var name: String
    public var url: URL
    /// A real folder (not a symlink). Packages are folders with `isPackage` set.
    public var isDirectory: Bool
    public var isPackage: Bool
    /// `st_blocks * 512`; folders: sum of the contents plus the folder's own blocks.
    public var allocatedSize: Int64
    /// `st_size` for files, the sum of contents for folders.
    public var logicalSize: Int64
    /// Directory entries that are not folders inside (1 for a file). A hard link seen again
    /// is still counted as an entry but contributes no bytes.
    public var fileCount: Int
    /// A folder that could not be listed.
    public var isUnreadable: Bool
    /// Sorted by `allocatedSize` descending, then by name.
    public var children: [DiskUsageNode]

    public init(
        id: Int, name: String, url: URL, isDirectory: Bool, isPackage: Bool = false,
        allocatedSize: Int64, logicalSize: Int64, fileCount: Int,
        isUnreadable: Bool = false, children: [DiskUsageNode] = []
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.fileCount = fileCount
        self.isUnreadable = isUnreadable
        self.children = children
    }
}

/// Throttled progress of a running scan.
public struct DiskUsageProgress: Sendable {
    public var files: Int
    public var bytes: Int64
    public var currentPath: String

    public init(files: Int, bytes: Int64, currentPath: String) {
        self.files = files
        self.bytes = bytes
        self.currentPath = currentPath
    }
}

/// Read-only disk usage scan. Only metadata is read; no file is opened.
public enum DiskUsage {
    /// Scans `root` with `fts` (physical walk, never follows links, stays on the root's device,
    /// so mounted volumes below it are not entered). Hard-linked files are counted once per
    /// (device, inode). Unreadable folders are flagged and the scan goes on. Throws
    /// `CancellationError` when the task is cancelled. `progress` is called at most ~10x/s.
    ///
    /// Package detection: only folders with a file name extension are asked for `.isPackageKey`
    /// (one Launch Services lookup each), plain folders are never packages.
    public static func scan(
        _ root: URL, progress: @Sendable (DiskUsageProgress) -> Void = { _ in }
    ) async throws -> DiskUsageNode {
        try Task.checkCancellation()
        return try scanBlocking(root, progress: progress)
    }

    /// Node at an index path from the root (indices into `children`); `[]` is the root.
    public static func node(at path: [Int], in root: DiskUsageNode) -> DiskUsageNode? {
        var current = root
        for index in path {
            guard current.children.indices.contains(index) else { return nil }
            current = current.children[index]
        }
        return current
    }

    // MARK: - Walk

    private struct Inode: Hashable {
        var dev: Int32
        var ino: UInt64
    }

    /// A folder whose `FTS_D` was seen but whose `FTS_DP` was not yet.
    private struct Builder {
        var id: Int
        var name: String
        var url: URL
        var isPackage: Bool
        var allocated: Int64
        var logical: Int64 = 0
        var fileCount = 0
        var isUnreadable = false
        var children: [DiskUsageNode] = []

        mutating func add(_ child: DiskUsageNode) {
            allocated += child.allocatedSize
            logical += child.logicalSize
            fileCount += child.fileCount
            children.append(child)
        }

        func finish() -> DiskUsageNode {
            DiskUsageNode(
                id: id, name: name, url: url, isDirectory: true, isPackage: isPackage,
                allocatedSize: allocated, logicalSize: logical, fileCount: fileCount,
                isUnreadable: isUnreadable, children: children.sorted(by: DiskUsage.areInOrder))
        }
    }

    private static func areInOrder(_ a: DiskUsageNode, _ b: DiskUsageNode) -> Bool {
        if a.allocatedSize != b.allocatedSize { return a.allocatedSize > b.allocatedSize }
        return NameRules.apfsDefault.order(a.name, b.name) == .orderedAscending
    }

    private static func nowNanos() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

    private static func scanBlocking(
        _ root: URL, progress: @Sendable (DiskUsageProgress) -> Void
    ) throws -> DiskUsageNode {
        let rootPath = root.path
        guard let cRoot = strdup(rootPath) else { throw CocoaError(.fileReadUnknown) }
        defer { free(cRoot) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cRoot, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_COMFOLLOW | FTS_XDEV | FTS_NOCHDIR, nil) else {
            throw CocoaError.fileError(errno: errno, url: root)
        }
        defer { fts_close(fts) }

        var nextID = 0
        func makeID() -> Int { defer { nextID += 1 }; return nextID }

        var stack: [Builder] = []
        var result: DiskUsageNode?
        var seen = Set<Inode>()
        var files = 0
        var bytes: Int64 = 0
        var lastReport: UInt64 = 0
        let interval: UInt64 = 100_000_000

        func finishFolder() {
            guard let builder = stack.popLast() else { return }
            let node = builder.finish()
            if stack.isEmpty { result = node } else { stack[stack.count - 1].add(node) }
        }

        func addLeaf(_ node: DiskUsageNode) {
            if stack.isEmpty { result = node } else { stack[stack.count - 1].add(node) }
        }

        while let entry = fts_read(fts) {
            try Task.checkCancellation()
            let info = Int32(entry.pointee.fts_info)
            let path = String(cString: entry.pointee.fts_path)
            let level = Int(entry.pointee.fts_level)
            let name = level == 0 ? (root.lastPathComponent.isEmpty ? "/" : root.lastPathComponent)
                : (path as NSString).lastPathComponent

            switch info {
            case FTS_D:
                let st = entry.pointee.fts_statp.pointee
                let allocated = Int64(st.st_blocks) * 512
                bytes += allocated
                let url = URL(fileURLWithPath: path, isDirectory: true)
                stack.append(Builder(
                    id: makeID(), name: name, url: url, isPackage: isPackage(url),
                    allocated: allocated))
            case FTS_DP:
                finishFolder()
            case FTS_DNR, FTS_ERR, FTS_NS:
                // A folder that failed to list is first returned as FTS_D, then again as FTS_DNR.
                if info == FTS_DNR, stack.count == level + 1, !stack.isEmpty {
                    stack[stack.count - 1].isUnreadable = true
                    finishFolder()
                } else {
                    if level == 0 { throw CocoaError.fileError(errno: entry.pointee.fts_errno, url: root) }
                    let st = entry.pointee.fts_statp.pointee
                    let valid = info != FTS_NS
                    let allocated = valid ? Int64(st.st_blocks) * 512 : 0
                    bytes += allocated
                    addLeaf(DiskUsageNode(
                        id: makeID(), name: name,
                        url: URL(fileURLWithPath: path, isDirectory: info == FTS_DNR),
                        isDirectory: info == FTS_DNR, allocatedSize: allocated,
                        logicalSize: valid ? Int64(st.st_size) : 0,
                        fileCount: info == FTS_DNR ? 0 : 1, isUnreadable: true))
                }
            default:
                // FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT: everything that is not a folder.
                let st = entry.pointee.fts_statp.pointee
                var allocated = Int64(st.st_blocks) * 512
                var logical = Int64(st.st_size)
                if st.st_nlink > 1, !seen.insert(Inode(dev: st.st_dev, ino: st.st_ino)).inserted {
                    allocated = 0
                    logical = 0
                }
                bytes += allocated
                addLeaf(DiskUsageNode(
                    id: makeID(), name: name, url: URL(fileURLWithPath: path, isDirectory: false),
                    isDirectory: false, allocatedSize: allocated, logicalSize: logical, fileCount: 1))
            }

            if info != FTS_DP { files += 1 }
            let now = nowNanos()
            if now &- lastReport >= interval {
                lastReport = now
                progress(DiskUsageProgress(files: files, bytes: bytes, currentPath: path))
            }
        }

        // An interrupted walk leaves open folders; fold them so the partial tree stays consistent.
        while !stack.isEmpty { finishFolder() }
        guard let result else { throw CocoaError.fileError(errno: errno == 0 ? ENOENT : errno, url: root) }
        return result
    }

    private static func isPackage(_ url: URL) -> Bool {
        guard !url.pathExtension.isEmpty else { return false }
        return (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }
}

private extension CocoaError {
    static func fileError(errno code: Int32, url: URL) -> CocoaError {
        let posix = POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        let kind: CocoaError.Code = switch code {
        case ENOENT: .fileReadNoSuchFile
        case EACCES, EPERM: .fileReadNoPermission
        default: .fileReadUnknown
        }
        return CocoaError(kind, userInfo: [NSUnderlyingErrorKey: posix, NSURLErrorKey: url])
    }
}
