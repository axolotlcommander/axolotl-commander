# Research: Link Commands, Go to Link Target and Change Attributes

Decisions for [plan.md](plan.md). Each one: Decision, Rationale, Alternatives considered.

## R1 — Where the logic lives

**Decision**: a new core file `Operations/LinkOperations.swift` with an extension of
`FileOperations` (create symbolic link, create hard link, retarget, create several) and a pure
enum `LinkPaths` (relative path, stored target, prefilled destination). Resolving a target lives
in `LinkTarget` in the same file. The UI only collects input and shows results.

**Rationale**: constitution IV (testable core); `FileOperations` already owns `makeDirectory` and
`makeFile` with `NameCheck`, `DirectoryLookup` and `FSPath.errorText`, which the link commands
reuse for names, conflicts and error texts.

**Alternatives**: `FileManager.createSymbolicLink` / `linkItem` — `linkItem` on a folder
recreates the tree and links every file recursively, which FR-010 forbids; the errors are also
less precise than `errno`.

## R2 — Never overwriting an existing name

**Decision**: before creating, `DirectoryLookup(rules: NameRules.forVolume(containing:))` checks
the folder for an existing entry by the volume's name rules (case and Unicode normalization);
the call itself is `symlink(2)` / `link(2)`, which fail with `EEXIST` instead of replacing, so a
name that appears between the check and the call is still never overwritten. Both map to
`OperationError.alreadyExists`.

**Rationale**: FR-023/FR-024; the pre-check gives the name as it is spelled on disk for the
message, the system call gives atomicity.

## R3 — Relative and stored targets

**Decision**: `LinkPaths.relativePath(from folder:, to target:)` works on the standardized paths
as the panels show them (no symlink resolution): common leading components are dropped, each
remaining folder component becomes `..`. Equal paths give `.`. `LinkPaths.storedTarget(typed:,
linkFolder:, relative:)`: a typed relative path (not starting with `/` or `~`) is returned as
typed; `~` is expanded; an absolute path is returned absolute or converted with
`relativePath` when `relative` is on.

**Rationale**: FR-006 and FR-012 need deterministic, testable text; resolving symlinks would
produce paths the user never saw (e.g. `/private/var` instead of `/var`).

**Alternatives**: `ln -sr`-style resolution of both sides (surprising paths on macOS).

## R4 — Hard links

**Decision**: `lstat` the source; only `S_IFREG` is accepted (folders and packages →
`LinkError.folderNotAllowed`, symlinks → `.symbolicLinkNotAllowed`). The destination folder's
`st_dev` must equal the source's (`.differentVolume`); `EXDEV` from `link(2)` maps to the same
error. `link(2)` is called on the verified regular file.

**Rationale**: FR-010; APFS refuses hard links to folders anyway, and the explanations need to be
specific before any attempt.

## R5 — Retargeting a link atomically

**Decision**: create the new link under a temporary hidden name in the same folder
(`.<name>.axolotl-<random>`), then `renamex_np(temp, link, RENAME_SWAP)`. After the swap the
temporary name holds the old item: when `lstat` shows it is a symbolic link it is unlinked;
otherwise (the link was replaced by something else meanwhile) the swap is reversed, the
temporary link removed and an error reported. When the volume does not support `RENAME_SWAP`
(`ENOTSUP`), the code checks `lstat` (must be a link) and uses `rename(2)`, which also replaces in
one step. Any failure removes the temporary link.

**Rationale**: FR-013 — the name always exists, and with the swap no item other than a symbolic
link can ever be replaced, even in a race.

**Alternatives**: unlink + symlink (a moment without the link; a failure loses it).

## R6 — Resolving a link's target

**Decision**: `LinkTarget.resolve(_ url:)` follows up to 32 steps (the system's limit): a symbolic
link → `readlink`, relative results resolved against the link's folder; a Finder alias →
`URL(resolvingAliasFileAt:options: [.withoutUI, .withoutMounting])`. The final item must exist
(`lstat`); its folder is then made real with `resolvingSymlinksInPath()`. Errors:
`LinkError.targetMissing(stored:)` (with the text the first link holds) and `.loop`.
`isAliasFile` is also true for symbolic links, so `isSymbolicLink` is checked first.

**Rationale**: FR-018/FR-019; a manual loop can name the missing target and detect loops, which
`resolvingSymlinksInPath` silently hides.

## R7 — Link sheet

**Decision**: one SwiftUI view `LinkSheet` with a mode (`symbolic`, `hard`, `edit`) and an item
count; hosted in an `NSHostingController` as a window sheet like `PropertiesSheet`. Confirm runs
the core call on a detached task; `alreadyExists`, `invalidName` and a missing folder become an
inline message (the sheet stays open); the "target does not exist" question is an `NSAlert`
through `OperationsController.present` (app-modal while the sheet is attached). The remembered
"Relative path" is a UserDefaults key `links.relativePath` (false).

**Rationale**: FR-003–FR-007, FR-012, FR-029; inline errors avoid a dialog per typo.

## R8 — Change Attributes sheet

**Decision**: `AttributesSheet.show(_ urls:in:onChange:)` hosts the existing `AttributesEditView`
with a header (icon, name or item count) and Cancel/Apply, and applies through the same function
as Get Info (`PropertiesSheet.apply`, made internal and shared).

**Rationale**: FR-021 — identical editor and rules, no second implementation.

## R9 — Paste as Symbolic Link

**Decision**: reads file URLs from the general pasteboard (`readObjects` with
`urlReadingFileURLsOnly`, the same as Paste Files), calls the core batch with the active panel's
folder, absolute targets, then shows one summary alert for skipped items.

**Rationale**: FR-015/FR-016; the format is what Copy Files writes and Finder reads/writes.

## R10 — Commands, menus, toolbar, shortcuts

**Decision**: six `Command` cases (`newSymbolicLink`, `newHardLink`, `editSymbolicLink`,
`pasteAsSymbolicLink`, `goToLinkTarget`, `changeAttributes`) registered in `CommandRegistry` at
the positions of the spec with chords ⌃⌘L, ⌃⌘V + ⌃S, ⌃T, ⌃F2. The panel handles them; all are
in `diskOnly` and refused for search results; validation per FR-011/FR-016/FR-017/FR-022.
`MainToolbar.symbols` gets an SF Symbol per command (not in the default set). The context menu
lists them in the item menu (links, Go to Link Target, Change Attributes) and the folder menu
(Paste as Symbolic Link). Quick search ignores chords with ⌃, so ⌃S and ⌃T never type.

**Rationale**: FR-001, FR-008, FR-011, FR-014, FR-017, FR-020, FR-028 with the existing machinery;
`KeyMapTests` already reject duplicate default chords.

## R11 — Refresh and cursor

**Decision**: after a link command, `MainWindowController.refreshPanels()`; for a single new link
the panel(s) showing the destination folder call `focus(name:)` with the link's name; Paste puts
the active panel's cursor on the first created link.

**Rationale**: FR-026.
