# Data Model: Panel and Bar Fonts

## FontChoice (core, Codable, Hashable, Sendable)

| Field | Type | Rule |
|---|---|---|
| `name` | `String?` | PostScript name; nil = the system font |
| `size` | `Double` | points, kept within the role's limits |

## FontRole (core)

| Role | Default size | Limits |
|---|---|---|
| `fileList` | 13 | 8–32 |
| `bars` (path bar, tabs, status line) | 11 | 8–20 |
| `volumeButtons` (volume bar, drive row) | 11 | 8–20 |

Operations: `clamped(_ size:)`, `bigger(_ choice:)` / `smaller(_ choice:)` (±1 pt, nil when at the limit),
`isDefault(_ choice:)` (nil, or the system font at the default size), `rowHeight(lineHeight:padding:)`.

## PanelAppearance (existing)

New optional fields `listFont`, `barFont`, `buttonFont` (`FontChoice?`), read and written per role with
`font(_:)` / `setFont(_:for:)`; nil = default. Missing keys decode as
nil.
