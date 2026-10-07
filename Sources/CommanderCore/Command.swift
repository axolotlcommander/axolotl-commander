/// Every user-facing command. Menu, key map and enablement all derive from
/// `CommandRegistry`, so a command is declared exactly once.
public enum Command: String, CaseIterable, Hashable, Sendable {
    // App
    case about, settings, quit, help

    // File
    case view, quickLook, edit, newFile, copy, move, makeDirectory
    case delete, deletePermanently, rename, properties, pack, unpack
    case changeCase, batchRename

    // Edit
    case copyFiles, pasteFiles, copyFullPath, copyName
    case selectByMask, deselectByMask, invertByMask
    case selectAll, deselectAll, selectSameExtension, deselectSameExtension

    // View
    case sortByName, sortByExtension, sortByDate, sortBySize
    case filter, refresh, toggleHidden, maximizePanel, comparePanels, calculateSizes
    case viewModeDetailed, viewModeBrief

    // Go (active panel)
    case goBack, goForward, goParent, goRoot, goHome, changeDirectory
    case hotPaths, workingDirectories
    case newTab, closeTab, nextTab, previousTab

    // Left / Right
    case leftVolumeMenu, rightVolumeMenu

    // Commands
    case find, occupiedSpace, openTerminal, revealInFinder, userMenu
    case connectToServer, disconnect, compareFiles
    case calculateChecksums, verifyChecksums

    // Options
    case configureKeys

    // Panel-only (no menu item)
    case open, switchPanel, toggleSelection, toggleSelectionAndSize
    case openInLeftPanel, openInRightPanel
    case focusCommandLine, insertNameToCommandLine, insertPathToCommandLine
    case insertLeftPathToCommandLine, insertRightPathToCommandLine

    // Hot paths 1…10 (⌃1…⌃0 go, ⌃⇧1…⌃⇧0 set to the current folder)
    case goHotPath1, goHotPath2, goHotPath3, goHotPath4, goHotPath5
    case goHotPath6, goHotPath7, goHotPath8, goHotPath9, goHotPath10
    case setHotPath1, setHotPath2, setHotPath3, setHotPath4, setHotPath5
    case setHotPath6, setHotPath7, setHotPath8, setHotPath9, setHotPath10

    // Viewer window (F3)
    case viewerNextFile, viewerPreviousFile, viewerNextSelected, viewerPreviousSelected
    case viewerFirstFile, viewerLastFile, viewerSaveAs, viewerClose
    case viewerCopy, viewerSelectAll, viewerFind, viewerFindNext, viewerFindPrevious
    case viewerUseSelectionForFind, viewerGoTo
    case viewerText, viewerHex, viewerWrap, viewerEncoding, viewerAutoEncoding
    case viewerNextEncoding, viewerPreviousEncoding, viewerSetDefaultEncoding
    case viewerZoomIn, viewerZoomOut, viewerActualSize, viewerReload
    case viewerPreview, viewerHighlight, viewerZoomToFit, viewerSaveImageAs, viewerLoadRemote

    // Find window (⌃⌥F7)
    case findStart, findStop, findOpen, findShowInPanel, findView, findEdit, findQuickLook
    case findProperties, findTrash, findRemove, findCopyFiles, findCopyPaths, findCopyNames
    case findSelectAll, findToPanel, findClose

    // Compare files window
    case compareNextDifference, comparePreviousDifference, compareFirstDifference, compareLastDifference
    case compareIgnoreWhitespace, compareIgnoreAllWhitespace, compareIgnoreCase, compareDifferencesOnly
    case compareSwap, compareReload, compareCopy, compareZoomIn, compareZoomOut, compareActualSize, compareClose

    public static let goHotPaths: [Command] = [
        .goHotPath1, .goHotPath2, .goHotPath3, .goHotPath4, .goHotPath5,
        .goHotPath6, .goHotPath7, .goHotPath8, .goHotPath9, .goHotPath10,
    ]
    public static let setHotPaths: [Command] = [
        .setHotPath1, .setHotPath2, .setHotPath3, .setHotPath4, .setHotPath5,
        .setHotPath6, .setHotPath7, .setHotPath8, .setHotPath9, .setHotPath10,
    ]

