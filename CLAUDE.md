# iCommander — nativní macOS port Tandem Commanderu

Vzor chování: `../tandemcommander` (Windows, WinAPI). Analýza portu: `../tandemcommander/docs/macos-port/`.
Plán etap a stav práce: `docs/PLAN.md` a `docs/STATE.md`.

## Šetření tokenů a kontextu (závazné)

- **Samostatné úkoly → subagent.** Úkol, který nepotřebuje kontext hlavní session
  (prozkoumání souborů ve vzorovém repu, implementace izolovaného modulu podle jasného
  zadání, psaní testů, hledání v nápovědě), spouštěj přes `Agent`.
  - Model: stejný jako hlavní session pro návrh/složitý kód; `sonnet` pro rutinní
    implementaci podle přesného zadání; `haiku` pro čisté vyhledávání/sumarizaci.
  - Zadání piš úplné a samostatné (cesty, rozhraní, akceptační kritéria), ať agent
    nemusí nic dohledávat. Chtěj zpět jen stručný výsledek, ne výpisy souborů.
- **Nečti velké soubory celé.** `../tandemcommander/CLAUDE.md` má ~150 kB — jen `grep`
  a cílené výřezy. Výstupy příkazů zkracuj (`| head`, `-q`, `2>&1 | tail`).
- **Stav ukládej průběžně** do `docs/STATE.md` (hotové kroky, rozpracované, další krok,
  známé problémy). Po každém dokončeném kroku commit.
- **Nabízej `/compact`**, když je hotová ucelená etapa a stav je zapsaný v `STATE.md`.
- Nová session začíná přečtením `docs/STATE.md`, ne prozkoumáváním celého repa.

## Bezpečnost souborového systému (závazné)

- **Nikdy nespouštěj souborové operace (kopie, přesun, mazání, přejmenování, zápis) na
  skutečných datech uživatele** — ani v GUI testech, ani v unit testech.
- Testy jen v izolovaném adresáři (`FileManager.default.temporaryDirectory`/scratchpad),
  který test sám vytvoří a uklidí. GUI test operací: oba panely nejdřív přesměrovat do
  takového testovacího adresáře, teprve pak posílat F5/F6/F8/F2…
- GUI testy mimo testovací adresář smí jen číst (procházet, vybírat, řadit).
- Mazání vlastních artefaktů (`build/`, `~/Applications/iCommander.app`) je v pořádku.

## Technologie

- Swift + AppKit, Swift Package Manager (`swift build`, `swift test`), bez Xcode projektu.
- Spuštění: `swift run iCommander` nebo `scripts/bundle.sh` → `build/iCommander.app`.
- Jádro (`Sources/CommanderCore`) bez AppKitu → testovatelné `swift test`.
- UI (`Sources/iCommander`) AppKit.

## Konvence

- Kód a identifikátory anglicky, dokumentace česky.
- Commit zprávy: `[Etapa N] stručný popis`.
- Nehotový příkaz v menu zůstává šedý (disabled), nepadá.
