# Data Model: File Sizes Like Finder

All types are in `CommanderCore` (no AppKit) unless marked UI.

## SizeDisplay (enum, String raw values)

| Case | Raw | Meaning |
|---|---|---|
| `finder` | `"finder"` | the Size column shows the rounded size (default) |
| `bytes` | `"bytes"` | the Size column shows exact bytes with grouping |

## SizeUnits (enum, String raw values)

| Case | Raw | Meaning |
|---|---|---|
| `decimal` | `"decimal"` | 1 kB = 1000 bytes, system file style (default) |
| `binary` | `"binary"` | 1 kB = 1024 bytes, system binary style |

## SizeFormat (value)

| Field | Type | Rule |
|---|---|---|
| display | `SizeDisplay` | default `.finder` |
| units | `SizeUnits` | default `.decimal` |

Functions (pure, with the locale injected for tests):
- `static func rounded(_ bytes: Int64, units: SizeUnits, locale: Locale) -> String`: the system
  byte-count text (R1).
- `static func exact(_ bytes: Int64, locale: Locale) -> String`: grouped digits, the same text as
  `Format.grouped`.
- `func columnVariants(_ bytes: Int64, locale: Locale) -> [String]`, longest first (R4):
  - `.bytes`: `[exact, rounded]`;
  - `.finder`: `[rounded]`.
  Duplicates are removed.
- `func roundedIsExact(_ bytes: Int64, locale: Locale) -> Bool`: true when the rounded text shows
  every byte (e.g. "402 bytes", "1 000 bajtů"). The status bar then shows no exact count in
  parentheses (R5).

`CellText.size(_:locale:)` is replaced by `SizeFormat.columnVariants`. `CellText.date` and
`CellText.fitting` stay.

## SizeSettings (UI)

| Member | Rule |
|---|---|
| `displayKey = "size.display"`, `unitsKey = "size.units"` | `UserDefaults` keys |
| `static var saved: SizeFormat` | an unknown or missing value gives the default |

Settings → Appearance binds both keys with `@AppStorage`. `Format.bytes` uses `saved.units`.
