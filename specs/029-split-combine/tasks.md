# Tasks: Split and Combine Files

**Input**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md),
[quickstart.md](quickstart.md)

## Phase 1: Core (blocking)

- [X] T001 `Sources/CommanderCore/Advanced/SplitCombine.swift` (NEW): `PartSize` (presets of R1, `parse` of
  R2, `count`, `problem` → `.invalid` / `.notLarger` / `.tooManyParts` "> 999"), `PartName` (R3,
  `name(base:index:)`, `parse(_:) -> (base, number)?` for "<base>.<3+ digits>"), `ChecksumFile` (R4, `text`,
  lenient `init?(data:)`, unsafe names → nil), `PartSet` (`find(around:in:)`, `marked(_:)`, `defaultName`,
  `totalSize`, R5), `SplitCombineError`, `FreeSpace.available(at:)` (R6).
- [X] T002 `Sources/CommanderCore/Advanced/FileSplitter.swift` (NEW): `split(source:name:partSize:writeChecksum:
  into:replacing:progress:)` (R7: staging `.~icmd-<uuid>`, `O_EXCL`, 4 MiB chunks, CRC32, size check, commit
  with `RENAME_EXCL` or `rename` for the confirmed names, rollback, staging removed) and `existingNames(...)`
  for the question; `combine(parts:name:checksum:into:progress:) -> CombineOutput` (R8).
- [X] T003 `Tests/CommanderCoreTests/SplitCombineTests.swift` (NEW, temporary folder only): presets and
  parser (units, decimal comma, spaces, invalid, zero), count and problems (exact multiple, remainder, one
  part, 999 limit, > 4 GB arithmetic); names; checksum file round trip, CR / LF / CR LF, case, spaces, extra
  lines, unsafe names; set from a part / from the `.crc` / gaps / missing first / marked natural order with
  a `.crc`; split + combine byte-identical; CRC and size mismatch; cancel removes only this run's files;
  existing names kept without replace, replaced with it; a folder in the way refused.

**Checkpoint**: `swift test` green, commit.

## Phase 2: US1 + US3 — Split (P1)

- [X] T004 [US1] `Sources/AxolotlCommander/DestinationMenuPopup.swift` (NEW): the destination menu from
  `TransferDialog.swift` (sections, items, choose callback); `TransferDialog` uses it.
- [X] T005 [US1] `Sources/AxolotlCommander/SplitCombine/SplitDialog.swift` (NEW): sheet (name and size, "To:"
  + destinations button ⌥↓, size popup with the presets and "Custom…", custom field, live count / reason,
  "Create checksum file"); OK disabled when invalid; remembers `split.partSize` / `split.writeChecksum`.
- [X] T006 [US1] [US3] `Sources/AxolotlCommander/SplitCombine/SplitCombineOperations.swift` (NEW):
  `splitFile(from:)` — the one-file rule, target default, dialog, path resolution (missing folder created,
  archive / server refused), free space, the existing-names question (Replace / Cancel), `perform` with
  progress, refresh and cursor on the first part.
- [X] T007 [US1] `Sources/CommanderCore/Command.swift`: `splitFile` "Split File…", `combineFiles` "Combine
  Files…" in the File menu after Test Archives, no keys; `PanelViewController` handled, disk only,
  `canPerform` (a local regular file or link under the cursor / marked; not "..", folders, packages),
  `perform`; `AppSettingsCatalog` keys.

## Phase 3: US2 — Combine (P1)

- [X] T008 [US2] `Sources/AxolotlCommander/SplitCombine/CombineDialog.swift` (NEW): part count, total size,
  "To:" with folder and name + destinations, check line.
- [X] T009 [US2] `SplitCombineOperations.swift`: `combineFiles(from:)` — set from the cursor or marked files,
  missing parts message, dialog, target resolution (an existing folder gets the default name), free space,
  `perform`, the move with `FileOperations.transfer` + `ConflictAsker`, staging removed, result message
  (passed / mismatch with values / not checked), refresh and cursor.

## Phase 4: Polish

- [X] T010 Czech strings in `Resources/Localizable.xcstrings`; no text cut.
- [X] T011 `scripts/bump-version.sh minor` (0.7.0); `CHANGELOG.md` and `CHANGELOG.cs.md` entries.
- [ ] T012 GUI check: quickstart steps 1–10 on the test copy; spec Status → Implemented; `docs/STATE.md`.

## Dependencies

T001 → T002 → T003; T004 before T005 and T008; T005 → T006; T007 with T006; T008 → T009; T010–T012 last.
MVP: Phases 1–2.
