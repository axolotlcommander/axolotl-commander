# Data Model: Split and Combine Files

## PartSize (core)

| Item | Meaning |
|---|---|
| `presets` | `[(title, bytes)]`: 25 MB, 100 MB, 700 MB (CD), 4.7 GB (DVD), 4 GB − 1 byte (FAT32) (R1). |
| `parse(_:) -> Int64?` | Custom text → bytes (R2); nil when invalid or < 1. |
| `count(fileSize:partSize:) -> Int` | ⌈fileSize / partSize⌉. |
| `problem(fileSize:partSize:) -> Problem?` | `.invalid`, `.notLarger`, `.tooManyParts` (> 999). |

## ChecksumFile (core)

| Field | Type | Meaning |
|---|---|---|
| `name` | String? | `filename=`; nil when missing or unsafe (empty, `/`, NUL, `.`, `..`). |
| `size` | Int64? | `size=`. |
| `crc32` | UInt32? | `crc32=`. |

`text(name:size:crc32:) -> Data` writes the CR LF format; `init?(data:)` reads leniently (R4).

## PartSet (core)

| Field | Type | Meaning |
|---|---|---|
| `parts` | [URL] | The files to join, in order. |
| `checksumFile` | URL? | The `.crc` file used for the check. |
| `defaultName` | String | Proposed name of the joined file (R5). |
| `totalSize` | Int64 | Sum of the part sizes. |

`PartSet.find(around name:, in folder:)` and `PartSet.marked(_ urls:)` throw `SplitCombineError.missingParts([String])`
or `.noParts`.

## FileSplitter results

- `split(...) -> [URL]`: the final URLs written (parts, then the checksum file).
- `combine(...) -> CombineOutput`: `staged` (URL of the file in the staging folder), `staging` (folder),
  `size`, `crc32`, `check` (`.passed`, `.mismatch(expectedSize, expectedCRC, size, crc)`, `.notChecked`).

## Errors (`SplitCombineError`)

`cannotRead(path, message)`, `cannotWrite(path, message)`, `notRegularFile`, `sourceChanged`, `noParts`,
`missingParts([String])`, `folderInTheWay(String)`, `notEnoughSpace(needed, available)`.

## Preferences

| Key | Type | Default |
|---|---|---|
| `split.partSize` | Int (bytes) | 104 857 600 (100 MB) |
| `split.writeChecksum` | Bool | true |
