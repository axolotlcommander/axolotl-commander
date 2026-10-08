# Releasing a new version

The release is built and uploaded by GitHub Actions (`.github/workflows/release.yml`); the maintainer
only marks the version with a tag and publishes the draft release.

## Procedure

1. Everything is merged into `main` and CI is green.
2. In [CHANGELOG.md](../CHANGELOG.md), move the items from "Unreleased" under the new version with a date.
3. Tag and push:

   ```sh
   git tag -a v0.1.0 -m "Axolotl Commander 0.1.0"
   git push origin v0.1.0
   ```

4. The workflow runs the tests, builds a universal app (Apple silicon + Intel) with the version from the tag,
   optionally signs and notarizes it, packages `Axolotl-Commander-0.1.0.zip` and `.dmg`
   with `SHA256SUMS.txt`, and creates a **draft** release with automatic notes from pull requests.
5. On GitHub, under *Releases*, review the draft, add notes, and click *Publish release*.

Versions follow [Semantic Versioning](https://semver.org/): before 1.0, `0.MINOR.PATCH`.

## Signing and notarization

Without an Apple Developer ID signature the app works, but macOS blocks it after download
("cannot verify the developer") and the user has to allow it once: open it, then
*System Settings → Privacy & Security → Open Anyway*.

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
UNIVERSAL=1 VERSION=0.1.0 scripts/bundle.sh release
ditto -c -k --keepParent "build/Axolotl Commander.app" Axolotl-Commander-0.1.0.zip
```
