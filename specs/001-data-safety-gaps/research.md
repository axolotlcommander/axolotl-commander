# Research: Bezpečnost dat (001)

Fakta z kódu (file:line) zjištěna 2026-10-08 na větvi `001-data-safety-gaps`.

## R1 — Přepis na serveru (D1, FR-001–004)

- **Fakta**: `RemoteTransfer.swift:132-134` v jednom `perform` volá `removeFile(final)` a pak
  `rename(temp → final)`; při chybě `:137` smaže i temp. Totéž v `renameOnServer` `:377-379`.
  `RemoteConnections.perform` po `.disconnected` opakuje celý closure (`RemoteConnections.swift:106-117`).
  SFTP klient je vlastní (`SFTPClient.swift`), `rename` `:580-583` odmítá existující cíl,
  rozšíření serveru v `extensions` (`:57`), vzor extended requestu `:149`. FTP `FTPClient.swift:193-199`
  odmítá existující cíl před RNFR/RNTO.
- **Decision**: Do `RemoteFileSystem` přidat `replace(_ from:, over to:) async throws -> Bool`
  (výchozí `false` = neumím, nic se nezměnilo). SFTP: `posix-rename@openssh.com`, když ho server
  hlásí. FTP: RNFR/RNTO bez předchozí kontroly, 5xx → `false` (neúspěšné RNTO nic nemění).
  `RemoteTransfer.placeReplacing`: (1) `replace`; (2) jinak `final → záloha` (skryté jméno ve stejné
  složce); (3) `temp → final`, při chybě vrátit zálohu; (4) smazat zálohu (selhání = upozornění).
  Každý krok samostatný `perform` (opakování po odpojení nesmí zopakovat smazání), v odpojeném
  `Task` (zrušení nepřeruší výměnu uprostřed). Nová chyba `RemoteError.replaceIncomplete(target:,
  newAt:, oldAt:)` pro případ, kdy nejde vrátit zálohu.
- **Rationale**: Atomická výměna, kde server umí; jinak sekvence, v níž v každém okamžiku existuje
  úplná verze pod známým jménem (FR-003).
- **Alternatives**: Nahrát rovnou přes cíl (STOR přes existující) — při přerušení zůstane
  poloviční soubor; zamítnuto. Smazat cíl až po nahrání (dnešní stav) — okno bez verze; zamítnuto.

## R2 — Úpravy členů archivu (D2, FR-005–009, FR-027)

- **Fakta**: `AppDelegate.swift:33-44` po `offerChanges` vždy ukončí a `applicationWillTerminate`
  volá `ArchiveScratch.removeAll()` (temp `Axolotl-<UUID>`). `ArchiveEdits`
  (`ArchiveOperations.swift:44-150`) jen v paměti; „Not Now“ (`:118-121`) přepíše `stamp`, takže
  kopie vypadá nezměněná a smaže se. Zápis zpět (`ArchiveWriter.update`, `ArchiveWriter.swift:41`)
  neověřuje, že se archiv mezitím nezměnil.
- **Decision**: Nový `CommanderCore/Archive/ArchiveEditStore.swift` (testovatelný, `init(root:)`).
  Kopie pro F4 se vytahují do `~/Library/Application Support/Axolotl Commander/Edits/<id>/`,
  seznam v `manifest.json` (zápis přes `SafeFileWriter`). Store rozhoduje, co je změněné, co
  zachovat, co uklidit; „Teď ne“ = `decline` (zůstane, nabídne se při startu). Zápis zpět ověří
  `PersistentFileStamp` archivu (UUID svazku + file id + velikost + mtime) a jinak odmítne
  (`ArchiveError.changedSinceRead`). UI zůstanou jen alerty a volání writeru/uploadu.
- **Rationale**: Temp složku může systém vyčistit; Application Support přežije restart. Logika
  v jádru splní princip IV a FR-027.
