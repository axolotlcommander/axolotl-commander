# Implementation Plan: Bezpečnost dat — mezery z auditu (D1–D8)

**Branch**: `001-data-safety-gaps` | **Date**: 2026-10-08 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-data-safety-gaps/spec.md`

## Summary

Osm mezer v bezpečnosti dat proti pravidlům vzoru (05-pravidla, specs 062/092/103/105/106/107/
112/119) a chybějící testy stávajících pojistek. Přístup (viz [research.md](research.md)):
přepis na serveru přes atomickou výměnu nebo zálohu (R1); úpravy členů archivu v novém
`ArchiveEditStore` v jádru s trvalým úložištěm v Application Support (R2); kontrola „do sebe“
v archivu a při balení podle identity souboru (R3); mazání rozdělené předem na Koš / trvale
s jedním dotazem (R4); `VolumeTraits` a odmítnutí mazacích operací na svazcích bez spolehlivé
identity (R5); „Uložit jako“ přes `SafeFileWriter` (R6); konflikt při přejmenování na jiný
hard link (R7); testy symlinku, neúplného průchodu a kódových jednotek (R8).

## Technical Context

**Language/Version**: Swift 6.2 (striktní souběžnost, upcoming features ExistentialAny,
InternalImportsByDefault, MemberImportVisibility)

**Primary Dependencies**: Foundation, AppKit (jen UI modul), Darwin (`statfs`, `rename`, `link`),
systémové libarchive a libcurl, vlastní SFTP klient nad `ssh`

**Storage**: soubory — `~/Library/Application Support/Axolotl Commander/Edits/` (manifest JSON +
kopie členů archivu); jinak UserDefaults beze změny

**Testing**: Swift Testing (`swift test`), sandbox v `FileManager.default.temporaryDirectory`,
fake `DirectoryFileSystem` pro server, lokální `/usr/libexec/sftp-server`, `scripts/ftp-test-server.py`

**Target Platform**: macOS 15+

**Project Type**: desktop-app (SwiftPM: `CommanderCore` knihovna bez AppKitu + `AxolotlCommander` AppKit)

**Performance Goals**: kontroly identity a Koše nepřidají znatelné zpoždění (cache po dobu
operace, `statfs` jednou na svazek); celá sada testů < 10 s

**Constraints**: žádné operace na skutečných datech v testech; skutečný Koš se v testech nepoužije
(seam `trashItem`); zrušení operace nesmí přerušit výměnu na serveru uprostřed

**Scale/Scope**: ~10 souborů jádra, ~5 souborů UI, ~25 nových testů

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princip | Splnění | Poznámka |
|---|---|---|
| I Bezpečnost dat | ✅ | Cíl celé funkce. Testy jen v sandboxu, fake Koš a fake svazky, lokální testovací servery. |
| II Věrnost vzoru | ✅ | Pravidla 05-pravidla (Identita, Přepsání, Přesun, Archiv); odchylka pro macOS: dotaz na trvalé smazání jako Finder (zapsáno ve spec US4). |
| III Nativní macOS | ✅ | Systémový Koš, `replaceItemAt`, Application Support; UI alerty AppKit; I/O mimo hlavní vlákno (stávající `perform`). |
| IV Testovatelné jádro | ✅ | Logika úprav archivu se stěhuje do jádra (`ArchiveEditStore`); každá oprava má test (FR-025). |
| V Čistá implementace, GPL | ✅ | Bez nových závislostí; vzorem jen dokumentace a specs, ne C++. SPDX hlavičky v nových souborech. |
| VI Postupné dodávání | ✅ | US1–US8 nezávislé; pořadí P1 → P3; commit po každé. |

Re-check po návrhu (Phase 1): beze změny, žádná porušení → Complexity Tracking prázdné.

## Project Structure

### Documentation (this feature)

```text
specs/001-data-safety-gaps/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/core-api.md
├── checklists/requirements.md
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
Sources/CommanderCore/
├── Network/
│   ├── RemoteFileSystem.swift        # + replace(_:over:), RemoteError.replaceIncomplete   (D1)
│   ├── RemoteTransfer.swift          # placeReplacing; upload overwrite, renameOnServer       (D1)
│   ├── SFTP/SFTPClient.swift         # replace přes posix-rename@openssh.com                  (D1)
│   └── FTP/FTPClient.swift           # replace přes RNFR/RNTO bez předkontroly                (D1)
├── Archive/
│   ├── ArchiveEditStore.swift        # NOVÉ: PendingEdit, manifest, stavy                     (D2)
│   ├── ArchiveTransferCheck.swift    # NOVÉ: validate, validatePack                           (D3, D7)
│   ├── ArchiveWriter.swift           # update(..., expecting: PersistentFileStamp?)          (D2)
│   └── ArchiveFormat.swift           # ArchiveError.changedSinceRead                          (D2)
├── Operations/
│   ├── FileIdentity.swift            # reliable, linkCount, PersistentFileStamp, VolumeTraits (D5, D8, D2)
│   ├── TransferPlan.swift            # identityUnknown na nespolehlivém svazku; lone symlink  (D5, US8)
│   ├── TransferRun.swift             # resolve; unlink samotného odkazu po kopii              (D5, US8)
│   └── TrashSupport.swift            # NOVÉ: isAvailable                                       (D4)
└── FileOperations.swift              # Options seamy, planDelete, trash → TrashReport, rename (D4, D8)

Sources/AxolotlCommander/
├── AppDelegate.swift                 # ukončení/start: cleanupForQuit, loadPending            (D2)
├── ArchiveOperations.swift           # ArchiveEdits → tenká vrstva nad store; volání checků   (D2, D3, D7)
├── OperationsController.swift        # F8 plán + dotaz + report; texty nových chyb           (D1, D4)
├── Find/FindWindowController.swift   # mazání z výsledků hledání přes nový plán               (D4)
└── Viewer/ViewerWindowController.swift  # saveCopy přes SafeFileWriter                        (D6)

Tests/CommanderCoreTests/
├── TestSupport.swift                 # NOVÉ: withSandbox, fake svazky/Koš
├── RemoteTransferTests.swift         # D1 (+ fake atomicReplace, injekce chyb)
├── SFTPTests.swift / FTPTests.swift  # replace proti lokálním serverům
├── ArchiveEditStoreTests.swift       # NOVÉ, D2
├── ArchiveTransferCheckTests.swift   # NOVÉ, D3, D7
├── DeletePlanTests.swift             # NOVÉ, D4
├── OperationsTests.swift             # D5, D8, US8
├── PreviewTests.swift                # D6
└── PanelModelTests.swift             # US8 kódové jednotky (oprava porovnání)
```

**Structure Decision**: Stávající dvoumodulová struktura. Veškerá rozhodovací logika v
`CommanderCore` (testovatelná), UI jen dotazy a volání.

## Pořadí implementace

1. Společné: `TestSupport.swift`, `VolumeTraits`/`PersistentFileStamp`/`linkCount` (základ pro D2, D5, D8).
2. P1: D1 (US1) → D2 (US2) → D3 + D7 (US3).
3. P2: D4 (US4) → D5 (US5) → D6 (US6).
4. P3: D8 (US7) → US8 testy.
5. Závěr: celá sada testů, GUI scénáře G1–G7 z [quickstart.md](quickstart.md) v testovací kopii,
   zápis do STATE, vedlejší nález `ArchiveCatalog.invalidate` do STATE (mimo rozsah).

## Complexity Tracking

Žádná porušení ústavy.
