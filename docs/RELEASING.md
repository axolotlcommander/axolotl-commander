# Releasing a new version

The release is built and uploaded by GitHub Actions (`.github/workflows/release.yml`); the maintainer
only marks the version with a tag and publishes the draft release.

## Procedure

1. The pull request raised the version with `scripts/bump-version.sh minor|patch`, which writes
   `VERSION` and moves the items from "Unreleased" in [CHANGELOG.md](../CHANGELOG.md) under the new
   version with a date (rules: "Versioning" in [CLAUDE.md](../CLAUDE.md)).
2. It is merged into `main` and CI is green.
3. Tag the merge commit with the version from `VERSION` and push the tag:

   ```sh
   git tag -a "v$(cat VERSION)" -m "Axolotl Commander $(cat VERSION)"
   git push origin "v$(cat VERSION)"
   ```

4. The workflow checks that the tag has the form `vX.Y.Z`, matches `VERSION`, is on `main` and that the signing secrets
   are set (see below), runs the tests, builds a universal app (Apple silicon + Intel) with the
   version from the tag, signs it (and notarizes it with a Developer ID), packages `Axolotl-Commander-X.Y.Z.zip` and `.dmg`
   with `SHA256SUMS.txt`, and creates a **draft** release with automatic notes from pull requests.
5. On GitHub, under *Releases*, review the draft, add notes, and click *Publish release*.

Versions follow [Semantic Versioning](https://semver.org/): before 1.0, `0.MINOR.PATCH`.

## Signing and notarization

Without an Apple Developer ID signature the app works, but macOS blocks it after download
("cannot verify the developer") and the user has to allow it once per download: open it, then
*System Settings → Privacy & Security → Open Anyway*. The draft release notes of such a build
start with these steps ([.github/release-install.md](../.github/release-install.md)).

### Without a Developer ID: the project's own certificate

macOS remembers the folder access users granted (Downloads, Documents, disks…) per signing
certificate. An ad-hoc signed release would make every user grant it again after each update, so
releases are signed with a stable self-signed certificate (the workflow refuses to release without
the signing secrets):

1. Once, on your Mac: `scripts/make-signing-cert.sh` (creates `~/axolotl-signing/`).
2. Add the secrets `MACOS_CERTIFICATE_P12`, `MACOS_CERTIFICATE_PASSWORD` and
   `MACOS_SIGNING_IDENTITY` (`Axolotl Commander Release Signing`) as the script prints them.
   Leave the `NOTARY_*` secrets unset.
3. **Back up `~/axolotl-signing/` and keep it private.** Releases signed with another certificate
   make all users grant folder access again. Never commit it.

The first tag after adding the secrets also checks the signing step on the runner; if it fails,
the draft release is not created and the log of the *Sign* step says why.

### With a Developer ID

With an [Apple Developer Program](https://developer.apple.com/programs/) account (99 USD per year)
the workflow signs and notarizes the app automatically; just add the repository secrets
(*Settings → Secrets and variables → Actions*):

| Secret | Contents |
|---|---|
| `MACOS_CERTIFICATE_P12` | the "Developer ID Application" certificate as .p12, base64-encoded (`base64 -i cert.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | password for the .p12 |
| `MACOS_SIGNING_IDENTITY` | e.g. `Developer ID Application: Name (TEAMID)` |
| `NOTARY_KEY_P8` | App Store Connect API key (.p8), base64-encoded |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | key ID and issuer ID from App Store Connect |

The app is not sandboxed (a file manager needs access to the whole disk), so it is
distributed outside the Mac App Store — via GitHub Releases, possibly a Homebrew Cask later.

## Manually (without GitHub)

```sh
UNIVERSAL=1 scripts/bundle.sh release
ditto -c -k --keepParent "build/Axolotl Commander.app" Axolotl-Commander-$(cat VERSION).zip
```
