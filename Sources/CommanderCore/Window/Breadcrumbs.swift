// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// One step of a panel's location in the path bar: a volume, server, folder, archive or the
/// title of search results.
public struct PathSegment: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case volume, home, folder, archive, archiveFolder, server, remoteFolder, results
    }

    public var name: String
    /// Where a click on the segment goes (for `results`, the results root; not clickable).
    public var url: URL
    public var kind: Kind

    public init(name: String, url: URL, kind: Kind) {
        self.name = name
        self.url = url
        self.kind = kind
    }

    public var isClickable: Bool { kind != .results }
}

/// Which segments of a trail fit into the path bar.
public struct BreadcrumbFit: Equatable, Sendable {
    /// Indices of the segments shown, ascending; always the first and the last one.
    public var visible: [Int]
    /// Middle segments collapsed into one "…" segment, right after the first one.
    public var hidden: Range<Int>?
    /// Width left for the last segment when even it does not fit; nil = its natural width.
    public var lastWidth: Double?

    public init(visible: [Int], hidden: Range<Int>? = nil, lastWidth: Double? = nil) {
        self.visible = visible
        self.hidden = hidden
        self.lastWidth = lastWidth
    }
}

/// The breadcrumb trail of a panel location and the rule for shortening it. Pure: the caller
/// supplies the volume and home folder, nothing here touches the file system.
public enum Breadcrumbs {
    /// Segments from the root of `location` to the location itself; never empty.
    /// `volume` is the volume containing a local location (mount point and name).
    public static func trail(
        location: URL, results: ResultsListing? = nil, archive: ArchivePath? = nil,
        remote: RemoteLocation? = nil, volume: (root: URL, name: String), home: URL
    ) -> [PathSegment] {
        if let results {
            let title = PathSegment(name: results.title, url: results.root, kind: .results)
            return [title] + trail(location: results.root, remote: RemoteURL.parse(results.root),
                                   volume: volume, home: home)
        }
        if let remote { return remoteTrail(remote) }

        let path = plainPath(location)
        let root = plainPath(volume.root)
        let underRoot = root != "/" && (path == root || path.hasPrefix(root + "/"))
        let base = underRoot ? root : "/"
        var segments = [PathSegment(name: volume.name, url: URL(filePath: base, directoryHint: .isDirectory),
                                    kind: .volume)]
        let rest = base == "/" ? path : String(path.dropFirst(base.count))
        let homePath = plainPath(home)
        let archivePath = archive.map { plainPath($0.archive) }
        var current = base == "/" ? "" : base
        var insideArchive = false
        for part in rest.split(separator: "/", omittingEmptySubsequences: true) {
            current += "/" + part
            let kind: PathSegment.Kind
            if insideArchive {
                kind = .archiveFolder
            } else if current == archivePath {
                kind = .archive
                insideArchive = true
            } else {
                kind = current == homePath ? .home : .folder
            }
            let url = URL(filePath: current, directoryHint: kind == .archive ? .notDirectory : .isDirectory)
            segments.append(PathSegment(name: String(part), url: url, kind: kind))
        }
        return segments
    }

    /// The item to put the cursor on after going to segment `index`: the next segment on the
    /// trail, which leads back toward where the panel was. Nil for the last segment.
    public static func focusName(after index: Int, in trail: [PathSegment]) -> String? {
        guard trail.indices.contains(index + 1), trail[index + 1].kind != .results else { return nil }
        return trail[index + 1].name
    }

    /// Keeps the first and the last segment and as many segments before the last as fit; the rest
    /// of the middle becomes one "…" segment. Only when even first, "…" and last do not fit, the
    /// last one is given the remaining width (it is then shortened at its end).
    public static func fit(widths: [Double], available: Double, ellipsis: Double, separator: Double) -> BreadcrumbFit {
        let n = widths.count
        guard n > 0 else { return BreadcrumbFit(visible: []) }
        let all = widths.reduce(0, +) + separator * Double(n - 1)
        if all <= available { return BreadcrumbFit(visible: Array(0..<n)) }
        if n == 1 { return BreadcrumbFit(visible: [0], lastWidth: max(available, 0)) }
        if n == 2 {
            return BreadcrumbFit(visible: [0, 1], lastWidth: max(available - widths[0] - separator, 0))
        }
        let head = widths[0] + separator + ellipsis + separator
        var used = head + widths[n - 1]
        if used > available {
            return BreadcrumbFit(visible: [0, n - 1], hidden: 1..<(n - 1), lastWidth: max(available - head, 0))
        }
        var start = n - 1
        while start - 1 > 1, used + widths[start - 1] + separator <= available {
            start -= 1
            used += widths[start] + separator
        }
        return BreadcrumbFit(visible: [0] + Array(start..<n), hidden: 1..<start)
    }

    private static func remoteTrail(_ remote: RemoteLocation) -> [PathSegment] {
        var segments = [PathSegment(name: RemoteURL.displayName(remote.endpoint),
                                    url: RemoteURL.make(remote.endpoint, path: "/"), kind: .server)]
        var current = ""
        for part in remote.path.split(separator: "/", omittingEmptySubsequences: true) {
            current += "/" + part
            segments.append(PathSegment(name: String(part), url: RemoteURL.make(remote.endpoint, path: current),
                                        kind: .remoteFolder))
        }
        return segments
    }

    /// The path as the panel shows it, without a trailing "/" (except for "/").
    private static func plainPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