    /// Hot path slot (0…9) of a go/set hot path command.
    public var hotPathSlot: Int? {
        Self.goHotPaths.firstIndex(of: self) ?? Self.setHotPaths.firstIndex(of: self)
    }
}

public enum MenuID: String, CaseIterable, Sendable {
    case app, file, edit, view, go, left, right, commands, options, window, help
}

/// Where a command lives. Panel commands need keyboard focus in a panel and are
/// disabled while a text field edits, so their keys fall through to the field.
/// Viewer commands exist only while a viewer window is key; the menu bar swaps
/// panel and viewer items, so the two scopes may reuse chords. Find commands
/// work the same way for the find window and the compare window.
public enum CommandScope: Sendable {
    case app, panel, viewer, find, compare
}

/// Which window kind the menu bar and key map currently serve.
public enum CommandContext: Sendable, CaseIterable {
    case panel, viewer, find, compare

    public func includes(_ scope: CommandScope) -> Bool {
        switch scope {
        case .app: true
        case .panel: self == .panel
        case .viewer: self == .viewer
        case .find: self == .find
        case .compare: self == .compare
        }
    }
}

public struct CommandSpec: Sendable {
    public let command: Command
    public let title: String
    public let menu: MenuID?
    /// First chord is shown in the menu (when menu-safe); all chords trigger.
    public let chords: [KeyChord]
    public let scope: CommandScope
    /// Draw a separator in the menu before this item.
    public let separatorBefore: Bool
}

public enum CommandRegistry {
    public static func spec(_ command: Command) -> CommandSpec { byCommand[command]! }

    public static func items(in menu: MenuID, context: CommandContext = .panel) -> [CommandSpec] {
        all.filter { $0.menu == menu && context.includes($0.scope) }
    }

