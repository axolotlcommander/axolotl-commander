<!--
Sync Impact Report
- Version: — → 1.0.0 (první ratifikace)
- Principy: I Bezpečnost dat, II Věrnost chování vzoru, III Nativní macOS, IV Testovatelné jádro,
  V Čistá implementace a GPL, VI Postupné dodávání
- Šablony: plan/spec/tasks-template.md beze změn (Constitution Check čte tento soubor)
- Odložené: žádné
-->

# Ústava Axolotl Commanderu

Ústava platí pro veškerou práci ve Spec Kitu (`/speckit-*`) i mimo něj. Provozní detaily
(cesty, skripty, testovací aplikace) jsou v `CLAUDE.md`, plán etap v `docs/PLAN.md`.

## Základní principy

### I. Bezpečnost uživatelských dat (NEPŘEKROČITELNÉ)

- Žádná souborová operace (kopie, přesun, mazání, přejmenování, zápis) na skutečných datech
  uživatele — ani v unit testech, ani v GUI testech, ani při ladění.
- Testy pracují jen v adresáři, který samy vytvoří v `temporaryDirectory`/scratchpadu a uklidí.
  GUI test operací nejdřív přesměruje oba panely do testovacího adresáře.
- Destruktivní příkazy v aplikaci se ptají, mažou do Koše (pokud to svazek umí) a hlásí chyby;
  nikdy tiše nepřepisují.

*Proč:* správce souborů, který jednou ztratí data, už nikdo nepoužije.

### II. Věrnost chování vzoru

- Klávesy, příkazy, dialogy a výsledek operací odpovídají Tandem Commanderu / Open Salamanderu
  (nápověda `../tandemcommander/help/`, `../tandemcommander/docs/macos-port/`).
- Odchylka je dovolená jen tam, kde macOS má silnou konvenci (⌘ zkratky, Koš, svazky místo
  písmen, menu bar), nebo kde ji zachytí systém; každá odchylka se zapíše do specifikace.
- Nehotový příkaz je v menu šedý, nikdy nepadá.

### III. Nativní macOS, moderně

- Swift 6 (striktní souběžnost), AppKit, SwiftPM bez `.xcodeproj`; minimální systém macOS 15.
- Systémové služby místo vlastních (Koš, Finder, Quick Look, Keychain, Terminál, NSWorkspace).
- Žádné blokování hlavního vlákna u I/O; dlouhé operace jdou zrušit a ukazují průběh.
- Lokalizace přes String Catalog (en, cs); UI texty se nepíšou natvrdo bez `String(localized:)`.

### IV. Testovatelné jádro

- `CommanderCore` nezávisí na AppKitu; logika (model panelu, masky, operace, parsery) žije
  v jádru a je pokrytá `swift test` (Swift Testing).
- Každá oprava chyby v jádru přidá test, který chybu zachytí.
- Build bez varování a zelené testy jsou podmínkou commitu.

### V. Čistá implementace a GPL

- Licence `GPL-3.0-or-later`; každý zdrojový soubor nese SPDX hlavičku.
- Vzorem je chování a dokumentace, ne kód: C++ zdrojáky vzoru (`../tandemcommander/src/`) se
  nečtou ani necitují (výjimka jen na výslovný pokyn uživatele a se zápisem do `NOTICE`).
  Texty nápovědy a dialogů se formulují nově.
- Závislosti jen s licencí slučitelnou s GPL-3.0, zapsané v `THIRD_PARTY.md`.

### VI. Postupné dodávání

- Práce po etapách z `docs/PLAN.md`; každá funkce je samostatně dokončitelná a použitelná.
- Jednodušší řešení má přednost (YAGNI); optimalizace až po měření.
- Po každém kroku commit `[Etapa N] popis`.

## Postup vývoje (Spec Kit)

1. `/speckit-specify` — specifikace funkce v `specs/NNN-nazev/spec.md` (co a proč, chování
   podle vzoru, odchylky pro macOS, akceptační scénáře z klávesnice).
2. `/speckit-clarify` (volitelně) — doptání nejasností před plánem.
3. `/speckit-plan` — technický plán; sekce *Constitution Check* ověří principy I–VI.
4. `/speckit-tasks` → `/speckit-analyze` (volitelně) → `/speckit-implement`.
5. Hotovo = build bez varování, `swift test` zelené, scénář z klávesnice ověřen v testovací
   aplikaci.

Drobné opravy (chyba, úprava rozvržení) nemusí projít celým cyklem; stačí test a commit.

## Správa ústavy

- Ústava má přednost před ostatními postupy; konflikt se řeší změnou ústavy, ne výjimkou.
- Změna: úprava tohoto souboru se zdůvodněním, zvýšení verze (MAJOR = zrušení/změna principu,
  MINOR = nový princip nebo sekce, PATCH = upřesnění), aktualizace dotčených šablon.
- Revize souladu: každý plán (`plan.md`) a každá revize kódu.

**Verze**: 1.0.0 | **Ratifikováno**: 2026-10-08 | **Poslední změna**: 2026-10-08
