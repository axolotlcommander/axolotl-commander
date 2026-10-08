# Port plan — stages

Source: the analysis in `../tandemcommander/docs/macos-port/` (steps 0–12, controls, rules).
This plan adopts it and adjusts the architecture so that later stages do not require a rewrite.
Keys and behavior: `../tandemcommander/docs/macos-port/02-ovladani.md`.
Safeguards for tests: `../tandemcommander/docs/macos-port/05-pravidla.md`.

## Architecture (differences from the analysis)

| Layer | Choice | Why |
|---|---|---|
| Build | SwiftPM (`Package.swift`), `scripts/bundle.sh` → `.app` | No `.xcodeproj`, everything is text, build/test from the terminal |
| `CommanderCore` | Pure Swift, no AppKit | Panel model, selection, sorting, masks, name/path/identity rules, operations. Covered by `swift test` |
| `AxolotlCommander` | AppKit | Window, panels (`NSTableView`), menus, dialogs |
| Commands | `Command` enum + `CommandRegistry` (title, menu, default shortcut, `isImplemented`) | Menus, grayed-out items, shortcuts and remapping (stage 11) from a single source |
| Keys | `KeyChord` → `Command` via `KeyMap` in the core | Testable without UI; the window catches F-keys before the system does |
| File source | `FileSource` protocol (`LocalFileSource` now, `ArchiveFileSource`/`RemoteFileSource` later) | The panel does not know where the items come from |
| Listing | `FileManager` with resource keys passed in (internally `getattrlistbulk`) in the background; custom `getattrlistbulk` only if measurements show a need | Simpler, equally fast for ordinary directories |
| Identity | `URLResourceKey.fileResourceIdentifierKey` + volume UUID, fallback `stat` (dev, ino) | The "identity, not path text" rule |
| Settings | plist in `~/Library/Application Support/Axolotl Commander/` | — |

## Stages

Every stage ends with: build without warnings, `swift test` green, the keyboard scenario passes
manually, unfinished commands grayed out in the menu, commit.

### Milestone A — first usable version

| # | Stage | Content | Done when |
|---|---|---|---|
| 0 | Skeleton | Package, app bundle, window with 2 panels, the whole menu from the registry (grayed out), Tab switches panels, F-keys arrive as commands, Settings (Cmd+,) window, Esc to go back | Tab, Cmd+,, Esc, Cmd+Q work; F5 logs the command |
| 1 | Disk browsing | Listing (name, extension, size, date), folders on top, `..`, sorting Ctrl+F3–F6 (second press reverses), movement, Enter/Backspace/Ctrl+\, history Ctrl+Opt+←/→, path line with editing, volume menu Ctrl+Opt+F1/F2, quick search by typing, Ctrl+F9, auto-refresh (FSEvents), name rule (case/NFC-NFD) and path length | I can walk the disk from the keyboard, an external change shows up |
| 2 | Selection | Insert, space bar (+ folder size), Shift+movement, mask Num+/−/* (+ Ctrl+=, Ctrl+−, Ctrl+8), Shift+Num± extension, Cmd+A / Cmd+Shift+A, info line (count + total), filter Ctrl+F12, name/path to the clipboard | Selection survives sorting and refresh |
| 3 | Operations | F5/F6 with a dialog (target = the other panel, name mask), progress + Cancel in the background, prompt for an existing target, F7, F8/Delete → Trash, Shift+Delete permanently, F2 in-place rename, Drag&Drop, Cmd+C/Cmd+V files. **Safeguards with tests:** copy onto itself (identity), folder into a descendant, atomic overwrite (temp + swap), move through a directory symlink does not delete the source | 6 tests from the rules fail on a violation |

### Milestone B — daily tool

| # | Stage | Content |
|---|---|---|
| 4 | Launching and command line | Enter opens via `NSWorkspace`, bottom command line (Ctrl+Tab, Ctrl+Enter, Ctrl+space bar, Ctrl+[/]), Ctrl+/ Terminal, Shift+F3 Finder, Cmd+I properties, F3 Quick Look |
| 5 | Commander window | Splitter + memory, Ctrl+F11 panel maximization, brief mode (grid), clicking the header sorts, volume bar, toolbar, colors and mask highlighting, tabs (Ctrl+Shift+T/W/PgUp/PgDn), favorite paths Shift+F9, Shift+F7 path dialog, Ctrl+F10 panel comparison, Ctrl+Shift+F10 sizes, saving the layout |
| 6 | Viewer and editor | F3 custom text/hex viewer (encoding BOM/UTF-8/choice, search, next file), F4 editor from settings, Shift+F4 new file |
| 7 | Find | Ctrl+Opt+F7: mask, date, text; result as a panel; Cancel; duplicates by name+size |

### Milestone C — additions

| # | Stage | Content |
|---|---|---|
| 8 | Archives | `ArchiveFileSource`: ZIP/tar (libarchive), 7z/RAR reading (`7zz`); 8a browsing/extracting/adding, 8b editing a member with rules |
| 9 | Network | FTP/SFTP as `RemoteFileSource`, Keychain, passwords kept out of history |
| 10 | Viewers by type | Markdown (WKWebView), images (ImageIO), code highlighting, file comparison |
| 11 | Advanced | Permissions/flags/labels, letter case, checksums, batch rename, disk map, user menu F9, key settings, duplicates by content |
| 12 | Plugins | Only with a concrete extension window |
