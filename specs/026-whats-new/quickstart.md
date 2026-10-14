# Quickstart: What's New Window

Prerequisites: `swift test` green; the GUI test copy (own bundle id `cz.acidek.axolotlcommander.gtest`) built
with `scripts/bundle.sh` (it contains `CHANGELOG.md`); both panels in scratch folders.

1. `defaults write cz.acidek.axolotlcommander.gtest app.lastRunVersion 0.4.2`; start the copy → about a
   second after the main window the What's New window shows 0.6.0, 0.5.0 and 0.4.x newer than 0.4.2, newest
   first; no "Unreleased".
2. Esc closes it; the panel has the focus again. Quit and start again → no window.
3. `defaults delete … app.lastRunVersion`; start → no window; the key now holds the running version.
4. `defaults write … app.lastRunVersion 9.0.0` (downgrade); start → no window; the key holds the running
   version.
5. Help → What's New… opens the window with all versions; asking again keeps one window.
6. Help → About: the About window shows the version and a "What's New…" button that opens the window.
7. Settings → General → What's New… opens it.
8. A link in the notes opens the browser (check only that the window stays and no page loads inside it).
9. Return (Close) and ⌘W close it; resize, reopen → the size is kept; dark appearance looks right.
