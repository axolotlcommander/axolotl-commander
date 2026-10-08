# Data Model: Link Commands

## LinkKind

`symbolic` | `hard`.

## LinkError (core, `Error`, `Equatable`)

| Case | Meaning | Spec |
|---|---|---|
| `folderNotAllowed(URL)` | Hard link to a folder or package | FR-010 |
| `symbolicLinkNotAllowed(URL)` | Hard link to a symbolic link | FR-010 |
| `differentVolume(URL)` | Hard link destination on another volume | FR-010 |
| `notASymbolicLink(URL)` | Edit target is not (or no longer) a symbolic link | FR-011, FR-013 |
| `targetMissing(stored: String)` | Go to Link Target: the final item does not exist | FR-019 |
| `loop(URL)` | More than 32 link steps | FR-019 |

Name conflicts, invalid names and system errors reuse `OperationError` (`alreadyExists`,
`invalidName`, `path(.notFound)`, `io(text)`).

## LinkOutcome (core)

Per source item of a batch (several items, paste):

- `source: URL`
- `result`: `.created(URL)` | `.skipped(any Error)` (the reason: `alreadyExists`,
  `folderNotAllowed`, `symbolicLinkNotAllowed`, `differentVolume` or a system error)

Batches never stop at the first problem; every source gets an outcome (FR-024).

## LinkPaths (core, pure)

- `relativePath(from folder: String, to target: String) -> String`
- `storedTarget(typed: String, linkFolder: String, relative: Bool) -> String`
- `isRelative(_ stored: String) -> Bool`
- `absolute(_ stored: String, linkFolder: String) -> String` (for toggling in Edit, FR-012, and
  for the existence check, FR-007)

## Link sheet input (UI)

| Field | One item | Several items | Edit |
|---|---|---|---|
| Target | editable (symbolic) / read-only (hard), absolute path of the item | — | stored target, editable |
| Link name | full path, prefilled other panel's folder + name | — | — (name fixed) |
| Destination folder | — | prefilled other panel's folder | — |
| Relative path | symbolic only, remembered | symbolic only, remembered | reflects the stored target |
| Inline message | conflict / invalid name / missing folder | missing folder | invalid target |

## Settings

UserDefaults `links.relativePath` (Bool, default false), shared by New Symbolic Link and Edit
Symbolic Link (FR-005).
