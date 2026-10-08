---
description: "Task list: Data Safety — Gaps from the Audit (D1–D8)"
---

# Tasks: Data Safety — Gaps from the Audit (D1–D8)

**Input**: `specs/001-data-safety-gaps/` — [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md), [contracts/core-api.md](contracts/core-api.md),
[quickstart.md](quickstart.md)

**Tests**: REQUIRED (FR-025, constitution IV). In every story, first a test that fails, then the fix.
Tests only in a sandbox (`FileManager.default.temporaryDirectory`), fake Trash/volumes, local servers.

**Conventions**: a new file starts with the SPDX header (`// SPDX-License-Identifier: GPL-3.0-or-later`
+ `// Copyright (C) 2026 The Axolotl Commander Authors`); do not read the reference's C++ sources; after each
story `swift build` without warnings, `swift test` green, commit `[Spec 001] USn …`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can be done in parallel (different file, no dependency on an unfinished task)
- **[Story]**: US1–US8 from spec.md

---

## Phase 1: Setup

- [X] T001 Create `Tests/CommanderCoreTests/TestSupport.swift`: shared `withSandbox(_:)` (creates and cleans up a folder in `temporaryDirectory`), `write(_:_:)`, `read(_:)`, `names(in:)`; keep the existing private variants in the test files (unify only where the file is being changed anyway)

---

## Phase 2: Foundational (blocks US2, US5, US7)

- [X] T002 In `Sources/CommanderCore/Operations/FileIdentity.swift` add `linkCount` to `FileStat` (from `st_nlink`) and a doc comment on `FileIdentity`: "valid only during a single mount of the volume, never persist"
- [X] T003 In `Sources/CommanderCore/Operations/FileIdentity.swift` add `public struct VolumeTraits: Sendable, Equatable { identityReliable: Bool; uuid: String? }` and `static func of(_ url: URL) -> VolumeTraits` based on `statfs.f_fstypename` — `apfs`, `hfs` → reliable; everything else (msdos, exfat, smbfs, afpfs, nfs, webdav, ntfs, fuse, unknown) → unreliable; `uuid` from `URLResourceKey.volumeUUIDStringKey`
- [X] T004 In `Sources/CommanderCore/Operations/FileIdentity.swift` add `public struct PersistentFileStamp: Codable, Sendable, Equatable { volumeUUID: String?; fileID: UInt64; size: Int64; modified: Int64 /* mtime ns */ }` + `init?(_ url: URL)`
- [X] T005 [P] Tests for T002–T004 in `Tests/CommanderCoreTests/FileIdentityTests.swift` (new): `linkCount == 2` after `link(2)`, a sandbox on APFS → `identityReliable`, `PersistentFileStamp` changes after a write and is a Codable round trip

---

## Phase 3: User Story 1 — Overwriting on a Server Does Not Destroy the Old Version (P1) 🎯 MVP

**Goal**: FR-001–004. **Independent Test**: the fake server fails in the replace → the target has the old content or the message says where each version is.

### Tests (first, must fail)

- [X] T006 [US1] Extend the fake `DirectoryFileSystem` in `Tests/CommanderCoreTests/RemoteTransferTests.swift:10-84` with an `atomicReplace` switch (replace via `rename(2)`), error injection `failRename(from:to:times:)`, and a call log
- [X] T007 [US1] Tests in `Tests/CommanderCoreTests/RemoteTransferTests.swift`: (a) atomic overwrite — no `removeFile(final)` in the log; (b) without an atomic replace `temp→final` fails → the target has the old content, neither temp nor backup remains; (c) both the replace and the backup restore fail → `RemoteError.replaceIncomplete` carries `newAt`/`oldAt` and the contents at those names are correct; (d) an upload failing halfway (`failUploads`) → old content, no temp; (e) cancellation during the upload → the same; (f) `renameOnServer` with overwrite — the same invariants
- [X] T008 [P] [US1] Test in `Tests/CommanderCoreTests/SFTPTests.swift` against the local `/usr/libexec/sftp-server` (pattern `SFTPTests.swift:22-37`): `replace(_:over:)` returns `true` and overwrites the target
- [X] T009 [P] [US1] Test in `Tests/CommanderCoreTests/FTPTests.swift` against `scripts/ftp-test-server.py` (RNTO onto an existing file → 553): `replace` returns `false`, both files unchanged

### Implementation

