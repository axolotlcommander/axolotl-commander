public import Foundation

/// A panel listing of files from several folders (find results shown in a panel).
/// Items are named by their path relative to `root`, so names stay unique and
/// sorting by name groups them by folder.
public struct ResultsListing: Hashable, Sendable {
    public var title: String
    /// Deepest folder containing every item; the panel's location while the listing is shown.
    public var root: URL
    public var urls: [URL]

    public init(title: String, urls: [URL]) {
        self.title = title
        self.urls = urls
        root = Self.commonFolder(of: urls)
    }

    /// The deepest folder that contains all `urls` ("/" when they share nothing).
    public static func commonFolder(of urls: [URL]) -> URL {
        guard var common = urls.first?.standardized.deletingLastPathComponent().pathComponents else {
            return URL(filePath: "/")
        }
        for url in urls.dropFirst() {
            let parts = url.standardized.deletingLastPathComponent().pathComponents
            var n = 0
            while n < min(common.count, parts.count), common[n] == parts[n] { n += 1 }
            common.removeLast(common.count - n)
        }
        guard common.count > 1 else { return URL(filePath: "/") }
        return URL(filePath: "/" + common.dropFirst().joined(separator: "/"), directoryHint: .isDirectory)
    }

    /// Path of `url` below `root`.
    public func relativeName(of url: URL) -> String {
        let base = root.standardized.pathComponents
        let parts = url.standardized.pathComponents
        guard parts.count > base.count, Array(parts.prefix(base.count)) == base else { return url.path }
        return parts.dropFirst(base.count).joined(separator: "/")
    }

    /// Current state of every item that still exists; vanished ones are left out.
    /// Hidden items stay: they were found on purpose.
    @concurrent
    public func load() async throws -> [FileItem] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey,
        ]
        var result: [FileItem] = []
        result.reserveCapacity(urls.count)
        for (index, stored) in urls.enumerated() {
            if index % 256 == 0 { try Task.checkCancellation() }
            // URLs cache resource values; a refresh must see the disk.
            var url = stored
            url.removeAllCachedResourceValues()
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let isSymlink = values.isSymbolicLink ?? false
            var isDirectory = values.isDirectory ?? false
            if isSymlink {
                var target: ObjCBool = false
                isDirectory = fm.fileExists(atPath: url.path, isDirectory: &target) && target.boolValue
            }
            let hidden = (values.isHidden ?? false) || url.lastPathComponent.hasPrefix(".")
            result.append(FileItem(
                url: url,
                name: relativeName(of: url),
                isDirectory: isDirectory,
                isSymlink: isSymlink,
                isPackage: isDirectory && (values.isPackage ?? false),
                isHidden: hidden,
                size: isDirectory ? nil : values.fileSize.map(Int64.init),
                modificationDate: values.contentModificationDate
            ))
        }
        return result
    }
}
