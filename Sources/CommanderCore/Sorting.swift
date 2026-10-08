// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

public enum SortField: String, Sendable, CaseIterable, Codable {
    case name, ext, date, size
}

public struct SortSpec: Sendable, Hashable, Codable {
    public var field: SortField
    public var ascending: Bool

    public init(field: SortField, ascending: Bool = true) {
        self.field = field
        self.ascending = ascending
    }

    public static let `default` = SortSpec(field: .name, ascending: true)

    /// Choosing the same field again reverses the order; a different field
    /// starts ascending.
    public func toggled(_ field: SortField) -> SortSpec {
        field == self.field
            ? SortSpec(field: field, ascending: !ascending)
            : SortSpec(field: field, ascending: true)
    }
}

/// Parent row first, then directories, then files; packages (apps, bundles) count as files, as in
/// Finder, with their size when it was calculated. Directories follow the
/// sort field when it applies to them (date; size when computed), otherwise
/// they are ordered by name. Ties always fall back to ascending name.
/// `directorySizes` is keyed by `rules.key(name)`.
public func sortItems(
    _ items: [FileItem],
    by spec: SortSpec,
    rules: NameRules,
    directorySizes: [String: Int64] = [:]
) -> [FileItem] {
    var parents: [FileItem] = []
    var dirs: [FileItem] = []
    var files: [FileItem] = []
    for item in items {
        if item.isParent { parents.append(item) }
        else if item.isDirectory && !item.isPackage { dirs.append(item) }
        else { files.append(item) }
    }

    func byName(_ a: FileItem, _ b: FileItem) -> ComparisonResult { rules.order(a.name, b.name) }
    func compare<T: Comparable>(_ x: T, _ y: T) -> ComparisonResult {
        x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
    }
    func sorted(_ list: [FileItem], primary: (FileItem, FileItem) -> ComparisonResult) -> [FileItem] {
        list.sorted { a, b in
            var r = primary(a, b)
            if r != .orderedSame {
                if !spec.ascending { r = r == .orderedAscending ? .orderedDescending : .orderedAscending }
                return r == .orderedAscending
            }
            return byName(a, b) == .orderedAscending
        }
    }

    let sortedDirs: [FileItem]
    switch spec.field {
    case .name, .ext:
        sortedDirs = sorted(dirs, primary: byName)
    case .date:
        sortedDirs = sorted(dirs) { compare($0.modificationDate ?? .distantPast, $1.modificationDate ?? .distantPast) }
    case .size:
        sortedDirs = sorted(dirs) {
            compare(directorySizes[rules.key($0.name)] ?? -1, directorySizes[rules.key($1.name)] ?? -1)
        }
    }

    let sortedFiles: [FileItem]
    switch spec.field {
    case .name:
        sortedFiles = sorted(files, primary: byName)
    case .ext:
        sortedFiles = sorted(files) { rules.order($0.fileExtension, $1.fileExtension) }
    case .date:
        sortedFiles = sorted(files) { compare($0.modificationDate ?? .distantPast, $1.modificationDate ?? .distantPast) }
    case .size:
        func size(_ item: FileItem) -> Int64 {
            item.isPackage ? directorySizes[rules.key(item.name)] ?? -1 : item.size ?? 0
        }
        sortedFiles = sorted(files) { compare(size($0), size($1)) }
    }
    return parents + sortedDirs + sortedFiles
}