    public static let all: [CommandSpec] = {
        typealias K = KeyChord
        let c: K.Modifiers = .control, o: K.Modifiers = .option
        let s: K.Modifiers = .shift, m: K.Modifiers = .command
        var list: [CommandSpec] = []
        func add(_ cmd: Command, _ title: String, _ menu: MenuID?, _ chords: [K] = [],
                 scope: CommandScope = .panel, sep: Bool = false) {
            list.append(CommandSpec(command: cmd, title: title, menu: menu, chords: chords,
                                    scope: scope, separatorBefore: sep))
        }
        func f(_ n: Int, _ mods: K.Modifiers = []) -> K { K(.function(n), mods) }
        func ch(_ char: Character, _ mods: K.Modifiers) -> K { K(.character(char), mods) }

        add(.about, "About iCommander", .app, scope: .app)
        add(.settings, "Settings…", .app, [ch(",", m)], scope: .app, sep: true)
        add(.quit, "Quit iCommander", .app, [ch("q", m)], scope: .app, sep: true)

        add(.view, "View", .file, [f(3)])
        add(.quickLook, "Quick Look", .file, [ch("y", m), f(3, o)])
        add(.edit, "Edit", .file, [f(4)])
        add(.newFile, "New File…", .file, [f(4, s)])
        add(.copy, "Copy…", .file, [f(5)], sep: true)
        add(.move, "Move…", .file, [f(6)])
        add(.makeDirectory, "New Folder…", .file, [f(7), ch("n", [m, s])])
        add(.rename, "Rename", .file, [f(2)])
        add(.delete, "Move to Trash", .file, [f(8), K(.forwardDelete), K(.backspace, m)], sep: true)
        add(.deletePermanently, "Delete Immediately…", .file,
            [f(8, s), K(.forwardDelete, s), K(.backspace, [m, o])])
        add(.properties, "Get Info", .file, [ch("i", m)], sep: true)
        add(.changeCase, "Change Case…", .file, [f(7, c)])
        add(.batchRename, "Batch Rename…", .file, [ch("m", c)])
        add(.pack, "Pack…", .file, [f(5, [c, o])], sep: true)
        add(.unpack, "Unpack…", .file, [f(6, [c, o])])

        add(.copyFiles, "Copy Files", .edit, [ch("c", m)])
        add(.pasteFiles, "Paste Files", .edit, [ch("v", m)])
        add(.copyFullPath, "Copy Path as Text", .edit, [ch("c", [m, o]), K(.insert, [c, o])])
        add(.copyName, "Copy Name as Text", .edit, [K(.insert, [c, o, s])])
        add(.selectByMask, "Select…", .edit, [K(.numPlus), ch("=", c)], sep: true)
        add(.deselectByMask, "Deselect…", .edit, [K(.numMinus), ch("-", c)])
        add(.invertByMask, "Invert Selection…", .edit, [K(.numStar), ch("8", [c, o])])
        add(.selectAll, "Select All", .edit, [ch("a", m), K(.numPlus, c)])
        add(.deselectAll, "Deselect All", .edit, [ch("a", [m, s]), K(.numMinus, c)])
        add(.selectSameExtension, "Select Same Extension", .edit, [K(.numPlus, s)])
        add(.deselectSameExtension, "Deselect Same Extension", .edit, [K(.numMinus, s)])

        add(.sortByName, "Sort by Name", .view, [f(3, c)])
        add(.sortByExtension, "Sort by Extension", .view, [f(4, c)])
        add(.sortByDate, "Sort by Date", .view, [f(5, c)])
        add(.sortBySize, "Sort by Size", .view, [f(6, c)])
        add(.viewModeDetailed, "Detailed", .view, [ch("1", [c, o])], sep: true)
        add(.viewModeBrief, "Brief", .view, [ch("2", [c, o])])
        add(.toggleHidden, "Show Hidden Files", .view, [ch(".", [m, s])], sep: true)
        add(.filter, "Filter…", .view, [f(12, c)])
        add(.refresh, "Refresh", .view, [f(9, c), ch("r", m)])
        add(.maximizePanel, "Maximize Panel", .view, [f(11, c)], sep: true)
        add(.comparePanels, "Compare Panels", .view, [f(10, c)])
        add(.calculateSizes, "Calculate Folder Sizes", .view, [f(10, [c, s])])

        add(.goBack, "Back", .go, [K(.left, [c, o]), ch("[", m)])
        add(.goForward, "Forward", .go, [K(.right, [c, o]), ch("]", m)])
        add(.goParent, "Enclosing Folder", .go, [K(.backspace), K(.up, m)])
        add(.goRoot, "Volume Root", .go, [ch("\\", c)])
        add(.goHome, "Home", .go, [ch("h", [m, s])])
        add(.changeDirectory, "Go to Folder…", .go, [f(7, s), ch("g", [m, s])], sep: true)
        add(.hotPaths, "Hot Paths…", .go, [f(9, s)])
        add(.workingDirectories, "Working Directories…", .go, [f(12, [c, o])])
        add(.newTab, "New Tab", .go, [ch("t", [c, s])], sep: true)
        add(.closeTab, "Close Tab", .go, [ch("w", [c, s])])
        add(.nextTab, "Next Tab", .go, [K(.pageDown, [c, s])])
        add(.previousTab, "Previous Tab", .go, [K(.pageUp, [c, s])])

        add(.leftVolumeMenu, "Volume…", .left, [f(1, [c, o])])
        add(.rightVolumeMenu, "Volume…", .right, [f(2, [c, o])])

        add(.find, "Find Files…", .commands, [f(7, [c, o])])
        add(.occupiedSpace, "Disk Map…", .commands, [f(10, [c, o]), ch("d", [c, s])])
        add(.compareFiles, "Compare Files…", .commands)
        add(.calculateChecksums, "Calculate Checksums…", .commands, sep: true)
        add(.verifyChecksums, "Verify Checksums…", .commands, [ch("v", [c, s])])
        add(.openTerminal, "Open Terminal Here", .commands, [ch("/", c), K(.numSlash)], sep: true)
        add(.revealInFinder, "Show in Finder", .commands, [f(3, s)])
        add(.userMenu, "User Menu…", .commands, [f(9)], sep: true)
        add(.connectToServer, "Connect to Server…", .commands, [ch("k", m), ch("f", [c, s])], sep: true)
        add(.disconnect, "Disconnect…", .commands, [f(12)])

        add(.configureKeys, "Keyboard Shortcuts…", .options, scope: .app)

        add(.help, "iCommander Help", .help, [f(1)], scope: .app)

        add(.open, "Open", nil, [K(.enter), K(.numEnter), K(.down, m)])
        add(.switchPanel, "Switch Panel", nil, [K(.tab), K(.tab, s)])
        add(.toggleSelection, "Toggle Selection", nil, [K(.insert)])
        add(.toggleSelectionAndSize, "Toggle Selection and Size", nil, [K(.space)])
        add(.openInLeftPanel, "Open in Left Panel", nil, [K(.left, [c, s])])
        add(.openInRightPanel, "Open in Right Panel", nil, [K(.right, [c, s])])
        add(.focusCommandLine, "Command Line", nil, [K(.tab, c)])
        add(.insertNameToCommandLine, "Insert Name", nil, [K(.enter, c)])
        add(.insertPathToCommandLine, "Insert Path", nil, [K(.space, c), K(.space, [c, s])])
        add(.insertLeftPathToCommandLine, "Insert Left Path", nil, [ch("[", c)])
        add(.insertRightPathToCommandLine, "Insert Right Path", nil, [ch("]", c)])
        for (slot, (go, set)) in zip(Command.goHotPaths, Command.setHotPaths).enumerated() {
            let digit = Character(String((slot + 1) % 10))
            add(go, "Go to Hot Path \(slot + 1)", nil, [ch(digit, c)])
            add(set, "Set Hot Path \(slot + 1)", nil, [ch(digit, [c, s])])
        }

        func viewer(_ cmd: Command, _ title: String, _ menu: MenuID?, _ chords: [K] = [], sep: Bool = false) {
            add(cmd, title, menu, chords, scope: .viewer, sep: sep)
        }
        viewer(.viewerNextFile, "Next File", .file, [K(.space)])
        viewer(.viewerPreviousFile, "Previous File", .file, [K(.backspace)])
        viewer(.viewerNextSelected, "Next Selected File", .file, [K(.space, c)])
        viewer(.viewerPreviousSelected, "Previous Selected File", .file, [K(.backspace, c)])
        viewer(.viewerFirstFile, "First File", .file, [K(.backspace, s)])
        viewer(.viewerLastFile, "Last File", .file, [K(.space, s)])
        viewer(.viewerSaveAs, "Copy to File…", .file, [ch("s", m)], sep: true)
        viewer(.viewerSaveImageAs, "Save Image As…", .file, [ch("s", [m, s])])
        viewer(.viewerClose, "Close Viewer", nil, [K(.escape)])
        viewer(.viewerCopy, "Copy", .edit, [ch("c", m)])
        viewer(.viewerSelectAll, "Select All", .edit, [ch("a", m)])
        viewer(.viewerFind, "Find…", .edit, [ch("f", m)], sep: true)
        viewer(.viewerFindNext, "Find Next", .edit, [ch("g", m)])
        viewer(.viewerFindPrevious, "Find Previous", .edit, [ch("g", [m, s])])
        viewer(.viewerUseSelectionForFind, "Use Selection for Find", .edit, [ch("e", m)])
        viewer(.viewerGoTo, "Go to Line or Offset…", .edit, [ch("l", m)], sep: true)
        viewer(.viewerText, "Text", .view, [ch("1", m), f(5)])
        viewer(.viewerHex, "Hex", .view, [ch("2", m), f(4)])
        viewer(.viewerPreview, "Preview", .view, [ch("3", m), f(6)])
        viewer(.viewerLoadRemote, "Load Images from the Internet", .view)
        viewer(.viewerWrap, "Wrap Lines", .view, [ch("w", c)], sep: true)
        viewer(.viewerHighlight, "Highlight Syntax", .view, [ch("h", c)])
        viewer(.viewerEncoding, "Text Encoding", .view, sep: true)
        viewer(.viewerNextEncoding, "Next Encoding", .view, [f(8)])
        viewer(.viewerPreviousEncoding, "Previous Encoding", .view, [f(8, s)])
        viewer(.viewerAutoEncoding, "Detect Automatically", nil)
        viewer(.viewerSetDefaultEncoding, "Set as Default", nil)
        viewer(.viewerZoomIn, "Bigger", .view, [ch("+", m), ch("=", m)], sep: true)
        viewer(.viewerZoomOut, "Smaller", .view, [ch("-", m)])
        viewer(.viewerActualSize, "Actual Size", .view, [ch("0", m)])
        viewer(.viewerZoomToFit, "Zoom to Fit", .view, [ch("9", m)])
        viewer(.viewerReload, "Reload", .view, [ch("r", m)], sep: true)

        func find(_ cmd: Command, _ title: String, _ menu: MenuID?, _ chords: [K] = [], sep: Bool = false) {
            add(cmd, title, menu, chords, scope: .find, sep: sep)
        }
        find(.findOpen, "Open", .file, [ch("o", m), K(.down, m), K(.enter), K(.numEnter)])
        find(.findShowInPanel, "Show in Panel", .file, [ch("r", m), K(.space)])
        find(.findView, "View", .file, [f(3)], sep: true)
        find(.findEdit, "Edit", .file, [f(4)])
        find(.findQuickLook, "Quick Look", .file, [ch("y", m), f(3, o)])
        find(.findProperties, "Get Info", .file, [ch("i", m)])
        find(.findTrash, "Move to Trash", .file, [f(8), K(.backspace, m), K(.forwardDelete)], sep: true)
        find(.findRemove, "Remove from List", .file, [K(.backspace)])
        find(.findCopyFiles, "Copy Files", .edit, [ch("c", m)])
        find(.findCopyPaths, "Copy Path as Text", .edit, [ch("c", [m, o])])
        find(.findCopyNames, "Copy Name as Text", .edit, [ch("c", [m, s])])
        find(.findSelectAll, "Select All", .edit, [ch("a", m)], sep: true)
        find(.findStart, "Find Now", .commands, [K(.enter, m)])
        find(.findStop, "Stop", .commands, [ch(".", m)])
        find(.findToPanel, "Show Results in Panel", .commands, [ch("p", [m, s])], sep: true)
        find(.findClose, "Close", nil, [K(.escape)])

        func compare(_ cmd: Command, _ title: String, _ menu: MenuID?, _ chords: [K] = [], sep: Bool = false) {
            add(cmd, title, menu, chords, scope: .compare, sep: sep)
        }
        compare(.compareCopy, "Copy", .edit, [ch("c", m)])
        compare(.compareNextDifference, "Next Difference", .go, [K(.down, m), K(.space)])
        compare(.comparePreviousDifference, "Previous Difference", .go, [K(.up, m), K(.backspace)])
        compare(.compareFirstDifference, "First Difference", .go, [K(.up, [m, o])], sep: true)
        compare(.compareLastDifference, "Last Difference", .go, [K(.down, [m, o])])
        compare(.compareDifferencesOnly, "Show Differences Only", .view, [ch("d", [m, s])])
        compare(.compareIgnoreWhitespace, "Ignore Whitespace Changes", .view, sep: true)
        compare(.compareIgnoreAllWhitespace, "Ignore All Whitespace", .view)
        compare(.compareIgnoreCase, "Ignore Case", .view)
        compare(.compareSwap, "Swap Sides", .view, [ch("s", [m, o])], sep: true)
        compare(.compareZoomIn, "Bigger", .view, [ch("+", m), ch("=", m)], sep: true)
        compare(.compareZoomOut, "Smaller", .view, [ch("-", m)])
        compare(.compareActualSize, "Actual Size", .view, [ch("0", m)])
        compare(.compareReload, "Reload", .view, [ch("r", m)], sep: true)
        compare(.compareClose, "Close", nil, [K(.escape)])
        return list
    }()

