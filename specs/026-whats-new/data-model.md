# Data Model: What's New Window

- **AppVersion** — `major`, `minor`, `patch` (Int ≥ 0); `init?(_ text:)` accepts `X.Y.Z`, `vX.Y.Z`, `[X.Y.Z]`;
  `Comparable`; `description` = `X.Y.Z`.
- **ReleaseNote** — `version: AppVersion`, `date: String?` (as written, `YYYY-MM-DD`), `body: String` (Markdown).
- **ReleaseNotes** — `parse(String) -> [ReleaseNote]` (newest first, no Unreleased), `markdown([ReleaseNote])
  -> String`.
- **WhatsNewStart** — `decide(lastRun: String?, running: AppVersion, notes: [ReleaseNote]) -> (show:
  [ReleaseNote], remember: String)`.
- **Setting** — `app.lastRunVersion: String` (UserDefaults, local, not exported).