- [X] T010 [US1] In `Sources/CommanderCore/Network/RemoteFileSystem.swift:113-133` add `func replace(_ from: String, over to: String) async throws -> Bool` to the protocol with a default implementation in an extension returning `false`; add `case replaceIncomplete(target: String, newAt: String, oldAt: String)` with a description to `RemoteError` (`:79-94`)
- [X] T011 [P] [US1] In `Sources/CommanderCore/Network/SFTP/SFTPClient.swift` implement `replace` via the extended request `posix-rename@openssh.com` (when it is in `extensions`, `:57`/`:146`; pattern `:149`), otherwise `false`
- [X] T012 [P] [US1] In `Sources/CommanderCore/Network/FTP/FTPClient.swift` implement `replace`: RNFR/RNTO without the pre-check from `:193-199`; success + `info(from) == nil` → `true`; a 5xx reply → `false`
- [X] T013 [US1] In `Sources/CommanderCore/Network/RemoteTransfer.swift` add a private `placeReplacing(temp:final:endpoint:)` per research R1 (replace → `final→".\(name).axo-old-<uuid>"` → `temp→final` with backup restore → delete the backup, failure = a warning); each step a separate `connections.perform`, the whole thing in a detached `Task` (cancellation does not interrupt the replace)
- [X] T014 [US1] Replace `RemoteTransfer.swift:131-138` (upload with overwrite) and `:377-379` (`renameOnServer` with overwrite) with a call to `placeReplacing`
- [X] T015 [US1] Add the text for `RemoteError.replaceIncomplete` to `OperationsController.describe` (`Sources/AxolotlCommander/OperationsController.swift:296`) and to `Resources/Localizable.xcstrings` (cs)

**Checkpoint**: `swift test --filter RemoteTransferTests|SFTPTests|FTPTests` green → commit.

---

## Phase 4: User Story 2 — Unsaved Archive Member Edits Survive Quitting (P1)

**Goal**: FR-005–009, FR-027. **Independent Test**: a store over a sandbox root; decline → a new store instance returns it.

### Tests

- [X] T016 [US2] `Tests/CommanderCoreTests/ArchiveEditStoreTests.swift` (new): (a) an unchanged copy → `cleanupForQuit` deletes it; (b) a changed copy → kept, a new `ArchiveEditStore(root:)` instance over the same root returns it from `loadPending`; (c) `decline` → kept even after `cleanupForQuit`; (d) `markSaved` + no further changes → cleaned up; (e) `discard` deletes both the copy and the record; (f) the archive overwritten/deleted after extraction → `verifyArchiveUnchanged` throws `ArchiveError.changedSinceRead`, the copy stays; (g) a record without a copy is discarded in `loadPending`
- [X] T017 [P] [US2] Test in `Tests/CommanderCoreTests/ArchiveTests.swift`: `ArchiveWriter.update(..., expecting:)` with a mismatched `PersistentFileStamp` → `changedSinceRead`, archive unchanged

### Implementation

- [X] T018 [US2] Add `case changedSinceRead(URL)` to `ArchiveError` (`Sources/CommanderCore/Archive/ArchiveFormat.swift:42-55`) with a description
- [X] T019 [US2] New `Sources/CommanderCore/Archive/ArchiveEditStore.swift` per `contracts/core-api.md` and `data-model.md` (PendingEdit: id, target `member(archive:path:)`/`server(...)`, copyRelPath, baseline FileStamp, archiveStamp `PersistentFileStamp?`, declined); manifest `root/manifest.json` via `SafeFileWriter`; `defaultRoot = ~/Library/Application Support/Axolotl Commander/Edits`; threading: `Mutex` or actor
- [X] T020 [US2] `ArchiveWriter.update(_:adding:expecting: PersistentFileStamp? = nil)` in `Sources/CommanderCore/Archive/ArchiveWriter.swift:41` (check after `stat` in `updateArchive`, `:94-95`)
- [X] T021 [US2] In `Sources/AxolotlCommander/ArchiveOperations.swift:44-150` rework `ArchiveEdits` into a thin layer over `ArchiveEditStore` (F4 copies into the store, F3 copies still into `ArchiveScratch`); "Not Now" (`:118-121`) → `decline`; a write error (`:138-145`) → the copy stays + a message with the path; `verifyArchiveUnchanged` before writing
- [X] T022 [US2] In `Sources/AxolotlCommander/AppDelegate.swift:33-44`: quit → `cleanupForQuit`, kept edits → an informational message with the path to the copies; `ArchiveScratch.removeAll()` now deletes only temp; at startup (`applicationDidFinishLaunching`) a non-empty `loadPending` → a single overview (Save Back / Not Now / Discard…); texts to `Resources/Localizable.xcstrings` (cs)

**Checkpoint**: `swift test --filter ArchiveEditStoreTests|ArchiveTests` green → commit.

---

## Phase 5: User Story 3 — Archive Operations Do Not Loop Into Themselves (P1)

**Goal**: FR-010–012. **Independent Test**: a ZIP via a symlink + directly; moving `docs`→`docs/old` → rejected, archive bytes unchanged.

### Tests

