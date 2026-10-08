---
description: "Task list: Bezpečnost dat — mezery z auditu (D1–D8)"
---

# Tasks: Bezpečnost dat — mezery z auditu (D1–D8)

**Input**: `specs/001-data-safety-gaps/` — [plan.md](plan.md), [spec.md](spec.md),
[research.md](research.md), [data-model.md](data-model.md), [contracts/core-api.md](contracts/core-api.md),
[quickstart.md](quickstart.md)

**Tests**: POVINNÉ (FR-025, ústava IV). V každém příběhu nejdřív test, který selže, pak oprava.
Testy jen v sandboxu (`FileManager.default.temporaryDirectory`), fake Koš/svazky, lokální servery.

**Konvence**: nový soubor začíná SPDX hlavičkou (`// SPDX-License-Identifier: GPL-3.0-or-later`
+ `// Copyright (C) 2026 The Axolotl Commander Authors`); C++ zdrojáky vzoru nečíst; po každém
příběhu `swift build` bez varování, `swift test` zelené, commit `[Spec 001] USn …`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: lze dělat paralelně (jiný soubor, bez závislosti na nedokončeném úkolu)
- **[Story]**: US1–US8 ze spec.md

---

## Phase 1: Setup

- [X] T001 Vytvořit `Tests/CommanderCoreTests/TestSupport.swift`: sdílené `withSandbox(_:)` (vytvoří a uklidí složku v `temporaryDirectory`), `write(_:_:)`, `read(_:)`, `names(in:)`; stávající privátní varianty v testových souborech ponechat (sjednotit jen tam, kde se soubor stejně mění)

---

## Phase 2: Foundational (blokuje US2, US5, US7)

- [X] T002 V `Sources/CommanderCore/Operations/FileIdentity.swift` přidat `linkCount` do `FileStat` (z `st_nlink`) a doc komentář u `FileIdentity`: „platí jen během jednoho připojení svazku, nikdy neukládat“
- [X] T003 V `Sources/CommanderCore/Operations/FileIdentity.swift` přidat `public struct VolumeTraits: Sendable, Equatable { identityReliable: Bool; uuid: String? }` a `static func of(_ url: URL) -> VolumeTraits` podle `statfs.f_fstypename` — `apfs`, `hfs` → reliable; vše ostatní (msdos, exfat, smbfs, afpfs, nfs, webdav, ntfs, fuse, neznámé) → nereliable; `uuid` z `URLResourceKey.volumeUUIDStringKey`
- [X] T004 V `Sources/CommanderCore/Operations/FileIdentity.swift` přidat `public struct PersistentFileStamp: Codable, Sendable, Equatable { volumeUUID: String?; fileID: UInt64; size: Int64; modified: Int64 /* mtime ns */ }` + `init?(_ url: URL)`
- [X] T005 [P] Testy T002–T004 v `Tests/CommanderCoreTests/FileIdentityTests.swift` (nový): `linkCount == 2` po `link(2)`, sandbox na APFS → `identityReliable`, `PersistentFileStamp` se změní po zápisu a je Codable round-trip

---

## Phase 3: User Story 1 — Přepis na serveru nezničí starou verzi (P1) 🎯 MVP

**Goal**: FR-001–004. **Independent Test**: fake server selže ve výměně → cíl má starý obsah nebo hláška uvede, kde je která verze.

### Tests (nejdřív, musí selhat)

- [X] T006 [US1] Rozšířit fake `DirectoryFileSystem` v `Tests/CommanderCoreTests/RemoteTransferTests.swift:10-84` o přepínač `atomicReplace` (replace přes `rename(2)`), injekci chyb `failRename(from:to:times:)` a log volání
- [X] T007 [US1] Testy v `Tests/CommanderCoreTests/RemoteTransferTests.swift`: (a) atomický přepis — v logu není `removeFile(final)`; (b) bez atomického replace selže `temp→final` → cíl má starý obsah, temp ani záloha nezůstanou; (c) selže výměna i obnova zálohy → `RemoteError.replaceIncomplete` nese `newAt`/`oldAt` a obsahy na nich sedí; (d) selhání nahrávání v půlce (`failUploads`) → starý obsah, žádný temp; (e) zrušení během nahrávání → totéž; (f) `renameOnServer` s přepisem — stejné invarianty
- [X] T008 [P] [US1] Test v `Tests/CommanderCoreTests/SFTPTests.swift` proti lokálnímu `/usr/libexec/sftp-server` (vzor `SFTPTests.swift:22-37`): `replace(_:over:)` vrátí `true` a přepíše cíl
- [X] T009 [P] [US1] Test v `Tests/CommanderCoreTests/FTPTests.swift` proti `scripts/ftp-test-server.py` (RNTO na existující → 553): `replace` vrátí `false`, oba soubory beze změny

