// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

public protocol FileSource: Sendable {
    /// Lists `directory`. Never includes the parent row.
    func list(_ directory: URL, includeHidden: Bool) async throws -> [FileItem]
}

public struct LocalFileSource: FileSource {
    public init() {}

    /// Folders inside archives (`/x/a.zip/dir`) are listed from the archive's index,
    /// server folders (`sftp://…`, `ftp://…`) through `RemoteConnections.shared`, the Network folder
    /// (`network:/`) from `NetworkDiscovery`.
    public func list(_ directory: URL, includeHidden: Bool) async throws -> [FileItem] {
        if NetworkPlaces.isNetwork(directory) { return NetworkDiscovery.shared.items() }
        if let remote = RemoteURL.parse(directory) {
            return try await RemoteConnections.shared.list(remote, includeHidden: includeHidden)
        }
        if let inArchive = ArchivePath.split(directory) {
            return try await ArchiveCatalog.shared.list(inArchive, includeHidden: includeHidden)
        }
        return try await Self.read(directory, includeHidden: includeHidden)
    }

    @concurrent
    private static func read(_ directory: URL, includeHidden: Bool) async throws -> [FileItem] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDir) else { throw PathError.notFound }
        guard isDir.boolValue else { throw PathError.notADirectory }

        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey,
            .fileSizeKey, .contentModificationDateKey, .isAliasFileKey,
        ]
        // Listing a symbolic link to a folder by URL fails with "Not a directory", so the link is
        // resolved for reading; the items keep the link's path (see below).
        let resolved = directory.resolvingSymlinksInPath()
        let viaLink = resolved.path != directory.path
        let urls = try fm.contentsOfDirectory(
            at: resolved,
            includingPropertiesForKeys: keys,
            options: includeHidden ? [] : [.skipsHiddenFiles]
        )
        var result: [FileItem] = []
        result.reserveCapacity(urls.count)
        for (index, url) in urls.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = url.lastPathComponent
            let isSymlink = values?.isSymbolicLink ?? false
            var isDirectory = values?.isDirectory ?? false
            if isSymlink {
                var target: ObjCBool = false
                isDirectory = fm.fileExists(atPath: url.path, isDirectory: &target) && target.boolValue
            }
            let hidden = (values?.isHidden ?? false) || name.hasPrefix(".")
            if hidden && !includeHidden { continue }
            result.append(FileItem(
                url: viaLink ? directory.appendingPathComponent(name, isDirectory: values?.isDirectory ?? false) : url,
                name: name,
                isDirectory: isDirectory,
                isSymlink: isSymlink,
                // `isAliasFile` is also true for symbolic links.
                isAlias: !isSymlink && !isDirectory && (values?.isAliasFile ?? false),
                isPackage: isDirectory && (values?.isPackage ?? false),
                isHidden: hidden,
                size: isDirectory ? nil : values?.fileSize.map(Int64.init),
                modificationDate: values?.contentModificationDate
            ))
        }
        return result
    }
}