- [X] T023 [US3] `Tests/CommanderCoreTests/ArchiveTransferCheckTests.swift` (new): a ZIP in a sandbox (`ArchiveWriter.create`), a symlink to it and a path with different letter case → `validate(source:names:target:)` with `target.inner = "docs/old"` throws `.intoItself`; a different archive → passes; `validatePack`: source `projekt` + archive `projekt/zaloha.zip` → `.intoItself`; archive among the sources → `.intoItself`; unrelated → passes; in all rejections the bytes of the archive and the sources are unchanged

### Implementation

- [X] T024 [US3] New `Sources/CommanderCore/Archive/ArchiveTransferCheck.swift`: `validate` (archive sameness via `FileIdentity.of`, nil → `.identityUnknown`; member `target.inner == m || hasPrefix(m + "/")`), `validatePack` (the archive's identity among the sources' identities; the source folder's identity in `TransferPlanner.ancestorIdentities(of: archive.deletingLastPathComponent())`, `TransferPlan.swift:211`, make it internal/public as needed)
- [X] T025 [US3] In `Sources/AxolotlCommander/ArchiveOperations.swift` call `validate` instead of `:285-288` in `addToArchive` and `validatePack` in `pack` (`:415-444`) before `create` and before `addToArchive(from: nil)`; show the error via `report`

**Checkpoint**: green → commit.

---

## Phase 6: User Story 4 — Deleting on a Volume Without a Trash Is Deliberate (P2)

**Goal**: FR-013–016. **Independent Test**: a fake Trash predicate; the plan splits the selection; a failure midway → report, nothing permanently deleted.

### Tests

- [X] T026 [US4] `Tests/CommanderCoreTests/DeletePlanTests.swift` (new) via `FileOperations(options:)` with `trashAvailable` (fake based on a sandbox subfolder) and `trashItem` (move to `sandbox/Trash`, failure on the Nth item): (a) `planDelete` splits `toTrash`/`permanent`; (b) a failure on the 2nd item → `TrashReport.trashed` = the 1st, `failed` = the 2nd, `notAttempted` = the rest, nothing permanently deleted; (c) everything succeeds → `failed == nil`

### Implementation

- [X] T027 [US4] New `Sources/CommanderCore/Operations/TrashSupport.swift`: `isAvailable(_ url: URL) -> Bool` via `FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)` (error → false)
- [X] T028 [US4] In `Sources/CommanderCore/FileOperations.swift`: add `trashAvailable: @Sendable (URL) -> Bool` (default `TrashSupport.isAvailable`) and `trashItem: @Sendable (URL) throws -> URL` (default `FileManager.trashItem`) to `Options` (`:12-17`); add `planDelete(_:) -> DeletePlan`; change `trash(_:)` (`:53-67`) to `async -> TrashReport` (no throwing midway)
- [X] T029 [US4] In `Sources/AxolotlCommander/OperationsController.swift:163-196` (F8): `planDelete` → if `permanent` is non-empty, a single critical prompt with a list ("These items will be deleted permanently and cannot be restored"), buttons "Delete Permanently" / "Cancel" (default Cancel) → `trash(toTrash)` → permanent deletion of `permanent` only when `failed == nil` → report (what is in the Trash, what remained)
- [X] T030 [P] [US4] Update the caller `Sources/AxolotlCommander/Find/FindWindowController.swift:624` to the new API (the same prompt flow as T029, a shared function in `OperationsController`)
- [X] T031 [US4] Prompt and report texts to `Resources/Localizable.xcstrings` (cs)

**Checkpoint**: green → commit.

---

## Phase 7: User Story 5 — Volume Without Reliable Identity (P2)

**Goal**: FR-017–019. **Independent Test**: fake traits "unreliable"; a move onto an existing name is rejected, onto a nonexistent one passes, a copy passes.

### Tests

- [X] T032 [US5] Tests in `Tests/CommanderCoreTests/OperationsTests.swift` via `Options.volumeTraits` (fake unreliable for the sandbox): (a) a move onto an existing name → `.identityUnknown`, source and target unchanged; (b) a move onto a nonexistent name → passes; (c) a copy onto an existing name with overwrite → passes (does not delete the source)

### Implementation

- [X] T033 [US5] Add `volumeTraits: @Sendable (URL) -> VolumeTraits` to `FileOperations.Options` (default `VolumeTraits.of`, cached by `st_dev` for the duration of a single operation) and pass it to `TransferPlanner`/`TransferRun`
- [X] T034 [US5] In `Sources/CommanderCore/Operations/TransferPlan.swift:166-177` and `validateNested` (`:197-201`) and in `Sources/CommanderCore/Operations/TransferRun.swift` `resolve` (`:237-239`): existing target + an operation that deletes the source + `!identityReliable` (of the source or the target) → `.identityUnknown(existing)`

**Checkpoint**: green → commit.

---

## Phase 8: User Story 6 — "Save As" in the Viewer Does Not Destroy the Target (P2)

**Goal**: FR-020–022. **Independent Test**: a symlink to a file with a label → after saving, both the symlink and the label remain; an error → target unchanged, no temp.

### Tests

- [X] T035 [P] [US6] `SafeFileWriter` tests in `Tests/CommanderCoreTests/PreviewTests.swift` (next to `:258-312`): labels (`URLResourceValues.tagNames`) and a custom xattr preserved on the target, also behind a symlink; `produce` throws → target unchanged and the folder has no file with `FileCopy.tempPrefix`

### Implementation

- [X] T036 [US6] In `Sources/AxolotlCommander/Viewer/ViewerWindowController.swift:863` replace `payload.write(to:options:.atomic)` with a call to `try SafeFileWriter.write(to: url) { try payload.write(to: $0) }`

**Checkpoint**: green → commit.

---

## Phase 9: User Story 7 — Renaming Onto Another Link of the Same File Is a Conflict (P3)

**Goal**: FR-023–024. **Independent Test**: `link(2)` a.txt/b.txt; rename a→b → `.alreadyExists`; `Zprava`→`zprava` passes.

### Tests

- [X] T037 [US7] Tests in `Tests/CommanderCoreTests/OperationsTests.swift`: two hard links, `rename(a, to: "b.txt")` → `.alreadyExists`, both entries exist; the existing `caseOnlyRename` (`:319`) stays green; NFC→NFD of the same entry passes

### Implementation

- [X] T038 [US7] In `Sources/CommanderCore/FileOperations.swift` `rename` (`:153-180`): with the same identity and `linkCount > 1`, go through the parent's listing — if there is another entry (different `unicodeScalars` than the source name) that the volume considers the same as the new name (`rules.same`) or that matches exactly → `.alreadyExists`

**Checkpoint**: green → commit.

---

## Phase 10: User Story 8 — Safeguards That Already Work Have Tests (P3)

**Goal**: FR-026. **Independent Test**: the new tests are green; after temporarily disabling a safeguard they fail.

- [X] T039 [P] [US8] Test in `Tests/CommanderCoreTests/OperationsTests.swift`: moving a lone symlink to a directory (a) on the same volume → the link is moved, the files behind it untouched; (b) with `forceCopyMove` → the link is copied, the files behind it untouched
- [X] T040 [US8] Per research R8, in `Sources/CommanderCore/Operations/TransferPlan.swift:77,84` / `TransferRun.swift:197` allow `unlink` of the link (does not follow the target) after copying for an item of the symlink kind (the link itself); a folder containing a link still stays in `keptSources`
- [X] T041 [P] [US8] Test in `Tests/CommanderCoreTests/OperationsTests.swift`: a `chmod 000` subfolder (restore `0o755` in `defer`), a move with `forceCopyMove` → the source in `keptSources`, nothing deleted
- [X] T042 [P] [US8] Fix `Tests/CommanderCoreTests/PanelModelTests.swift:225` to compare `Array(name.unicodeScalars)`; add tests of copying and renaming a different file in a folder with an NFD name → code units unchanged

**Checkpoint**: green → commit.

---

## Phase 11: Polish

- [X] T043 `swift build` without warnings, the whole `swift test` green and < 10 s (SC-005)
- [X] T044 Manually, once, temporarily disable the D1, D2, D3 safeguard and verify that the tests fail (then restore)
- [X] T045 GUI scenarios G1–G7 from `quickstart.md` in a test copy of the app (own bundle id, both panels in a test folder)
- [X] T046 Update `docs/STATE.md` (local) and `docs/AUDIT.md` (D1–D8 → resolved); record the side finding `ArchiveCatalog.invalidate` (URL key) as a known issue
- [X] T047 Check off the tasks in this file, commit `[Spec 001] Done`

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → stories. US1, US3, US6 do not depend on Phase 2 (they can start right after T001).
- US2 needs T004 (`PersistentFileStamp`); US5 needs T003; US7 needs T002.
- US4 is independent. US8 is independent (T040 after T039).
- Polish after all stories.

## Parallel Opportunities

- T005 ‖ T006–T009 (different test files).
- US1: T008 ‖ T009; T011 ‖ T012 (SFTP vs. FTP client).
- Between stories: US3 ‖ US6 ‖ US4 (different core and UI files); US7 and US5 both change `OperationsTests.swift` and the operations core → sequentially.

## Implementation Strategy

- **MVP**: US1 (the only place with an immediate risk of data loss without a Trash) → commit.
- Then US2, US3 (the rest of P1), P2 (US4–US6), P3 (US7, US8).
- Each story can be completed and committed on its own; the full test suite after each.