### Implementation

- [X] T010 [US1] V `Sources/CommanderCore/Network/RemoteFileSystem.swift:113-133` přidat do protokolu `func replace(_ from: String, over to: String) async throws -> Bool` s výchozí implementací v extension vracející `false`; do `RemoteError` (`:79-94`) přidat `case replaceIncomplete(target: String, newAt: String, oldAt: String)` s popisem
- [X] T011 [P] [US1] V `Sources/CommanderCore/Network/SFTP/SFTPClient.swift` implementovat `replace` přes extended request `posix-rename@openssh.com` (když je v `extensions`, `:57`/`:146`; vzor `:149`), jinak `false`
- [X] T012 [P] [US1] V `Sources/CommanderCore/Network/FTP/FTPClient.swift` implementovat `replace`: RNFR/RNTO bez předkontroly z `:193-199`; úspěch + `info(from) == nil` → `true`; odpověď 5xx → `false`
- [X] T013 [US1] V `Sources/CommanderCore/Network/RemoteTransfer.swift` přidat privátní `placeReplacing(temp:final:endpoint:)` podle research R1 (replace → `final→".\(name).axo-old-<uuid>"` → `temp→final` s obnovou zálohy → smazat zálohu, selhání = upozornění); každý krok samostatný `connections.perform`, celé v odpojeném `Task` (zrušení nepřeruší výměnu)
- [X] T014 [US1] Nahradit `RemoteTransfer.swift:131-138` (upload s přepisem) a `:377-379` (`renameOnServer` s přepisem) voláním `placeReplacing`
- [X] T015 [US1] Doplnit text `RemoteError.replaceIncomplete` do `OperationsController.describe` (`Sources/AxolotlCommander/OperationsController.swift:296`) a do `Resources/Localizable.xcstrings` (cs)

**Checkpoint**: `swift test --filter RemoteTransferTests|SFTPTests|FTPTests` zelené → commit.

---

## Phase 4: User Story 2 — Neuložené úpravy členů archivu přežijí ukončení (P1)

**Goal**: FR-005–009, FR-027. **Independent Test**: store nad sandbox root; decline → nová instance store ji vrátí.

### Tests

- [X] T016 [US2] `Tests/CommanderCoreTests/ArchiveEditStoreTests.swift` (nový): (a) nezměněná kopie → `cleanupForQuit` ji smaže; (b) změněná kopie → zachována, nová instance `ArchiveEditStore(root:)` nad stejným root ji vrátí z `loadPending`; (c) `decline` → zachována i po `cleanupForQuit`; (d) `markSaved` + bez dalších změn → uklizena; (e) `discard` smaže kopii i záznam; (f) archiv přepsán/smazán po vytažení → `verifyArchiveUnchanged` vyhodí `ArchiveError.changedSinceRead`, kopie zůstane; (g) záznam bez kopie se při `loadPending` zahodí
- [X] T017 [P] [US2] Test v `Tests/CommanderCoreTests/ArchiveTests.swift`: `ArchiveWriter.update(..., expecting:)` s neshodným `PersistentFileStamp` → `changedSinceRead`, archiv beze změny

### Implementation

