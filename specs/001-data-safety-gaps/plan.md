# Implementation Plan: Data Safety — Gaps from the Audit (D1–D8)

**Branch**: `001-data-safety-gaps` | **Date**: 2026-10-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-data-safety-gaps/spec.md`

## Summary

Eight data-safety gaps against the rules of the reference program (05-pravidla, specs 062/092/103/105/106/107/
112/119) and missing tests for the existing safeguards. Approach (see [research.md](research.md)):
overwriting on a server via an atomic replace or a backup (R1); edits of archive members in a new
`ArchiveEditStore` in the core with persistent storage in Application Support (R2); the "into itself"
check in archives and when packing, based on file identity (R3); deletion split up front into Trash /
permanent with a single prompt (R4); `VolumeTraits` and rejection of delete operations on volumes
without reliable identity (R5); "Save As" via `SafeFileWriter` (R6); a conflict when renaming onto
another hard link (R7); tests for symlinks, incomplete traversal, and code units (R8).

## Technical Context

**Language/Version**: Swift 6.2 (strict concurrency, upcoming features ExistentialAny,
InternalImportsByDefault, MemberImportVisibility)

**Primary Dependencies**: Foundation, AppKit (UI module only), Darwin (`statfs`, `rename`, `link`),
system libarchive and libcurl, a custom SFTP client on top of `ssh`

**Storage**: files — `~/Library/Application Support/Axolotl Commander/Edits/` (JSON manifest +
copies of archive members); otherwise UserDefaults unchanged

**Testing**: Swift Testing (`swift test`), sandbox in `FileManager.default.temporaryDirectory`,
fake `DirectoryFileSystem` for the server, local `/usr/libexec/sftp-server`, `scripts/ftp-test-server.py`

**Target Platform**: macOS 15+

**Project Type**: desktop-app (SwiftPM: `CommanderCore` library without AppKit + `AxolotlCommander` AppKit)

**Performance Goals**: identity and Trash checks add no noticeable delay (cache for the duration of
the operation, `statfs` once per volume); the whole test suite < 10 s

**Constraints**: no operations on real data in tests; the real Trash is not used in tests
(`trashItem` seam); canceling an operation must not interrupt a replace on the server midway

**Scale/Scope**: ~10 core files, ~5 UI files, ~25 new tests

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Note |
|---|---|---|
| I Data Safety | ✅ | The goal of the whole feature. Tests only in a sandbox, fake Trash and fake volumes, local test servers. |
| II Fidelity to the Reference | ✅ | Rules from 05-pravidla (Identity, Overwrite, Move, Archive); macOS deviation: a prompt for permanent deletion like Finder (recorded in spec US4). |
| III Native macOS | ✅ | System Trash, `replaceItemAt`, Application Support; AppKit alerts for UI; I/O off the main thread (existing `perform`). |
| IV Testable Core | ✅ | The archive-edit logic moves into the core (`ArchiveEditStore`); every fix has a test (FR-025). |
| V Clean Implementation, GPL | ✅ | No new dependencies; the reference is used only for documentation and specs, not C++. SPDX headers in new files. |
| VI Incremental Delivery | ✅ | US1–US8 independent; order P1 → P3; commit after each. |

Re-check after design (Phase 1): unchanged, no violations → Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/001-data-safety-gaps/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/core-api.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/CommanderCore/
├── Network/
│   ├── RemoteFileSystem.swift        # + replace(_:over:), RemoteError.replaceIncomplete   (D1)
│   ├── RemoteTransfer.swift          # placeReplacing; upload overwrite, renameOnServer       (D1)
│   ├── SFTP/SFTPClient.swift         # replace via posix-rename@openssh.com                   (D1)
│   └── FTP/FTPClient.swift           # replace via RNFR/RNTO without a pre-check              (D1)
├── Archive/
│   ├── ArchiveEditStore.swift        # NEW: PendingEdit, manifest, states                     (D2)
│   ├── ArchiveTransferCheck.swift    # NEW: validate, validatePack                            (D3, D7)
│   ├── ArchiveWriter.swift           # update(..., expecting: PersistentFileStamp?)          (D2)
│   └── ArchiveFormat.swift           # ArchiveError.changedSinceRead                          (D2)
├── Operations/
│   ├── FileIdentity.swift            # reliable, linkCount, PersistentFileStamp, VolumeTraits (D5, D8, D2)
│   ├── TransferPlan.swift            # identityUnknown on an unreliable volume; lone symlink  (D5, US8)
│   ├── TransferRun.swift             # resolve; unlink of the link alone after copy           (D5, US8)
│   └── TrashSupport.swift            # NEW: isAvailable                                       (D4)
└── FileOperations.swift              # Options seams, planDelete, trash → TrashReport, rename (D4, D8)

Sources/AxolotlCommander/
├── AppDelegate.swift                 # quit/start: cleanupForQuit, loadPending                (D2)
├── ArchiveOperations.swift           # ArchiveEdits → thin layer over the store; check calls  (D2, D3, D7)
├── OperationsController.swift        # F8 plan + prompt + report; texts of new errors         (D1, D4)
├── Find/FindWindowController.swift   # deleting from search results via the new plan          (D4)
└── Viewer/ViewerWindowController.swift  # saveCopy via SafeFileWriter                         (D6)

Tests/CommanderCoreTests/
├── TestSupport.swift                 # NEW: withSandbox, fake volumes/Trash
├── RemoteTransferTests.swift         # D1 (+ fake atomicReplace, error injection)
├── SFTPTests.swift / FTPTests.swift  # replace against local servers
├── ArchiveEditStoreTests.swift       # NEW, D2
├── ArchiveTransferCheckTests.swift   # NEW, D3, D7
├── DeletePlanTests.swift             # NEW, D4
├── OperationsTests.swift             # D5, D8, US8
├── PreviewTests.swift                # D6
└── PanelModelTests.swift             # US8 code units (comparison fix)
```

**Structure Decision**: The existing two-module structure. All decision logic is in
`CommanderCore` (testable); the UI only does prompts and calls.

## Implementation Order

1. Shared: `TestSupport.swift`, `VolumeTraits`/`PersistentFileStamp`/`linkCount` (the basis for D2, D5, D8).
2. P1: D1 (US1) → D2 (US2) → D3 + D7 (US3).
3. P2: D4 (US4) → D5 (US5) → D6 (US6).
4. P3: D8 (US7) → US8 tests.
5. Wrap-up: the whole test suite, GUI scenarios G1–G7 from [quickstart.md](quickstart.md) in a test copy,
   a note in STATE, the side finding `ArchiveCatalog.invalidate` into STATE (out of scope).

## Complexity Tracking

No constitution violations.
