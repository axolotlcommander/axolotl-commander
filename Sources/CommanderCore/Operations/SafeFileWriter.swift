public import Foundation

/// Writes a new version of a file without risking the old one: the content goes to a
/// temporary file next to the target, and only a complete file replaces the target.
/// On an error or cancellation the temporary file is removed and the target stays as it was.
public enum SafeFileWriter {
    /// `produce` writes the complete content to the URL it is given (which does not exist yet).
    /// A symlinked target is resolved, so the file the link points to gets the new content.
    public static func write(to target: URL, _ produce: (URL) throws -> Void) throws {
        let target = target.resolvingSymlinksInPath()
        let folder = target.deletingLastPathComponent()
        let ext = target.pathExtension
        let temp = folder.appending(path: FileCopy.tempPrefix + UUID().uuidString + (ext.isEmpty ? "" : "." + ext))
        let manager = FileManager.default
        defer { try? manager.removeItem(at: temp) }
        try produce(temp)
        try Task.checkCancellation()
        guard manager.fileExists(atPath: temp.path) else { throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: target]) }
        if manager.fileExists(atPath: target.path) {
            // Swaps the files and keeps the old one's attributes (permissions, tags, creation date).
            _ = try manager.replaceItemAt(target, withItemAt: temp)
        } else if renamex_np(temp.path, target.path, UInt32(RENAME_EXCL)) != 0 {
            if errno == EEXIST {
                _ = try manager.replaceItemAt(target, withItemAt: temp)
            } else {
                throw CocoaError(.fileWriteUnknown, userInfo: [
                    NSURLErrorKey: target, NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO),
                ])
            }
        }
    }
}
