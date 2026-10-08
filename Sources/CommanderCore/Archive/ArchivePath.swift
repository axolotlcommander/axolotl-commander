// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation

/// A location inside an archive: the archive file on disk plus a folder path inside it.
public struct ArchivePath: Hashable, Sendable {
    /// File URL of the archive file.
    public var archive: URL
    /// "" for the archive root, else "a/b" (no leading/trailing slash).
    public var inner: String
    public var format: ArchiveFormat

    public init(archive: URL, inner: String = "", format: ArchiveFormat) {
        self.archive = URL(filePath: archive.standardizedFileURL.path, directoryHint: .notDirectory)
        self.inner = inner.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
        self.format = format
    }

    /// The pseudo file URL panels use: archive URL + inner components (e.g. /x/a.zip/dir/sub).
    public var url: URL {
        inner.isEmpty ? archive : URL(filePath: archive.path + "/" + inner, directoryHint: .isDirectory)
    }

    /// Splits a pseudo URL at the first prefix that has an archive extension and is a regular file.
    public static func split(
        _ url: URL,
        isRegularFile: (URL) -> Bool = ArchivePath.defaultIsRegularFile
    ) -> ArchivePath? {
        let parts = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        for (i, part) in parts.enumerated() {
            guard let format = ArchiveFormat.detect(fileName: part) else { continue }
            let file = URL(filePath: "/" + parts[...i].joined(separator: "/"), directoryHint: .notDirectory)
            guard isRegularFile(file) else { continue }
            return ArchivePath(archive: file, inner: parts[(i + 1)...].joined(separator: "/"), format: format)
        }
        return nil
    }

    /// Exists and is not a directory (a symlink to a file counts).
    public static func defaultIsRegularFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    /// Member path for a child name of this folder.
    public func member(_ name: String) -> String {
        inner.isEmpty ? name : inner + "/" + name
    }
}
