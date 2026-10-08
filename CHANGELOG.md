# Changelog

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

First public release of the source code: a two-panel file manager (stages 0–11 of the plan in
[docs/PLAN.md](docs/PLAN.md)) and the data-safety fixes from the
[001-data-safety-gaps](specs/001-data-safety-gaps/spec.md) specification.

### Added

- Function key bar F1–F12 at the bottom of the main window, following the held modifiers
  (⇧ ⌃ ⌥ ⌘); the bar and the command line can be hidden from the View menu or Settings
  ([002-function-key-bar](specs/002-function-key-bar/spec.md)).
- Settings → Keyboard shows whether F1–F12 need `fn` and opens System Settings; a one-time
  notice on launch explains it.
- Clickable breadcrumb path bar above each panel: click a folder to go there, ⌘-click for a
  new tab, right-click for more; ⌘L (Edit Path) types a path; long paths collapse into "…";
  the text field stays available in Settings → Appearance
  ([003-breadcrumb-path-bar](specs/003-breadcrumb-path-bar/spec.md)).
- Open server connections as buttons in the volume bar: one click returns to the last folder on
  the server, ⏏ on hover or the right-click menu disconnects; the volume menu (⌥F1/⌥F2) lists
  them under "Servers". The volume bar also offers iCloud Drive, Network (mounted network
  volumes, connections, Connect to Server…) and an optional Home button, chosen in Settings →
  Appearance; the toolbar gets Connect to Server, and Disconnect can be added
  ([004-server-connection-buttons](specs/004-server-connection-buttons/spec.md)).
- The macOS prompts for folder access (Desktop, Documents, Downloads, disks, cloud storage)
  explain why a file manager needs it, in English and Czech.
- Releases can be signed with a stable project certificate (`scripts/make-signing-cert.sh`), so
  folder access granted by users survives updates even without an Apple Developer ID; local
  builds are signed with the developer's "Apple Development" certificate when there is one.
