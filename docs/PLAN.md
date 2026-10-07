# Plán portu — etapy

Zdroj: analýza `../tandemcommander/docs/macos-port/` (kroky 0–12, ovládání, pravidla).
Tento plán ji přebírá a upravuje architekturu tak, aby pozdější etapy nevyžadovaly přepis.
Klávesy a chování: `../tandemcommander/docs/macos-port/02-ovladani.md`.
Pojistky do testů: `../tandemcommander/docs/macos-port/05-pravidla.md`.

## Architektura (rozdíl proti analýze)

| Vrstva | Volba | Proč |
|---|---|---|
| Build | SwiftPM (`Package.swift`), `scripts/bundle.sh` → `.app` | Bez `.xcodeproj`, vše textové, build/test z terminálu |
| `CommanderCore` | Čistý Swift, bez AppKitu | Model panelu, výběr, řazení, masky, pravidla jmen/cest/identity, operace. Pokryto `swift test` |
| `iCommander` | AppKit | Okno, panely (`NSTableView`), menu, dialogy |
| Příkazy | `Command` enum + `CommandRegistry` (titulek, menu, výchozí zkratka, `isImplemented`) | Menu, šedé položky, zkratky i přemapování (etapa 11) z jednoho zdroje |
| Klávesy | `KeyChord` → `Command` přes `KeyMap` v jádru | Testovatelné bez UI; F-klávesy zachytí okno dřív než systém |
| Zdroj souborů | protokol `FileSource` (`LocalFileSource` teď, `ArchiveFileSource`/`RemoteFileSource` později) | Panel nezná, odkud položky jsou |
| Výpis | `FileManager` s předanými resource keys (interně `getattrlistbulk`) na pozadí; vlastní `getattrlistbulk` jen pokud měření ukáže potřebu | Jednodušší, stejně rychlé pro běžné adresáře |
| Identita | `URLResourceKey.fileResourceIdentifierKey` + volume UUID, fallback `stat` (dev, ino) | Pravidlo „identita, ne text cesty" |
| Nastavení | plist v `~/Library/Application Support/iCommander/` | — |

## Etapy

Každá etapa končí: build bez varování, `swift test` zelené, scénář z klávesnice projde ručně,
nehotové příkazy v menu šedé, commit, zápis do `docs/STATE.md`.

### Milník A — první použitelná verze

| # | Etapa | Obsah | Hotovo, když |
|---|---|---|---|
| 0 | Kostra | Package, app bundle, okno se 2 panely, celé menu z registru (šedé), Tab přepíná panel, F-klávesy dorazí jako příkaz, Nastavení (Cmd+,) okno, Esc zpět | Tab, Cmd+,, Esc, Cmd+Q funguje; F5 zaloguje příkaz |
| 1 | Prohlížení disku | Výpis (jméno, přípona, velikost, datum), složky nahoře, `..`, řazení Ctrl+F3–F6 (2. stisk obrátí), pohyb, Enter/Backspace/Ctrl+\, historie Ctrl+Opt+←/→, řádek cesty s editací, menu svazků Ctrl+Opt+F1/F2, quick search psaním, Ctrl+F9, auto-refresh (FSEvents), pravidlo jmen (case/NFC-NFD) a délky cesty | Projdu disk z klávesnice, vnější změna se ukáže |
| 2 | Výběr | Insert, mezerník (+ velikost složky), Shift+pohyb, maska Num+/−/* (+ Ctrl+=, Ctrl+−, Ctrl+8), Shift+Num± přípona, Cmd+A / Cmd+Shift+A, info řádek (počet + součet), filtr Ctrl+F12, jméno/cesta do schránky | Výběr přežije řazení i refresh |
| 3 | Operace | F5/F6 s dialogem (cíl = druhý panel, maska jména), průběh + Storno na pozadí, dotaz na existující cíl, F7, F8/Delete → Koš, Shift+Delete natrvalo, F2 přejmenování na místě, Drag&Drop, Cmd+C/Cmd+V soubory. **Pojistky s testy:** kopie na sebe (identita), složka do potomka, atomické přepsání (temp + výměna), přesun přes symlink adresáře nesmaže zdroj | 6 testů z pravidel padá na porušení |

### Milník B — denní nástroj

| # | Etapa | Obsah |
|---|---|---|
| 4 | Spouštění a příkazový řádek | Enter otevře přes `NSWorkspace`, spodní příkazový řádek (Ctrl+Tab, Ctrl+Enter, Ctrl+mezerník, Ctrl+[/]), Ctrl+/ Terminál, Shift+F3 Finder, Cmd+I vlastnosti, F3 Quick Look |
| 5 | Okno commanderu | Dělítko + paměť, Ctrl+F11 maximalizace panelu, stručný režim (mřížka), hlavička klikem řadí, lišta svazků, toolbar, barvy a zvýraznění masek, záložky (Ctrl+Shift+T/W/PgUp/PgDn), oblíbené cesty Shift+F9, Shift+F7 dialog cesty, Ctrl+F10 porovnání panelů, Ctrl+Shift+F10 velikosti, uložení rozložení |
| 6 | Prohlížeč a editor | F3 vlastní text/hex prohlížeč (kódování BOM/UTF-8/volba, hledání, další soubor), F4 editor z nastavení, Shift+F4 nový soubor |
| 7 | Hledání | Ctrl+Opt+F7: maska, datum, text; výsledek jako panel; Storno; duplicity jméno+velikost |

### Milník C — přírůstky

| # | Etapa | Obsah |
|---|---|---|
| 8 | Archivy | `ArchiveFileSource`: ZIP/tar (libarchive), 7z/RAR čtení (`7zz`); 8a procházení/vytažení/přidání, 8b úprava člena s pravidly |
| 9 | Síť | FTP/SFTP jako `RemoteFileSource`, Keychain, hesla mimo historii |
| 10 | Prohlížeče podle typu | Markdown (WKWebView), obrázky (ImageIO), zvýraznění kódu, porovnání souborů |
| 11 | Pokročilé | Práva/příznaky/štítky, velikost písmen, checksumy, dávkové přejmenování, disk map, user menu F9, nastavení kláves, duplicity podle obsahu |
| 12 | Pluginy | Jen s konkrétním rozšiřujícím oknem |

## Jak pracovat (úspora tokenů)

- Izolované moduly jádra s jasným rozhraním (masky, pravidla jmen, řazení, operace + testy)
  → subagent (`sonnet`), zadání obsahuje rozhraní a akceptační testy.
- Hledání v nápovědě vzoru (`../tandemcommander/help/src/hh/salamand/*.htm`) → subagent
  (`haiku`), vrací jen pravidla v bodech.
- Hlavní session: architektura, AppKit integrace, review, commit, `STATE.md`.
