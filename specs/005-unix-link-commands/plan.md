# Implementation Plan: Link Commands, Go to Link Target and Change Attributes

**Branch**: `005-unix-link-commands` | **Date**: 2026-10-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/005-unix-link-commands/spec.md`

## Summary

Six panel commands: New Symbolic Link… (⌃⌘L), New Hard Link…, Edit Symbolic Link…, Paste as
Symbolic Link (⌃⌘V, ⌃S), Go to Link Target (⌃T) and Change Attributes… (⌃F2). Links are created
in the other panel's folder, never over an existing name.

Approach (see [research.md](research.md)): the core gains `LinkOperations.swift`. It holds:
- `FileOperations` extensions for creating, batch-creating and atomically retargeting links;
- the pure path helpers `LinkPaths`;
- target resolution `LinkTarget`.

The UI gains a `LinkSheet` (one view, three modes) and an `AttributesSheet` that reuses the
existing editor. The commands plug into `CommandRegistry`, the panel's validation and perform
switch, the context menu and the toolbar symbol map.

## Technical Context

**Language/Version**: Swift 6.2 (strict concurrency, upcoming features ExistentialAny,
InternalImportsByDefault, MemberImportVisibility)

**Primary Dependencies**: Foundation, Darwin (`symlink`, `link`, `readlink`, `lstat`,
`renamex_np`); AppKit and SwiftUI (UI module only)

**Storage**: UserDefaults `links.relativePath` (false)

**Testing**: Swift Testing (`swift test`):
- path helpers;
- symbolic, hard and batch creation in a temporary folder (conflicts, folders, symlinks,
  dangling targets);
- retarget (swap path, the refusal when the item is not a link);
- resolution (chains, relative, alias, missing, loop);
- default chords (no duplicates).

GUI checks run in the test copy `iCmdTest.app` in a scratch folder.

**Target Platform**: macOS 15+

**Project Type**: desktop-app (SwiftPM: `CommanderCore` without AppKit + `AxolotlCommander` AppKit)

**Performance Goals**: every command finishes within one user-visible step. Batches are a
handful of system calls per item and run off the main thread. Validation does at most one
`getattrlist` per menu update (alias check).

**Constraints**:
- no deletion, move or overwrite of existing items (FR-023);
- edit replaces only a symbolic link (R5);
- local folders only;
- texts in en + cs.

**Scale/Scope**:
- 1 new core file and 1 new test file;
- 2 new UI files and ~5 UI files touched;
- 6 commands, ~20 strings, ~30 tests.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Compliance | Note |
|---|---|---|
| I Data safety | ✅ | Creation via `symlink`/`link` (fail on existing names), retarget via `RENAME_SWAP` with a link check, batches skip conflicts. Tests in temp folders only; GUI tests in a scratch folder in the test copy. |
| II Faithful reference behavior | ✅ | Change Attributes on ⌃F2, Go to Link Target on ⌃T, Paste as link on ⌃S, as in the reference. Deviations D-001–D-004 recorded in the spec. |
| III Native macOS | ✅ | Finder aliases resolved, standard pasteboard file URLs, SwiftUI sheets, `String(localized:)`, accessible labelled fields. |
| IV Testable core | ✅ | Paths, creation, retarget and resolution in `CommanderCore` with tests; the UI collects input and shows results. |
| V Clean-room, GPL | ✅ | Behavior from the spec, the reference help and common Unix tools; no reference sources; own wording; no new dependencies; SPDX headers. |
| VI Incremental delivery | ✅ | US1–US3 (P1) first, then US4–US6; commit after each step. |
| VII Language | ✅ | Spec, plan, code, comments and commits in English; Czech only in the String Catalog. |

Re-check after Phase 1 design: unchanged, no violations, so Complexity Tracking is empty.

## Project Structure

### Documentation (this feature)

```text
specs/005-unix-link-commands/
├── plan.md              # This file
├── research.md          # Phase 0: decisions R1–R11
├── data-model.md        # Phase 1: errors, outcomes, path helpers, sheet input
├── quickstart.md        # Phase 1: validation scenarios Q1–Q17
├── contracts/
│   └── link-commands.md # Core API, commands, UI behavior, texts
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/CommanderCore/
├── Command.swift                       # + 6 commands, registry entries and chords
└── Operations/LinkOperations.swift     # NEW: LinkKind, LinkError, LinkOutcome, LinkPaths,
                                        #   FileOperations link functions, LinkTarget

Sources/AxolotlCommander/
├── LinkSheet.swift                     # NEW: symbolic / hard / edit sheet + presenters
├── AttributesSheet.swift               # NEW: Change Attributes sheet around AttributesEditView
├── PropertiesView.swift                # PropertiesSheet.apply shared (internal)
├── PanelViewController.swift           # handled/diskOnly sets, validation, perform, paste, go to target
├── PanelContextMenu.swift              # item and folder menu entries
├── MainToolbar.swift                   # symbols for the new commands (not default)
└── OperationsController.swift          # describe(LinkError) texts

Resources/Localizable.xcstrings         # new texts (en, cs)

Tests/CommanderCoreTests/
└── LinkTests.swift                     # NEW
```

**Structure Decision**: the existing two-module layout. Everything that touches the file system
or decides a path is in the core next to `makeDirectory`/`makeFile`; AppKit/SwiftUI only present
sheets and route commands.

## Implementation Notes

- **Errors to text**: `OperationsController.describe(_:)` gains the `LinkError` cases. Inline
  sheet messages use the same texts.
- **Prefill**: other panel = `router.otherPanel(than:)`. When its `model.archive`, `model.remote`
  or `model.results` is set, the prefill uses the active folder instead (spec edge case).
- **Destination check**: the typed link path's folder must exist and be a local folder.
  `PathInput.resolve(_, relativeTo: model.location, absoluteIsLocal: true)` turns a typed
  relative path into a full one.
- **Off main thread**: the core calls run in `Task.detached`. Results return on the main actor,
  then `refreshPanels()` and `focus(name:)`.
- **Go to Link Target**: `LinkTarget.resolve` gives a URL. A folder becomes `go(to: url)` and a
  file becomes `go(to: url.deletingLastPathComponent(), focusing: url.lastPathComponent)`. Both
  are recorded in history by `model.go`.
- **Change Attributes for a single "..":** disabled (targets empty). The folder itself stays
  reachable through Get Info as today.

## Complexity Tracking

No violations.
