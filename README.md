# Axolotl Commander

Nativní dvoupanelový správce souborů pro macOS ovládaný z klávesnice. Chováním a klávesami
vychází z [Tandem Commanderu](https://github.com/tandemcommander/tandemcommander) a
[Open Salamanderu](https://github.com/OpenSalamander/salamander); implementace je napsaná znovu
ve Swiftu a AppKitu.

## Sestavení

```sh
swift build            # sestavení
swift test             # testy jádra
scripts/bundle.sh      # build/Axolotl Commander.app
```

Vyžaduje macOS 15 a Swift 6.2.

## Licence

Axolotl Commander je svobodný software pod licencí [GNU GPL verze 3 nebo novější](LICENSE)
(`GPL-3.0-or-later`). Původ a poděkování: [NOTICE](NOTICE), autoři: [AUTHORS](AUTHORS),
software třetích stran: [THIRD_PARTY.md](THIRD_PARTY.md).

Axolotl Commander není spojen s autory Tandem Commanderu ani Open Salamanderu.
