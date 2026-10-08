# Stage 5 — commander window core (implementation brief)

Everything in `Sources/CommanderCore/Window/` (new folder), tests in
`Tests/CommanderCoreTests/WindowTests.swift` (Swift Testing, `import Testing`, `@testable import CommanderCore`).
Swift 6.2, upcoming features ExistentialAny, InternalImportsByDefault, MemberImportVisibility →
a file with public API using `URL` etc. starts with `public import Foundation`.
Core without AppKit. All types `Sendable`; value types where possible.
No disk writes outside `FileManager.default.temporaryDirectory/<uuid>` created and cleaned up by the test.

Existing API to use: `FileItem` (name, url, isParent, isDirectory, isSymlink, isPackage, isHidden,
size: Int64? (nil for folders), modificationDate, fileExtension), `NameRules` (`key(_:)`, `same(_:_:)`),
`WildcardMask(_ pattern:)` + `matches(_:rules:)` (can the pattern contain multiple masks separated by `;`? — check
in `WildcardMask.swift` and stick to what it supports), `SortSpec` (Codable), `PanelModel` (@Observable, @MainActor? — check).

## 1. `PanelState` + PanelModel snapshot (file `Window/PanelState.swift` + change to `PanelModel.swift`)

```swift
public struct PanelState: Codable, Hashable, Sendable {
    public struct Place: Codable, Hashable, Sendable { public var url: URL; public var cursorName: String? }
    public var location: URL
    public var cursorName: String?
    public var sort: SortSpec
    public var showHidden: Bool
    public var filterPattern: String?      // WildcardMask.pattern
    public var back: [Place]               // oldest first, as in PanelModel
    public var forward: [Place]
    public init(location: URL, cursorName: String? = nil, sort: SortSpec = .default, showHidden: Bool = false,
                filterPattern: String? = nil, back: [Place] = [], forward: [Place] = [])
    /// Short tab title: the last path component; for "/" returns "/".
    public var title: String
}
```
In `PanelModel`:
- replace the internal `HistoryEntry` with `PanelState.Place` (or map to it).
- `public func snapshot() -> PanelState` — the current state (cursorName = name of the item under the cursor, not "..";
  if the cursor is on "..", cursorName = nil).
- `public func restore(_ state: PanelState) async throws` — sets sort, showHidden, filter (without
  an unnecessary double load: set the values so that `didSet` does not trigger a refresh — e.g. an internal flag
  or directly private storage), loads `state.location` with the cursor on `cursorName`, and **then** sets
  back/forward from `state` (the history is not extended by the outgoing directory). The selection is cleared.
  On a load error (directory does not exist) it throws and the model stays unchanged.
- Existing `PanelModelTests` must keep passing.

## 2. `TabList` (file `Window/TabList.swift`)

Tabs of one panel. The last tab cannot be closed.
```swift
public struct TabList: Codable, Hashable, Sendable {
    public private(set) var tabs: [PanelState]   // never empty
    public private(set) var active: Int
    public init(_ first: PanelState)
    /// Decoding: empty tabs or active out of range → repair (active clamped; empty = decoding error).
    public var current: PanelState { get }
    /// Stores the state of the active tab (called before every switch/save).
    public mutating func updateCurrent(_ state: PanelState)
    /// Inserts `state` right after the active one and makes it active.
    public mutating func open(_ state: PanelState)
    /// Closes the active one; returns false (and changes nothing) if it is the only one. The one to the right becomes active, otherwise the left.
    @discardableResult public mutating func closeCurrent() -> Bool
    @discardableResult public mutating func close(at index: Int) -> Bool
    public mutating func select(_ index: Int)          // out of range → ignore
    public mutating func next()                        // cyclic
    public mutating func previous()                    // cyclic
    public mutating func move(from: Int, to: Int)      // drag; active follows the moved/shifted tab
}
```

## 3. `RecentPaths` (file `Window/RecentPaths.swift`)

History of the "Go to folder" dialog (⇧F7) — newest first.
```swift
public struct RecentPaths: Codable, Hashable, Sendable {
    public static let limit = 20
    public private(set) var paths: [String]
    public init(paths: [String] = [])           // trims to limit
    /// Trim whitespace, ignore empty; Credentials.scrub; the same path (after removing a trailing "/",
    /// except for "/" itself) moves to the front; limit.
    public mutating func add(_ path: String)
}
```

