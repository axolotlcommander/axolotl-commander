# Research: Data Safety (001)

Facts from the code (file:line) established on 2026-10-08 on the `001-data-safety-gaps` branch.

## R1 — Overwriting on a Server (D1, FR-001–004)

- **Facts**: `RemoteTransfer.swift:132-134` calls `removeFile(final)` and then
  `rename(temp → final)` in a single `perform`; on error `:137` it also deletes the temp file. The same in `renameOnServer` `:377-379`.
  After `.disconnected`, `RemoteConnections.perform` repeats the entire closure (`RemoteConnections.swift:106-117`).
  The SFTP client is custom (`SFTPClient.swift`); `rename` `:580-583` rejects an existing target,
  server extensions are in `extensions` (`:57`), a pattern for an extended request is at `:149`. FTP `FTPClient.swift:193-199`
  rejects an existing target before RNFR/RNTO.
- **Decision**: Add `replace(_ from:, over to:) async throws -> Bool` to `RemoteFileSystem`
  (default `false` = cannot do it, nothing changed). SFTP: `posix-rename@openssh.com` when the server
  advertises it. FTP: RNFR/RNTO without a prior check, 5xx → `false` (a failed RNTO changes nothing).
  `RemoteTransfer.placeReplacing`: (1) `replace`; (2) otherwise `final → backup` (a hidden name in the same
  folder); (3) `temp → final`, on error restore the backup; (4) delete the backup (failure = a warning).
  Each step is a separate `perform` (a retry after a disconnect must not repeat a delete), in a detached
  `Task` (canceling does not interrupt the replace midway). A new error `RemoteError.replaceIncomplete(target:,
  newAt:, oldAt:)` for the case when the backup cannot be restored.
- **Rationale**: An atomic replace where the server supports it; otherwise a sequence in which a complete
  version exists under a known name at every moment (FR-003).
- **Alternatives considered**: Upload straight over the target (STOR over an existing file) — an interruption leaves a
  half-written file; rejected. Delete the target only after the upload (the current state) — a window with no version; rejected.

## R2 — Archive Member Edits (D2, FR-005–009, FR-027)

- **Facts**: `AppDelegate.swift:33-44`, after `offerChanges`, always quits and `applicationWillTerminate`
  calls `ArchiveScratch.removeAll()` (temp `Axolotl-<UUID>`). `ArchiveEdits`
  (`ArchiveOperations.swift:44-150`) is in memory only; "Not Now" (`:118-121`) overwrites `stamp`, so the
  copy looks unchanged and gets deleted. Writing back (`ArchiveWriter.update`, `ArchiveWriter.swift:41`)
  does not verify that the archive has not changed in the meantime.
- **Decision**: New `CommanderCore/Archive/ArchiveEditStore.swift` (testable, `init(root:)`).
  Copies for F4 are extracted into `~/Library/Application Support/Axolotl Commander/Edits/<id>/`,
  the list is in `manifest.json` (written via `SafeFileWriter`). The store decides what is changed, what to
  keep, what to clean up; "Not Now" = `decline` (it stays and is offered at startup). Writing back verifies the
  archive's `PersistentFileStamp` (volume UUID + file id + size + mtime) and otherwise refuses
  (`ArchiveError.changedSinceRead`). The UI keeps only alerts and calls to the writer/upload.
- **Rationale**: The system may clean up a temp folder; Application Support survives a restart. Logic
  in the core satisfies principle IV and FR-027.
- **Alternatives considered**: Only warn on quit (without keeping) — work would still be lost on a write
  error; rejected. Block quitting — it holds the user up and does not help on a crash; rejected.

## R3 — Archive Into Itself and Packing Into Its Own Source (D3, D7, FR-010–012)

- **Facts**: `ArchiveOperations.swift:285` compares `standardizedFileURL` (text). Then `:320`
  adds and `:327` `update(removing:)` removes everything under the source. `pack` (`:415-444`) and F5/F6 into an archive
  (`addToArchive`, `source == nil`) do not check whether the archive lies among the sources / inside a source.
  `FileIdentity.of(_:followingLinks:)` (`Operations/FileIdentity.swift:9-26`),
  `TransferPlanner.ancestorIdentities(of:)` (`TransferPlan.swift:211`).
- **Decision**: Core `ArchiveTransferCheck` with two functions: `validate(source:names:target:)`
  (archive sameness by `FileIdentity`, unknown → `.identityUnknown`) and
  `validatePack(archive:sources:)` (archive among the sources, or a source folder among the archive's ancestors →
  `.intoItself`). Called before any write in `addToArchive` and `pack`.
- **Rationale**: The same identity rule as for local operations (05-pravidla, Identity).
- **Alternatives considered**: A `realpath` comparison — does not handle hard links or letter case on all volumes;
  rejected.
- **Side finding (out of scope)**: `ArchiveCatalog.invalidate` keyed by URL — a panel with a symlinked
  path may have a stale listing. Record in STATE.

## R4 — Deleting Without a Trash (D4, FR-013–016)

