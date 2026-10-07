# Etapa 5 — jádro okna commanderu (zadání pro implementaci)

Vše v `Sources/CommanderCore/Window/` (nová složka), testy v
`Tests/CommanderCoreTests/WindowTests.swift` (Swift Testing, `import Testing`, `@testable import CommanderCore`).
Swift 6.2, upcoming features ExistentialAny, InternalImportsByDefault, MemberImportVisibility →
soubor s veřejným API používajícím `URL` apod. začíná `public import Foundation`.
Jádro bez AppKitu. Všechny typy `Sendable`; hodnotové typy, kde to jde.
Žádné zápisy na disk mimo `FileManager.default.temporaryDirectory/<uuid>` vytvořené a uklizené testem.

Existující API k použití: `FileItem` (name, url, isParent, isDirectory, isSymlink, isPackage, isHidden,
size: Int64? (nil u složek), modificationDate, fileExtension), `NameRules` (`key(_:)`, `same(_:_:)`),
`WildcardMask(_ pattern:)` + `matches(_:rules:)` (pattern může obsahovat více masek oddělených `;`? — ověř
v `WildcardMask.swift` a dodrž, co umí), `SortSpec` (Codable), `PanelModel` (@Observable, @MainActor? — ověř).

## 1. `PanelState` + PanelModel snapshot (soubor `Window/PanelState.swift` + úprava `PanelModel.swift`)

```swift
public struct PanelState: Codable, Hashable, Sendable {
    public struct Place: Codable, Hashable, Sendable { public var url: URL; public var cursorName: String? }
    public var location: URL
    public var cursorName: String?
    public var sort: SortSpec
    public var showHidden: Bool
    public var filterPattern: String?      // WildcardMask.pattern
    public var back: [Place]               // nejstarší první, jako v PanelModel
    public var forward: [Place]
    public init(location: URL, cursorName: String? = nil, sort: SortSpec = .default, showHidden: Bool = false,
                filterPattern: String? = nil, back: [Place] = [], forward: [Place] = [])
    /// Krátký titulek záložky: poslední komponenta cesty; pro "/" vrátí "/".
    public var title: String
}
```
V `PanelModel`:
- interní `HistoryEntry` nahraď `PanelState.Place` (nebo mapuj).
- `public func snapshot() -> PanelState` — aktuální stav (cursorName = jméno položky pod kurzorem, ne "..";
  pokud kurzor stojí na "..", cursorName = nil).
- `public func restore(_ state: PanelState) async throws` — nastaví sort, showHidden, filter (bez
  zbytečného dvojího načtení: nastav hodnoty tak, aby `didSet` nespustil refresh — např. interní flag
  nebo přímo privátní uložení), načte `state.location` s kurzorem na `cursorName`, a **pak** nastaví
  back/forward z `state` (historie se neprodlouží o odchozí adresář). Výběr se vyprázdní.
  Při chybě načtení (adresář neexistuje) vyhodí chybu a model zůstane beze změny.
- Stávající testy `PanelModelTests` musí dál procházet.

## 2. `TabList` (soubor `Window/TabList.swift`)

Záložky jednoho panelu. Poslední záložku zavřít nejde.
```swift
public struct TabList: Codable, Hashable, Sendable {
    public private(set) var tabs: [PanelState]   // nikdy prázdné
    public private(set) var active: Int
    public init(_ first: PanelState)
    /// Dekódování: prázdné tabs nebo active mimo rozsah → opravit (active clamp; prázdné = chyba dekódování).
    public var current: PanelState { get }
    /// Uloží stav aktivní záložky (volá se před každým přepnutím/ukládáním).
    public mutating func updateCurrent(_ state: PanelState)
    /// Vloží `state` hned za aktivní a udělá ji aktivní.
    public mutating func open(_ state: PanelState)
    /// Zavře aktivní; vrátí false (a nic nezmění), je-li jediná. Aktivní se stane ta vpravo, jinak vlevo.
    @discardableResult public mutating func closeCurrent() -> Bool
    @discardableResult public mutating func close(at index: Int) -> Bool
    public mutating func select(_ index: Int)          // mimo rozsah → ignoruj
    public mutating func next()                        // cyklicky
    public mutating func previous()                    // cyklicky
    public mutating func move(from: Int, to: Int)      // přetažení; active sleduje přesunutou/posunutou záložku
}
```

## 3. `RecentPaths` (soubor `Window/RecentPaths.swift`)

Historie dialogu „Jdi na složku" (⇧F7) — nejnovější první.
```swift
public struct RecentPaths: Codable, Hashable, Sendable {
    public static let limit = 20
    public private(set) var paths: [String]
    public init(paths: [String] = [])           // ořízne na limit
    /// Trim whitespace, prázdné ignoruj; Credentials.scrub; stejná cesta (po odstranění koncového "/",
    /// kromě samotného "/") se přesune dopředu; limit.
    public mutating func add(_ path: String)
}
```

