# Data Model: Clickable Breadcrumb Path Bar

## PathSegment (core, value type)

| Field | Type | Notes |
|---|---|---|
| `name` | String | Display name: volume name, server display name, folder name, results title |
| `url` | URL | Location the segment leads to (for `results`: the results root, not used for navigation) |
| `kind` | `PathSegment.Kind` | `volume`, `home`, `folder`, `archive`, `archiveFolder`, `server`, `remoteFolder`, `results` |
| `isClickable` | Bool | false only for `results` |

Rules:
- Names are never empty; the root of a volume is shown by the volume name.
- A name containing "›" stays one segment (the separator is never parsed from names).

## Breadcrumb trail (core, derived)

`Breadcrumbs.trail(location:results:archive:remote:volume:home:) -> [PathSegment]`

- **Input** `volume`: `(root: URL, name: String)` of the volume containing a local location,
  supplied by the UI; `home`: the user's home folder URL.
- **Output**: ordered from root to the current folder; never empty.
- **Focus on click**: `Breadcrumbs.focusName(after index:, in trail:) -> String?` — the
  last path component of the segment after `index` (nil for the last segment).
- Derived on every model change; never stored.

## Fit (core, value type)

`Breadcrumbs.fit(widths: [Double], available: Double, ellipsis: Double, separator: Double) -> BreadcrumbFit`

| Field | Type | Notes |
|---|---|---|
| `visible` | [Int] | Indices of segments shown, ascending |
| `hidden` | Range<Int>? | Collapsed middle segments shown as "…" (between `visible[0]` and the next) |
| `lastWidth` | Double? | Width allowed for the last segment when it must be truncated; nil = natural width |

Invariants: `visible.first == 0` and `visible.last == widths.count - 1` (for a non-empty trail);
`hidden` never contains 0 or the last index; only the last segment may be truncated.

## Path bar settings (UserDefaults)

| Key | Type | Default | Meaning |
|---|---|---|---|
| `pathBar.style` | String | `breadcrumbs` | `breadcrumbs` or `text` |
| `pathBar.showIcons` | Bool | true | Icons in segments |

## Command

| Command | Title | Menu | Default chord |
|---|---|---|---|
| `editPath` | Edit Path | Go | ⌘L |
