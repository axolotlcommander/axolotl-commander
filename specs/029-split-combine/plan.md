# Implementation Plan: Split and Combine Files

**Branch**: `029-split-combine` | **Date**: 2026-10-14 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (`Sources/CommanderCore/Advanced/`, unit tested, no AppKit):
  - `SplitCombine.swift` (NEW): part sizes (presets, the parser with k/M/G units, part count with the 999
    limit) (R1, R2); part names `<name>.001` (R3); the checksum file — writing and lenient reading, unsafe
    names dropped (R4); part set detection from a part or a `.crc` name and from marked files in natural
    order, with the missing parts (R5); free space of the target volume (R6).
  - `FileSplitter.swift` (NEW): `split` writes the parts (and the checksum file) into a staging folder inside
    the target, computing CRC32 on the way, checks that the source size did not change, then gives the parts
    their names — with `RENAME_EXCL`, or replacing files when the user confirmed it; cleanup on cancel or
    error (R7). `combine` joins parts into a staging folder inside the target, computing size and CRC32, and
    returns the staged file with the check result (R8).
- **UI** (`Sources/AxolotlCommander/`):
  - `SplitCombine/SplitDialog.swift` (NEW): sheet with the file name and size, "To:" with the destination
    menu, the part size popup (presets + Custom…) with the custom field, the live part count / reason, the
    checkbox; OK disabled when invalid.
  - `SplitCombine/CombineDialog.swift` (NEW): sheet with the part count, total size, "To:" (folder and file
    name) with the destination menu and the check line.
  - `SplitCombine/SplitCombineOperations.swift` (NEW): `OperationsController` extension — target choice,
    conflict question for Split (one list, Replace / Cancel), free space check, running through `perform`
    with progress, moving Combine's staged file in with `FileOperations.transfer` and `ConflictAsker`
    (spec 021), the result message, refresh and cursor.
  - `DestinationMenuPopup` (NEW, extracted from `TransferDialog.swift`): the destination menu shared by the
    Copy, Split and Combine dialogs.
  - `Command.swift`: `splitFile` ("Split File…"), `combineFiles` ("Combine Files…") in the File menu after
    Test Archives, no default keys. `PanelViewController`: handled, disk only, `canPerform`, `perform`.
  - `AppSettingsCatalog.swift`: `split.partSize`, `split.writeChecksum`.
- Czech strings; version 0.7.0 (`scripts/bump-version.sh minor`); `CHANGELOG.md` / `CHANGELOG.cs.md`.

## Technical Context

- Swift 6.2, AppKit, Swift Testing; macOS 15+. No new dependencies; CRC32 from `Checksums`.
- **Storage**: two preferences (part size in bytes, checksum checkbox), exported with Settings like the
  others.
- **Performance**: read and write in 4 MiB chunks with POSIX `read` / `write`, CRC32 slicing-by-8 on the same
  buffer; progress updated per chunk (SC-005).
- **Constraints**: nothing outside the staging folder is written until the data is complete; existing files
  are replaced only after confirmation (constitution I).

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Staging folder inside the target, names given only when complete, `RENAME_EXCL` unless replacing was confirmed, cleanup of only this run's files; tests in a temporary folder; GUI test only in the scratchpad on the test copy. |
| II Reference | ✅ The reference has Split & Combine; names and checksum file follow the usual two-panel managers (recorded in the spec). |
| III Native macOS | ✅ AppKit sheets like the Copy dialog, progress sheet, String Catalog. |
| IV Testable core | ✅ Parser, names, checksum file, set detection, split / combine with cleanup in the core with unit tests. |
| V Clean-room / GPL | ✅ Behavior from public descriptions; own code; CRC32 already ours. |
| VI Incremental | ✅ Core → Split UI → Combine UI → polish, each committed. |
| VII Language | ✅ English code and docs, Czech UI strings and changelog. |

## Project Structure

```text
specs/029-split-combine/{plan,research,data-model,quickstart,tasks}.md

Sources/CommanderCore/Advanced/SplitCombine.swift       NEW sizes, names, checksum file, sets, free space
Sources/CommanderCore/Advanced/FileSplitter.swift       NEW split / combine with staging and cleanup
Tests/CommanderCoreTests/SplitCombineTests.swift        NEW
Sources/AxolotlCommander/SplitCombine/SplitDialog.swift NEW
Sources/AxolotlCommander/SplitCombine/CombineDialog.swift NEW
Sources/AxolotlCommander/SplitCombine/SplitCombineOperations.swift NEW
Sources/AxolotlCommander/DestinationMenuPopup.swift     NEW (from TransferDialog)
Sources/AxolotlCommander/TransferDialog.swift           uses DestinationMenuPopup
Sources/CommanderCore/Command.swift                     two commands
Sources/AxolotlCommander/PanelViewController.swift      enablement, perform
Sources/CommanderCore/Settings/AppSettingsCatalog.swift two preferences
Resources/Localizable.xcstrings                         Czech strings
```

## Complexity Tracking

None.