- [X] T018 [US2] Přidat `case changedSinceRead(URL)` do `ArchiveError` (`Sources/CommanderCore/Archive/ArchiveFormat.swift:42-55`) s popisem
- [X] T019 [US2] Nový `Sources/CommanderCore/Archive/ArchiveEditStore.swift` podle `contracts/core-api.md` a `data-model.md` (PendingEdit: id, target `member(archive:path:)`/`server(...)`, copyRelPath, baseline FileStamp, archiveStamp `PersistentFileStamp?`, declined); manifest `root/manifest.json` přes `SafeFileWriter`; `defaultRoot = ~/Library/Application Support/Axolotl Commander/Edits`; vlákna: `Mutex` nebo actor
- [X] T020 [US2] `ArchiveWriter.update(_:adding:expecting: PersistentFileStamp? = nil)` v `Sources/CommanderCore/Archive/ArchiveWriter.swift:41` (kontrola po `stat` v `updateArchive`, `:94-95`)
- [X] T021 [US2] V `Sources/AxolotlCommander/ArchiveOperations.swift:44-150` předělat `ArchiveEdits` na tenkou vrstvu nad `ArchiveEditStore` (F4 kopie do store, F3 kopie dál do `ArchiveScratch`); „Teď ne“ (`:118-121`) → `decline`; chyba zápisu (`:138-145`) → kopie zůstane + hláška s cestou; před zápisem `verifyArchiveUnchanged`
- [X] T022 [US2] V `Sources/AxolotlCommander/AppDelegate.swift:33-44`: ukončení → `cleanupForQuit`, zachované úpravy → informativní hláška s cestou ke kopiím; `ArchiveScratch.removeAll()` maže už jen temp; při startu (`applicationDidFinishLaunching`) `loadPending` neprázdné → jeden přehled (Vrátit / Zahodit / Teď ne); texty do `Resources/Localizable.xcstrings` (cs)

**Checkpoint**: `swift test --filter ArchiveEditStoreTests|ArchiveTests` zelené → commit.

---

## Phase 5: User Story 3 — Operace s archivem se nezacyklí do sebe (P1)

**Goal**: FR-010–012. **Independent Test**: ZIP přes symlink + přímo; přesun `docs`→`docs/old` → odmítnuto, bajty archivu beze změny.

### Tests

- [X] T023 [US3] `Tests/CommanderCoreTests/ArchiveTransferCheckTests.swift` (nový): ZIP v sandboxu (`ArchiveWriter.create`), symlink na něj a cesta s jinou velikostí písmen → `validate(source:names:target:)` s `target.inner = "docs/old"` vyhodí `.intoItself`; jiný archiv → projde; `validatePack`: zdroj `projekt` + archiv `projekt/zaloha.zip` → `.intoItself`; archiv mezi zdroji → `.intoItself`; nesouvisející → projde; ve všech odmítnutích bajty archivu i zdrojů beze změny

### Implementation

- [X] T024 [US3] Nový `Sources/CommanderCore/Archive/ArchiveTransferCheck.swift`: `validate` (totožnost archivu přes `FileIdentity.of`, nil → `.identityUnknown`; člen `target.inner == m || hasPrefix(m + "/")`), `validatePack` (identita archivu mezi identitami zdrojů; identita zdrojové složky v `TransferPlanner.ancestorIdentities(of: archive.deletingLastPathComponent())`, `TransferPlan.swift:211`, zpřístupnit jako internal/public podle potřeby)
- [X] T025 [US3] V `Sources/AxolotlCommander/ArchiveOperations.swift` volat `validate` místo `:285-288` v `addToArchive` a `validatePack` v `pack` (`:415-444`) před `create` i před `addToArchive(from: nil)`; chybu ukázat přes `report`

**Checkpoint**: zelené → commit.

---

## Phase 6: User Story 4 — Mazání na svazku bez Koše je vědomé (P2)

**Goal**: FR-013–016. **Independent Test**: fake predikát Koše; plán rozdělí výběr; selhání uprostřed → report, nic trvale nesmazáno.

### Tests

- [X] T026 [US4] `Tests/CommanderCoreTests/DeletePlanTests.swift` (nový) přes `FileOperations(options:)` s `trashAvailable` (fake podle podsložky sandboxu) a `trashItem` (přesun do `sandbox/Trash`, selhání na N-té položce): (a) `planDelete` rozdělí `toTrash`/`permanent`; (b) selhání na 2. položce → `TrashReport.trashed` = 1., `failed` = 2., `notAttempted` = zbytek, nic trvale smazáno; (c) vše úspěšné → `failed == nil`