    private static let byCommand: [Command: CommandSpec] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.command, $0) })
}

/// User key binding overrides on top of the factory chords in `CommandRegistry`.
public struct KeyBindings: Codable, Sendable, Equatable {
    /// Commands whose chords the user replaced; an empty array means "no shortcut".
    public var overrides: [Command: [KeyChord]]

    public init(overrides: [Command: [KeyChord]] = [:]) {
        self.overrides = overrides.filter { $0.value != CommandRegistry.spec($0.key).chords }
    }

    public static let factory = KeyBindings()

    /// The user's chords when overridden, otherwise the factory chords.
    public func chords(for command: Command) -> [KeyChord] {
        overrides[command] ?? CommandRegistry.spec(command).chords
    }

    public func isCustomized(_ command: Command) -> Bool { overrides[command] != nil }

    /// Replaces the chords of `command`; chords equal to the factory ones remove the override.
    public mutating func set(_ chords: [KeyChord], for command: Command) {
        if chords == CommandRegistry.spec(command).chords {
            overrides[command] = nil
        } else {
            overrides[command] = chords
        }
    }

    public mutating func reset(_ command: Command) { overrides[command] = nil }

    public mutating func resetAll() { overrides = [:] }

    /// Commands (other than `command`) that currently use `chord` in a context overlapping `command`'s scope.
    public func conflicts(_ chord: KeyChord, for command: Command) -> [Command] {
        let scope = CommandRegistry.spec(command).scope
        let contexts = CommandContext.allCases.filter { $0.includes(scope) }
        return CommandRegistry.all.compactMap { spec in
            guard spec.command != command, contexts.contains(where: { $0.includes(spec.scope) }),
                  chords(for: spec.command).contains(chord) else { return nil }
            return spec.command
        }
    }

