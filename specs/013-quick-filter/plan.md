# Implementation Plan: Quick Filter

**Branch**: `013-quick-filter` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

## Summary

- **Core (`PanelModel`)**:
  - `quickFilter: String?` applied in `buildItems()` after the mask filter;
  - `setQuickFilter(_:) -> Bool`, which refuses text that would leave no item;
  - `navigate` and `restore` clear it, and `refresh` keeps it.
  Matching lives in a core `QuickFilter.matches(name:text:rules:)`: a substring, or a `WildcardMask` when
  the text has `*?;|`.
- **Commands**: `quickFilter` and `quickFilterLast` (View, after Filter…). The Classic Commander change
  is ⌃S.
- **UI (`PanelViewController`)**:
  - a typing state `quickFilterTyping` next to `quickSearch`, handled in `handleKey` before quick search
    and before the spec 011 typing route;
  - `lastQuickFilter`;
  - the status line text;
  - Esc clears an active filter.

## Technical Context

- Swift 6.2, AppKit, Swift Testing. No storage.
- Tests (`QuickFilterTests`):
  - matching: substring, case, mask, folders, "..", branch names;
  - the model: refusing, clearing on navigation, keeping on refresh, `selectedItems` limited to visible
    items, and working with the mask filter;
  - chords in both schemes.

## Constitution Check

| Principle | Compliance |
|---|---|
| I Data safety | ✅ Commands use `selectedItems`, which is derived from visible items, so hidden marked items are never processed (FR-008); a test guards it. |
| II Reference | ✅ Classic quick filter; deviations listed. |
| III Native macOS | ✅ ⌥⌘F as in Finder's search. |
| IV Testable core | ✅ Matching and model state in the core. |
| V Clean-room | ✅ |
| VI Incremental | ✅ Core, then UI, then the last-text and quick-search links. |
| VII Language | ✅ |

## Source code

```text
Sources/CommanderCore/QuickFilter.swift         # NEW: matching
Sources/CommanderCore/PanelModel.swift          # quickFilter, setQuickFilter, clearing
Sources/CommanderCore/Command.swift             # quickFilter, quickFilterLast
Sources/CommanderCore/KeyScheme.swift           # Classic ⌃S
Sources/AxolotlCommander/PanelViewController.swift  # typing state, keys, status
Resources/Localizable.xcstrings
Tests/CommanderCoreTests/QuickFilterTests.swift # NEW
```

## Complexity Tracking

None.