## 4. `HotPaths` (file `Window/HotPaths.swift`)

Favorite paths: 30 slots, the first 10 have shortcuts ⌃1…⌃9, ⌃0 (go) and ⌃⇧1…⌃⇧0 (save the current directory here).
```swift
public struct HotPath: Codable, Hashable, Sendable { public var name: String; public var path: String
    public init(name: String? = nil, path: String)   // name nil/empty → last path component, "/" → "/"
}
public struct HotPaths: Codable, Hashable, Sendable {
    public static let capacity = 30
    public static let shortcutSlots = 10
    public private(set) var slots: [HotPath?]        // always exactly capacity elements
    public init(slots: [HotPath?] = [])               // pads with nil / trims to capacity
    /// Decoding: an array of a different length → pad/trim.
    public subscript(slot: Int) -> HotPath? { get }   // out of range → nil
    public mutating func set(_ slot: Int, _ hotPath: HotPath?)   // out of range → ignore
    /// Stores into the first free slot starting from `shortcutSlots` (10..29), then 0..9; returns the slot or nil if full.
    /// If the same path (after normalizing the trailing "/") is already stored, adds nothing and returns its slot.
    @discardableResult public mutating func add(_ hotPath: HotPath) -> Int?
    public mutating func move(from: Int, to: Int)     // swaps the contents of two slots
    public var defined: [(slot: Int, hotPath: HotPath)] { get }   // only occupied, ascending
    /// Key digit → slot: 1→0, 2→1 … 9→8, 0→9. Anything else → nil.
    public static func slot(forDigit digit: Int) -> Int?
    /// Slot → digit for displaying the shortcut (0…9 → 1…9,0), otherwise nil.
    public static func digit(forSlot slot: Int) -> Int?
}
```

## 5. `PanelComparison` (file `Window/PanelComparison.swift`)

⌃F10 compares the listings of both panels (no recursion — subfolders later) and returns the names to select.
```swift
public struct ComparisonOptions: Codable, Hashable, Sendable {
    public var compareDate = true            // for same-named files select the newer one
    public var compareSize = true            // for same-named files select the larger one
    public var dateTolerance: TimeInterval = 2   // difference ≤ tolerance = same time (FAT/SMB)
    public var selectDirectoriesOnlyInOnePanel = true
    public var ignoreFiles: String? = nil        // WildcardMask pattern; nil/empty = nothing
    public var ignoreDirectories: String? = nil
    public init()
}
public struct ComparisonResult: Hashable, Sendable {
    public var left: [String]     // names (FileItem.name) to select on the left, in input order
    public var right: [String]
    public var isIdentical: Bool { left.isEmpty && right.isEmpty }
}
public enum PanelComparison {
    public static func compare(left: [FileItem], right: [FileItem], options: ComparisonOptions = .init(),
                               rules: NameRules) -> ComparisonResult
}
```
Rules:
- Ignore `isParent` items. Match names via `rules.key`.
- Items matching the ignore masks (files vs. folders according to `isDirectory && !isPackage`;
  a package (`isPackage`) is treated as a file) are neither matched nor selected.
- An item on only one side: a file is always selected; a folder only with `selectDirectoriesOnlyInOnePanel`.
- Same name, one a file and the other a folder → select both.
- Both folders → nothing (recursion later).
- Both files: the criteria apply independently — `compareDate`: the newer side (difference > tolerance);
  if the date is missing on one side, the date is not compared. `compareSize`: the larger side. Both can be selected.
- Add to `PanelModel` `public func setSelection(names: some Sequence<String>)` — replaces the selection
  with the items having these names (via `rules.key`, only existing ones and not `..`).

## 6. `Highlighting` (file `Window/Highlighting.swift`)

