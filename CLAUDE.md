# Axolotl Commander — nativní macOS port Tandem Commanderu

Vzor chování: [Tandem Commander](https://github.com/tandemcommander/tandemcommander) (Windows,
WinAPI), naklonovaný vedle tohoto repa jako `../tandemcommander`. Analýza portu:
`../tandemcommander/docs/macos-port/`.
Plán etap: `docs/PLAN.md`.
Principy: `.specify/memory/constitution.md`. Nové funkce přes Spec Kit (`/speckit-specify` →
`/speckit-plan` → `/speckit-tasks` → `/speckit-implement`), specifikace v `specs/NNN-nazev/`.
Soukromé pokyny pro vlastní stroj patří do `CLAUDE.local.md` (je v `.gitignore`).

## Postup práce

- Po každém dokončeném kroku commit (build bez varování, `swift test` zelené).
- Nečti velké soubory celé: `../tandemcommander/CLAUDE.md` má ~150 kB — jen `grep`
  a cílené výřezy.

## Bezpečnost souborového systému (závazné)

- **Nikdy nespouštěj souborové operace (kopie, přesun, mazání, přejmenování, zápis) na
  skutečných datech uživatele** — ani v GUI testech, ani v unit testech.
- Testy jen v izolovaném adresáři (`FileManager.default.temporaryDirectory`), který test sám
  vytvoří a uklidí. GUI test operací: oba panely nejdřív přesměrovat do takového testovacího
  adresáře, teprve pak posílat F5/F6/F8/F2…
- GUI testy mimo testovací adresář smí jen číst (procházet, vybírat, řadit).
- GUI testy pouštěj na kopii aplikace s vlastním bundle id (ne `cz.acidek.axolotlcommander`),
  ať nesahají na nastavení nainstalované aplikace.
- Mazání vlastních artefaktů (`build/`) je v pořádku.

## Licence a čistota implementace (závazné)

- Projekt je `GPL-3.0-or-later`. Každý nový zdrojový soubor začíná hlavičkou
  `// SPDX-License-Identifier: GPL-3.0-or-later` + `// Copyright (C) 2026 The Axolotl Commander Authors`.
- Vzorem je **chování**: nápověda (`../tandemcommander/help/`), `docs/macos-port/`, `specs/`
  a spuštěný program. **C++ zdrojáky vzoru (`../tandemcommander/src/**/*.cpp|h|rc`) nečíst
  ani necitovat** — ani v subagentech. Výjimka jen na výslovný pokyn správce projektu, a pak
  zapsat do `NOTICE`, co se odkud převzalo.
- Texty nápovědy a dialogů nepřebírat doslovně; psát vlastní formulace.
- Nová závislost jen s licencí slučitelnou s GPL-3.0; zapsat do `THIRD_PARTY.md`.

## Technologie

- Swift + AppKit, Swift Package Manager (`swift build`, `swift test`), bez Xcode projektu.
- Spuštění: `swift run AxolotlCommander` nebo `scripts/bundle.sh` → `build/Axolotl Commander.app`.
- Jádro (`Sources/CommanderCore`) bez AppKitu → testovatelné `swift test`.
- UI (`Sources/AxolotlCommander`) AppKit.

## Konvence

- Kód a identifikátory anglicky, specifikace (`specs/`) anglicky, ostatní dokumentace česky.
- Nová funkce: nejdřív diskuse v chatu (česky), po odsouhlasení shrnutí ji agent zapíše
  přes `/speckit-specify` anglicky; specifikace `001-…` zůstává česky.
- Commit zprávy: `[Etapa N] stručný popis` (mimo etapy `[Oblast] popis`).
- Nehotový příkaz v menu zůstává šedý (disabled), nepadá.
