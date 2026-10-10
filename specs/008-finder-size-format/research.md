# Research: File Sizes Like Finder

## R1 — What "Like Finder" means

**Decision**: the system's file byte count style (`ByteCountFormatStyle(style: .file)`) for the
current locale. The 1024 base uses `style: .binary`.

**Rationale**: Finder formats sizes with the same system formatter, so the panel matches Finder
without hard-coded unit tables. The app already uses it for its rounded sizes (`Format.bytes`).

Sample output on macOS 26, measured on 2026-10-10:

| Bytes | en_US, 1000 | en_US, 1024 | cs_CZ, 1000 | cs_CZ, 1024 |
|---|---|---|---|---|
| 0 | Zero kB | Zero kB | 0 kB | 0 kB |
| 1 | 1 byte | 1 byte | 1 bajt | 1 bajt |
| 402 | 402 bytes | 402 bytes | 402 bajtů | 402 bajtů |
| 999 | 1 kB | 999 bytes | 1 kB | 999 bajtů |
| 1 000 | 1 kB | 1,000 bytes | 1 kB | 1 000 bajtů |
| 1 024 | 1 kB | 1 kB | 1 kB | 1 kB |
| 4 300 000 | 4.3 MB | 4.1 MB | 4,3 MB | 4,1 MB |
| 1.2 × 10¹² | 1.2 TB | 1.09 TB | 1,2 TB | 1,09 TB |

The binary style writes "kB", not "KB" or "KiB". This is why the setting names the base
("1000 (like Finder)", "1024 (like Windows)"), as the spec says.

**Alternatives considered**:
- Our own unit table: rejected, because it would drift from Finder and would need its own
  translations.
- `ByteCountFormatter` with `.memory`: it gives the same results as `.binary`. `.binary` names
  the intent.

## R2 — Where the settings live

**Decision**: two `UserDefaults` string keys, `size.display` (`finder` | `bytes`) and
`size.units` (`decimal` | `binary`).
- A missing key means the default (`finder`, `decimal`).
- The keys are bound in Settings → Appearance with `@AppStorage`, like the path bar settings
  (`pathBar.style`).
- The pure types and formatting live in the core. The UI reads the saved values through a small
  `SizeSettings` helper.

**Rationale**: this is the same pattern as `PathBar.styleKey` / `savedStyle` and the volume bar
settings. Panels already observe `UserDefaults.didChangeNotification` for the path bar. Plain keys
keep the defaults readable and need no migration: an existing installation without the keys gets
the defaults, as FR-001 asks.

**Alternatives considered**:
- A field in `AppSettings.appearance` (JSON): rejected. `PanelAppearance` is Codable JSON, a new
  field needs decoding defaults, and every change of the selection color would rewrite it too.

## R3 — One formatter for every rounded size (FR-008)

**Decision**: `Format.bytes(_:)` (UI, `Support.swift`) formats with the saved units base. It
calls the core function `SizeFormat.rounded(_:units:locale:)`.

**Rationale**: every rounded size in the app goes through `Format.bytes`: status bars, the volume
bar, volume info, operation conflicts, Properties, Compare, Disk Usage, the viewer's notice. One
change covers all of FR-008. Exact counts go through `Format.grouped`, which stays unchanged
(FR-008, last sentence).

**Alternatives considered**:
- Passing the base to every call site: rejected. It means about 20 edits for no gain.

## R4 — Column text and the narrow-column fallback (FR-002, FR-003, FR-005)

**Decision**: the `CellText.size` variants take the display mode and the units base:

| Mode | Variants, longest first |
|---|---|
| `bytes` | exact grouped, then rounded |
| `finder` | rounded only |

`CellText.fitting` already falls back to "…". The tooltip shows the exact grouped bytes whenever
the shown text is not the exact value. This replaces 0.2.2's rule "tooltip = first variant": in
`finder` mode the first variant is already rounded.

**Rationale**: this keeps 0.2.2's guarantee that no number is ever cut (SC-004). The cell view
already re-fits on width changes.

## R5 — Exact bytes in the status bar (FR-004)

**Finding**: the status line for the item under the cursor shows `Format.bytes` today, which is
rounded, not exact.

**Decision**: when the rounded text is not already the exact count (sizes of 1 000 bytes and more
in the 1000 base), the line shows both: "4,1 MB (4 100 000 bytes)". It reuses the existing
localized pattern `"%@ (%@ bytes)"` from Properties. A calculated folder size is shown the same
way. The selection and folder totals stay rounded only, because they are sums.

**Rationale**: the exact count is one glance away in both modes (SC-003). The Brief view, which
has no Size column, benefits too.

## R6 — Live update (FR-006, FR-010, SC-002)

**Decision**: `PanelViewController` remembers the size settings it last applied. On
`UserDefaults.didChangeNotification` it compares them with the saved values. When they differ, it:
- reloads only the Size column of all rows (`reloadData(forRowIndexes:columnIndexes:)`), which
  keeps the selection, cursor and scroll position;
- refreshes the status line.

Tabs share the panel's table, so the next tab switch reloads it anyway. Other windows read
`Format.bytes` when they next show a value (FR-010).

## R7 — Initial width of the Size column (FR-012)

**Decision**: `Column.sizeWidth` becomes the widest bold text of the current mode, over a fixed
set of sample values:
- `bytes` mode: 999 999 999 999 grouped, as today;
- `finder` mode: rounded values in both bases, e.g. 999 bytes, 1 023 bytes, 999.9 kB … 999.9 TB.

It is computed when a panel is created. The saved column widths still win, so an existing user
keeps their width; a narrow width falls back as in R4.

## R8 — Version

The feature changes behavior and adds settings, so it is a **minor** bump: 0.2.2 → 0.3.0
(`scripts/bump-version.sh minor`). The CHANGELOG states that the panels now show Finder-style
sizes by default, and how to get exact bytes back.
