<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Axolotl Commander">
</p>

# Axolotl Commander

[![CI](https://github.com/ACiDekCZ/axolotl-commander/actions/workflows/ci.yml/badge.svg)](https://github.com/ACiDekCZ/axolotl-commander/actions/workflows/ci.yml)
[![License: GPL v3+](https://img.shields.io/badge/license-GPL--3.0--or--later-blue.svg)](LICENSE)

Nativní dvoupanelový správce souborů pro macOS ovládaný z klávesnice. Chováním a klávesami
vychází z [Tandem Commanderu](https://github.com/tandemcommander/tandemcommander) a
[Open Salamanderu](https://github.com/OpenSalamander/salamander); implementace je napsaná znovu
ve Swiftu a AppKitu.

*A native, keyboard-driven two-panel file manager for macOS, modeled on the behavior of Tandem
Commander and Open Salamander and written from scratch in Swift and AppKit. Contributions in
English are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).*

> **Stav:** ve vývoji, zatím bez vydané verze. Funkce níže fungují; zkoušej je ale na datech,
> o která nemůžeš přijít, nebo na jejich kopii.

## Co umí

- Dva panely, záložky, oblíbené a nedávné cesty, stručné zobrazení, porovnání složek.
- Kopírování, přesun, mazání do Koše, přejmenování (i hromadné), atributy a štítky Finderu,
  kontrolní součty, mapa disku — s důrazem na bezpečnost dat (úplný zápis před nahrazením,
  identita souborů místo textu cest, odmítnutí operací „do sebe“).
- Archivy ZIP, 7z, tar (gz/bz2/xz) jako složky; RAR pro čtení.
- SFTP (přes systémové `ssh`) a FTP/FTPS, hesla v Klíčence.
- Prohlížeč textu a hexu s rozpoznáním kódování, náhled Markdownu a obrázků, porovnání souborů.
- Hledání podle jména a obsahu, duplicity, výsledky do panelu.
- Příkazová řádka, uživatelské menu, vlastní klávesové zkratky; čeština a angličtina.

## Sestavení

Vyžaduje macOS 15+ a Swift 6.2 (Xcode 26 nebo Command Line Tools).

```sh
swift build            # sestavení
swift test             # testy jádra
scripts/bundle.sh      # build/Axolotl Commander.app
scripts/install.sh     # ~/Applications/Axolotl Commander.app
```

## Přispívání

Návod je v [CONTRIBUTING.md](CONTRIBUTING.md) — hlavně dvě závazná pravidla: testy jen
v dočasných složkách a čistá implementace (zdrojáky vzoru se nečtou ani nekopírují).
Platí [pravidla chování](CODE_OF_CONDUCT.md); bezpečnostní chyby hlas podle [SECURITY.md](SECURITY.md).

## Původ a poděkování

Axolotl Commander je nová implementace chování
[Tandem Commanderu](https://github.com/tandemcommander/tandemcommander), který vychází
z [Open Salamanderu](https://github.com/OpenSalamander/salamander) (dříve Altap Salamander).
Díky jejich autorům za desítky let práce na klávesnicově ovládaném správci souborů a za jejich
uvolnění jako svobodného softwaru (GPL-2.0-or-later). Rozložení kláves, příkazy, dialogy
a chování vycházejí z těchto programů a jejich nápovědy; podrobnosti v [NOTICE](NOTICE).

Axolotl Commander není spojen s autory Tandem Commanderu ani Open Salamanderu a není jimi
podporován. Názvy těchto programů patří jejich projektům.

## Licence

Axolotl Commander je svobodný software pod licencí [GNU GPL verze 3 nebo novější](LICENSE)
(`GPL-3.0-or-later`). Autoři: [AUTHORS](AUTHORS), software třetích stran:
[THIRD_PARTY.md](THIRD_PARTY.md).
