# Research: What's New Window

## R1. Version numbers

- **Decision**: `AppVersion(major, minor, patch)` parsed from `X.Y.Z` with an optional leading `v` and
  optional surrounding brackets; anything else is not a version (nil). Compared by numbers.
- **Rationale**: The project follows Semantic Versioning without pre-release tags (`VERSION`, tags
  `vX.Y.Z`); text comparison would put 0.10.0 before 0.9.9. The update spec reuses the type.
- **Alternatives**: `String.compare(options: .numeric)` — accepts garbage silently.

## R2. Parsing the changelog

- **Decision**: Split at lines starting with `## `. A heading `## [X.Y.Z] - YYYY-MM-DD` (brackets, the date and
  the dash optional) starts a version; `## [Unreleased]` and text before the first version are dropped. The
  body is the text up to the next `## ` heading, trimmed. Result sorted newest first; a repeated version keeps
  the first section.
- **Rationale**: The format is fixed by the project (Keep a Changelog). Splitting by headings keeps any other
  Markdown inside a section unchanged.

## R3. The page

- **Decision**: `## X.Y.Z — date` headings (an en dash when there is no date: just the version), then the
  body with its `###` headings; rendered by `MarkdownRenderer.render(_, allowRemote: false)`. On demand all
  versions; after an update the chosen range. Empty → a localized line "No release notes are available."
- **Rationale**: Reuses the viewer's renderer (CSP without scripts and remote loads, light/dark CSS).

## R4. The start decision

- **Decision**: `decide(lastRun: String?, running: AppVersion, notes:) -> (show: [ReleaseNote], remember:
  String)`: `show` = notes with `lastRun < version <= running` when `lastRun` parses and is older than
  `running`, else empty; `remember` = the running version. The app writes `remember` before showing (two
  copies: the second reads the new value and shows nothing).
- **Key**: `app.lastRunVersion` (local to this Mac; listed in `SettingsCatalog.notExported`).
- **Timing**: 1 s after `applicationDidFinishLaunching`; while a modal window or a sheet is up, it retries
  every second; it opens without becoming key when a sheet is open (shown later otherwise).

## R5. The window

- **Decision**: `NSWindowController` with a `WKWebView` (non-persistent data store, JavaScript off), a Close
  button (default, Return), `cancelOperation` (Esc) and ⌘W closing; frame autosave name `WhatsNewWindow`;
  links (`linkActivated`) open with `NSWorkspace` and the navigation is cancelled. One shared controller.
- **Rationale**: The viewer already shows such pages; the policy keeps it offline (FR-007).

## R6. About window

- **Decision**: Our own About window (icon, name, "Version X.Y.Z", the credits HTML as an attributed text
  with clickable links, the copyright from the Info.plist) with a "What's New…" button. Help → About opens it.
- **Rationale**: The standard about panel shows credits but cannot run an app action from them; a custom URL
  scheme would route through Launch Services and could reach another installed copy (the GUI test copy has
  its own bundle id). The update spec adds the update status to the same window.
- **Alternatives**: a URL scheme `axolotlcommander://whats-new` in the credits — rejected (above).

## R7. Testing

- Unit: `ReleaseNotesTests` — version parse/compare, changelog parse (headings with and without brackets or
  date, Unreleased dropped, preamble dropped, body kept), page Markdown, start decision (update, skipped
  versions, same, downgrade, first start, garbage).
- GUI (test copy): see quickstart.md.
