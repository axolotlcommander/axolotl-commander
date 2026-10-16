# Implementation Plan: Basic Commands

**Branch**: `033-basic-commands` | **Date**: 2026-10-16 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (unit tested):
  - `Sources/CommanderCore/Operations/CutSet.swift` (NEW): the cut items and the pasteboard change count they
    belong to; `contains(_:changeCount:)`, `isActive(changeCount:)`, `remaining(exists:)` after a move,
    `pasteAction(for urls:, destination:, changeCount:)` → `.move` / `.copy` / `.sameFolder` (R1, R2).
  - `Sources/CommanderCore/Operations/DuplicateName.swift` (NEW): Finder-style names, `name(for:isDirectory:
    word:isTaken:)` → "base word.ext", "base word 2.ext", …; dot files and names without an extension get the
    word at the end; folders do not split an extension; the base is shortened to stay within 255 UTF-8 bytes
    (R4).
  - `StandardFolder` (`desktop`, `documents`, `downloads`, `applications`) with its URL for a home folder (R5).
- **Command registry** (`Command.swift`): `cutFiles` ("Cut Files", Edit, ⌘X and ⌃X, before Copy Files);
  `duplicate` ("Duplicate", File, ⌘D, after Copy As…); `goDesktop` (⇧⌘D), `goDocuments` (⇧⌘O), `goDownloads`
  (⌥⌘L), `goApplications` (no key) after Home; New Tab + ⌘T, Next Tab + ⇧⌘], Previous Tab + ⇧⌘[; the classic
  scheme's lists for these tab commands get the same additions (R3).
- **Clipboard** (`Sources/AxolotlCommander/CutClipboard.swift`, NEW, `@MainActor` singleton): holds the
  `CutSet`, writes the pasteboard, polls `NSPasteboard.general.changeCount` once a second while a cut exists
  and on app activation, posts `.cutSetChanged` when the dimmed items change (R2).
- **Panel** (`PanelViewController`):
  - Cut Files: `CutClipboard.shared.cut(targets URLs)`; enabled like F6 (`diskOnly`, needs targets);
  - Paste Files: `pasteAction` decides: move with the existing transfer (and `onFinish` that settles the cut
    set), beep for the same folder, copy otherwise (R1);
  - Duplicate: `OperationsController.duplicate(_:panel:)` copies each target to its free name in one progress
    sheet and puts the cursor on the first copy; disabled in archives, on servers and in flat listings;
  - standard folders go through `go(to:)` like Home;
  - dimming: `textColor(for:marked:)` gives the secondary color to unmarked cut items; the icon of a cut item
    is drawn at half opacity in the detailed, brief and thumbnail views; `.cutSetChanged` reloads visible
    cells.
- **Main window**: `cut(_:)` responder (standard `NSText.cut(_:)` selector for `cutFiles`, so ⌘X cuts text in
  the command line and other text fields, R6).
- **Operations**: `transfer(…, onFinish:)` and `run(…, onFinish:)` call back when the operation ends, success
  or not.
- Czech strings; CHANGELOG entries under Unreleased; version bump minor (0.9.0) when the PR is prepared.

## Technical Context

Swift 6, AppKit, SwiftPM; tests with Swift Testing in `Tests/CommanderCoreTests`.

## Constitution Check

| Principle | Status |
|---|---|
| Data safety | ✅ Paste moves only items cut in this run with an unchanged pasteboard; everything else copies. Moves use the existing operation (conflicts, refusals, kept sources). GUI tests only in scratchpad folders on the test copy. |
| Clean room | ✅ Behavior from the reference help and Finder conventions only. |
| Keyboard first | ✅ Every new command has a key (Applications assignable); all appear in Settings → Keyboard. |
| Testable core | ✅ Cut set, paste decision, duplicate names, standard folders and chords in CommanderCore with tests. |
| Incremental | ✅ Core → commands → cut/paste → dimming → duplicate → folders → strings, each committed. |

## Research

- **R1** Paste decision: move only when the pasteboard change count equals the one recorded by Cut and every
  pasteboard URL is in the cut set; when all cut items already sit in the destination folder → `.sameFolder`
  (beep). Otherwise copy, as today. After the move the cut set keeps only the sources that still exist; when
  none remain the pasteboard is cleared, otherwise it is rewritten with the remaining ones (new change count).
- **R2** `NSPasteboard` has no change notification; a 1 s timer that runs only while a cut set exists, plus a
  check on `didBecomeActive`, ends the cut when another app copies. The in-memory set dies with the app, so a
  cut never survives a relaunch (clarification).
- **R3** Classic scheme entries replace whole chord lists; the new Mac keys are appended to the classic lists
  of New Tab / Next Tab / Previous Tab so both schemes have them. ⌃Tab stays Command Line in the default
  scheme. ⌃X joins ⌘X in both schemes, as ⌃C and ⌃V already do for Copy and Paste.
- **R4** Finder names copies "name copy.ext", "name copy 2.ext"; Czech Finder "name kopie.ext". The word
  comes from the app's localization. Taken names are checked on disk at the time of the copy; names chosen
  for earlier items of the same Duplicate count as taken.
- **R5** Desktop, Documents, Downloads are `~/Desktop`, `~/Documents`, `~/Downloads`
  (`FileManager.homeDirectoryForCurrentUser`); Applications is `/Applications`.
- **R6** Copy Files and Paste Files already use the standard `copy:` / `paste:` selectors so text fields get
  them first; Cut Files does the same with `cut:`. The other new keys are menu commands like F5 and, like every other
  panel command, are disabled while the command line has the focus (clarification, corrected 2026-10-16).

## Project Structure

```text
Sources/CommanderCore/Operations/CutSet.swift           NEW cut set + paste decision
Sources/CommanderCore/Operations/DuplicateName.swift    NEW duplicate names, standard folders
Sources/CommanderCore/Command.swift                     new commands and chords
Sources/CommanderCore/KeyScheme.swift                   classic scheme additions
Sources/AxolotlCommander/CutClipboard.swift             NEW pasteboard + polling + notification
Sources/AxolotlCommander/PanelViewController.swift      cut, paste decision, duplicate, folders, dimming
Sources/AxolotlCommander/PanelTabs.swift / BriefView.swift / ThumbnailView.swift  dimmed cut items
Sources/AxolotlCommander/OperationsController.swift     onFinish, duplicate
Sources/AxolotlCommander/MainWindowController.swift     cut(_:)
Sources/AxolotlCommander/MainMenuBuilder.swift          cut: selector
Resources/Localizable.xcstrings                         Czech
Tests/CommanderCoreTests/CutSetTests.swift              NEW
Tests/CommanderCoreTests/DuplicateNameTests.swift       NEW
```
