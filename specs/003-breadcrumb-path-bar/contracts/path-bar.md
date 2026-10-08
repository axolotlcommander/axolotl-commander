# Contract: Path Bar

## Core API (`CommanderCore/Window/Breadcrumbs.swift`)

```swift
public struct PathSegment: Hashable, Sendable {
    public enum Kind: Sendable { case volume, home, folder, archive, archiveFolder, server, remoteFolder, results }
    public var name: String
    public var url: URL
    public var kind: Kind
    public var isClickable: Bool { kind != .results }
}

public struct BreadcrumbFit: Equatable, Sendable {
    public var visible: [Int]
    public var hidden: Range<Int>?
    public var lastWidth: Double?
}

public enum Breadcrumbs {
    public static func trail(location: URL, results: ResultsListing?, archive: ArchivePath?,
                             remote: RemoteLocation?, volume: (root: URL, name: String),
                             home: URL) -> [PathSegment]
    public static func focusName(after index: Int, in trail: [PathSegment]) -> String?
    public static func fit(widths: [Double], available: Double, ellipsis: Double,
                           separator: Double) -> BreadcrumbFit
}
```

Guarantees:
- `trail` never returns an empty array and never touches the file system.
- For a local location under the volume root, `trail.first.kind == .volume` and
  `trail.last.url` is the location.
- With `results`, `trail.first.kind == .results` and the rest is the trail of `results.root`.
- `fit` keeps index 0 and the last index; middle segments disappear only as one contiguous range
  right after index 0.

## UI behavior (`AxolotlCommander/PathBar.swift`)

| Input | Breadcrumb mode | Text mode |
|---|---|---|
| Click on a clickable segment (not current) | activate panel, `go(to: url, focusing: next name)` | — |
| Click on the current folder's segment | activate panel only | — |
| Click on "…" | menu of hidden segments; choice = segment click | — |
| ⌘-click on a segment | new tab in this panel at that folder | — |
| Right-click / ⌃-click on a segment | segment menu (FR-019, FR-020) | — |
| Click right of the last segment | activate panel, begin editing | (field gets the click) |
| ⌘L (Edit Path) | begin editing in the active panel | focus field, select all |
| Enter in field | today's commit; focus back to list; row shown | today's commit |
| Esc in field | restore text; focus back to list; row shown | today's behavior |
| Field loses focus | row shown | — |
| Settings change (style, icons) | both panels re-render at once | both panels re-render at once |

Segment menu items: Open in Other Panel · Open in New Tab · Copy Path · Set as Hot Path ▸ (slots
1–10 with current names) · Show in Finder (disabled for `server`, `remoteFolder`,
`archiveFolder`).

Accessibility: row = group "Path"; segment = button (label = name, press = click); "…" = button
"Hidden folders"; results title = static text.
