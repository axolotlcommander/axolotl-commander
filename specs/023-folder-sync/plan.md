# Implementation Plan: Synchronize Folders

**Branch**: `023-folder-sync` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (pure, tested; `Sources/CommanderCore/Sync/`, NEW):
  - `SyncOptions` (Codable with `decodeIfPresent`, persisted) and `SyncDirection` (FR-002, FR-003).
  - `SyncGuard.check(left:right:)`: same folder or nested folders, on resolved paths (FR-004).
  - `SyncScanner.compare(left:right:options:includeHidden:progress:) async throws -> SyncComparison`:
    walks both trees folder by folder, matches by `NameRules.key`, applies the ignore masks, gives each
    item a `SyncState` (dates with the 2-second and one-hour rules, size, content in chunks, links by
    target, packages as folders, one-sided folders as one row with their total size, unreadable folders
    and name clashes as error rows); cancellable, reports items scanned and the current folder (FR-005 to
    FR-010).
  - `SyncRules`: default actions per direction, possible actions, setting an action on several items,
    excluding (FR-011, FR-013, FR-014).
  - `SyncPlan`: copies, replacements and deletions per side, file counts and bytes, the summary texts
    (FR-015, FR-016).
  - `SyncCheck.unchanged`: the changed-since-comparing test (FR-017).
  - `SyncRunner.run(plan:operations:progress:) async throws -> SyncRunReport`: replacements, then copies
    grouped by destination folder through `FileOperations.transfer` with a conflict closure that only
    overwrites what the plan expects, then deletions to the Trash; checks every item first (FR-017,
    FR-018).
- **UI** (`Sources/AxolotlCommander/Sync/`, NEW):
  - `Command.synchronizeFolders` ("Synchronize Folders…", `.commands`, ⌥⇧F10), enabled in
    `MainWindowController.canPerformHere` when both panels are plain local folders (not Network, server,
    archive, search results or branch view) (FR-001).
  - `SyncSheet` (SwiftUI, like `CompareSheet`) bound to `AppSettings.shared.sync`; Return compares, Esc
    cancels; the delete toggle disabled for Both ways (FR-002).
  - `SyncWindowController` (AppKit): one per main window; header, filter buttons, table, summary line,
    Compare Again / Synchronize; in-window progress with Cancel while comparing; keys Space, ←, →, =,
    Delete, F3 (Compare Files), Return, ⌘R, Esc; clicking the action cell cycles; context menu (FR-012 to
    FR-015, FR-021).
  - Run: confirmation alert with the plan summary (Synchronize default, Esc cancels), then
    `OperationsController.perform(_:in:)` (new optional window for the progress sheet) with
    `OperationState(title:urls: [left, right])`; afterwards a report of skipped and failed items, the
    panels refresh and the window compares again (FR-016 to FR-019).
  - `VolumeEjector.users()` lists the sync window's comparing state (FR-020).
  - Settings: `AppSettings.sync` under `syncOptions`, `SettingsCatalog.app` entry (FR-003).
  - Czech strings (FR-023).

## Technical Context

- Swift 6.2, AppKit + SwiftUI for the sheet, Swift Testing. Copying through the existing
  `FileOperations` actor (spec 021 engine), Trash through `TrashSupport`.
- **Performance**: SC-003 (100 000 files per side within 15 s on an SSD): one directory listing per
  folder per side with prefetched resource keys, a dictionary per folder for matching, progress throttled
  to a few updates a second; the table is view-based with row reuse over a filtered index array.
- **Constraints**: nothing on disk changes before the confirmation; no permanent deletion; no following of
  symbolic links; CI fails on warnings.
- No new dependencies.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Read-only until the user confirms a summary; deletions off by default, one-way only, Trash only, never permanent; changed items skipped; nested/same folders refused; links not followed; tests only in temp folders; the GUI check only in scratch folders. |
| II Reference | ✅ Compare-directories criteria (subfolders, date, size, content, ignore masks, time tolerance); the separate window and the run step are a recorded deviation. |
| III Native macOS | ✅ Trash, Compare Files, background work with progress, String Catalog. |
| IV Testable core | ✅ Scanner, states, rules, plan, guard, check and runner in the core with tests on temp folders. |
| V Clean-room | ✅ Behavior from the help only. |
| VI Incremental | ✅ US1 (compare and copy) → US2 (per-item control) → US3 (one way with deleting) → US4 (criteria). |
| VII Language | ✅ |

## Project Structure

```text
specs/023-folder-sync/{plan,research,data-model,quickstart}.md

Sources/CommanderCore/Sync/{SyncOptions,SyncModel,SyncGuard,SyncScanner,SyncRules,SyncPlan,SyncRunner}.swift   NEW
Sources/CommanderCore/Command.swift                       synchronizeFolders
Sources/CommanderCore/Settings/AppSettingsCatalog.swift   syncOptions
Sources/AxolotlCommander/Sync/{SyncSheet,SyncWindowController,SyncTableView}.swift                           NEW
Sources/AxolotlCommander/{MainWindowController,MainMenuBuilder,OperationsController,AppSettings,VolumeEjector}.swift
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/{SyncScannerTests,SyncRulesTests,SyncRunnerTests}.swift                             NEW
```

**Structure Decision**: the existing two-target layout; the sync logic lives in the core so that every
rule of the spec is covered by `swift test`.