- **Alternatives**: Jen varovat při ukončení (bez zachování) — při chybě zápisu by se práce stejně
  ztratila; zamítnuto. Zablokovat ukončení — uživatele zdržuje, při pádu nepomůže; zamítnuto.

## R3 — Archiv do sebe a balení do vlastního zdroje (D3, D7, FR-010–012)

- **Fakta**: `ArchiveOperations.swift:285` porovnává `standardizedFileURL` (text). Následně `:320`
  přidá a `:327` `update(removing:)` odstraní vše pod zdrojem. `pack` (`:415-444`) a F5/F6 do archivu
  (`addToArchive`, `source == nil`) nekontrolují, zda archiv leží mezi zdroji / uvnitř zdroje.
  `FileIdentity.of(_:followingLinks:)` (`Operations/FileIdentity.swift:9-26`),
  `TransferPlanner.ancestorIdentities(of:)` (`TransferPlan.swift:211`).
- **Decision**: Core `ArchiveTransferCheck` se dvěma funkcemi: `validate(source:names:target:)`
  (totožnost archivu podle `FileIdentity`, neznámá → `.identityUnknown`) a
  `validatePack(archive:sources:)` (archiv mezi zdroji nebo zdrojová složka mezi předky archivu →
  `.intoItself`). Volá se před jakýmkoli zápisem v `addToArchive` i `pack`.
- **Rationale**: Stejné pravidlo identity jako u lokálních operací (05-pravidla, Identita).
- **Alternatives**: `realpath` porovnání — neřeší hard linky a velikost písmen na všech svazcích;
  zamítnuto.
- **Vedlejší nález (mimo rozsah)**: `ArchiveCatalog.invalidate` klíčovaný URL — panel se symlinkovou
  cestou může mít zastaralý výpis. Zapsat do STATE.

## R4 — Mazání bez Koše (D4, FR-013–016)

- **Fakta**: `FileOperations.trash` (`FileOperations.swift:53-67`) při první chybě vyhodí `.io`
  a předchozí položky jsou už v Koši bez hlášení. UI `OperationsController.delete`
  (`OperationsController.swift:163-196`), další volající `FindWindowController.swift:624`.
  Klíč „svazek má Koš“ v SDK není; `FileManager.url(for: .trashDirectory, in: .userDomainMask,
  appropriateFor: url, create: false)` vrací `~/.Trash` na domácím svazku a chybu 3328 na svazcích
  bez Koše (ověřeno na DMG, Time Machine, devfs).
- **Decision**: `TrashSupport.isAvailable(_:)` přes tento dotaz (cache podle svazku po dobu jedné
  operace). `FileOperations.planDelete(_:) -> DeletePlan { toTrash, permanent }`; `trash` vrací
  `TrashReport { trashed, failed, notAttempted }` místo vyhození uprostřed. Seamy v
  `FileOperations.Options`: `trashAvailable`, `trashItem` — testy nikdy nesahají na skutečný Koš.
  UI: když `permanent` není prázdné, jeden kritický dotaz se seznamem, výchozí „Zrušit“; po
  potvrzení nejdřív Koš, při jeho selhání se trvalé mazání neprovede a ukáže se report.
- **Rationale**: Chování jako Finder („Položka bude okamžitě smazána“), rozhodnutí před první změnou.
- **Alternatives**: Zkusit Koš a při chybě se zeptat — dávka už je napůl; zamítnuto.
- **Ruční ověření (jen čtení)**: USB FAT a SMB svazek — zda dotaz vrací chybu (quickstart).

## R5 — Identita na svazku bez spolehlivých id (D5, FR-017–019)

- **Fakta**: `FileStat.init` (`FileIdentity.swift:37-44`) = `st_dev` + `st_ino`, `ino == 0` → nil.
  `TransferPlanner.plan` (`TransferPlan.swift:166-177`), `validateNested` (`:197-201`),
  `TransferRun.resolve` (`:237-239`), `deleteSource` znovu ověří identitu (`:205-216`).
