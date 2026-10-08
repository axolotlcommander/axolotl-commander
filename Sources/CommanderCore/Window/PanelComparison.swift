// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation

public struct ComparisonOptions: Codable, Hashable, Sendable {
    /// For same-named files select the newer one.
    public var compareDate = true
    /// For same-named files select the larger one.
    public var compareSize = true
    /// Time difference up to this many seconds counts as equal (FAT/SMB granularity).
    public var dateTolerance: TimeInterval = 2
    public var selectDirectoriesOnlyInOnePanel = true
    /// `WildcardMask` pattern; nil or blank ignores nothing.
    public var ignoreFiles: String? = nil
    public var ignoreDirectories: String? = nil

    public init() {}
}

/// Named to avoid clashing with `Foundation.ComparisonResult`.
public struct PanelComparisonResult: Hashable, Sendable {
    /// `FileItem.name`s to select on the left, in input order.
    public var left: [String]
    public var right: [String]

    public var isIdentical: Bool { left.isEmpty && right.isEmpty }
}

/// Compares two directory listings (non-recursive) and says what to select.
public enum PanelComparison {
    public static func compare(
        left: [FileItem],
        right: [FileItem],
        options: ComparisonOptions = .init(),
        rules: NameRules
    ) -> PanelComparisonResult {
        let fileMask = mask(options.ignoreFiles)
        let dirMask = mask(options.ignoreDirectories)
        func kept(_ list: [FileItem]) -> [FileItem] {
            list.filter { item in
                guard !item.isParent else { return false }
                let ignore = isDirectory(item) ? dirMask : fileMask
                return !(ignore?.matches(item.name, rules: rules) ?? false)
            }
        }
        let l = kept(left), r = kept(right)

        var rightByKey: [String: FileItem] = [:]
        for item in r where rightByKey[rules.key(item.name)] == nil { rightByKey[rules.key(item.name)] = item }
        let leftKeys = Set(l.map { rules.key($0.name) })

        var selectLeft = Set<String>(), selectRight = Set<String>()
        for a in l {
            guard let b = rightByKey[rules.key(a.name)] else {
                if !isDirectory(a) || options.selectDirectoriesOnlyInOnePanel { selectLeft.insert(a.name) }
                continue
            }
            switch (isDirectory(a), isDirectory(b)) {
            case (true, true):
                break
            case (false, false):
                if options.compareDate, let da = a.modificationDate, let db = b.modificationDate {
                    let diff = da.timeIntervalSince(db)
                    if diff > options.dateTolerance { selectLeft.insert(a.name) }
                    if diff < -options.dateTolerance { selectRight.insert(b.name) }
                }
                if options.compareSize, let sa = a.size, let sb = b.size {
                    if sa > sb { selectLeft.insert(a.name) }
                    if sb > sa { selectRight.insert(b.name) }
                }
            default:
                selectLeft.insert(a.name)
                selectRight.insert(b.name)
            }
        }
        for b in r where !leftKeys.contains(rules.key(b.name)) {
            if !isDirectory(b) || options.selectDirectoriesOnlyInOnePanel { selectRight.insert(b.name) }
        }

        return PanelComparisonResult(
            left: l.map(\.name).filter(selectLeft.contains),
            right: r.map(\.name).filter(selectRight.contains)
        )
    }

    /// Packages count as files.
    private static func isDirectory(_ item: FileItem) -> Bool { item.isDirectory && !item.isPackage }

    private static func mask(_ pattern: String?) -> WildcardMask? {
        guard let pattern, !pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return WildcardMask(pattern)
    }
}