## 4. `HotPaths` (soubor `Window/HotPaths.swift`)

Oblíbené cesty: 30 slotů, prvních 10 má zkratky ⌃1…⌃9, ⌃0 (jdi) a ⌃⇧1…⌃⇧0 (ulož sem aktuální adresář).
```swift
public struct HotPath: Codable, Hashable, Sendable { public var name: String; public var path: String
    public init(name: String? = nil, path: String)   // name nil/prázdné → poslední komponenta cesty, "/" → "/"
}
public struct HotPaths: Codable, Hashable, Sendable {
    public static let capacity = 30
    public static let shortcutSlots = 10
    public private(set) var slots: [HotPath?]        // vždy přesně capacity prvků
    public init(slots: [HotPath?] = [])               // doplní nil / ořízne na capacity
    /// Dekódování: pole jiné délky → doplnit/oříznout.
    public subscript(slot: Int) -> HotPath? { get }   // mimo rozsah → nil
    public mutating func set(_ slot: Int, _ hotPath: HotPath?)   // mimo rozsah → ignoruj
    /// Uloží do prvního volného slotu od `shortcutSlots` (10..29), pak 0..9; vrátí slot nebo nil, je-li plno.
    /// Je-li stejná cesta (po normalizaci koncového "/") už uložena, nic nepřidá a vrátí její slot.
    @discardableResult public mutating func add(_ hotPath: HotPath) -> Int?
    public mutating func move(from: Int, to: Int)     // prohodí obsah dvou slotů
    public var defined: [(slot: Int, hotPath: HotPath)] { get }   // jen obsazené, vzestupně
    /// Číslice klávesy → slot: 1→0, 2→1 … 9→8, 0→9. Jiné → nil.
    public static func slot(forDigit digit: Int) -> Int?
    /// Slot → číslice pro zobrazení zkratky (0…9 → 1…9,0), jinak nil.
    public static func digit(forSlot slot: Int) -> Int?
}
```

## 5. `PanelComparison` (soubor `Window/PanelComparison.swift`)

⌃F10 porovná výpisy obou panelů (bez rekurze — podsložky až později) a vrátí jména k výběru.
```swift
public struct ComparisonOptions: Codable, Hashable, Sendable {
    public var compareDate = true            // u stejnojmenných souborů vyber novější
    public var compareSize = true            // u stejnojmenných souborů vyber větší
    public var dateTolerance: TimeInterval = 2   // rozdíl ≤ tolerance = stejný čas (FAT/SMB)
    public var selectDirectoriesOnlyInOnePanel = true
    public var ignoreFiles: String? = nil        // WildcardMask pattern; nil/prázdné = nic
    public var ignoreDirectories: String? = nil
    public init()
}
public struct ComparisonResult: Hashable, Sendable {
    public var left: [String]     // jména (FileItem.name) k výběru vlevo, v pořadí vstupu
    public var right: [String]
    public var isIdentical: Bool { left.isEmpty && right.isEmpty }
}
public enum PanelComparison {
    public static func compare(left: [FileItem], right: [FileItem], options: ComparisonOptions = .init(),
                               rules: NameRules) -> ComparisonResult
}
```
Pravidla:
- `isParent` položky ignoruj. Párování jmen přes `rules.key`.
- Položky odpovídající ignore maskám (soubory vs. složky podle `isDirectory && !isPackage`;
  balíček (`isPackage`) se bere jako soubor) se nepárují ani nevybírají.
- Položka jen na jedné straně: soubor vždy vybrán; složka jen při `selectDirectoriesOnlyInOnePanel`.
- Stejné jméno, jeden soubor a druhý složka → vyber obě.
- Obě složky → nic (rekurze později).
- Oba soubory: kritéria se uplatní nezávisle — `compareDate`: novější strana (rozdíl > tolerance);
  chybí-li datum na jedné straně, datum se nesrovnává. `compareSize`: větší strana. Mohou být vybrány obě.
- Do `PanelModel` přidej `public func setSelection(names: some Sequence<String>)` — nahradí výběr
  položkami s těmito jmény (přes `rules.key`, jen existující a ne `..`).

## 6. `Highlighting` (soubor `Window/Highlighting.swift`)

