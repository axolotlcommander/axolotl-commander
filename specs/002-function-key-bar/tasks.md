---
description: "Task list: Function Key Bar and Hideable Command Line"
---

# Tasks: Function Key Bar and Hideable Command Line

**Input**: `specs/002-function-key-bar/` — [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md),
[contracts/function-key-bar.md](contracts/function-key-bar.md), [quickstart.md](quickstart.md)

**Tests**: REQUIRED for the core logic (constitution IV): slots, short titles, symbols, notice
rule. UI behavior is verified by the GUI scenarios Q1–Q14 in the test copy of the app.

**Conventions**: a new file starts with the SPDX header (`// SPDX-License-Identifier: GPL-3.0-or-later`
+ `// Copyright (C) 2026 The Axolotl Commander Authors`); do not read the reference's C++ sources;
new UI texts through `String(localized:)` with an English key and a Czech translation in
`Resources/Localizable.xcstrings`; after each story `swift build` without warnings, `swift test`
green, commit `[Spec 002] USn …`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can be done in parallel (different file, no dependency on an unfinished task)
- **[Story]**: US1–US4 from spec.md

---

## Phase 1: Setup

- [ ] T001 Move the SF Symbol table from `MainToolbar.symbols` (`Sources/AxolotlCommander/MainToolbar.swift`) into the core as `CommandRegistry.symbolName(_:)` in `Sources/CommanderCore/Window/FunctionKeyBar.swift` (plain `[Command: String]`, no AppKit); `MainToolbar` reads it (allowed items = commands with a symbol that the toolbar listed before, keep the toolbar's current set and order unchanged)

---

## Phase 2: Foundational

- [ ] T002 Add `FunctionKeyBar.count = 12` and `FunctionKeyBar.slots(in: KeyMap, modifiers: KeyChord.Modifiers) -> [Command?]` (`map.command(for: KeyChord(.function(n), modifiers))`, n = 1…12) in `Sources/CommanderCore/Window/FunctionKeyBar.swift`
- [ ] T003 Add `CommandRegistry.shortTitle(_:) -> String?` (English, only for long titles: delete "Trash", deletePermanently "Delete", makeDirectory "New Folder", userMenu "User Menu", revealInFinder "Finder", changeDirectory "Go to", contextMenu "Menu", leftVolumeMenu "Left", rightVolumeMenu "Right", loadSelection "Apply Selection", saveSelection "Remember", calculateSizes "Sizes", occupiedSpace "Disk Map", workingDirectories "Work Dirs", sortByName "Name", sortByExtension "Ext", sortByDate "Date", sortBySize "Size", comparePanels "Compare", maximizePanel "Maximize", changeCase "Case", viewWith "View With", editWith "Edit With", find "Find", quickLook "Quick Look", help "Help", hotPaths "Hot Paths", disconnect "Disconnect") in `Sources/CommanderCore/Window/FunctionKeyBar.swift`
- [ ] T004 Extend the symbol table so every command with a factory F-key chord in the panel map has a symbol (help, rename, view, edit, viewWith, editWith, newFile, copy, move, makeDirectory, delete, deletePermanently, userMenu, disconnect, revealInFinder, changeDirectory, hotPaths, contextMenu, quickLook, pack, unpack, find, occupiedSpace, workingDirectories, leftVolumeMenu, rightVolumeMenu, sort×4, changeCase, refresh, comparePanels, maximizePanel, filter, saveSelection, loadSelection, calculateSizes) in `Sources/CommanderCore/Window/FunctionKeyBar.swift`
- [ ] T005 Add `localizedShortTitle` (short title looked up in the main bundle, falling back to the full localized title) and `barTitle` (localized title without a trailing "…") on `CommandSpec` in `Sources/AxolotlCommander/Localization.swift`
- [ ] T006 [P] Tests in `Tests/CommanderCoreTests/FunctionKeyBarTests.swift`: (a) slots equal `map.command(for:)` for n 1…12 × all 16 combinations of ⇧⌃⌥⌘, factory map and a map with overrides (F2 → comparePanels, F5 cleared); (b) factory plain set F1 help, F2 rename, F3 view, F4 edit, F5 copy, F6 move, F7 makeDirectory, F8 delete, F9 userMenu, F10 nil, F11 nil, F12 disconnect; (c) pack appears at ⌥F5 and ⌃⌥F5; (d) every symbol name exists (`NSImage(systemSymbolName:)`, import AppKit in the test) and every factory F-key command of the panel map has a symbol; (e) every short title is shorter than its title without "…"
- [ ] T007 Add Czech translations for all short titles to `Resources/Localizable.xcstrings`; extend `FunctionKeyBarTests` with a check that every short title is a key of the String Catalog with a `cs` translation (read the JSON from the package root)

**Checkpoint**: `swift test` green; the core answers what each slot shows.

---

## Phase 3: User Story 1 — Function key buttons (P1) 🎯 MVP

**Goal**: The bar with F1–F12 for the plain set, icons, enabled state, clicks without focus change, narrow-window fitting.

**Independent Test**: Q1–Q4, Q7, Q8, Q14 in [quickstart.md](quickstart.md).

- [ ] T008 [US1] Create `Sources/AxolotlCommander/FunctionKeyBarView.swift`: `final class FunctionKeyBarView: NSView` with twelve `NSButton`s in a horizontal `NSStackView` (`.fillEqually`, spacing 1), bezel `.recessed`, `showsBorderOnlyWhileMouseInside`, `refusesFirstResponder = true`, small control size, image leading, single-line titles with tail truncation; API `update(slots: [Command?])`, `validate(_ isEnabled: (Command) -> Bool)`, `onClick: (Command) -> Void`
- [ ] T009 [US1] Button content in `FunctionKeyBarView.swift`: attributed title "F<n>" (secondary label color) + " " + name (primary), template SF Symbol from `CommandRegistry.symbolName`, tooltip "<full localized title> (<chord>)", accessibility label "F<n>, <full localized title>"; empty slot: "F<n>" in tertiary color, disabled, no tooltip; disabled buttons dim key and name
- [ ] T010 [US1] Label fitting in `FunctionKeyBarView.swift` (`layout()`): per button pick the first variant whose measured width fits the button: full `barTitle` → `localizedShortTitle` → short title truncated → key only (no title text, icon kept)
- [ ] T011 [US1] In `Sources/AxolotlCommander/MainWindowController.swift`: create the bar, add it with its own separator below the command line in `container(...)` (`[split, separator, commandLine, separator, bar]`, width constraints, hugging `.required`), fill it with `FunctionKeyBar.slots(in: KeyMaps.panel, modifiers: [])`, refresh on `KeyMaps.didChange`
- [ ] T012 [US1] `performFromBar(_:)` in `MainWindowController.swift`: guard `canPerformIgnoringFocus`, then the same routing as `perform` (app → `AppDelegate`, window commands → `performHere`, else active panel) without changing the first responder; wire `bar.onClick`
- [ ] T013 [US1] Validate bar buttons on `NSWindow.didUpdateNotification` of the main window with `canPerformIgnoringFocus` in `MainWindowController.swift`
- [ ] T014 [US1] Build, `swift test`, GUI Q1–Q4, Q7, Q8, Q14 in the test copy (both panels in a scratch folder); commit `[Spec 002] US1 Function key bar`

**Checkpoint**: The bar works for the plain set.

---

## Phase 4: User Story 2 — Modifier sets (P1)

**Goal**: The bar follows the held ⇧⌃⌥⌘; clicks run the shown variant; never stuck.

**Independent Test**: Q5, Q6.

- [ ] T015 [US2] Add `KeyChord.Modifiers(flags: NSEvent.ModifierFlags)` (only ⇧⌃⌥⌘; ignores `.function`, Caps Lock, numeric pad) in `Sources/AxolotlCommander/KeyChord+AppKit.swift` and use it in `KeyChord(event:)`
- [ ] T016 [US2] In `MainWindowController.swift`: local monitor for `.flagsChanged` (events of this window only) → recompute slots when the modifier set changes; `windowDidBecomeKey`/`windowDidResignKey` re-read `NSEvent.modifierFlags` (resign → plain set); remove the monitor in `deinit` like `keyMonitor`
- [ ] T017 [US2] Ctrl-click in `FunctionKeyBarView.swift`: override `menu(for:)` on the bar and its buttons so a ⌃-left-click is an ordinary click and only `.rightMouseDown` opens the context menu (menu itself in T021)
- [ ] T018 [US2] Build, `swift test`, GUI Q5, Q6 (⌃⇧/⌃⌥ sets checked by holding the modifiers and reading AX labels); commit `[Spec 002] US2 Modifier sets in the function key bar`

---

## Phase 5: User Story 3 — Hide or show the bar and the command line (P2)

**Goal**: Both visible by default; toggles in View, Settings, bar context menu; remembered; command-line commands bring the command line back.

**Independent Test**: Q9–Q11.

- [ ] T019 [US3] Add `case toggleCommandLine, toggleFunctionKeyBar` to `Command` and register them in the View menu after Maximize Panel's group with a separator: `add(.toggleCommandLine, "Show Command Line", .view, sep: true)`, `add(.toggleFunctionKeyBar, "Show Function Key Bar", .view)` in `Sources/CommanderCore/Command.swift`; Czech translations in `Resources/Localizable.xcstrings`; `KeyMapTests` stays green (no default chords)
- [ ] T020 [US3] In `MainWindowController.swift`: UserDefaults keys `showCommandLine`, `showFunctionKeyBar` (missing = `true`); apply on init and on `UserDefaults.didChangeNotification` (hide element + its separator; hiding the command line while it edits returns focus to the active panel); both commands handled in `performHere`, focus-independent in `canPerform`; `validateMenuItem` sets the checkmark
- [ ] T021 [US3] Bar context menu with "Hide Function Key Bar" in `FunctionKeyBarView.swift` (calls back to set `showFunctionKeyBar = false`)
- [ ] T022 [US3] `.focusCommandLine` and the four `insert…ToCommandLine` commands set `showCommandLine = true` and apply it before doing their work, both from keys (`interceptKey`, `performHere`) and from the bar, in `MainWindowController.swift`
- [ ] T023 [P] [US3] Settings → General: two toggles "Show command line" and "Show function key bar" bound with `@AppStorage` (default `true`) in `Sources/AxolotlCommander/SettingsView.swift`; Czech translations
- [ ] T024 [US3] Build, `swift test`, GUI Q9–Q11 (including quit + relaunch of the test copy); commit `[Spec 002] US3 Hide the function key bar and the command line`

---

## Phase 6: User Story 4 — Help when function keys need `fn` (P3)

**Goal**: Settings line + one-time notice; the system setting is only read.

**Independent Test**: Q12, Q13.

- [ ] T025 [P] [US4] Create `Sources/CommanderCore/Window/FunctionKeyNotice.swift`: `public struct FunctionKeyNotice: Codable, Equatable, Sendable` with `timesShown` (Int, 0), `suppressed` (Bool, false), `maxShowings = 2`, `shouldShow(standardFunctionKeys:)` = `!standardFunctionKeys && !suppressed && timesShown < maxShowings`, `recordShown()`, `suppress()`
- [ ] T026 [P] [US4] Tests in `Tests/CommanderCoreTests/FunctionKeyNoticeTests.swift`: never when standard; at most twice; never after suppress; JSON round-trip and decoding of an empty object to defaults
- [ ] T027 [US4] Create `Sources/AxolotlCommander/FunctionKeys.swift`: `FunctionKeys.areStandard` (read-only `CFPreferencesAppSynchronize` + `CFPreferencesCopyAppValue("com.apple.keyboard.fnState", kCFPreferencesAnyApplication)`, missing = false), `openKeyboardSettings()` (`x-apple.systempreferences:com.apple.Keyboard-Settings.extension`), `showNoticeIfNeeded(in: NSWindow)` (state JSON in UserDefaults `functionKeyNotice`; `NSAlert` sheet: message + where to switch it, buttons "Open Keyboard Settings" (default), "Don't Show Again", "Close" (Esc); record shown; own wording, Czech translations)
- [ ] T028 [US4] Call `FunctionKeys.showNoticeIfNeeded` on the next run-loop turn after `controller.showWindow` in `Sources/AxolotlCommander/AppDelegate.swift`
- [ ] T029 [US4] Settings → Keyboard: a line above the table "Function keys act as standard function keys." / "Function keys control brightness, volume and media; hold fn or change the system setting." + button "Open Keyboard Settings"; state re-read on appear and on `NSApplication.didBecomeActiveNotification` in `Sources/AxolotlCommander/KeyboardSettings.swift`; Czech translations
- [ ] T030 [US4] Build, `swift test`, GUI Q12, Q13 (`defaults read -g com.apple.keyboard.fnState` unchanged before/after; do not change the system setting); commit `[Spec 002] US4 Function key help`

---

## Phase 7: Polish & Cross-Cutting

- [ ] T031 [P] Update `README.md` (Getting started: the function key bar, hiding it and the command line) and `CHANGELOG.md` (Unreleased: Added)
- [ ] T032 Full check: `swift build` without warnings, `swift test` green < 10 s, quickstart Q1–Q14 all passed in the test copy; clean up the scratch folder and the test copy's defaults
- [ ] T033 Mark the spec Status "Implemented", update local `docs/STATE.md`; commit `[Spec 002] Done`

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → US1 → US2. US3 depends on US1 (the bar exists) for T021 only; T019, T020, T022, T023 could start after Phase 2. US4 is independent of US1–US3 (T025–T027 can start after Phase 1).
- Within a story: core + tests first, then UI, then GUI check and commit.

## Parallel Opportunities

- T006 alongside T005 (test file vs. UI file).
- T023 (SettingsView) alongside T020–T022 (MainWindowController).
- T025 + T026 (core notice) alongside any US1–US3 UI task.

## Implementation Strategy

1. MVP = Phase 1–3 (US1): the plain bar is already useful for mouse users and `fn` keyboards.
2. Add US2 (modifier sets) — completes the reference behavior.
3. Add US3 (hiding) and US4 (fn help).
4. Polish, full quickstart, done.