- **Decision**: `VolumeTraits { identityReliable, uuid }` podle `statfs.f_fstypename`; spolehlivé jen
  `apfs` a `hfs` (allowlist), ostatní (msdos, exfat, smbfs, afpfs, nfs, webdav, ntfs, fuse, neznámé)
  nespolehlivé. `FileIdentity` = (`st_dev`, `st_ino`) jen v rámci jednoho připojení (dokumentovat:
  neukládat); co se ukládá (R2), používá `PersistentFileStamp` s UUID svazku. Na nespolehlivém svazku:
  existující cíl + operace mazající zdroj (přesun, přepis při přesunu) → `.identityUnknown`; kopie
  a přesun na neexistující jméno projdou. Seam `Options.volumeTraits`.
- **Rationale**: Pravidlo vzoru výslovně: „Operace, která by při shodě mazala zdroj, se odmítne.“
- **Tradeoff**: Přesun s přepsáním existujícího souboru na SMB/FAT se odmítne; uživatel může
  kopírovat a pak smazat. Přijato (bezpečnost má přednost, princip I).
- **Alternatives**: Důvěřovat `st_ino` na všech svazcích (dnešní stav) — FAT/SMB id mohou být
  syntetická; zamítnuto.

## R6 — „Uložit jako“ v prohlížeči (D6, FR-020–022)

- **Fakta**: `ViewerWindowController.saveCopy()` (`:843-867`) zapisuje přes `Data.write(.atomic)`
  (`:863`) — nahradí symlink, ztratí atributy. `saveImage()` už jde přes `ImageExport` →
  `SafeFileWriter.write(to:_:)` (`SafeFileWriter.swift:12`, rozřeší symlink, temp ve stejné složce,
  `replaceItemAt` zachová práva/štítky).
- **Decision**: `:863` → `SafeFileWriter.write(to: url) { try payload.write(to: $0) }`. Testy doplní
  štítky, xattr a úklid tempu při chybě.
- **Alternatives**: Vlastní kopírování atributů — duplicita SafeFileWriteru; zamítnuto.

## R7 — Přejmenování na jiný hard link (D8, FR-023–024)

- **Fakta**: `FileOperations.rename` (`:153-180`): identita zdroje == identita existujícího `b.txt`
  → `Darwin.rename` (`:169`), které u dvou odkazů téhož inode vrátí 0 a nic neudělá.
- **Decision**: Při shodě identity a `st_nlink > 1` projít výpis rodiče: existuje-li jiný záznam
  (jiné `unicodeScalars` než zdroj) se jménem, které svazek považuje za stejné jako nové → 
  `.alreadyExists`. Do `FileStat` přidat `linkCount`. Změna jen velikosti písmen / NFC↔NFD téhož
  záznamu projde.

## R8 — Testy stávajících pojistek (FR-026)

- **Samotný symlink na adresář**: na stejném svazku rename (odkaz se přesune). Přes `forceCopyMove`
  dnes zdroj zůstane v `keptSources` (`TransferPlan.swift:77,84`, `TransferRun.swift:197`).
  **Decision**: u položky druhu symlink (samotný odkaz, ne obsah) po zkopírování povolit `unlink`
  odkazu — nesmaže nic za ním (05-pravidla, Přesun a odkaz). Test oba případy.
- **Neúplný průchod**: podsložka `chmod 000` v sandboxu (vrátit v `defer`), přesun s `forceCopyMove`
  → zdroj v `keptSources`.
- **Kódové jednotky**: porovnávat `Array(name.unicodeScalars)`, ne `==` (kanonická ekvivalence).
- **Společné pomůcky**: `Tests/CommanderCoreTests/TestSupport.swift` (`withSandbox`, zápis/čtení,
  fake svazky/Koš) — dnes má každý testový soubor vlastní.