Zvýraznění jmen podle masky a atributů; první vyhovující pravidlo shora vyhrává. Barvy jsou systémové
(UI je převede na `NSColor.systemX`, takže fungují ve světlém i tmavém režimu).
```swift
public enum SystemColor: String, Codable, Sendable, CaseIterable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray
}
public enum Tristate: String, Codable, Sendable, CaseIterable { case any, yes, no
    public func accepts(_ value: Bool) -> Bool
}
public struct HighlightRule: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var masks: String              // WildcardMask pattern, prázdné = vše
    public var directory: Tristate = .any // isDirectory && !isPackage
    public var hidden: Tristate = .any
    public var symlink: Tristate = .any
    public var color: SystemColor
    public var isEnabled = true
    public init(id: UUID = UUID(), masks: String, directory: Tristate = .any, hidden: Tristate = .any,
                symlink: Tristate = .any, color: SystemColor, isEnabled: Bool = true)
    public func matches(_ item: FileItem, rules: NameRules) -> Bool   // `..` nikdy
}
public struct PanelAppearance: Codable, Hashable, Sendable {
    public var markColor: SystemColor = .red          // barva vybraných položek
    public var highlights: [HighlightRule]
    public init(markColor: SystemColor = .red, highlights: [HighlightRule] = PanelAppearance.defaultHighlights)
    public static let defaultHighlights: [HighlightRule]
        // archivy "*.zip;*.tar;*.gz;*.tgz;*.bz2;*.xz;*.7z;*.rar;*.dmg;*.pkg" → .purple (jen soubory),
        // skripty "*.sh;*.command;*.py;*.rb;*.pl" → .green (jen soubory)
    public func color(for item: FileItem, rules: NameRules) -> SystemColor?   // první povolené vyhovující
    /// Dekódování odolné: chybějící klíče → výchozí (decodeIfPresent).
}
```

## 7. `WindowLayout` (soubor `Window/WindowLayout.swift`)

Uložené rozložení okna (UI ho ukládá do UserDefaults jako JSON).
```swift
public enum PanelViewMode: String, Codable, Sendable, CaseIterable { case detailed, brief }
public enum Side: String, Codable, Sendable { case left, right }
public struct WindowLayout: Codable, Hashable, Sendable {
    public var left: TabList
    public var right: TabList
    public var leftMode: PanelViewMode
    public var rightMode: PanelViewMode
    public var activeSide: Side
    public var maximized: Side?          // nil = oba panely viditelné
    public var splitFraction: Double     // podíl šířky levého panelu, clamp 0.1...0.9
    public init(left: TabList, right: TabList, leftMode: PanelViewMode = .detailed, rightMode: PanelViewMode = .detailed,
                activeSide: Side = .left, maximized: Side? = nil, splitFraction: Double = 0.5)
    /// Dekódování odolné: chybějící klíče → výchozí hodnoty (decodeIfPresent), splitFraction clamp.
    public static func decode(_ data: Data) -> WindowLayout?
    public func encoded() -> Data
}
```

## Akceptační testy (minimum)
- PanelState: title pro `/`, `/Users/x/`, `/Users/x`; Codable round-trip.
- PanelModel snapshot/restore v temp adresáři se 3 podadresáři: projdi a→b, snapshot, jdi jinam, restore →
  location, kurzor na jménu, canGoBack odpovídá; restore do neexistujícího adresáře hodí chybu a stav zůstane;
  restore nastaví sort/showHidden/filter.
- `PanelState.nearestExisting(_ url: URL, exists: (URL) -> Bool) -> URL` (static): nejbližší existující
  předek (včetně url samotné), nejhůř "/" — pro záložku, jejíž adresář zmizel. Otestuj.
- TabList: open vloží za aktivní; close poslední = false; close aktivní uprostřed → aktivní vpravo; poslední
  vpravo → vlevo; next/previous cyklí; move udrží aktivní; dekódování s active mimo rozsah se opraví.
- RecentPaths: dedupe s/bez koncového lomítka, "/" zůstane "/", limit, scrub hesla.
- WindowLayout: round-trip, chybějící klíče → výchozí, splitFraction 2.0 → 0.9.
- HotPaths: slot(forDigit:) 1→0, 0→9; add plní 10+ a pak 0–9, plno → nil, duplicitní cesta vrátí slot;
  dekódování pole délky 3 → 30; name z cesty.
- PanelComparison: (a) stejné složky → identické; (b) soubor jen vlevo → vlevo; (c) novější vpravo → vpravo;
  (d) rozdíl 1 s při toleranci 2 → nic; (e) větší vlevo, novější vpravo → obojí; (f) `README.md` vs `readme.md`
  s case-insensitive rules = pár; (g) ignore maska; (h) složka jen vpravo s/bez option; (i) soubor vs složka.
- setSelection(names:) v temp adresáři.
- Highlighting: první pravidlo vyhrává, Tristate, `..` nikdy, výchozí archiv, vypnuté pravidlo, decode bez klíčů.

Na konci: `swift build 2>&1 | tail` bez varování a `swift test 2>&1 | tail` zelené. Vrať stručně:
seznam souborů, počet testů, odchylky od zadání a proč.
