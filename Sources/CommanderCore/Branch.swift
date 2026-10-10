// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Branch view: every file of a folder and of all its subfolders in one flat list (Total
/// Commander's Ctrl+B). Works wherever the panel can list a folder: on disk, in archives and on
/// servers.
public struct BranchListing: Hashable, Sendable {
    /// The branch folder; the panel's location while the branch is shown.
    public var root: URL
    /// The marked items the branch was made from, all directly in `root`; nil for the whole folder.
    public var starts: [URL]?

    public init(root: URL, starts: [URL]? = nil) {
        self.root = root
        self.starts = starts
    }

    /// The mark in the path bar, window and tab titles.
    public static var title: String { String(localized: "Branch") }
}

/// How far a branch scan is.
public struct BranchProgress: Sendable, Equatable {
    /// Files found so far.
    public var files: Int
    /// The folder being read, relative to the branch folder ("" for the folder itself).
    public var folder: String

    public init(files: Int, folder: String) {
        self.files = files
        self.folder = folder
    }
}

public struct BranchResult: Sendable {
    /// Files only, each named by its path relative to the branch folder; the URL is the real
    /// location.
    public var items: [FileItem]
    /// Subfolders that could not be listed (no permission, vanished, a server error).
    public var unreadable: Int
}

public enum BranchScanner {
    private static let progressInterval: Duration = .milliseconds(100)

    /// Lists the files of `listing`. Folder links are not entered (no loops); packages count as
    /// files. A subfolder that cannot be read is counted and skipped; an error reading the branch
    /// folder itself is thrown. Cancelling the task stops the scan with `CancellationError`.
    @concurrent
    public static func scan(
        _ listing: BranchListing,
        source: any FileSource,
        includeHidden: Bool,
        progress: @Sendable (BranchProgress) -> Void = { _ in }
    ) async throws -> BranchResult {
        var files: [FileItem] = []
        var unreadable = 0
        // Folders still to read, with their path below the root; the last one is read next.
        var pending: [(url: URL, path: String)] = []

        if let starts = listing.starts {
            let wanted = Set(starts.map(\.lastPathComponent))
            let top = try await source.list(listing.root, includeHidden: true).filter { wanted.contains($0.name) }
            for item in top.reversed() {
                if isFolder(item) {
                    if !item.isSymlink { pending.append((item.url, item.name)) }
                } else {
                    files.append(item)
                }
            }
        } else {
            pending.append((listing.root, ""))
        }

        let clock = ContinuousClock()
        var lastReport = clock.now
        let isRootScan = listing.starts == nil
        while let folder = pending.popLast() {
            try Task.checkCancellation()
            if clock.now - lastReport >= progressInterval {
                progress(BranchProgress(files: files.count, folder: folder.path))
                lastReport = clock.now
            }
            let children: [FileItem]
            do {
                children = try await source.list(folder.url, includeHidden: includeHidden)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if isRootScan, folder.path.isEmpty { throw error }
                unreadable += 1
                continue
            }
            var subfolders: [(url: URL, path: String)] = []
            for child in children where !child.isParent {
                let path = folder.path.isEmpty ? child.name : folder.path + "/" + child.name
                if isFolder(child) {
                    if !child.isSymlink { subfolders.append((child.url, path)) }
                } else {
                    files.append(child.renamed(path))
                }
            }
            // Depth first, in listing order.
            pending.append(contentsOf: subfolders.reversed())
        }
        progress(BranchProgress(files: files.count, folder: ""))
        return BranchResult(items: files, unreadable: unreadable)
    }

    /// A folder to walk into: packages are files to the user.
    private static func isFolder(_ item: FileItem) -> Bool { item.isDirectory && !item.isPackage }
}

extension FileItem {
    /// The same item under another name (its path below a listing's root).
    func renamed(_ name: String) -> FileItem {
        FileItem(url: url, name: name, isDirectory: isDirectory, isSymlink: isSymlink, isAlias: isAlias,
                 isPackage: isPackage, isHidden: isHidden, size: size, modificationDate: modificationDate)
    }
}

/// Sources grouped by the folder holding them, in the order they come: operations that work on one
/// folder at a time (archives) run once per group.
public enum SourceGroups {
    public static func byFolder(_ urls: [URL]) -> [(folder: URL, names: [String])] {
        var groups: [(folder: URL, names: [String])] = []
        var index: [String: Int] = [:]
        for url in urls {
            let folder = url.deletingLastPathComponent()
            let key = folder.standardized.absoluteString
            if let i = index[key] {
                groups[i].names.append(url.lastPathComponent)
            } else {
                index[key] = groups.count
                groups.append((folder, [url.lastPathComponent]))
            }
        }
        return groups
    }
}
