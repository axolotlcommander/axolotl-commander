# Data model: Bezpečnost dat (001)

## FileIdentity (změna)

| Pole | Typ | Poznámka |
|---|---|---|
| device | Int64 | `st_dev` — platí jen po dobu připojení svazku |
| inode | UInt64 | `st_ino`; 0 → identita neznámá (`nil`) |
| reliable | Bool | z `VolumeTraits.identityReliable` |

- Rovnost dvou identit má význam „týž soubor“ jen když jsou obě `reliable`; jinak operace
  mazající zdroj nad existujícím cílem → `OperationError.identityUnknown`.
- Nikdy se neukládá (mezi spuštěními ani přes odpojení svazku).

## VolumeTraits (nové)

| Pole | Typ | Poznámka |
|---|---|---|
| identityReliable | Bool | `apfs`, `hfs` → true; ostatní typy → false |
| uuid | String? | `URLResourceKey.volumeUUIDStringKey` |
| trashAvailable | Bool | `FileManager.url(for: .trashDirectory, …, appropriateFor:, create: false)` uspěje |

Cache podle `st_dev` jen po dobu jedné operace.

## PersistentFileStamp (nové)

| Pole | Typ | Poznámka |
|---|---|---|
| volumeUUID | String? | identita svazku přes odpojení |
| fileID | UInt64 | `fileIdentifierKey` / `st_ino` |
| size | Int64 | |
| modified | Int64 | mtime v ns |

Shoda všech polí = „archiv se od vytažení nezměnil“ (FR-009). Codable.

## PendingEdit (nové, `ArchiveEditStore`)

| Pole | Typ | Poznámka |
|---|---|---|
| id | UUID | název podsložky v `Edits/` |
| target | enum `member(archive: URL, path: String)` / `server(location)` | kam se vrací |
| copyRelPath | String | relativně k `Edits/<id>/` |
| baseline | FileStamp | velikost + mtime kopie po vytažení / posledním uložení |
| archiveStamp | PersistentFileStamp? | stav archivu při vytažení (jen `member`) |
| declined | Bool | uživatel zvolil „Teď ne“ — kopie se nesmí uklidit |

**Stavy**: `extracted` (kopie = baseline) → `changed` (kopie ≠ baseline) →
`saved` (vráceno; baseline := kopie, archiveStamp := nový) | `declined` (zachovat, nabídnout
při startu) | `discarded` (smazat kopii i záznam). Při ukončení: `extracted`/`saved` bez dalších
změn → uklidit; `changed`/`declined` → zachovat. Při startu: záznam bez kopie → zahodit;
`changed`/`declined` → nabídnout.

**Úložiště**: `~/Library/Application Support/Axolotl Commander/Edits/manifest.json` (pole
`PendingEdit`), zapisuje se přes `SafeFileWriter`. V testech vlastní `root` v sandboxu.

## DeletePlan / TrashReport (nové)

| Typ | Pole |
|---|---|
| DeletePlan | `toTrash: [URL]`, `permanent: [URL]` (svazek bez Koše) |
| TrashReport | `trashed: [(original: URL, inTrash: URL)]`, `failed: (URL, String)?`, `notAttempted: [URL]` |

Pravidlo: `permanent` se smaže jen po potvrzení; když se Koš v téže dávce nepovede
(`failed != nil`), `permanent` se neprovede.

## Chyby (rozšíření)

| Enum | Nový případ | Kdy |
|---|---|---|
| RemoteError | `replaceIncomplete(target:, newAt:, oldAt:)` | výměna na serveru selhala a zálohu nešlo vrátit |
| ArchiveError | `changedSinceRead(URL)` | archiv se změnil/zmizel mezi vytažením a vrácením |
| OperationError | (beze změny) `intoItself`, `identityUnknown`, `alreadyExists` | D3, D5, D7, D8 |
