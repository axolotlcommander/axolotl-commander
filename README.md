<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Axolotl Commander">
</p>

<h1 align="center">Axolotl Commander</h1>

<p align="center">
  A keyboard-driven two-panel file manager for macOS.
</p>

<p align="center">
  <a href="https://github.com/axolotlcommander/axolotl-commander/actions/workflows/ci.yml"><img src="https://github.com/axolotlcommander/axolotl-commander/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg" alt="License: GPL v3+"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-lightgrey.svg" alt="macOS 15+">
</p>

## Why

For years I used Salamander on Windows: two panels, everything from the keyboard, a quick
look at a file with F3, comparing files and whole folders, archives and FTP as ordinary folders.
Nothing on the Mac felt like that. The Finder is slow for serious file work and a lot of
things simply cannot be done in it.

Axolotl Commander is an attempt to have the same on the Mac, as a real macOS app (Swift,
AppKit, Trash, Keychain, Quick Look, Finder tags) rather than a ported Windows program.
If you are missing a Salamander, Total Commander or Norton Commander-style (orthodox,
dual-pane) file manager on the Mac, this is for you.

## Inspiration

The behavior, key layout, commands and dialogs follow
[Tandem Commander](https://github.com/tandemcommander/tandemcommander), which builds on
[Open Salamander](https://github.com/OpenSalamander/salamander) (formerly Altap Salamander).
The reference was the behavior of these programs and their help. The code is written from
scratch; nothing was taken from their source code (see [NOTICE](NOTICE)).

Axolotl Commander is not affiliated with or endorsed by the authors of Tandem Commander or
Open Salamander.

## Built with AI — please read before use

This project is **AI-written and spec-driven**: the code is written by the AI assistant
[Claude Code](https://claude.com/claude-code) by Anthropic, following specifications that the
maintainer agrees on first. The maintainer decides what the program should do and how, tries it
out and decides on changes, but not every line has had a detailed human review.

The base program was built in the stages of [docs/PLAN.md](docs/PLAN.md); since then, a feature
comes about like this:

1. **Specification first.** Every feature starts as a specification in
   [`specs/NNN-name/`](specs/) made with [Spec Kit](https://github.com/github/spec-kit): user
   stories with priorities, acceptance scenarios that can be checked from the keyboard, edge
   cases, what is out of scope, and every deviation from the reference program.
2. **Maintainer approval.** Nothing is planned or coded until the maintainer has agreed on the
   specification.
3. **Plan, tasks, code and tests.** The AI writes the technical plan, the task list and the
   implementation with automated tests, then checks the scenarios in a separate test copy of the
   app, in temporary folders only.
4. **The specification stays the source of truth.** Anything that changes during development is
   first recorded in the specification (a dated *Clarifications* entry), so code and
   specification never drift apart.

Examples: [001-data-safety-gaps](specs/001-data-safety-gaps/spec.md),
[002-function-key-bar](specs/002-function-key-bar/spec.md),
[003-breadcrumb-path-bar](specs/003-breadcrumb-path-bar/spec.md).

What that means for you:

- **This is early development software**, provided without warranty, as the GPL says.
- **Data safety comes first.** File operations are covered by automated tests (more than 600,
  all running in temporary folders only): a complete write before a file is replaced, file
  identity instead of comparing path strings, refusing to copy something into itself, deleting
  to the Trash with a clear report of what failed. Still:
- **Keep a backup of important data** (Time Machine). Please report bugs in the
  [issues](https://github.com/axolotlcommander/axolotl-commander/issues); if a bug could lose
  data, label it `data-safety`.

## Features

- **Panels:** two panels with tabs, detailed and brief view, sorting, filters, selection by
  mask, favorite and recent paths, volume information.
- **Operations:** copy, move, delete to the Trash, rename (also batch rename, with ⌘Z undo),
  new folder, attributes, permissions and Finder tags, checksums, folder sizes, disk map.
  Drag and drop works too.
- **Viewing:** text and hex viewer with encoding detection, wrapping and search. Preview of
  Markdown, HTML (without scripts) and images, plus Quick Look (⌘Y).
- **Comparing:** two files side by side, and the contents of both panels (folders).
- **Archives:** ZIP, 7z and tar (gz/bz2/xz) open like folders; you can copy into them and edit
  their contents. Encrypted ZIP, and RAR (read-only).
- **Servers:** SFTP (through the system `ssh`, so your `~/.ssh/config` applies) and FTP/FTPS,
  passwords in the Keychain, name encodings for older servers.
- **Find:** by name and content, duplicate search, results can be sent to a panel.
- **Customization:** command line, user menu (F9), custom keyboard shortcuts. English and
  Czech user interface.

## Installation

### Prebuilt app

1. Download `Axolotl-Commander-<version>.dmg` (or `.zip`) from
   [Releases](https://github.com/axolotlcommander/axolotl-commander/releases). The app is
   universal (Apple silicon and Intel) and needs **macOS 15 Sequoia or later**.
2. Drag **Axolotl Commander** into the **Applications** folder.
3. **First launch:** until the releases are signed with an Apple Developer ID, macOS blocks
   the app with a message that it cannot be verified. Click *Done*, then go to *System
   Settings → Privacy & Security* and click *Open Anyway* next to Axolotl Commander. This is
   needed only once.

Checksums of the downloads are in `SHA256SUMS.txt` attached to each release.

### From source

You need macOS 15+ and Swift 6.2: either Xcode 26 or just the Command Line Tools
(`xcode-select --install`).

```sh
git clone https://github.com/axolotlcommander/axolotl-commander.git
cd axolotl-commander

swift run AxolotlCommander     # quick start without installing
swift test                     # core tests (run in temporary folders only)

scripts/bundle.sh release      # builds build/Axolotl Commander.app
scripts/install.sh             # installs into ~/Applications and puts an alias on the Desktop
```

`scripts/install.sh` **quits a running Axolotl Commander** before replacing it with the new
build. `UNIVERSAL=1 scripts/bundle.sh release` builds the app for both architectures.

## Getting started

**Function keys.** On a Mac, F1–F12 control brightness, volume and so on by default. Either
hold `fn`, or turn on *System Settings → Keyboard → Keyboard Shortcuts → Function Keys → Use
F1, F2, etc. keys as standard function keys* (Settings → Keyboard in the app shows the current
state and opens that page). The bar at the bottom of the window shows what F1–F12 do and runs
them with a click; hold ⇧, ⌃, ⌥ or ⌘ to see the other commands. The bar and the command line
can be hidden in the View menu. Clashes with system shortcuts (Mission Control,
Spotlight) can be resolved in the app's settings (⌘,) under *Keyboard*, where every command
can be remapped.

**Path bar.** Above each panel the current folder is shown as breadcrumbs: click any part to go
there, ⌘-click to open it in a new tab, right-click for more (other panel, copy path, hot path,
Finder). To type a path, press ⌘L or click right of the path. Settings → Appearance switches back
to the plain text field.

| Key | Command | Key | Command |
|---|---|---|---|
| Tab | switch panel | F7 | new folder |
| F2 | rename | F8 | move to Trash |
| F3 | view | ⇧F8 | delete permanently |
| F4 | edit | F9 | user menu |
| F5 | copy | ⌃F10 | compare panels |
| F6 | move | ⌘Y | Quick Look |
| ⌘F | find files | ⌘K | connect to server |
| ⇧F7 / ⌘⇧G | go to folder | ⌘, | settings |

All commands and their shortcuts are in the menus.

**Permissions.** The first time you open the Desktop, Documents, Downloads, or a network or
removable volume, macOS asks whether to allow access. For folders protected by the system
(such as `~/Library/Mail`) you can add the app to *Privacy & Security → Full Disk Access*,
but it is not required.

**Uninstalling.** Delete the app and, if you like, the settings in
`~/Library/Preferences/cz.acidek.axolotlcommander.plist` and the folder
`~/Library/Application Support/Axolotl Commander`. Saved server passwords are in the Keychain
Access app, with "(Axolotl Commander)" in their name.

## Contributing

Help is welcome: bug reports, ideas, translations and pull requests. See
[CONTRIBUTING.md](CONTRIBUTING.md). Two rules are binding:

- tests work only in temporary folders, never on real data,
- the implementation is clean-room: the reference program's source code is not read or copied.

Everything in the repository is in English; issues and pull requests can be discussed in
English or Czech. The [Code of Conduct](CODE_OF_CONDUCT.md) applies. Report security issues
as described in [SECURITY.md](SECURITY.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Acknowledgments

Thanks to the authors of Open Salamander and Tandem Commander for decades of work on a
keyboard-driven file manager and for releasing it as free software (GPL-2.0-or-later). Thanks
also to the authors of the libraries the app uses: libarchive, libcurl, swift-markdown and
cmark (see [THIRD_PARTY.md](THIRD_PARTY.md)).

## License

Axolotl Commander is free software under the [GNU GPL version 3 or later](LICENSE)
(`GPL-3.0-or-later`). Authors: [AUTHORS](AUTHORS).
