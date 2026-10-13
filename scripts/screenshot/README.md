# Screenshots

`make-screenshot.sh` takes the screenshot of the README and the website, one per language, so a
new one is a single command after a visible change.

```sh
scripts/screenshot/make-screenshot.sh            # release build, then English and Czech
scripts/screenshot/make-screenshot.sh --no-build cs
```

It writes `docs/images/screenshot.png` (English, used by the README) and
`docs/images/screenshot-<lang>.png` for the other languages.

## What it does

1. Copies `build/Axolotl Commander.app` with its own bundle id
   (`cz.acidek.axolotlcommander.screenshot`), so the app starts with default settings and never
   reads or changes the settings of an installed copy. The settings it sets: the panels'
   folders and the button bar at the top with its sample buttons.
2. Makes a made-up folder `/Users/Shared/Demo` (`demo-tree.sh`): a small website project and a
   Documents folder. Big files are sparse, and dates count back from today, so the shot never
   looks old. The script stops if the folder already exists and removes only the folder it made.
3. For each language, starts the app with that language and locale, sizes the window to
   1320 × 660 points, opens `website` in a new tab of the left panel and marks three files with
   Space (`drive.swift`), then captures the window with its shadow (`screencapture -l`).
4. Quits the copy and removes it, its settings and the demo folder.

## While it runs

- It brings the copy to the front for about ten seconds per language. **Do not touch the
  keyboard or mouse**: keys go only to the copy and stop as soon as it is not frontmost, and the
  shot is then missing the marks.
- The terminal needs Accessibility access (to size the window) and Screen Recording access.
- Only the copy's window is captured. The drive row shows the real free space of the startup
  disk, and the volume bar shows the volumes mounted at the time; eject private ones first.

## Changing the shot

- The folder content is in `demo-tree.sh`; the key presses in `make-screenshot.sh` count rows,
  so they follow the order of the listed items (folders first, then files by name).
- A new language: add its locale to the `case` at the end of `make-screenshot.sh`.
- The website (`axolotlcommander/axolotlcommander-org`) takes the images into `assets-src/` and
  regenerates its formats with `tools/make-assets.sh`.
