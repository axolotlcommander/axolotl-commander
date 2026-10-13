# Implementation Plan: Small Commands

**Branch**: `015-small-commands` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core**:
  - `TransferRequest.targetName`: the new name of a single source; the plan gives the top-level node
    that name and keeps the inner names (FR-001). Copy As = a copy into the item's own folder with it.
  - `CopyAsName.suggestion(for:isDirectory:)`: "‹base› copy.‹ext›" / "‹name› copy";
    `NewFolderName.suggestion(for:)`: a folder's name, a file's base name.
  - `ArchiveTester.test(archive:passphrases:progress:)`: reads every entry's data with libarchive
    (CRC and stream checks happen while reading), throws the problem; encrypted entries are checked
    as Unpack checks them.
  - `PanelModel.setSelection(filesOnly:_:)` (Select / Deselect All Files) and
    `toggleSelectionAtCursor()` without moving.
  - Commands and chords in `Command.swift`; Classic changes in `KeyScheme.swift`.
- **UI**:
  - `PanelViewController`: Copy As (TextPrompt, then `operations.transfer(... targetName:)` into the
    item's folder and focus on the copy), View Cursor File Only (a one-file `FileSequence`), the
    selection commands; enabling rules.
  - `OperationsController.makeDirectory(in:initial:keepFocus:)` for New Folder in Other Panel.
  - `ArchiveOperations.pack(_:from:moving:)`: after `ArchiveWriter.create` succeeds, move the sources
    to the Trash (`FileManager.trashItem`); into an existing archive `.move`.
  - `ArchiveOperations.testArchives(_:from:)`: progress window, `ArchivePasswords.run` per archive,
    result alert.

## Technical Context

- Swift 6.2, AppKit, libarchive (already linked), Swift Testing.
- Tests (`SmallCommandsTests`): `targetName` for a file and a folder (inner names kept, own name
  refused as same file), name suggestions, the archive tester on a good and a corrupted zip, files-only
  selection, toggle without moving, chords in both schemes.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Copy As goes through the transfer planner (same-file and overwrite checks). Pack and Move removes originals only after a successful write, to the Trash. Test Archives is read-only. Tests use temporary folders. |
| II Reference | ✅ Classic commands; deviations listed. |
| III Native macOS | ✅ "copy" names as Finder, Trash instead of delete. |
| IV Testable core | ✅ Naming, transfer, tester and selection in the core. |
| V Clean-room | ✅ |
| VI Incremental | ✅ One command at a time. |
| VII Language | ✅ |

## Source code

```text
Sources/CommanderCore/Operations/OperationTypes.swift   # TransferRequest.targetName
Sources/CommanderCore/Operations/TransferPlan.swift     # top-level rename
Sources/CommanderCore/SmallCommands.swift               # NEW: CopyAsName, NewFolderName
Sources/CommanderCore/Archive/ArchiveTester.swift       # NEW
Sources/CommanderCore/PanelModel.swift                  # files-only selection, toggle in place
Sources/CommanderCore/Command.swift, KeyScheme.swift
Sources/AxolotlCommander/PanelViewController.swift
Sources/AxolotlCommander/OperationsController.swift
Sources/AxolotlCommander/ArchiveOperations.swift
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/SmallCommandsTests.swift       # NEW
```

## Complexity Tracking

None.
