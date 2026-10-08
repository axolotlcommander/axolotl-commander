// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Darwin

public struct SearchProgress: Sendable, Equatable {
    public var currentDirectory: String
    public var directories: Int
    public var files: Int
    public var matches: Int

    public init(currentDirectory: String = "", directories: Int = 0, files: Int = 0, matches: Int = 0) {
        self.currentDirectory = currentDirectory
        self.directories = directories
        self.files = files
        self.matches = matches
    }
}

public enum SearchEvent: Sendable {
    case found([FileItem])
    case progress(SearchProgress)
    case problem(path: String, message: String)
}

/// Recursive file search: name mask, kind, size, date and content filters.
/// Symlinks are never followed into directories.
public enum FileSearch {
    public static func run(_ criteria: SearchCriteria,
                           legacyEncoding: TextEncoding = .windows1252) -> AsyncThrowingStream<SearchEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) {
                do {
                    guard !criteria.roots.isEmpty else { throw SearchError.noRoots }
                    var matcher: ContentMatcher?
                    if let query = criteria.content {
                        matcher = try ContentMatcher(query, legacyEncoding: legacyEncoding)
                    }
                    let walker = SearchWalker(criteria: criteria, matcher: matcher, continuation: continuation)
                    walker.run()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Used from a single thread only.
private final class SearchWalker {
    private let criteria: SearchCriteria
    private let matcher: ContentMatcher?
    private let continuation: AsyncThrowingStream<SearchEvent, any Error>.Continuation
    private let mask: SearchMask
    private var rules = NameRules.apfsDefault
    private let excludedNames: WildcardMask?
    private var excludedPaths: [String] = []

    private var visited = Set<DirectoryID>()
    private var batch: [FileItem] = []
    private var progress = SearchProgress()
    private var lastEmit = DispatchTime.now()
    private var cancelled = false

    private struct DirectoryID: Hashable { let dev: Int32; let ino: UInt64 }

    init(criteria: SearchCriteria, matcher: ContentMatcher?,
         continuation: AsyncThrowingStream<SearchEvent, any Error>.Continuation) {
        self.criteria = criteria
        self.matcher = matcher
        self.continuation = continuation
        mask = SearchMask(criteria.namePattern)
        var names: [String] = []
        for piece in criteria.excludedDirectories.split(separator: ";") {
            let entry = piece.trimmingCharacters(in: .whitespaces)
            if entry.isEmpty { continue }
            if entry.hasPrefix("/") || entry.hasPrefix("~") {
                excludedPaths.append(Self.normalize(SearchCriteria.expandTilde(entry)))
            } else {
                names.append(entry.replacingOccurrences(of: ";", with: ";;"))
            }
        }
        excludedNames = names.isEmpty ? nil : WildcardMask(names.joined(separator: ";"))
    }

    func run() {
        if criteria.content != nil && criteria.kind == .folders {
            flush(force: true)
            return
        }
        for rawRoot in criteria.roots {
            if checkCancelled() { break }
            let root = Self.normalize(SearchCriteria.expandTilde(rawRoot))
            var st = stat()
            guard stat(root, &st) == 0 else {
                continuation.yield(.problem(path: root, message: String(cString: strerror(errno))))
                continue
            }
            rules = NameRules.forVolume(containing: URL(fileURLWithPath: root))
            walk(root)
        }
        flush(force: true)
    }

    // MARK: Traversal

    private func checkCancelled() -> Bool {
        if !cancelled && Task.isCancelled { cancelled = true }
        return cancelled
    }

    private func walk(_ directory: String) {
        if checkCancelled() { return }
        guard let dir = opendir(directory) else {
            continuation.yield(.problem(path: directory, message: String(cString: strerror(errno))))
            return
        }
        var dirStat = stat()
        if fstat(dirfd(dir), &dirStat) == 0 {
            let id = DirectoryID(dev: dirStat.st_dev, ino: UInt64(dirStat.st_ino))
            if !visited.insert(id).inserted {
                closedir(dir)
                return
            }
        }
        progress.currentDirectory = directory
        progress.directories += 1
        flush(force: false)

        var subdirectories: [String] = []
        let prefix = directory == "/" ? "/" : directory + "/"
        while let entry = readdir(dir) {
            if checkCancelled() { break }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            if let descend = process(name: name, path: prefix + name, parent: directory) {
                subdirectories.append(descend)
            }
        }
        closedir(dir)
        guard criteria.subdirectories else { return }
        for sub in subdirectories {
            if checkCancelled() { return }
            walk(sub)
        }
    }

    /// Examines one entry; returns its path when it is a directory to descend into.
    private func process(name: String, path: String, parent: String) -> String? {
        var st = stat()
        guard lstat(path, &st) == 0 else {
            continuation.yield(.problem(path: path, message: String(cString: strerror(errno))))
            return nil
        }
        let hidden = name.hasPrefix(".") || (st.st_flags & UInt32(UF_HIDDEN)) != 0
        if hidden && !criteria.includeHidden { return nil }

        let isLink = (st.st_mode & S_IFMT) == S_IFLNK
        var isRealDirectory = (st.st_mode & S_IFMT) == S_IFDIR
        var isDirectory = isRealDirectory
        var info = st
        if isLink {
            var target = stat()
            if stat(path, &target) == 0 {
                isDirectory = (target.st_mode & S_IFMT) == S_IFDIR
                info = target
            }
        }
        isRealDirectory = isRealDirectory && !isLink

        if isRealDirectory && isExcluded(name: name, path: path) { return nil }

        if isDirectory { /* counted on entry for real directories */ } else { progress.files += 1 }

        // Package status is only needed for matching items and for descending.
        var packageKnown = false
        var packageValue = false
        func isPackage() -> Bool {
            if packageKnown { return packageValue }
            packageKnown = true
            if isRealDirectory && name.contains(".") {
                let url = URL(fileURLWithPath: path, isDirectory: true)
                packageValue = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
            }
            return packageValue
        }

        if matchesFilters(name: name, path: path, st: info, isLink: isLink, isDirectory: isDirectory) {
            progress.matches += 1
            let modified = Date(timeIntervalSince1970:
                Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000)
            batch.append(FileItem(
                url: URL(fileURLWithPath: path, isDirectory: isDirectory),
                name: name,
                isDirectory: isDirectory,
                isSymlink: isLink,
                isPackage: isDirectory && isPackage(),
                isHidden: hidden,
                size: isDirectory ? nil : Int64(info.st_size),
                modificationDate: modified
            ))
            flush(force: false)
        }

        guard isRealDirectory, criteria.subdirectories else { return nil }
        if !criteria.searchPackages && isPackage() { return nil }
        return path
    }

    private func matchesFilters(name: String, path: String, st: stat, isLink: Bool, isDirectory: Bool) -> Bool {
        switch criteria.kind {
        case .all: break
        case .files: if isDirectory { return false }
        case .folders: if !isDirectory { return false }
        }
        if !mask.matches(name, rules: rules) { return false }
        if criteria.minSize != nil || criteria.maxSize != nil {
            if isDirectory { return false }
            let size = Int64(st.st_size)
            if let minSize = criteria.minSize, size < minSize { return false }
            if let maxSize = criteria.maxSize, size > maxSize { return false }
        }
        if criteria.modifiedFrom != nil || criteria.modifiedTo != nil {
            let modified = Date(timeIntervalSince1970:
                Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000)
            if let from = criteria.modifiedFrom, modified < from { return false }
            if let to = criteria.modifiedTo, modified > to { return false }
        }
        if let matcher {
            guard !isDirectory, !isLink, (st.st_mode & S_IFMT) == S_IFREG else { return false }
            do {
                return try matcher.matches(fileAt: path)
            } catch is CancellationError {
                cancelled = true
                return false
            } catch let SearchError.cannotRead(message) {
                continuation.yield(.problem(path: path, message: message))
                return false
            } catch {
                continuation.yield(.problem(path: path, message: "\(error)"))
                return false
            }
        }
        return true
    }

    private func isExcluded(name: String, path: String) -> Bool {
        if let excludedNames, excludedNames.matches(name, rules: rules) { return true }
        if !excludedPaths.isEmpty {
            let key = rules.key(path)
            for excluded in excludedPaths {
                let e = rules.key(excluded)
                if key == e || key.hasPrefix(e == "/" ? "/" : e + "/") { return true }
            }
        }
        return false
    }

    // MARK: Events

    private func flush(force: Bool) {
        let now = DispatchTime.now()
        let elapsed = now.uptimeNanoseconds &- lastEmit.uptimeNanoseconds
        let due = elapsed >= 100_000_000
        if force || batch.count >= 64 || (due && !batch.isEmpty) {
            if !batch.isEmpty {
                continuation.yield(.found(batch))
                batch.removeAll(keepingCapacity: true)
            }
        }
        if force || due {
            continuation.yield(.progress(progress))
            lastEmit = now
        }
    }

    /// Absolute, without trailing slashes, `.` and `..` resolved lexically.
    private static func normalize(_ path: String) -> String {
        var p = path
        if !p.hasPrefix("/") { p = FileManager.default.currentDirectoryPath + "/" + p }
        var parts: [Substring] = []
        for component in p.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." { _ = parts.popLast(); continue }
            parts.append(component)
        }
        return "/" + parts.joined(separator: "/")
    }
}