    // Encoded as `{ "<command rawValue>": ["cmd+shift+F5", …] }`; unknown commands and malformed
    // chord lists are ignored so files written by other versions still load.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: [String]].self)
        var result: [Command: [KeyChord]] = [:]
        for (name, texts) in raw {
            guard let command = Command(rawValue: name) else { continue }
            let chords = texts.compactMap(KeyChord.init(storageString:))
            guard chords.count == texts.count else { continue }
            result[command] = chords
        }
        self.init(overrides: result)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: overrides.map {
            ($0.key.rawValue, $0.value.map(\.storageString))
        }))
    }
}

/// Chord → command lookup built from the factory chords and optional user overrides.
public struct KeyMap: Sendable {
    public private(set) var bindings: [KeyChord: Command]
    /// Candidate chords per command in declaration order (including ones another command won).
    private let candidates: [Command: [KeyChord]]

    /// Factory chords first-wins, then `overrides` (chord → command) replace whatever they hit.
    public init(context: CommandContext = .panel, overrides: [KeyChord: Command] = [:]) {
        var map: [KeyChord: Command] = [:]
        var order: [Command: [KeyChord]] = [:]
        for spec in CommandRegistry.all where context.includes(spec.scope) {
            order[spec.command] = spec.chords
            for chord in spec.chords where map[chord] == nil { map[chord] = spec.command }
        }
        for (chord, command) in overrides.sorted(by: { $0.key.storageString < $1.key.storageString }) {
            if order[command]?.contains(chord) != true { order[command, default: []].append(chord) }
        }
        map.merge(overrides) { _, new in new }
        bindings = map
        candidates = order
    }

