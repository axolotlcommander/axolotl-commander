# Research: Copy Dialog and Replace Question

## R1. Where do the new choices live?

- **Decision**: a per-operation `ConflictPolicy` in front of the question answers automatically; the
  backends keep receiving the existing `ConflictResolution` values.
- **Rationale**: the local transfer, the remote transfers and the extraction (which ends in a local move
  from a staging folder) all call one conflict handler per conflict. "Overwrite All Older" is one
  `overwrite` or `skip` per conflict; an automatic name is a `rename`. Nothing in the backends has to
  learn the new modes.
- **Alternatives**: new `ConflictResolution` cases handled in each backend (three places to keep in
  step).

## R2. Automatic names that collide again

- **Decision**: a rename to a taken name asks again with that name as the destination. The local
  transfer already loops this way; `RemoteTransfer` (upload and download) changes from failing with
  "already exists" to asking again. The policy recognises its own candidate and answers the next one.
- **Rationale**: no backend has to list the destination folder for the UI, and a server folder is not
  read twice.
- **Alternatives**: pass an "exists" lookup into the question (extra round trips, per backend).

## R3. Dialog technology

- **Decision**: AppKit sheets for both dialogs, with a window subclass that sees key presses first.
- **Rationale**: the F5/F6 selection cycle needs the field editor's selected range; F3/⇧F3/⌥F3 must
  work whatever button is default; More… needs a menu under a button that does not end the sheet. An
  `NSAlert` ends on every button and SwiftUI text fields do not give the range reliably.
- **Alternatives**: `NSAlert` with a replaced button action (fragile), SwiftUI `onKeyPress` (focus
  dependent).

## R4. Looking into files during the question

- **Decision**: the existing `ArchiveScratch.download` / `ArchiveScratch.extract` make the local copies;
  `ViewerWindowController.show` and `CompareWindowController.show` display them. The sheet is
  window-modal, so the viewer and compare windows work while it waits.
- **Risk**: a server download while a transfer on the same connection waits for the answer. The
  transfer is suspended outside `RemoteConnections.perform` when it asks, so the connection is free;
  covered by the GUI check on a test server when one is at hand.

## R5. Recent destinations

- **Decision**: `RecentPaths` with a per-instance limit (10), stored as `transfer.recentDestinations` in
  the defaults, not exported (like `recentPaths`). Added when an operation starts (after OK), with the
  destination folder (not the new name).
