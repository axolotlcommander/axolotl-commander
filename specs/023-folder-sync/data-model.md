# Data Model: Synchronize Folders

All types are in `Sources/CommanderCore/Sync/` (no AppKit) and `Sendable`.

## SyncOptions (Codable, persisted as `syncOptions`)

| Field | Type | Default |
|---|---|---|
| includeSubfolders | Bool | true |
| compareDate | Bool | true |
| ignoreHourDifference | Bool | true |
| compareSize | Bool | true |
| compareContent | Bool | false |
| ignoreFiles | String? | nil |
| ignoreFolders | String? | nil |
| direction | `SyncDirection` (`bothWays`, `leftToRight`, `rightToLeft`) | bothWays |
| deleteMissing | Bool | false (effective only when direction ≠ bothWays) |

`dateTolerance` is a constant 2 s. Decoding uses `decodeIfPresent` for every field.

## SyncSide (what one side holds for an item)

- `kind`: `file`, `folder`, `link(target: String)`
- `size: Int64` (file: its size; folder: total of the files inside when the item is one-sided, else 0)
- `fileCount: Int` (folder: files inside when one-sided; 1 for a file or link)
- `modified: Date?`

## SyncState

`onlyLeft`, `onlyRight`, `equal`, `leftNewer`, `rightNewer`, `different`, `error(String)`.

## SyncAction

`none`, `toRight` ("make the right side like the left"), `toLeft`. What it does follows from the sides:

| Action | Source side has it | Target side has it | Effect |
|---|---|---|---|
| toRight | yes | no | copy left → right |
| toRight | yes | yes, same kind | overwrite right |
| toRight | yes | yes, other kind | right to the Trash, then copy (replacement) |
| toRight | no | yes | right to the Trash (deletion, ✕) |

`toLeft` is the mirror image. Shown as → / ← for copies and replacements, ✕ on the target column for
deletions, = for `none` on an equal item, ≠ for `none` on a differing item, nothing for `none` on a
one-sided item.

## SyncItem

- `path: String` (relative, "/"-separated, original spelling of the left side when present), `depth: Int`
- `left: SyncSide?`, `right: SyncSide?`, `state: SyncState`
- `defaultAction: SyncAction`, `action: SyncAction`, `excluded: Bool`

Rules (`SyncRules`):
- `defaultAction(state:, options:)` per FR-011.
- `possible(_ item:, options:) -> [SyncAction]`: `none` always; `toRight` when left exists, or when left is
  missing and `deleteMissing` is on with direction `leftToRight`; `toLeft` mirrored; error rows only `none`.
- `set(_ action:, on items:)` changes only items where it is possible and returns the ones it could not
  change (the UI beeps). `toggleExcluded` flips `excluded` and keeps `action`.

## SyncComparison

`left: URL`, `right: URL`, `options: SyncOptions`, `rules: NameRules`, `items: [SyncItem]` sorted by path
(`NameRules.order` per component, a folder before its contents).

## SyncPlan (from a comparison, excluded and `none` left out)

- `copies(to: .right/.left) -> [SyncItem]`, `replacements(on:)`, `deletions(on:)`
- `files(to:)`, `bytes(to:)` (sum of source sizes, folders by their totals), `deletionCount`
- `summary` texts for the confirmation and the summary line.

## SyncGuard

`check(left:, right:) -> SyncRefusal?` with `.same`, `.nested(inner: URL)`; compares resolved,
standardized paths by components (case-insensitive unless both volumes are case-sensitive).

## SyncCheck

`unchanged(_ item:, left:, right:) -> Bool`: both sides still exist as compared (kind, size, date within
1 ms, link target); a side compared as missing must still be missing.

## SyncRunReport

`copied: Int`, `trashed: Int`, `skipped: [(path, reason)]` (changed since comparing, no Trash, conflicts the
plan did not expect), `failed: [(path, reason)]`.
