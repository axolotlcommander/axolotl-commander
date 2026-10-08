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
