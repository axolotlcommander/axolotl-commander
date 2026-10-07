public import Foundation

public protocol FileSource: Sendable {
    /// Lists `directory`. Never includes the parent row.
    func list(_ directory: URL, includeHidden: Bool) async throws -> [FileItem]
}

public struct LocalFileSource: FileSource {
    public init() {}

    /// Folders inside archives (`/x/a.zip/dir`) are listed from the archive's index,
    /// server folders (`sftp://…`, `ftp://…`) through `RemoteConnections.shared`.
    public func list(_ directory: URL, includeHidden: Bool) async throws -> [FileItem] {
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
            .fileSizeKey, .contentModificationDateKey,
        ]
        let urls = try fm.contentsOfDirectory(
            at: directory,
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
                url: url,
                name: name,
                isDirectory: isDirectory,
                isSymlink: isSymlink,
                isPackage: isDirectory && (values?.isPackage ?? false),
                isHidden: hidden,
                size: isDirectory ? nil : values?.fileSize.map(Int64.init),
                modificationDate: values?.contentModificationDate
            ))
        }
        return result
    }
}
