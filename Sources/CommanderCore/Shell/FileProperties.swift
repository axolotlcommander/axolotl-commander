public import Foundation
import Darwin
import UniformTypeIdentifiers

/// Read-only file attributes for the Properties dialog.
public struct FileProperties: Sendable, Equatable {
    public var url: URL
    public var name: String
    public var kind: String?
    public var isDirectory: Bool
    public var isPackage: Bool
    public var isSymlink: Bool
    public var linkDestination: String?
    public var size: Int64?
    public var allocatedSize: Int64?
    public var created: Date?
    public var modified: Date?
    public var accessed: Date?
    public var mode: Int
    public var owner: String?
    public var group: String?
    public var isHidden: Bool
    public var isLocked: Bool

    /// Reads with lstat semantics (does not follow the item itself if it is a link). Read-only.
    /// `size`/`allocatedSize` are nil for directories.
    public static func load(_ url: URL) throws -> FileProperties {
        var st = stat()
        guard lstat(url.path, &st) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let type = st.st_mode & S_IFMT
        let isSymlink = type == S_IFLNK
        let isDirectory = type == S_IFDIR
        let isPackage = isDirectory
            && ((try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false)
        let name = url.lastPathComponent

        func date(_ t: timespec) -> Date {
            Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1e9)
        }
        func ownerName(_ uid: uid_t) -> String {
            getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        }
        func groupName(_ gid: gid_t) -> String {
            getgrgid(gid).map { String(cString: $0.pointee.gr_name) } ?? String(gid)
        }

        let ext = url.pathExtension
        let contentType: UTType? =
            isSymlink ? .symbolicLink
            : isPackage ? (UTType(filenameExtension: ext) ?? .package)
            : isDirectory ? .folder
            : (ext.isEmpty ? nil : UTType(filenameExtension: ext))

        return FileProperties(
            url: url,
            name: name,
            kind: contentType?.localizedDescription,
            isDirectory: isDirectory,
            isPackage: isPackage,
            isSymlink: isSymlink,
            linkDestination: isSymlink
                ? try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil,
            size: isDirectory ? nil : Int64(st.st_size),
            allocatedSize: isDirectory ? nil : Int64(st.st_blocks) * 512,
            created: date(st.st_birthtimespec),
            modified: date(st.st_mtimespec),
            accessed: date(st.st_atimespec),
            mode: Int(st.st_mode & 0o7777),
            owner: ownerName(st.st_uid),
            group: groupName(st.st_gid),
            isHidden: name.hasPrefix(".") || st.st_flags & UInt32(UF_HIDDEN) != 0,
            isLocked: st.st_flags & UInt32(UF_IMMUTABLE) != 0)
    }

    /// "drwxr-xr-x", "-rw-r--r--", "lrwxr-xr-x"; setuid/setgid s/S, sticky t/T.
    public static func permissionsString(mode: Int, isDirectory: Bool, isSymlink: Bool) -> String {
        var s = isSymlink ? "l" : isDirectory ? "d" : "-"
        let triplets: [(shift: Int, special: Int, on: Character, off: Character)] = [
            (6, 0o4000, "s", "S"), (3, 0o2000, "s", "S"), (0, 0o1000, "t", "T"),
        ]
        for t in triplets {
            let bits = (mode >> t.shift) & 0o7
            let exec = bits & 1 != 0
            s += bits & 4 != 0 ? "r" : "-"
            s += bits & 2 != 0 ? "w" : "-"
            if mode & t.special != 0 {
                s.append(exec ? t.on : t.off)
            } else {
                s += exec ? "x" : "-"
            }
        }
        return s
    }

    /// "0755", "4755".
    public static func octal(_ mode: Int) -> String {
        let digits = String(mode & 0o7777, radix: 8)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }
}
