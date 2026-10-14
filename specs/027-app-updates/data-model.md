# Data Model: App Updates

## ReleaseInfo (core)

- `version: AppVersion`, `published: Date?`, `page: URL`, `isDraft: Bool`, `isPrerelease: Bool`
- `archive: URL?` (`Axolotl-Commander-X.Y.Z.zip`), `checksums: URL?` (`SHA256SUMS.txt`),
  `changelog: URL?`, `czechChangelog: URL?`
- `isComplete`: archive and checksums present, all HTTPS.

## UpdateState (settings, `updates.*`)

| Key | Type | Exported | Meaning |
|---|---|---|---|
| `updates.automatic` | Bool, default true | yes | check by itself |
| `updates.lastCheck` | Date | no | last attempt (written before the request) |
| `updates.lastSuccess` | Date | no | last successful answer |
| `updates.lastResult` | String `upToDate`/`available`/`failed` | no | for About and Settings |
| `updates.availableVersion` | String | no | the version found |
| `updates.skippedVersion` | String | no | Skip This Version |
| `updates.remindAfter` | Date | no | Remind Me Later (+24 h) |
| `updates.feedURL` | String | no, hidden | test server instead of the API |

Rules (pure functions, with `now`):

- `isDue`: automatic on, and (no `lastCheck`) or (`lastCheck` > now) or (last result failed and
  now − `lastCheck` ≥ 1 h) or (now − `lastSuccess` ≥ 24 h).
- `offer(release, running, manual)`: complete, not draft/pre-release, version > running; if not manual
  also ≠ skipped and now ≥ `remindAfter`.

## Checksums (core)

`[file name: lowercase hex SHA-256]` parsed from `SHA256SUMS.txt`; malformed lines ignored.

## InstallCapability (core)

`.ready` or `.manual(reason)` with reasons `developmentBuild`, `adHocSignature`, `translocated`,
`readOnlyVolume`, `notWritable`; after the download also `signatureMismatch`, `identifierMismatch`,
`versionMismatch`, `checksumMismatch`, `badArchive`.

## Installer steps (core)

`verify(archive, expectedHash, release, appURL)` → the unpacked app URL; `replace(appURL, with:)` → the
Trash URL of the old app; each step throws a typed error; the work folder is removed in every case.
