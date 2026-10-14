# Contract: what the app expects from a release

The app reads one JSON answer and, on the user's consent, downloads files of that release.

## Releases API answer (`releases/latest`)

| Field | Use |
|---|---|
| `tag_name` | `vX.Y.Z` (or `X.Y.Z`); anything else → no offer |
| `draft`, `prerelease` | either true → no offer |
| `published_at` | ISO 8601 date shown as the release date |
| `html_url` | the release page for Download… and links |
| `assets[].name`, `assets[].browser_download_url`, `assets[].size` | the files below |

Unknown fields are ignored; missing required fields → a failed check ("no suitable release").

## Assets

| Name | Required | Content |
|---|---|---|
| `Axolotl-Commander-X.Y.Z.zip` | yes | `ditto -c -k --keepParent` of the signed app |
| `SHA256SUMS.txt` | yes | `shasum -a 256` lines `<hash>  <name>`, one for the zip |
| `CHANGELOG.md` | no | the English changelog at that release |
| `CHANGELOG.cs.md` | no | its Czech translation |

The zip holds exactly one `.app` whose bundle identifier is `cz.acidek.axolotlcommander`, whose
`CFBundleShortVersionString` is X.Y.Z, and whose signature satisfies the running app's designated
requirement.

## Release description

The English section of X.Y.Z, then `## Česky` and the Czech section (after the installation steps for
builds that are not notarized). Made by `scripts/release-notes.sh`.
