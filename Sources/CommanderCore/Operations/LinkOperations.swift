// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin

public enum LinkKind: Sendable { case symbolic, hard }

public enum LinkError: Error, Equatable {
    /// Hard link to a folder (or package).
    case folderNotAllowed(URL)
    /// Hard link to a symbolic link.
    case symbolicLinkNotAllowed(URL)
    /// Hard link to something that is neither a file nor a folder (pipe, socket, device).
    case notARegularFile(URL)
    /// Hard link destination on another volume than the file.
    case differentVolume(URL)
    /// The item to retarget is not (or no longer) a symbolic link.
    case notASymbolicLink(URL)
    /// The final item behind a link does not exist; `stored` is what the first link holds.
    case targetMissing(stored: String)
    /// More link steps than the system allows.
    case loop(URL)
}

/// What happened to one source of a batch.
public struct LinkOutcome: Sendable {
    public enum Result: Sendable {
        case created(URL)
        case skipped(any Error)
    }

    public let source: URL
    public let result: Result

    public var created: URL? {
        if case .created(let url) = result { url } else { nil }
    }
}

/// Text of link targets. The system follows ".." physically (from the real folder, after any
/// links in the path), so relative paths are computed and read back from real folders; an
/// absolute target is stored exactly as typed.
public enum LinkPaths {
    /// `target` as seen from `folder`, both taken as written: `../shared/file`; "." when equal.
    public static func relativePath(from folder: String, to target: String) -> String {
        let from = components(folder), to = components(target)
        var common = 0
        while common < from.count, common < to.count, from[common] == to[common] { common += 1 }
        let parts = Array(repeating: "..", count: from.count - common) + to[common...]
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }

    /// The text a new symbolic link in `linkFolder` holds. A typed relative path stays as typed;
    /// `~` is expanded; an absolute path is kept as typed, or made relative from the real folders
    /// of the link and the target.
    public static func storedTarget(typed: String, linkFolder: String, relative: Bool) -> String {
        let text = expanded(typed)
        guard text.hasPrefix("/"), relative else { return text }
        return relativePath(from: realFolder(linkFolder), to: physical(text))
    }

    public static func isRelative(_ stored: String) -> Bool { !expanded(stored).hasPrefix("/") }

    /// The absolute path a stored target means for a link in `linkFolder`, with the folders that
    /// exist made real (so ".." means what the system makes of it).
    public static func absolute(_ stored: String, linkFolder: String) -> String {
        let text = expanded(stored)
        return physical(text.hasPrefix("/") ? text : realFolder(linkFolder) + "/" + text)
    }

    /// `path` with its folder made real when that folder exists; otherwise only "." and ".."
    /// applied as text.
    static func physical(_ path: String) -> String {
        let name = FSPath.name(path)
        if name == "." || name == ".." || name == "/" { return realPath(path) ?? normalized(path) }
        guard let folder = realPath(FSPath.parent(path)) else { return normalized(path) }
        return FSPath.join(folder, name)
    }

    /// The folder itself made real (all links in it followed) when it exists.
    static func realFolder(_ folder: String) -> String {
        realPath(folder) ?? physical(folder)
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func expanded(_ text: String) -> String {
        text.hasPrefix("~") ? (text as NSString).expandingTildeInPath : text
    }

    /// Absolute path with "." and ".." applied and duplicate slashes removed.
    static func normalized(_ path: String) -> String {
        "/" + components(path).joined(separator: "/")
    }

    private static func components(_ path: String) -> [String] {
        var parts: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(String(part))
            }
        }
        return parts
    }
}

extension FileOperations {
    /// Creates a symbolic link at `path` holding `stored`. Never replaces an existing item.
    @discardableResult
    public func makeSymbolicLink(at path: String, storing stored: String) throws -> URL {
        if stored.isEmpty { throw OperationError.path(.empty) }
        let dir = try checkedFolder(forNewItemAt: path)
        try refuseExisting(path, in: dir)
        if symlink(stored, path) != 0 { throw creationError(errno, "Cannot create link", path) }
        return FSPath.url(path)
    }

    /// Creates a hard link at `path` to the regular file `file`, on the same volume. Never replaces.
    @discardableResult
    public func makeHardLink(at path: String, to file: URL) throws -> URL {
        var source = stat()
        guard lstat(file.path, &source) == 0 else {
            throw creationError(errno, "Cannot read", file.path)
        }
        switch source.st_mode & S_IFMT {
        case S_IFREG: break
        case S_IFDIR: throw LinkError.folderNotAllowed(file)
        case S_IFLNK: throw LinkError.symbolicLinkNotAllowed(file)
        default: throw LinkError.notARegularFile(file)
        }
        let dir = try checkedFolder(forNewItemAt: path)
        var folder = stat()
        if stat(dir, &folder) == 0, folder.st_dev != source.st_dev { throw LinkError.differentVolume(file) }
        try refuseExisting(path, in: dir)
        // Flags 0: never follows a link that replaced the file meanwhile.
        if linkat(AT_FDCWD, file.path, AT_FDCWD, path, 0) != 0 {
            let err = errno
            if err == EXDEV { throw LinkError.differentVolume(file) }
            throw creationError(err, "Cannot create link", path)
        }
        return FSPath.url(path)
    }

    /// One link per source in `folder`, named like the source. Never stops at a problem: every
    /// source gets an outcome. Symbolic links hold the source's absolute or relative path.
    public func makeLinks(_ kind: LinkKind, to sources: [URL], in folder: URL, relative: Bool) -> [LinkOutcome] {
        sources.map { source in
            let path = FSPath.join(folder.path, source.lastPathComponent)
            do {
                let made = switch kind {
                case .symbolic:
                    try makeSymbolicLink(
                        at: path,
                        storing: LinkPaths.storedTarget(typed: source.path, linkFolder: folder.path, relative: relative))
                case .hard:
                    try makeHardLink(at: path, to: source)
                }
                return LinkOutcome(source: source, result: .created(made))
            } catch {
                return LinkOutcome(source: source, result: .skipped(error))
            }
        }
    }

