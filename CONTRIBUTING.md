# Jak přispět do Axolotl Commanderu

Díky za zájem! Vítané jsou opravy chyb, nové funkce, překlady, testy i hlášení problémů.
Issues a pull requesty můžeš psát česky i anglicky.

*English summary: contributions are welcome in Czech or English. Build with `swift build`,
test with `swift test`, open a pull request against `main`. Please read the two binding rules
below (data safety and clean implementation) and sign off your commits (`git commit -s`).*

## Než začneš

- Menší opravy rovnou pošli jako pull request.
- Větší změnu nebo novou funkci nejdřív navrhni v [issue](https://github.com/ACiDekCZ/axolotl-commander/issues)
  nebo v [Discussions](https://github.com/ACiDekCZ/axolotl-commander/discussions), ať se domluvíme
  na chování dřív, než napíšeš hodně kódu.
- Chování se řídí vzorem — [Tandem Commanderem](https://github.com/tandemcommander/tandemcommander)
  a [Open Salamanderem](https://github.com/OpenSalamander/salamander) — upravené na zvyklosti macOS.
  Plán vývoje je v [docs/PLAN.md](docs/PLAN.md), principy v
  [.specify/memory/constitution.md](.specify/memory/constitution.md).

## Sestavení a testy

Vyžaduje macOS 15+ a Swift 6.2 (Xcode 26 nebo Command Line Tools). Xcode projekt není potřeba.

```sh
swift build                  # sestavení (musí projít bez varování)
swift test                   # testy jádra
swift run AxolotlCommander   # spuštění
scripts/bundle.sh            # build/Axolotl Commander.app
```

Struktura:

- `Sources/CommanderCore` — jádro bez AppKitu (operace, archivy, síť, hledání…). Veškerá
  rozhodovací logika patří sem a má testy.
- `Sources/AxolotlCommander` — uživatelské rozhraní v AppKitu; jen dialogy a volání jádra.
- `Tests/CommanderCoreTests` — testy (Swift Testing).
- `specs/` — specifikace funkcí ([Spec Kit](https://github.com/github/spec-kit)).

## Závazná pravidla

### 1. Bezpečnost dat

Správce souborů nesmí ztratit data. Proto:

- Testy pracují **jen v dočasné složce**, kterou si samy vytvoří
  (`FileManager.default.temporaryDirectory`) a uklidí — viz `Tests/CommanderCoreTests/TestSupport.swift`.
  Nikdy nesahají na skutečné soubory, skutečný Koš, Klíčenku ani skutečné servery
  (síťové testy používají lokální `sftp-server` a `scripts/ftp-test-server.py`).
- Ruční zkoušky operací (kopírování, přesun, mazání…) dělej jen v testovací složce.
- Operace, která by mohla zničit data, se raději odmítne s jasnou hláškou.
- Každá oprava chování má test, který bez opravy selže.

### 2. Čistá implementace (clean room)

Projekt je nová implementace **chování** vzoru, ne převod jeho kódu.

- **Nečti ani nekopíruj C++ zdrojáky** Tandem Commanderu ani Open Salamanderu
  (`src/**/*.cpp|h|rc`). Vzorem je chování spuštěného programu, jeho uživatelská nápověda
  a dokumentace.
- Texty nápovědy a dialogů nepřebírej doslova; napiš vlastní.
- Nová závislost jen s licencí slučitelnou s GPL-3.0; zapiš ji do [THIRD_PARTY.md](THIRD_PARTY.md).

## Konvence

- Kód, identifikátory a komentáře anglicky; dokumentace česky.
- Každý nový zdrojový soubor začíná hlavičkou:

  ```swift
  // SPDX-License-Identifier: GPL-3.0-or-later
  // Copyright (C) 2026 The Axolotl Commander Authors
  ```

- Nové texty v UI patří do `Resources/Localizable.xcstrings` (angličtina je zdroj, čeština překlad).
- Nehotový příkaz v menu zůstává šedý, nepadá.
- Commit zpráva: `[Oblast] stručný popis` (např. `[Archivy] F6 z 7z zachová datum`).

## Pull requesty

1. Udělej fork a větev od `main`.
2. Drž změnu malou a s jedním tématem; přidej testy.
3. `swift build` bez varování a `swift test` zelené (stejně to ověří CI).
4. Otevři pull request a vyplň šablonu. Každý PR potřebuje schválení správce
   (viz [CODEOWNERS](.github/CODEOWNERS)) a zelené CI; do `main` se slučuje přes *squash*.

Větší funkce se dělají přes Spec Kit: `/speckit-specify` → `/speckit-plan` → `/speckit-tasks` →
`/speckit-implement`, specifikace vznikne v `specs/NNN-nazev/` a patří do pull requestu.

## Původ příspěvků (DCO)

Podepiš každý commit volbou `-s` (`git commit -s`). Tím potvrzuješ
[Developer Certificate of Origin](https://developercertificate.org/): příspěvek je tvůj (nebo ho
smíš poskytnout) a souhlasíš s jeho zveřejněním pod licencí GPL-3.0-or-later.

Používáš-li při psaní AI asistenta, odpovídáš za výsledek stejně jako za vlastní kód — včetně
pravidla čisté implementace výše.

## Chování v komunitě

Platí [pravidla chování](CODE_OF_CONDUCT.md). Bezpečnostní chyby hlas soukromě podle
[SECURITY.md](SECURITY.md).
