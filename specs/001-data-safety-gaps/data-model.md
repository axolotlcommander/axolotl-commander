# Data Model: Data Safety (001)

## FileIdentity (changed)

| Field | Type | Note |
|---|---|---|
| device | Int64 | `st_dev` — valid only while the volume is mounted |
| inode | UInt64 | `st_ino`; 0 → identity unknown (`nil`) |
| reliable | Bool | from `VolumeTraits.identityReliable` |

- Equality of two identities means "the same file" only when both are `reliable`; otherwise an
  operation that deletes the source over an existing target → `OperationError.identityUnknown`.
- Never persisted (neither across launches nor across a volume being unmounted).

## VolumeTraits (new)

| Field | Type | Note |
|---|---|---|
| identityReliable | Bool | `apfs`, `hfs` → true; other types → false |
| uuid | String? | `URLResourceKey.volumeUUIDStringKey` |
| trashAvailable | Bool | `FileManager.url(for: .trashDirectory, …, appropriateFor:, create: false)` succeeds |

Cached by `st_dev` for the duration of a single operation only.

## PersistentFileStamp (new)

| Field | Type | Note |
|---|---|---|
| volumeUUID | String? | volume identity across unmounts |
| fileID | UInt64 | `fileIdentifierKey` / `st_ino` |
| size | Int64 | |
| modified | Int64 | mtime in ns |

All fields matching = "the archive has not changed since extraction" (FR-009). Codable.

## PendingEdit (new, `ArchiveEditStore`)

| Field | Type | Note |
|---|---|---|
| id | UUID | name of the subfolder in `Edits/` |
| target | enum `member(archive: URL, path: String)` / `server(location)` | where it is written back to |
| copyRelPath | String | relative to `Edits/<id>/` |
| baseline | FileStamp | size + mtime of the copy after extraction / the last save |
| archiveStamp | PersistentFileStamp? | state of the archive at extraction (`member` only) |
| declined | Bool | the user chose "Not Now" — the copy must not be cleaned up |

**States**: `extracted` (copy = baseline) → `changed` (copy ≠ baseline) →
`saved` (written back; baseline := copy, archiveStamp := new) | `declined` (keep, offer
at startup) | `discarded` (delete both the copy and the record). On quit: `extracted`/`saved` with no
further changes → clean up; `changed`/`declined` → keep. On startup: a record without a copy → discard;
`changed`/`declined` → offer.

**Storage**: `~/Library/Application Support/Axolotl Commander/Edits/manifest.json` (an array of
`PendingEdit`), written via `SafeFileWriter`. In tests, a custom `root` in a sandbox.

## DeletePlan / TrashReport (new)

| Type | Fields |
|---|---|
| DeletePlan | `toTrash: [URL]`, `permanent: [URL]` (volume without a Trash) |
| TrashReport | `trashed: [(original: URL, inTrash: URL)]`, `failed: (URL, String)?`, `notAttempted: [URL]` |

Rule: `permanent` is deleted only after confirmation; when the Trash step fails in the same batch
(`failed != nil`), `permanent` is not performed.

## Errors (extended)

| Enum | New case | When |
|---|---|---|
| RemoteError | `replaceIncomplete(target:, newAt:, oldAt:)` | the replace on the server failed and the backup could not be restored |
| ArchiveError | `changedSinceRead(URL)` | the archive changed/disappeared between extraction and write-back |
| OperationError | (unchanged) `intoItself`, `identityUnknown`, `alreadyExists` | D3, D5, D7, D8 |