    /// Points the symbolic link `link` to `stored` in one step: the name exists all the time, and
    /// only a symbolic link is ever replaced (a new link is swapped in; when the swapped-out item
    /// turns out not to be a link, the swap is reversed).
    public func retargetSymbolicLink(_ link: URL, storing stored: String) throws {
        if stored.isEmpty { throw OperationError.path(.empty) }
        let path = link.path
        guard Self.isSymbolicLink(path) else { throw LinkError.notASymbolicLink(link) }
        let dir = FSPath.parent(path)
        let temp = FSPath.join(dir, ".axolotl-link-\(UUID().uuidString.prefix(8))")
        if symlink(stored, temp) != 0 { throw creationError(errno, "Cannot create link", path) }
        if renamex_np(temp, path, UInt32(RENAME_SWAP)) == 0 {
            // `temp` now holds what was at `path`.
            if Self.isSymbolicLink(temp) {
                unlink(temp)
                return
            }
            // Swap back; only when that worked is `temp` our new link again. Otherwise the user's
            // item stays under the temporary name and the error says where.
            guard renamex_np(temp, path, UInt32(RENAME_SWAP)) == 0 else {
                throw OperationError.io(FSPath.errorText(errno, "Cannot restore", path) + " (\(temp))")
            }
            unlink(temp)
            throw LinkError.notASymbolicLink(link)
        }
        let err = errno
        guard err == ENOTSUP || err == EINVAL else {
            unlink(temp)
            throw creationError(err, "Cannot change link", path)
        }
        // No swap on this volume (some network and FAT volumes): rename(2) still replaces in one
        // step. Only an item replacing the link between this check and the rename could be lost.
        guard Self.isSymbolicLink(path) else {
            unlink(temp)
            throw LinkError.notASymbolicLink(link)
        }
        if Darwin.rename(temp, path) != 0 {
            let err = errno
            unlink(temp)
            throw creationError(err, "Cannot change link", path)
        }
    }

    // MARK: Helpers

    /// Validates the new item's name and path; returns its folder, which must exist.
    private func checkedFolder(forNewItemAt path: String) throws -> String {
        try NameCheck.validate(FSPath.name(path))
        try NameCheck.validate(path: path)
        let dir = FSPath.parent(path)
        var info = stat()
        guard stat(dir, &info) == 0 else { throw OperationError.path(.notFound) }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw OperationError.path(.notADirectory) }
        return dir
    }

    /// An existing entry by the volume's name rules (case, normalization) is a conflict.
    private func refuseExisting(_ path: String, in dir: String) throws {
        let rules = NameRules.forVolume(containing: FSPath.url(dir))
        let name = FSPath.name(path)
        guard try DirectoryLookup(rules: rules).existing(in: dir, named: name) != nil else { return }
        // The spelling on disk, so the message names the item the user sees.
        let actual = (try? FileManager.default.contentsOfDirectory(atPath: dir))?.first { rules.same($0, name) } ?? name
        throw OperationError.alreadyExists(FSPath.url(FSPath.join(dir, actual)))
    }

    private func creationError(_ err: Int32, _ what: String, _ path: String) -> OperationError {
        switch err {
        case EEXIST: .alreadyExists(FSPath.url(path))
        case ENOENT: .path(.notFound)
        default: .io(FSPath.errorText(err, what, path))
        }
    }

    static func isSymbolicLink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFLNK
    }
}

/// Following symbolic links and Finder aliases to what they finally point to.
public enum LinkTarget {
    /// The system's limit of link steps in one path.
    static let maxSteps = 32

    /// True for a symbolic link or a Finder alias (the item itself, not followed).
    public static func isLink(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        switch info.st_mode & S_IFMT {
        case S_IFLNK: return true
        case S_IFREG: return isAlias(url)
        default: return false
        }
    }

    /// The final existing item behind `url`: chains of links and aliases are followed, relative
    /// targets resolved against the link's folder, and the folder holding the result made real.
    public static func resolve(_ url: URL) throws -> URL {
        var current = LinkPaths.normalized(url.path)
        var firstStored: String?
        for _ in 0..<maxSteps {
            var info = stat()
            guard lstat(current, &info) == 0 else {
                throw LinkError.targetMissing(stored: firstStored ?? current)
            }
            let type = info.st_mode & S_IFMT
            if type == S_IFLNK, let stored = try? FileManager.default.destinationOfSymbolicLink(atPath: current) {
                if firstStored == nil { firstStored = stored }
                current = LinkPaths.absolute(stored, linkFolder: FSPath.parent(current))
                continue
            }
            let item = FSPath.url(current)
            if type == S_IFREG, isAlias(item) {
                guard let original = try? URL(resolvingAliasFileAt: item, options: [.withoutUI, .withoutMounting]) else {
                    throw LinkError.targetMissing(stored: firstStored ?? item.lastPathComponent)
                }
                if firstStored == nil { firstStored = original.path }
                current = LinkPaths.normalized(original.path)
                continue
            }
            let folder = URL(fileURLWithPath: FSPath.parent(current), isDirectory: true).resolvingSymlinksInPath()
            return folder.appendingPathComponent(FSPath.name(current), isDirectory: type == S_IFDIR)
        }
        throw LinkError.loop(url)
    }

    /// `isAliasFile` is also true for symbolic links; callers check those first.
    private static func isAlias(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true
    }
}
