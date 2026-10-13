// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Compares two folder trees, one relative folder at a time.
public enum SyncScanner {
    /// Walks both trees together. Symbolic links are never followed; packages are folders. An
    /// unreadable subfolder becomes an error row; an error reading either top folder is thrown.
    /// Cancelling the task throws `CancellationError`.
    @concurrent
    public static func compare(left: URL, right: URL, options: SyncOptions, includeHidden: Bool,
                               progress: @escaping @Sendable (SyncProgress) -> Void) async throws -> SyncComparison {
        try compare(left: left, right: right, options: options, includeHidden: includeHidden,
                    rules: SyncRulesForPair.rules(left: left, right: right), list: SyncEntry.list, progress: progress)
    }

    /// Tests pass their own name rules and listing (two names of one key cannot exist on the
    /// test volume).
    static func compare(left: URL, right: URL, options: SyncOptions, includeHidden: Bool, rules: NameRules,
                        list: @escaping (URL, SyncFilter) throws -> [SyncEntry],
                        progress: @escaping @Sendable (SyncProgress) -> Void) throws -> SyncComparison {
        let walk = SyncWalk(options: options, filter: SyncFilter(options: options, includeHidden: includeHidden, rules: rules),
                            rules: rules, list: list, progress: progress)
        try walk.level(left: left, right: right, leftPath: "", rightPath: "")
        progress(SyncProgress(scanned: walk.scanned, folder: "", bytesRead: walk.bytesRead))
        return SyncComparison(left: left, right: right, options: options, rules: rules, includeHidden: includeHidden,
                              items: walk.items)
    }
}

/// Which names take part (hidden items, ignore masks).
struct SyncFilter: Sendable {
    let includeHidden: Bool
    let files: WildcardMask?
    let folders: WildcardMask?
    let rules: NameRules

    init(options: SyncOptions, includeHidden: Bool, rules: NameRules) {
        self.includeHidden = includeHidden
        files = Self.mask(options.ignoreFiles)
        folders = Self.mask(options.ignoreFolders)
        self.rules = rules
    }

    func keeps(_ entry: SyncEntry) -> Bool {
        if !includeHidden && (entry.hidden || entry.name.hasPrefix(".")) { return false }
        let mask = entry.side.isFolder ? folders : files
        return !(mask?.matches(entry.name, rules: rules) ?? false)
    }

    private static func mask(_ pattern: String?) -> WildcardMask? {
        guard let pattern, !pattern.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return WildcardMask(pattern)
    }
}

/// One directory entry as compared.
struct SyncEntry {
    var url: URL
    var name: String
    var side: SyncSide
    var hidden: Bool

    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey,
    ]

    /// The entries of a folder that pass the filter. Resource values describe the entry itself,
    /// not the target of a link.
    static func list(_ folder: URL, filter: SyncFilter) throws -> [SyncEntry] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])
        return urls.map(entry).filter(filter.keeps)
    }

    static func entry(_ url: URL) -> SyncEntry {
        let values = try? url.resourceValues(forKeys: Set(keys))
        let kind: SyncSide.Kind
        if values?.isSymbolicLink == true {
            kind = .link(target: (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? "")
        } else if values?.isDirectory == true {
            kind = .folder
        } else {
            kind = .file
        }
        let size = kind == .folder ? 0 : Int64(values?.fileSize ?? 0)
        return SyncEntry(url: url, name: url.lastPathComponent,
                         side: SyncSide(kind: kind, size: size, fileCount: kind == .folder ? 0 : 1,
                                        modified: values?.contentModificationDate),
                         hidden: values?.isHidden ?? false)
    }
}

/// The state of one comparison while it runs.
private final class SyncWalk {
    let options: SyncOptions
    let filter: SyncFilter
    let rules: NameRules
    let list: (URL, SyncFilter) throws -> [SyncEntry]
    let progress: @Sendable (SyncProgress) -> Void
    var items: [SyncItem] = []
    var scanned = 0
    var bytesRead: Int64 = 0
    private let clock = ContinuousClock()
    private var lastReport: ContinuousClock.Instant
    private var folder = ""
    private static let progressInterval: Duration = .milliseconds(100)
    private static let chunk = 1 << 20

    init(options: SyncOptions, filter: SyncFilter, rules: NameRules, list: @escaping (URL, SyncFilter) throws -> [SyncEntry],
         progress: @escaping @Sendable (SyncProgress) -> Void) {
        self.options = options
        self.filter = filter
        self.rules = rules
        self.list = list
        self.progress = progress
        lastReport = clock.now
    }

    private func report() throws {
        try Task.checkCancellation()
        if clock.now - lastReport >= Self.progressInterval {
            progress(SyncProgress(scanned: scanned, folder: folder, bytesRead: bytesRead))
            lastReport = clock.now
        }
    }

    /// One row of a folder before sorting, and the pair of folders to walk into after it.
    private struct Row {
        var item: SyncItem
        var descend: (left: URL, right: URL)?
    }

