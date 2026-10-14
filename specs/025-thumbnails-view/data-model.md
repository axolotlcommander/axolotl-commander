# Data Model: Thumbnails View

Core types live in `CommanderCore` (no AppKit) and have unit tests; the AppKit side only draws and calls
the system preview service.

## PanelViewMode (changed)

```swift
public enum PanelViewMode: String, Codable, Sendable, CaseIterable { case detailed, brief, thumbnails }
```

Stored per side in `WindowLayout` (`leftMode`, `rightMode`); an unknown stored value decodes as `detailed`.

## PanelGrid

```swift
public enum PanelGrid: Sendable, Equatable {
    case list(pageRows: Int)                                  // Detailed
    case columns(rowsPerColumn: Int, visibleColumns: Int)     // Brief: top to bottom, then left to right
    case rows(columnsPerRow: Int, visibleRows: Int)           // Thumbnails: left to right, then down
    public func target(from: Int, count: Int, key: MoveKey) -> Int
}
public enum MoveKey: Sendable { case up, down, left, right, home, end, pageUp, pageDown }
```

| Key | `.list` | `.columns(r, c)` | `.rows(c, r)` |
|---|---|---|---|
| ↑ / ↓ | ∓1 | ∓1 | ∓c |
| ← / → | none (not a move) | ∓r | ∓1 |
| Page ↑ / ↓ | ∓pageRows | ∓r·c | ∓c·r |
| Home / End | 0 / count−1 | 0 / count−1 | 0 / count−1 |

The result is clamped to `0...count−1` (↓ from a row above a shorter last row lands on the last item, ↑
from the first row on the first item).

## GridGeometry

```swift
public struct GridGeometry: Sendable {
    public enum Order: Sendable { case columnsFirst, rowsFirst }  // Brief, Thumbnails
    var origin: CGPoint; var cell: CGSize; var stride: CGSize      // stride = cell + spacing
    var perLine: Int                                               // rows per column / columns per row
    var order: Order; var count: Int
    public func indices(in rect: CGRect) -> IndexSet               // cells the rectangle touches
}
```

A rectangle that lies only in a gap between cells covers nothing.

## ThumbnailSize

```swift
public enum ThumbnailSize: String, CaseIterable, Sendable { case small, medium, large }
// points: 64, 128, 256; larger / smaller (nil at the ends); key "panel.thumbnailSize", default medium
```

## ThumbnailKey and ThumbnailCache

```swift
public struct ThumbnailKey: Hashable, Sendable { let path: String; let modified: Date?; let size: ThumbnailSize }
public struct ThumbnailCache<Value> {            // least recently used goes first
    public init(costLimit: Int)                  // 256 MB in the app
    public mutating func value(for: ThumbnailKey) -> Value?          // marks as recently used
    public mutating func insert(_: Value, for: ThumbnailKey, cost: Int)
}
```

## ThumbnailQueue

```swift
public struct ThumbnailQueue {
    public init(limit: Int)                       // 8 in the app
    /// The keys wanted now, most important first (visible, then the margin).
    public mutating func want(_ keys: [ThumbnailKey]) -> (start: [ThumbnailKey], cancel: [ThumbnailKey])
    public mutating func finished(_ key: ThumbnailKey) -> [ThumbnailKey]   // keys to start next
}
```

Keys already in the cache are not passed to the queue.

## ThumbnailPolicy

```swift
public enum ThumbnailPolicy {
    public static func allowsPreviews(inArchive: Bool, onServer: Bool, isNetwork: Bool) -> Bool
    public static func allowsPreview(of url: URL) -> Bool   // a file URL, not inside an archive
}
```
