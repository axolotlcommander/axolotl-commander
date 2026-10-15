# Implementation Plan: Find Results Like the Classic Commander

**Branch**: `032-find-results` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

## Summary

- **Core** (`Sources/CommanderCore/Search/FindResultActions.swift`, NEW, unit tested):
  - `FindWindowBehavior` (`hide` default, `keepOpen`; key `find.afterGoToFile`, part of the settings file).
  - `FindGoToTarget.resolve(_ url:, exists:)` → `.focus(folder, name)` / `.folderOnly(folder)` (the item is
    gone: beep) / `.gone(folder)` (the folder is gone too: message) (R1).
- **Command registry** (`Command.swift`): `findNewSearch` ("New Search", ⌘N, scope `.find`, Commands menu);
  `findInNewWindow` ("Find Files in New Window…", app/panel scope next to `.find`, no keys); `.findToPanel`
  retitled "Results to Panel"; `.findOpen` loses Return / keypad Enter, `.findShowInPanel` (retitled "Go to
  File") gains them. Command names (raw values) stay, so saved key maps keep working (R2).
- **Find window** (`FindWindowController.swift`):
  - double click → `.findShowInPanel`;
  - Go to File: the target from `FindGoToTarget`; the main window comes front, `activate(activeSide)` puts
    the focus in the panel (R3);
  - a button row under the status line: F3 View, F4 Edit, New Search, Go to File, Results to Panel
    (`refusesFirstResponder`, no key equivalents; the form's Find button stays the default button, R4);
    enabled state refreshed with the selection and the search state;
  - New Search: stop, clear items, groups, problems, outcome, status; focus the name field (FindForm gets a
    `focusName` request) (R5);
  - hide instead of close (R6): `FindWindowController.hidden` (one, weak-safe strong ref), `stepAside()`
    orders the window out; Find Files (`show(from:)`) brings `hidden` back if there is one, else opens a new
    one; `showNew(from:)` always opens a new one; hiding another closes the earlier hidden one; Esc with no
    search hides (behavior `hide`) or closes (`keepOpen`).
- **Settings → General**: picker "After going to a file:" with the two choices and a caption.
- Czech strings; CHANGELOG entries under 0.8.0 (same PR as spec 031, one version).

## Technical Context

Swift 6, AppKit + SwiftUI (form), SwiftPM; tests with Swift Testing in `Tests/CommanderCoreTests`.

## Constitution Check

| Principle | Status |
|---|---|
| Data safety | ✅ No new file operations; GUI tests only in scratchpad folders on the test copy. |
| Clean room | ✅ Behavior from the reference help and the classic commander's documented behavior only. |
| Keyboard first | ✅ Every button has a key; new commands assignable. |
| Testable core | ✅ Behavior setting and go-to target in CommanderCore with unit tests. |
| Incremental | ✅ Core → commands → window → settings → strings, each committed. |

## Research

- **R1** Missing items are checked when the user acts (results can be stale); the panel's own navigation
  reports a missing folder too, but the Find window shows its message itself so nothing changes in the panel.
- **R2** Retitling keeps `Command` raw values; only titles and default chords change. Users who assigned keys
  keep them (key maps store command names).
- **R3** `MainWindowController.activate(_:)` already makes the list the first responder.
- **R4** A second default button would fight the form's Find button over Return (Return in the form starts
  the search). Decision: Go to File is a plain button; Return in the results reaches it through the table's
  key handling (clarification 2026-10-15).
- **R5** The form is SwiftUI; a `FindForm.focusRequest` counter drives `@FocusState` on the name field and
  selects its text.
- **R6** A hidden window keeps its controller alive in `open`; `windowWillClose` still cleans up.

## Project Structure

```text
Sources/CommanderCore/Search/FindResultActions.swift   NEW behavior + go-to target
Sources/CommanderCore/Command.swift                    new commands, retitles, chords
Sources/CommanderCore/Settings/AppSettingsCatalog.swift  the new preference
Sources/AxolotlCommander/Find/FindWindowController.swift  buttons, go to file, new search, hide/show
Sources/AxolotlCommander/Find/FindForm.swift / FindFormView.swift  focus request for the name field
Sources/AxolotlCommander/PanelViewController.swift / AppDelegate or MainWindowController  Find in New Window
Sources/AxolotlCommander/SettingsView.swift            General: After going to a file
Resources/Localizable.xcstrings                        Czech
Tests/CommanderCoreTests/FindResultActionsTests.swift  NEW
```