### Implementation

- [X] T027 [US4] Nový `Sources/CommanderCore/Operations/TrashSupport.swift`: `isAvailable(_ url: URL) -> Bool` přes `FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: url, create: false)` (chyba → false)
- [X] T028 [US4] V `Sources/CommanderCore/FileOperations.swift`: do `Options` (`:12-17`) přidat `trashAvailable: @Sendable (URL) -> Bool` (výchozí `TrashSupport.isAvailable`) a `trashItem: @Sendable (URL) throws -> URL` (výchozí `FileManager.trashItem`); přidat `planDelete(_:) -> DeletePlan`; `trash(_:)` (`:53-67`) změnit na `async -> TrashReport` (žádné vyhození uprostřed)
- [X] T029 [US4] V `Sources/AxolotlCommander/OperationsController.swift:163-196` (F8): `planDelete` → je-li `permanent` neprázdné, jeden kritický dotaz se seznamem („Tyto položky se smažou trvale, nelze vrátit“), tlačítka „Smazat trvale“ / „Zrušit“ (výchozí Zrušit) → `trash(toTrash)` → trvalé smazání `permanent` jen když `failed == nil` → report (co je v Koši, co zůstalo)
- [X] T030 [P] [US4] Upravit volajícího `Sources/AxolotlCommander/Find/FindWindowController.swift:624` na nové API (stejný tok dotazu jako T029, sdílená funkce v `OperationsController`)
- [X] T031 [US4] Texty dotazu a reportu do `Resources/Localizable.xcstrings` (cs)

**Checkpoint**: zelené → commit.

---

## Phase 7: User Story 5 — Svazek bez spolehlivé identity (P2)

**Goal**: FR-017–019. **Independent Test**: fake traits „nereliable“; přesun na existující jméno odmítnut, na neexistující projde, kopie projde.

### Tests

- [X] T032 [US5] Testy v `Tests/CommanderCoreTests/OperationsTests.swift` přes `Options.volumeTraits` (fake nereliable pro sandbox): (a) přesun na existující jméno → `.identityUnknown`, zdroj i cíl beze změny; (b) přesun na neexistující jméno → projde; (c) kopie na existující jméno s přepisem → projde (nemaže zdroj)

### Implementation

- [X] T033 [US5] Do `FileOperations.Options` přidat `volumeTraits: @Sendable (URL) -> VolumeTraits` (výchozí `VolumeTraits.of`, cache podle `st_dev` po dobu jedné operace) a předat do `TransferPlanner`/`TransferRun`
- [X] T034 [US5] V `Sources/CommanderCore/Operations/TransferPlan.swift:166-177` a `validateNested` (`:197-201`) a v `Sources/CommanderCore/Operations/TransferRun.swift` `resolve` (`:237-239`): existující cíl + operace mazající zdroj + `!identityReliable` (zdroje nebo cíle) → `.identityUnknown(existing)`

**Checkpoint**: zelené → commit.

---

## Phase 8: User Story 6 — „Uložit jako“ v prohlížeči neničí cíl (P2)

**Goal**: FR-020–022. **Independent Test**: symlink na soubor se štítkem → po uložení symlink i štítek zůstanou; chyba → cíl beze změny, žádný temp.

### Tests

- [X] T035 [P] [US6] Testy `SafeFileWriter` v `Tests/CommanderCoreTests/PreviewTests.swift` (vedle `:258-312`): štítky (`URLResourceValues.tagNames`) a vlastní xattr zachovány na cíli i za symlinkem; `produce` vyhodí → cíl beze změny a ve složce není soubor s `FileCopy.tempPrefix`

### Implementation

- [X] T036 [US6] V `Sources/AxolotlCommander/Viewer/ViewerWindowController.swift:863` nahradit `payload.write(to:options:.atomic)` voláním `try SafeFileWriter.write(to: url) { try payload.write(to: $0) }`

**Checkpoint**: zelené → commit.

---

## Phase 9: User Story 7 — Přejmenování na jiný odkaz téhož souboru je konflikt (P3)

