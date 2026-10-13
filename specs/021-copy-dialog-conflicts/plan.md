# Implementation Plan: Copy Dialog and Replace Question

**Branch**: `021-copy-dialog-conflicts` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (pure, tested):
  - `ConflictMarks` (`Operations/ConflictMarks.swift`, NEW): which side is newer and which is larger.
  - `AutoName` (`Operations/AutoName.swift`, NEW): "base N.ext" / "base N" candidates, shortened to the
    255-byte UTF-8 name limit; `name(for:attempt:)`.
  - `ConflictPolicy` (`Operations/ConflictPolicy.swift`, NEW): the per-operation answer machine in front
    of the question. States: `ask`, `overwriteAllOlder`, `renameAllAutomatically`. `decide(_:)` returns
    either an automatic `ConflictResolution` or `.ask`; `record(_:for:)` takes the user's choice. It
    also continues an automatic rename: when a backend comes back with a conflict for the same source
    and the candidate name, it answers the next candidate.
  - `ConflictResolution` stays as is (`overwrite`, `overwriteAll`, `skip`, `skipAll`, `rename`,
    `cancel`); the new choices are expressed through the policy, so no backend changes their logic.
  - `Conflict.canRename` (new field, default `true`): `false` for a server-side move (rename of an
    existing entry on the same server), which cannot take another name.
  - `TransferTarget` (`Operations/TransferTarget.swift`, NEW): for one item, splits the "To:" text into
    the folder and the name (FR-018) and gives the selection ranges of the F5/F6 cycle (FR-017).
  - `DestinationMenu` (`Window/DestinationMenu.swift`, NEW): builds the sections (other panel, tabs,
    hot paths, recent), without duplicates, the source folder, Network and missing folders (an `exists`
    closure is passed in).
  - `RecentPaths` gets an instance limit; recent destinations use limit 10 under the key
    `transfer.recentDestinations`, listed in `AppSettingsCatalog.notExported`.
  - `RemoteTransfer`: a rename to a name that exists asks again with the new destination (as the local
    transfer already does) instead of failing, so automatic names keep counting on servers too.
- **UI**:
  - `ConflictSheet` (`ConflictSheet.swift`, NEW, AppKit): replaces the `NSAlert` in
    `OperationsController.askConflict`. A sheet window that offers key presses to a handler first (as
    `KeyPanel` in the history list): F3, ⇧F3, ⌥F3. The text: title, the two info lines with the marks,
    the hint line. Buttons in a column like the alert today: Overwrite, Overwrite All, Skip, Skip All,
    More…, Cancel; `DialogKeys` keeps working because they are push buttons in a sheet. More… pops up
    a menu under itself (Return on it opens the menu too).
  - `ConflictAsker` (in `ConflictSheet.swift`): one per operation, owns a `ConflictPolicy`, shows the
    sheet only when the policy says `.ask`. The five call sites (`OperationsController` ×2,
    `ArchiveOperations` ×2, `RemoteOperations`) create one per operation.
  - Looking into files: `ConflictPeek` opens the viewer (`ViewerWindowController.show`) and Compare
    Files (`CompareWindowController.show`) from local copies made by the existing `ArchiveScratch`
    (server download, archive member extraction); errors go to `report` and the question stays.
  - Rename…: an `ask` text sheet on top of the question's window (the existing `PathInput.ask` style),
    prefilled with the automatic name, base selected; checks empty, "/", and for local destinations an
    existing name (message, field stays). For server destinations an existing name brings the question
    back for that name (backends ask again).
  - `TransferDialog` (`TransferDialog.swift`, NEW, AppKit): replaces the SwiftUI `TransferSheet`. A
    key-handling sheet window with "To:" (NSTextField), a menu button (pull-down) beside it, "Name mask:"
    only for several items, Cancel / OK. Keys: ⌥↓ opens the destination menu, ⌃D opens the hot paths
    submenu as its own menu, F5 (copy) / F6 (move) cycle the selection. On OK the destination is
    added to the recent destinations.
  - `OperationsController.transfer`: for one item fills "To:" with folder + name and resolves the result
    with `TransferTarget` (existing folder / trailing "/" / new name), then runs as today with the name as
    `targetName` (the request already has it for ⇧F5).

## Technical Context

- Swift 6.2, AppKit sheets (no SwiftUI for the two dialogs: exact control over the field editor's
  selection and the F-keys), Swift Testing.
- No new dependencies, no new settings in the export.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Safeguards unchanged (FR-019); automatic names never overwrite; "Overwrite All Older" skips equal dates; the GUI check runs in scratch folders only. |
| II Reference | ✅ Classic replace question and copy dialog features; deviations in the spec. |
| III Native macOS | ✅ Sheets, pop-up menus, Finder-style names, String Catalog for all texts. |
| IV Testable core | ✅ Marks, names, policy, "To:" parsing, selection cycle, destination menu and recent list in the core with tests. |
| V Clean-room | ✅ Behavior only. |
| VI Incremental | ✅ Stories ship in order US1/US2 (question) → US4/US3 (dialog) → US5 (More…). |
| VII Language | ✅ |

## Decisions found while planning (confirmed by the maintainer on 2026-10-13)

- Adding to an archive keeps its own question for all existing members at once (Overwrite / Skip /
  Cancel): the archive is rewritten in one pass, so a per-file question does not fit. The replace
  question of this spec covers copy, move, extraction, downloads and uploads.
- When extracting from an archive the new file is already a local temporary copy, so ⇧F3 opens it
  without another fetch.
- Rename… checks an existing name at once for local destinations; on a server the question comes back
  for that name.

## Project Structure

```text
Sources/CommanderCore/Operations/{ConflictMarks,AutoName,ConflictPolicy,TransferTarget}.swift   NEW
Sources/CommanderCore/Window/DestinationMenu.swift                                              NEW
Sources/CommanderCore/Operations/OperationTypes.swift        Conflict.canRename
Sources/CommanderCore/Window/RecentPaths.swift               instance limit
Sources/CommanderCore/Network/RemoteTransfer.swift           ask again on a taken name; canRename
Sources/CommanderCore/Settings/AppSettingsCatalog.swift      notExported += transfer.recentDestinations
Sources/AxolotlCommander/{ConflictSheet,TransferDialog}.swift                                   NEW
Sources/AxolotlCommander/{OperationsController,ArchiveOperations,RemoteOperations,AppSettings}.swift
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/{ConflictPolicyTests,TransferTargetTests,DestinationMenuTests}.swift   NEW
```
