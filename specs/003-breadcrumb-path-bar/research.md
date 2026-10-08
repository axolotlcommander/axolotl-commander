# Research: Clickable Breadcrumb Path Bar

Decisions for [plan.md](plan.md). Each: Decision / Rationale / Alternatives considered.

## R1 — Trail of a local location

**Decision**: Split the panel location's path (the same `path(percentEncoded: false)` the display
path uses) into components. The first segment is the volume that contains it: if the path starts
with the volume's mount point (e.g. `/Volumes/Ext`), the volume segment stands for the mount point
and the remaining components follow; otherwise (boot volume "/", or a mount point that is not a
prefix, as with firmlinked `/Users`) the first segment is the boot volume "/" named by its volume
name ("Macintosh HD"). A segment whose URL equals the home folder is of kind `home`.

**Rationale**: Matches Finder's path bar and the volume bar's names; resource values give
`volumeURL` "/" for `/Users/...`, `/tmp`, `/Library` on APFS, so the boot volume name appears for
all system and user folders. Keeping the panel's own path text guarantees that both modes agree
(FR-010).

**Alternatives**: `URL.pathComponents` with `/System/Volumes/Data` resolution (shows internal
firmlink paths users never see); starting at the home folder (Finder sidebar style; hides
where the folder really is).

## R2 — Archives and servers

**Decision**: Inside an archive the pseudo path (`/x/pack.zip/inner/deep`) is split the same way;
the segment whose URL equals `archive.archive` gets kind `archive`, the ones after it are folders
inside the archive. On a server the first segment is the server (`RemoteURL.displayName`, URL =
the server's "/" path), followed by the components of the remote path; an empty path (login
folder not known yet) gives the server segment only.

**Rationale**: The panel already navigates archive pseudo URLs and remote URLs with `go(to:)`;
no new navigation code is needed. `displayName` is the "user@host" / "host:port" text used in
titles and menus.

**Alternatives**: A separate trail type per location kind (more code, same result).

## R3 — Search results

**Decision**: With results, the trail is a non-clickable `results` segment (the results title)
followed by the trail of `results.root`; in this mode the last segment is clickable too, because
going to the root folder leaves the results (FR-025).

**Rationale**: Today's text field shows "title — root"; the trail shows the same information.

## R4 — Fitting rule

**Decision**: Pure function `Breadcrumbs.fit(widths:available:ellipsis:separator:)` returning the
indices to show, the hidden range (if any) and the width allowed for the last segment. Algorithm:
if everything fits, show all. Otherwise always show the first and the last; add segments from
just before the last backwards while `first + "…" + kept + last` fits; the rest becomes the "…"
range. If even first + "…" + last does not fit (or first + last for a two-segment trail), the
last segment gets the remaining width (it is truncated with "…" at its end, FR-016).

**Rationale**: Keeps the current folder and its nearest parents (where users go most), like
Finder; testable with numbers, no AppKit.

**Alternatives**: Truncating each name (forbidden by FR-011); hiding from the start (loses the
volume).

## R5 — Segment view

**Decision**: A custom `NSView` per segment (icon + name), drawn with `labelColor` text, a small
icon (16 pt) and a rounded highlight on hover (tracking area). `acceptsFirstResponder` is false.
Mouse down/up inside → click; ⌘ held → new tab; right mouse / ⌃-click → context menu. Separators
"›" are drawn as labels in `secondaryLabelColor` between segments.

**Rationale**: `NSPathControl` was considered: it has its own ellipsis rules (truncates names
in the middle), no per-segment context menu hook beyond the whole control, no hover highlight
control, and no non-clickable title segment. A custom row is small and gives exact control
over FR-011/FR-015.

**Alternatives**: `NSPathControl` (see above); `NSButton`s (focus ring and bezel handling,
harder to make look like text).

## R6 — Icons

**Decision**: `NSWorkspace.shared.icon(forFile:)` for local folders, the volume and the home
folder (Finder's own icons); for archive files the icon of the file; for folders inside archives
and on servers the generic folder icon (`icon(for: .folder)`); for the server SF Symbol
`network`; for results SF Symbol `magnifyingglass`. Icons are 16 × 16 and adapt to dark mode as
system icons do.

## R7 — Editing in breadcrumb mode

**Decision**: `PathBar.beginEditing()` hides the row, shows the field with the current location
text, makes it first responder and selects all. `controlTextDidEndEditing` → `endEditing()`
shows the row again. In breadcrumb mode `pathFieldCommitted` returns focus to the list at once
(also on error, after the beep and status message).

**Rationale**: Reuses the field's input rules (sftp://, ~, relative, errors) without
duplication (SC-003).

## R8 — Activation and focus

**Decision**: A segment click calls `router?.activate(side)` (which makes the list first
responder and marks the panel active) before navigating; the segment never becomes first
responder. Clicking the empty area right of the last segment activates the panel and begins
editing.

## R9 — Settings

**Decision**: `@AppStorage("pathBar.style")` with values `breadcrumbs` (default) / `text`, and
`@AppStorage("pathBar.showIcons")` (default true) in Settings → Appearance. Panels observe
`UserDefaults.didChangeNotification` and re-apply (same pattern as the command line / function
key bar visibility in spec 002).

## R10 — Segment actions

**Decision**: Reuse panel functions: `go(to:focusing:)`, `router?.otherPanel(than:).go(to:)`,
`newTab()` + `go(to:)`, `NSPasteboard` with the segment's display path (as Copy Path as Text),
`setHotPath(slot, path:)` (refactor of the existing `setHotPath(slot)`), `Launcher.revealInFinder`
for local folders (and the archive file of an archive segment). Disabled: Show in Finder for
remote segments and for folders inside an archive.

## R11 — Edit Path command

**Decision**: `Command.editPath`, title "Edit Path", menu `.go`, default chord ⌘L; handled by the
panel (`handled` set). ⌘L is free in the panel key map (⌃L = Volume Information; the viewer's
⌘L belongs to the viewer map).

## R12 — Accessibility

**Decision**: The row is an accessibility group labeled "Path"; each clickable segment is an
element with role button, label = folder name, and `accessibilityPerformPress` = click; the
"…" segment's label is "Hidden folders"; the results title is a static text element.
