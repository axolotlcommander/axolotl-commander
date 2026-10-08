# Quickstart: verifying data safety (001)

Everything runs only in temporary folders and on local test servers. No operation on the user's
real data, no real Trash in the automated tests.

## 1. Automated tests

```sh
swift build                       # no warnings
swift test                        # whole suite green, < 10 s
swift test --filter RemoteTransferTests    # D1: overwrite on a server
swift test --filter ArchiveEditStoreTests  # D2: keeping edits
swift test --filter ArchiveTransferCheck   # D3, D7
swift test --filter DeletePlanTests        # D4
swift test --filter OperationsTests        # D5, D8, US8
swift test --filter PreviewTests           # D6
```

Expectation: every test from `tasks.md` for D1–D8 and US8 exists and fails when the safeguard in
the code is temporarily switched off (verify manually once for D1, D2, D3).

## 2. Manual scenarios in the GUI (test copy of the app with its own bundle id)

Prerequisite: both panels in a test folder (e.g. `$TMPDIR/axo-001/`).

| # | Scenario | Expectation |
|---|---|---|
| G1 | SFTP to a local (test) `sftp-server`: F5 over an existing file | file replaced, no hidden `.…icmd-old…` left behind |
| G2 | F4 on a ZIP member, edit, ⌘Q, "Not Now"; launch again | at startup an offer to save the edit back; after "Save Back" the change is in the ZIP |
| G3 | ZIP open via a symlink on the left and directly on the right; F6 `docs` → `docs/old` | rejected, ZIP unchanged |
| G4 | Alt+F5 of the folder `projekt` into `projekt/zaloha.zip` | rejected before any write |
| G5 | F8 on a mounted DMG without a Trash (create with `hdiutil create` in the test folder) | prompt "will be deleted permanently", default Cancel; Cancel deletes nothing |
| G6 | Viewer F3 → Save As over a symlink to a file with a label | symlink stayed, label stayed |
| G7 | `ln a.txt b.txt`; F2 `a.txt` → `b.txt` | message "already exists"; `Zprava`→`zprava` works |

## 3. Read-only manual verification (optional)

On a mounted USB (FAT/exFAT) or SMB volume, run a one-off read-only script that prints
`statfs.f_fstypename` and the result of the Trash query (`FileManager.url(for: .trashDirectory, …,
create: false)`). It writes nothing. Record the result in `research.md` (R4, R5).