    /// Builds the map from `bindings.chords(for:)` of every command in the context. Chords the user
    /// assigned explicitly win over factory chords of other commands; among factory chords the
    /// declaration order decides.
    public init(context: CommandContext = .panel, bindings userBindings: KeyBindings) {
        var map: [KeyChord: Command] = [:]
        var order: [Command: [KeyChord]] = [:]
        let specs = CommandRegistry.all.filter { context.includes($0.scope) }
        for spec in specs { order[spec.command] = userBindings.chords(for: spec.command) }
        for spec in specs where userBindings.isCustomized(spec.command) {
            for chord in order[spec.command] ?? [] where map[chord] == nil { map[chord] = spec.command }
        }
        for spec in specs where !userBindings.isCustomized(spec.command) {
            for chord in order[spec.command] ?? [] where map[chord] == nil { map[chord] = spec.command }
        }
        self.bindings = map
        candidates = order
    }

    public func command(for chord: KeyChord) -> Command? { bindings[chord] }

    /// Chords that actually trigger `command` in this map, in the command's order.
    public func chords(for command: Command) -> [KeyChord] {
        (candidates[command] ?? []).filter { bindings[$0] == command }
    }

    public static let standard = KeyMap()
    public static let viewer = KeyMap(context: .viewer)
    public static let find = KeyMap(context: .find)
    public static let compare = KeyMap(context: .compare)
}