    func level(left: URL, right: URL, leftPath: String, rightPath: String) throws {
        folder = leftPath
        try report()
        let l = try list(left, filter).sorted { rules.order($0.name, $1.name) == .orderedAscending }
        let r = try list(right, filter).sorted { rules.order($0.name, $1.name) == .orderedAscending }
        scanned += l.count + r.count

        var groups: [String: (left: [SyncEntry], right: [SyncEntry])] = [:]
        for e in l { groups[rules.key(e.name), default: ([], [])].left.append(e) }
        for e in r { groups[rules.key(e.name), default: ([], [])].right.append(e) }

        func join(_ base: String, _ name: String) -> String { base.isEmpty ? name : base + "/" + name }

        var rows: [Row] = []
        for group in groups.values {
            if group.left.count > 1 || group.right.count > 1 {
                rows += try clashRows(group, leftPath: leftPath, rightPath: rightPath, join: join)
                continue
            }
            let le = group.left.first, re = group.right.first
            let name = le?.name ?? re?.name ?? ""
            let lp = join(leftPath, le?.name ?? name), rp = join(rightPath, re?.name ?? name)
            var ls = le?.side, rs = re?.side
            let state: SyncState
            var descend: (URL, URL)?
            switch (le, re) {
            case let (l?, r?):
                if l.side.isFolder && r.side.isFolder {
                    state = .equal
                    if options.includeSubfolders { descend = (l.url, r.url) }
                } else if !l.side.sameKind(as: r.side) {
                    state = .different
                    if l.side.isFolder { ls = try totals(l) }
                    if r.side.isFolder { rs = try totals(r) }
                } else {
                    state = try compare(l, r)
                }
            case let (l?, nil):
                state = .onlyLeft
                if l.side.isFolder { ls = try totals(l) }
            case let (nil, r?):
                state = .onlyRight
                if r.side.isFolder { rs = try totals(r) }
            case (nil, nil):
                continue
            }
            rows.append(Row(item: makeItem(path: lp, left: ls, right: rs, state: state, leftPath: lp, rightPath: rp),
                            descend: descend))
        }
        rows.sort { rules.order($0.item.name, $1.item.name) == .orderedAscending }

        for row in rows {
            items.append(row.item)
            guard let pair = row.descend else { continue }
            let index = items.count - 1
            do {
                try level(left: pair.left, right: pair.right, leftPath: row.item.leftPath, rightPath: row.item.rightPath)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                items[index].state = .error(error.localizedDescription)
                items[index].defaultAction = .none
                items[index].action = .none
            }
        }
    }

    private func makeItem(path: String, left: SyncSide?, right: SyncSide?, state: SyncState,
                          leftPath: String, rightPath: String) -> SyncItem {
        let action = SyncRules.defaultAction(state: state, left: left, right: right, options: options)
        return SyncItem(path: path, left: left, right: right, state: state, defaultAction: action,
                        leftPath: leftPath, rightPath: rightPath)
    }

    /// Names that fold to one key on a side: every item of the group is an error row, so the run
    /// never copies one of them over the other.
    private func clashRows(_ group: (left: [SyncEntry], right: [SyncEntry]), leftPath: String, rightPath: String,
                           join: (String, String) -> String) throws -> [Row] {
        var names: [String] = []
        for e in group.left + group.right where !names.contains(e.name) { names.append(e.name) }
        names.sort { rules.order($0, $1) == .orderedAscending }
        return try names.map { name in
            let other = names.first { $0 != name } ?? name
            var ls = group.left.first { $0.name == name }
            var rs = group.right.first { $0.name == name }
            if let l = ls, l.side.isFolder { ls?.side = try totals(l) }
            if let r = rs, r.side.isFolder { rs?.side = try totals(r) }
            let state = SyncState.error(String(localized: "Name clashes with “\(other)”"))
            return Row(item: makeItem(path: join(leftPath, name), left: ls?.side, right: rs?.side, state: state,
                                      leftPath: join(leftPath, name), rightPath: join(rightPath, name)),
                       descend: nil)
        }
    }

    /// A folder facing nothing: the size and number of the files inside that pass the filter.
    private func totals(_ entry: SyncEntry) throws -> SyncSide {
        var side = entry.side
        var pending = [entry.url]
        while let url = pending.popLast() {
            try report()
            guard let children = try? list(url, filter) else { continue }
            scanned += children.count
            for child in children {
                if child.side.isFolder {
                    pending.append(child.url)
                } else {
                    side.size += child.side.size
                    side.fileCount += 1
                }
            }
        }
        return side
    }

    private func compare(_ l: SyncEntry, _ r: SyncEntry) throws -> SyncState {
        if case .link(let a) = l.side.kind, case .link(let b) = r.side.kind {
            if a == b { return .equal }
            return newer(l.side, r.side) ?? .different
        }
        if let state = newer(l.side, r.side) { return state }
        let sizesDiffer = l.side.size != r.side.size
        if options.compareSize && sizesDiffer { return .different }
        if options.compareContent {
            if sizesDiffer { return .different }
            do {
                return try sameContent(l.url, r.url) ? .equal : .different
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .error(error.localizedDescription)
            }
        }
        return .equal
    }

    /// The newer side when dates are compared and differ beyond the tolerance and the hour rule.
    private func newer(_ l: SyncSide, _ r: SyncSide) -> SyncState? {
        guard options.compareDate, let a = l.modified, let b = r.modified else { return nil }
        let delta = a.timeIntervalSince(b)
        let distance = abs(delta)
        let tolerance = SyncOptions.dateTolerance
        if distance <= tolerance { return nil }
        if options.ignoreHourDifference && abs(distance - 3600) <= tolerance { return nil }
        return delta > 0 ? .leftNewer : .rightNewer
    }

    private func sameContent(_ a: URL, _ b: URL) throws -> Bool {
        let ha = try FileHandle(forReadingFrom: a)
        defer { try? ha.close() }
        let hb = try FileHandle(forReadingFrom: b)
        defer { try? hb.close() }
        while true {
            try report()
            let da = try ha.read(upToCount: Self.chunk) ?? Data()
            let db = try hb.read(upToCount: Self.chunk) ?? Data()
            bytesRead += Int64(da.count + db.count)
            if da != db { return false }
            if da.isEmpty { return true }
        }
    }
}