- **Facts**: `FileOperations.trash` (`FileOperations.swift:53-67`) throws `.io` on the first error
  and the preceding items are already in the Trash with no report. UI `OperationsController.delete`
  (`OperationsController.swift:163-196`), another caller `FindWindowController.swift:624`.
  There is no "volume has a Trash" key in the SDK; `FileManager.url(for: .trashDirectory, in: .userDomainMask,
  appropriateFor: url, create: false)` returns `~/.Trash` on the home volume and error 3328 on volumes
  without a Trash (verified on a DMG, Time Machine, devfs).
- **Decision**: `TrashSupport.isAvailable(_:)` via this query (cached per volume for the duration of a single
  operation). `FileOperations.planDelete(_:) -> DeletePlan { toTrash, permanent }`; `trash` returns
  `TrashReport { trashed, failed, notAttempted }` instead of throwing midway. Seams in
  `FileOperations.Options`: `trashAvailable`, `trashItem` — tests never touch the real Trash.
  UI: when `permanent` is non-empty, a single critical prompt with a list, default "Cancel"; after
  confirmation the Trash goes first, if it fails the permanent deletion is not performed and a report is shown.
- **Rationale**: Behaves like Finder ("The item will be deleted immediately"), the decision is made before the first change.
- **Alternatives considered**: Try the Trash and ask on error — the batch is already half done; rejected.
- **Manual verification (read-only)**: a USB FAT volume and an SMB volume — whether the query returns an error (quickstart).

## R5 — Identity on a Volume Without Reliable IDs (D5, FR-017–019)

- **Facts**: `FileStat.init` (`FileIdentity.swift:37-44`) = `st_dev` + `st_ino`, `ino == 0` → nil.
  `TransferPlanner.plan` (`TransferPlan.swift:166-177`), `validateNested` (`:197-201`),
  `TransferRun.resolve` (`:237-239`); `deleteSource` re-verifies identity (`:205-216`).
- **Decision**: `VolumeTraits { identityReliable, uuid }` based on `statfs.f_fstypename`; reliable only
  `apfs` and `hfs` (allowlist), all others (msdos, exfat, smbfs, afpfs, nfs, webdav, ntfs, fuse, unknown)
  unreliable. `FileIdentity` = (`st_dev`, `st_ino`) only within a single mount (document it:
  do not persist); what is persisted (R2) uses `PersistentFileStamp` with the volume UUID. On an unreliable volume:
  existing target + an operation that deletes the source (move, overwrite during a move) → `.identityUnknown`; copy
  and move to a nonexistent name pass.
- **Rationale**: The reference's rule is explicit: "An operation that would delete the source if the identities match is rejected."
- **Tradeoff**: A move that overwrites an existing file on SMB/FAT is rejected; the user can
  copy and then delete. Accepted (safety takes precedence, principle I).
- **Alternatives considered**: Trust `st_ino` on all volumes (the current state) — FAT/SMB ids may be
  synthetic; rejected.

## R6 — "Save As" in the Viewer (D6, FR-020–022)

- **Facts**: `ViewerWindowController.saveCopy()` (`:843-867`) writes via `Data.write(.atomic)`
  (`:863`) — it replaces a symlink and loses attributes. `saveImage()` already goes through `ImageExport` →
  `SafeFileWriter.write(to:_:)` (`SafeFileWriter.swift:12`, resolves a symlink, temp in the same folder,
  `replaceItemAt` preserves permissions/labels).
- **Decision**: `:863` → `SafeFileWriter.write(to: url) { try payload.write(to: $0) }`. Tests add
  labels, xattr, and temp cleanup on error.
- **Alternatives considered**: Copying attributes ourselves — duplicates SafeFileWriter; rejected.

## R7 — Renaming Onto Another Hard Link (D8, FR-023–024)

- **Facts**: `FileOperations.rename` (`:153-180`): source identity == identity of the existing `b.txt`
  → `Darwin.rename` (`:169`), which for two links to the same inode returns 0 and does nothing.
- **Decision**: When the identities match and `st_nlink > 1`, go through the parent's listing: if there is another entry
  (different `unicodeScalars` than the source) with a name the volume considers the same as the new one →
  `.alreadyExists`. Add `linkCount` to `FileStat`. A change of only letter case / NFC↔NFD of the same
  entry passes.

## R8 — Tests of Existing Safeguards (FR-026)

- **A lone symlink to a directory**: on the same volume a rename (the link is moved). Via `forceCopyMove`
  the source currently stays in `keptSources` (`TransferPlan.swift:77,84`, `TransferRun.swift:197`).
  **Decision**: for an item of the symlink kind (the link itself, not its contents), after copying allow `unlink`
  of the link — it deletes nothing behind it (05-pravidla, Move and Link). Test both cases.
- **Incomplete traversal**: a `chmod 000` subfolder in the sandbox (restored in `defer`), a move with `forceCopyMove`
  → the source in `keptSources`.
- **Code units**: compare `Array(name.unicodeScalars)`, not `==` (canonical equivalence).
- **Shared helpers**: `Tests/CommanderCoreTests/TestSupport.swift` (`withSandbox`, write/read,
  fake volumes/Trash) — currently every test file has its own.