Highlighting of names by mask and attributes; the first matching rule from the top wins. Colors are system colors
(the UI converts them to `NSColor.systemX`, so they work in both light and dark mode).
```swift
public enum SystemColor: String, Codable, Sendable, CaseIterable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray
}
public enum Tristate: String, Codable, Sendable, CaseIterable { case any, yes, no
    public func accepts(_ value: Bool) -> Bool
}
public struct HighlightRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var masks: String              // WildcardMask pattern, empty = everything
    public var directory: Tristate = .any // isDirectory && !isPackage
    public var hidden: Tristate = .any
    public var symlink: Tristate = .any
    public var color: SystemColor
    public var isEnabled = true
    public init(id: UUID = UUID(), masks: String, directory: Tristate = .any, hidden: Tristate = .any,
                symlink: Tristate = .any, color: SystemColor, isEnabled: Bool = true)
    public func matches(_ item: FileItem, rules: NameRules) -> Bool   // `..` never
}
public struct PanelAppearance: Codable, Hashable, Sendable {
    public var markColor: SystemColor = .red          // color of selected items
    public var highlights: [HighlightRule]
    public init(markColor: SystemColor = .red, highlights: [HighlightRule] = PanelAppearance.defaultHighlights)
    public static let defaultHighlights: [HighlightRule]
        // archives "*.zip;*.tar;*.gz;*.tgz;*.bz2;*.xz;*.7z;*.rar;*.dmg;*.pkg" → .purple (files only),
        // scripts "*.sh;*.command;*.py;*.rb;*.pl" → .green (files only)
    public func color(for item: FileItem, rules: NameRules) -> SystemColor?   // first enabled matching one
    /// Resilient decoding: missing keys → defaults (decodeIfPresent).
}
```

## 7. `WindowLayout` (file `Window/WindowLayout.swift`)

Saved window layout (the UI stores it in UserDefaults as JSON).
```swift
public enum PanelViewMode: String, Codable, Sendable, CaseIterable { case detailed, brief }
public enum Side: String, Codable, Sendable { case left, right }
public struct WindowLayout: Codable, Hashable, Sendable {
    public var left: TabList
    public var right: TabList
    public var leftMode: PanelViewMode
    public var rightMode: PanelViewMode
    public var activeSide: Side
    public var maximized: Side?          // nil = both panels visible
    public var splitFraction: Double     // share of the left panel's width, clamp 0.1...0.9
    public init(left: TabList, right: TabList, leftMode: PanelViewMode = .detailed, rightMode: PanelViewMode = .detailed,
                activeSide: Side = .left, maximized: Side? = nil, splitFraction: Double = 0.5)
    /// Resilient decoding: missing keys → default values (decodeIfPresent), splitFraction clamped.
    public static func decode(_ data: Data) -> WindowLayout?
    public func encoded() -> Data
}
```

## Acceptance tests (minimum)
- PanelState: title for `/`, `/Users/x/`, `/Users/x`; Codable round trip.
- PanelModel snapshot/restore in a temp directory with 3 subdirectories: walk a→b, snapshot, go elsewhere, restore →
  location, cursor on the name, canGoBack matches; restore into a nonexistent directory throws and the state stays;
  restore sets sort/showHidden/filter.
- `PanelState.nearestExisting(_ url: URL, exists: (URL) -> Bool) -> URL` (static): the nearest existing
  ancestor (including url itself), at worst "/" — for a tab whose directory has disappeared. Test it.
- TabList: open inserts after the active one; closing the last one = false; closing the active one in the middle → active to the right; the last
  one on the right → left; next/previous cycle; move keeps the active one; decoding with active out of range is repaired.
- RecentPaths: dedupe with/without trailing slash, "/" stays "/", limit, password scrub.
- WindowLayout: round trip, missing keys → defaults, splitFraction 2.0 → 0.9.
- HotPaths: slot(forDigit:) 1→0, 0→9; add fills 10+ and then 0–9, full → nil, a duplicate path returns its slot;
  decoding an array of length 3 → 30; name from the path.
- PanelComparison: (a) same folders → identical; (b) file only on the left → left; (c) newer on the right → right;
  (d) 1 s difference with tolerance 2 → nothing; (e) larger on the left, newer on the right → both; (f) `README.md` vs `readme.md`
  with case-insensitive rules = a pair; (g) ignore mask; (h) folder only on the right with/without the option; (i) file vs folder.
- setSelection(names:) in a temp directory.
- Highlighting: first rule wins, Tristate, `..` never, default archive, disabled rule, decode without keys.

At the end: `swift build 2>&1 | tail` without warnings and `swift test 2>&1 | tail` green. Return briefly:
list of files, number of tests, deviations from the brief and why.