**Goal**: FR-023–024. **Independent Test**: `link(2)` a.txt/b.txt; rename a→b → `.alreadyExists`; `Zprava`→`zprava` projde.

### Tests

- [X] T037 [US7] Testy v `Tests/CommanderCoreTests/OperationsTests.swift`: dva hard linky, `rename(a, to: "b.txt")` → `.alreadyExists`, oba záznamy existují; stávající `caseOnlyRename` (`:319`) dál zelený; NFC→NFD téhož záznamu projde

### Implementation

- [X] T038 [US7] V `Sources/CommanderCore/FileOperations.swift` `rename` (`:153-180`): při shodné identitě a `linkCount > 1` projít výpis rodiče — existuje-li jiný záznam (jiné `unicodeScalars` než zdrojové jméno), který svazek považuje za stejný jako nové jméno (`rules.same`) nebo se shoduje přesně → `.alreadyExists`

**Checkpoint**: zelené → commit.

---

## Phase 10: User Story 8 — Pojistky, které už platí, mají testy (P3)

**Goal**: FR-026. **Independent Test**: nové testy zelené; po dočasném vypnutí pojistky selžou.

- [ ] T039 [P] [US8] Test v `Tests/CommanderCoreTests/OperationsTests.swift`: přesun samotného symlinku na adresář (a) na stejném svazku → odkaz přesunut, soubory za ním nedotčené; (b) s `forceCopyMove` → odkaz zkopírován, soubory za ním nedotčené
- [ ] T040 [US8] Podle research R8 v `Sources/CommanderCore/Operations/TransferPlan.swift:77,84` / `TransferRun.swift:197` povolit u položky druhu symlink (samotný odkaz) po zkopírování `unlink` odkazu (nesleduje cíl); složka obsahující odkaz dál zůstane v `keptSources`
- [ ] T041 [P] [US8] Test v `Tests/CommanderCoreTests/OperationsTests.swift`: podsložka `chmod 000` (v `defer` vrátit `0o755`), přesun s `forceCopyMove` → zdroj v `keptSources`, nic smazáno
- [ ] T042 [P] [US8] Opravit `Tests/CommanderCoreTests/PanelModelTests.swift:225` na porovnání `Array(name.unicodeScalars)`; přidat testy kopie a přejmenování jiného souboru ve složce s NFD jménem → kódové jednotky beze změny

**Checkpoint**: zelené → commit.

---

## Phase 11: Polish

- [ ] T043 `swift build` bez varování, `swift test` celé zelené a < 10 s (SC-005)
- [ ] T044 Ručně jednou dočasně vypnout pojistku D1, D2, D3 a ověřit, že testy selžou (pak vrátit)
- [ ] T045 GUI scénáře G1–G7 z `quickstart.md` v testovací kopii aplikace (vlastní bundle id, oba panely v testovací složce)
- [ ] T046 Aktualizovat `docs/STATE.md` (lokální) a `docs/AUDIT.md` (D1–D8 → vyřešeno); zapsat vedlejší nález `ArchiveCatalog.invalidate` (klíč URL) jako známý problém
- [ ] T047 Zaškrtnout úkoly v tomto souboru, commit `[Spec 001] Hotovo`

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → příběhy. US1, US3, US6 na Phase 2 nezávisí (lze začít hned po T001).
- US2 potřebuje T004 (`PersistentFileStamp`); US5 potřebuje T003; US7 potřebuje T002.
- US4 nezávislý. US8 nezávislý (T040 po T039).
- Polish po všech příbězích.

## Parallel Opportunities

- T005 ‖ T006–T009 (různé soubory testů).
- US1: T008 ‖ T009; T011 ‖ T012 (SFTP vs FTP klient).
- Mezi příběhy: US3 ‖ US6 ‖ US4 (různé soubory jádra i UI); US7 a US5 oba mění `OperationsTests.swift` a jádro operací → sekvenčně.

## Implementation Strategy

- **MVP**: US1 (jediné místo s okamžitým rizikem ztráty dat bez Koše) → commit.
- Pak US2, US3 (zbytek P1), P2 (US4–US6), P3 (US7, US8).
- Každý příběh samostatně dokončitelný a commitnutý; plná sada testů po každém.
