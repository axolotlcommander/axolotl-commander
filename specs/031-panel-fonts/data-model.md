# Data Model: File List and Main Window Fonts

## FontChoice (core, Codable, Hashable, Sendable)

| Field | Type | Rule |
|---|---|---|
| `name` | `String?` | PostScript name; nil = the system font |
| `size` | `Double` | points, kept within the role's limits |

## FontRole (core)

| Role | Default size | Limits |
|---|---|---|
| `fileList` | 13 | 8–32 |
| `mainWindow` (volume bar, drive row, path bar, tabs, command line, function keys) | 11 | 8–20 |

The file list role also covers the column titles and the status line (2 pt smaller), the folder history and
the hot path menu; parts of the main window drawn at another size today keep that distance from the chosen
size (command line +1, function key names 0, key caps −1).

Operations: `clamped(_ size:)`, `bigger(_ choice:)` / `smaller(_ choice:)` (±1 pt, nil when at the limit),
`isDefault(_ choice:)` (nil, or the system font at the default size), `rowHeight(lineHeight:padding:)`.

## PanelAppearance (existing)

New optional fields `listFont`, `windowFont` (`FontChoice?`), read and written per role with
`font(_:)` / `setFont(_:for:)`; nil = default. Missing keys decode as
nil.
