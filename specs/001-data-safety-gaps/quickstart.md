# Quickstart: ověření bezpečnosti dat (001)

Vše běží jen v dočasných složkách a na lokálních testovacích serverech. Žádná operace na
skutečných datech uživatele, žádný skutečný Koš v automatických testech.

## 1. Automatické testy

```sh
swift build                       # bez varování
swift test                        # celá sada zelená, < 10 s
swift test --filter RemoteTransferTests    # D1: přepis na serveru
swift test --filter ArchiveEditStoreTests  # D2: zachování úprav
swift test --filter ArchiveTransferCheck   # D3, D7
swift test --filter DeletePlanTests        # D4
swift test --filter OperationsTests        # D5, D8, US8
swift test --filter PreviewTests           # D6
```

Očekávání: každý test z `tasks.md` u D1–D8 a US8 existuje a selže, když se pojistka v kódu
dočasně vypne (ověřit ručně u D1, D2, D3 jednou).

## 2. Ruční scénáře v GUI (testovací kopie aplikace s vlastním bundle id)

Předpoklad: oba panely v testovací složce (např. `$TMPDIR/axo-001/`).

| # | Scénář | Očekávání |
|---|---|---|
| G1 | SFTP na lokální `sftp-server` (testovací): F5 přes existující soubor | soubor nahrazen, žádný skrytý `.…icmd-old…` nezůstal |
| G2 | F4 na člen ZIPu, upravit, ⌘Q, „Teď ne“; spustit znovu | při startu nabídka vrácení úpravy; po Vrátit je změna v ZIPu |
| G3 | ZIP otevřený přes symlink vlevo a přímo vpravo; F6 `docs` → `docs/old` | odmítnuto, ZIP beze změny |
| G4 | Alt+F5 složky `projekt` do `projekt/zaloha.zip` | odmítnuto před zápisem |
| G5 | F8 na připojeném DMG bez Koše (vytvořit `hdiutil create` v testovací složce) | dotaz „smaže se trvale“, výchozí Zrušit; Zrušit nic nesmaže |
| G6 | Prohlížeč F3 → Uložit jako přes symlink na soubor se štítkem | symlink zůstal, štítek zůstal |
| G7 | `ln a.txt b.txt`; F2 `a.txt` → `b.txt` | hláška „už existuje“; `Zprava`→`zprava` funguje |

## 3. Ruční ověření jen čtením (nepovinné)

Na připojeném USB (FAT/exFAT) nebo SMB svazku spustit jednorázový čtecí skript, který vypíše
`statfs.f_fstypename` a výsledek dotazu na Koš (`FileManager.url(for: .trashDirectory, …,
create: false)`). Nic nezapisuje. Výsledek zapsat do `research.md` (R4, R5).
