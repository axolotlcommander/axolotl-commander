# Contract: Size Settings and Panel Display

## Settings → Appearance

A new row below "Path bar", with two pickers:

| Label | Choices (tag) | Default |
|---|---|---|
| Size in panels: | Like Finder (kB, MB, GB) (`finder`) · In bytes (`bytes`) | Like Finder |
| Units: | 1000 (like Finder) (`decimal`) · 1024 (like Windows) (`binary`) | 1000 |

Both take effect at once (no Apply button) and persist.

Czech:
- "Velikost v panelech:", "Jako ve Finderu (kB, MB, GB)", "V bajtech";
- "Jednotky:", "1000 (jako Finder)", "1024 (jako Windows)".

## Size column cell

| Item | Like Finder | In bytes | Tooltip |
|---|---|---|---|
| file | rounded, else "…" | exact, else rounded, else "…" | exact bytes when the text is not exact |
| folder with calculated size | as a file | as a file | as a file |
| folder (not calculated) | `<DIR>` | `<DIR>` | none |
| package (not calculated) | `—` | `—` | none |
| `..`, servers in Network | empty | empty | none |

Alignment: right. Sorting is by exact bytes.

## Status bar

| Situation | Text |
|---|---|
| cursor on a file or a calculated folder | `name   4,1 MB (4 100 000 bytes)   date` |
| the same, when the rounded text is exact | `name   402 bytes   date` |
| marked items | `Selected N files, M folders — <rounded>` (unchanged, base from Units) |
| nothing marked | `N files, M folders — <rounded>` (unchanged, base from Units) |

## Elsewhere

Every rounded size the app shows uses the Units base the next time it is shown:
- the volume bar tooltip and volume info;
- operation conflicts;
- Properties;
- Compare;
- Disk Usage;
- the viewer notice.

Exact counts with grouping do not change.
