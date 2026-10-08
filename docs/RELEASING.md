# Vydání nové verze

Vydání sestavuje a nahrává GitHub Actions (`.github/workflows/release.yml`); správce jen
označí verzi tagem a návrh vydání zveřejní.

## Postup

1. V `main` je vše sloučené a CI zelené.
2. V [CHANGELOG.md](../CHANGELOG.md) přesunout položky z „Nevydáno“ pod novou verzi s datem.
3. Tag a push:

   ```sh
   git tag -a v0.1.0 -m "Axolotl Commander 0.1.0"
   git push origin v0.1.0
   ```

4. Workflow spustí testy, sestaví univerzální aplikaci (Apple silicon + Intel) s verzí z tagu,
   případně ji podepíše a notarizuje, zabalí `Axolotl-Commander-0.1.0.zip` a `.dmg`
   se `SHA256SUMS.txt` a vytvoří **návrh** vydání s automatickými poznámkami z pull requestů.
5. Na GitHubu v *Releases* návrh zkontrolovat, doplnit poznámky a kliknout na *Publish release*.

Verze se řídí [Semantic Versioning](https://semver.org/lang/cs/): do 1.0 `0.MINOR.PATCH`.

## Podpis a notarizace

Bez podpisu Apple Developer ID aplikace funguje, ale macOS ji po stažení zablokuje
(„nelze ověřit vývojáře“) a uživatel ji musí jednou povolit: otevřít, pak
*Nastavení systému → Soukromí a zabezpečení → Přesto otevřít*.

S účtem [Apple Developer Program](https://developer.apple.com/programs/) (99 USD ročně)
workflow aplikaci podepíše a notarizuje automaticky, stačí přidat tajemství repozitáře
(*Settings → Secrets and variables → Actions*):

| Tajemství | Obsah |
|---|---|
| `MACOS_CERTIFICATE_P12` | certifikát „Developer ID Application“ jako .p12, v base64 (`base64 -i cert.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | heslo k .p12 |
| `MACOS_SIGNING_IDENTITY` | např. `Developer ID Application: Jméno (TEAMID)` |
| `NOTARY_KEY_P8` | API klíč App Store Connect (.p8) v base64 |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | ID klíče a vydavatele z App Store Connect |

Aplikace není v sandboxu (správce souborů potřebuje přístup k celému disku), proto se
distribuuje mimo Mac App Store — přes GitHub Releases, později případně Homebrew Cask.

## Ručně (bez GitHubu)

```sh
UNIVERSAL=1 VERSION=0.1.0 scripts/bundle.sh release
ditto -c -k --keepParent "build/Axolotl Commander.app" Axolotl-Commander-0.1.0.zip
```
