# Contract: Link Commands

## Core API (CommanderCore)

```swift
public enum LinkKind: Sendable { case symbolic, hard }

public enum LinkError: Error, Equatable {
    case folderNotAllowed(URL), symbolicLinkNotAllowed(URL), notARegularFile(URL), differentVolume(URL)
    case notASymbolicLink(URL), targetMissing(stored: String), loop(URL)
}

public struct LinkOutcome: Sendable {
    public enum Result: Sendable { case created(URL), skipped(any Error) }
    public let source: URL
    public let result: Result
}

public enum LinkPaths {
    public static func relativePath(from folder: String, to target: String) -> String
    public static func storedTarget(typed: String, linkFolder: String, relative: Bool) -> String
    public static func isRelative(_ stored: String) -> Bool
    public static func absolute(_ stored: String, linkFolder: String) -> String
}

extension FileOperations {
    /// `path` = full path of the new link; `stored` = text the link holds. Never replaces.
    public func makeSymbolicLink(at path: String, storing stored: String) throws -> URL
    /// Regular files only, same volume. Never replaces.
    public func makeHardLink(at path: String, to file: URL) throws -> URL
    /// One link per source in `folder`, named like the source; never stops early.
    public func makeLinks(_ kind: LinkKind, to sources: [URL], in folder: URL,
                          relative: Bool) -> [LinkOutcome]
    /// Replaces the symbolic link at `link` atomically; only a symbolic link is ever replaced.
    public func retargetSymbolicLink(_ link: URL, storing stored: String) throws
}

public enum LinkTarget {
    /// The final existing item behind a symbolic link or Finder alias (chains followed,
    /// folder made real). Throws `LinkError.targetMissing` / `.loop`.
    public static func resolve(_ url: URL) throws -> URL
    /// True for a symbolic link or a Finder alias (not following).
    public static func isLink(_ url: URL) -> Bool
}
```

## Commands (CommandRegistry)

| Command | Title | Menu (after) | Default chords |
|---|---|---|---|
| `newSymbolicLink` | New Symbolic Link… | File (New Folder…) | ⌃⌘L |
| `newHardLink` | New Hard Link… | File (New Symbolic Link…) | — |
| `editSymbolicLink` | Edit Symbolic Link… | File (New Hard Link…) | — |
| `changeAttributes` | Change Attributes… | File (Get Info) | ⌃F2 |
| `pasteAsSymbolicLink` | Paste as Symbolic Link | Edit (Move Files Here) | ⌃⌘V, ⌃S |
| `goToLinkTarget` | Go to Link Target | Commands (Show in Finder) | ⌃T |

Enabled (all: local folder only — not archive, server or search results):

- `newSymbolicLink`, `newHardLink`, `changeAttributes`: targets not empty (".." alone is no target).
- `editSymbolicLink`: cursor item is a symbolic link.
- `goToLinkTarget`: cursor item is a symbolic link or a Finder alias.
- `pasteAsSymbolicLink`: the pasteboard holds at least one file URL.

## UI behavior

| Situation | Result |
|---|---|
| One item, confirm | link at "Link name"; panels refresh; cursor on it in the panel showing its folder |
| Name exists (one item) | inline "An item named “X” already exists."; sheet stays |
| Several items / paste with problems | created ones stay; one alert lists skipped names with reasons |
| Typed target missing (symbolic, edit) | alert "The target does not exist. Create the link anyway?" Create / Cancel |
| Go to Link Target, file | panel at the target's folder, cursor on the target; Back returns |
| Go to Link Target, folder | panel in the real folder |
| Broken link / loop | alert naming the stored target; panel unchanged |

Toolbar symbols (Customize Toolbar only): `newSymbolicLink` "link.badge.plus", `newHardLink`
"link", `editSymbolicLink` "pencil.line", `pasteAsSymbolicLink` "doc.on.clipboard",
`goToLinkTarget` "arrowshape.turn.up.right", `changeAttributes` "lock.doc".

## Texts (en → cs, String Catalog)

| Key | cs |
|---|---|
| New Symbolic Link… | Nový symbolický odkaz… |
| New Hard Link… | Nový pevný odkaz… |
| Edit Symbolic Link… | Upravit symbolický odkaz… |
| Paste as Symbolic Link | Vložit jako symbolický odkaz |
| Go to Link Target | Přejít na cíl odkazu |
| Change Attributes… | Změnit atributy… |
| Target: | Cíl: |
| Link name: | Název odkazu: |
| Create links in: | Vytvořit odkazy ve složce: |
| Relative path | Relativní cesta |
| Create | Vytvořit |
| The target does not exist. Create the link anyway? | Cíl neexistuje. Vytvořit odkaz přesto? |
| Some links were not created. | Některé odkazy nebyly vytvořeny. |
| Folders cannot have hard links. | Složky nemohou mít pevné odkazy. |
| A hard link cannot point to a symbolic link. | Pevný odkaz nemůže ukazovat na symbolický odkaz. |
| Hard links must be on the same volume as the file. | Pevný odkaz musí být na stejném svazku jako soubor. |
| The link target “%@” does not exist. | Cíl odkazu „%@“ neexistuje. |
| The link “%@” could not be resolved (too many levels of links). | Odkaz „%@“ nelze rozvinout (příliš mnoho úrovní odkazů). |
| “%@” is not a symbolic link. | „%@“ není symbolický odkaz. |
