/// Every user-facing command. Menu, key map and enablement all derive from
/// `CommandRegistry`, so a command is declared exactly once.
public enum Command: String, CaseIterable, Hashable, Sendable {
    // App
    case about, settings, quit, help

    // File
    case view, quickLook, edit, newFile, copy, move, makeDirectory
    case delete, deletePermanently, rename, properties, pack, unpack

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

    // Options
    case configureKeys

    // Panel-only (no menu item)
    case open, switchPanel, toggleSelection, toggleSelectionAndSize
    case openInLeftPanel, openInRightPanel
    case focusCommandLine, insertNameToCommandLine, insertPathToCommandLine
    case insertLeftPathToCommandLine, insertRightPathToCommandLine
}

public enum MenuID: String, CaseIterable, Sendable {
    case app, file, edit, view, go, left, right, commands, options, window, help
}

/// Whether a command needs keyboard focus in a panel. Panel commands are
/// disabled while a text field edits, so their keys fall through to the field.
public enum CommandScope: Sendable {
    case app, panel
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

    public static func items(in menu: MenuID) -> [CommandSpec] {
        all.filter { $0.menu == menu }
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
        add(.quickLook, "Quick Look", .file, [K(.space, m)])
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
        add(.pack, "Pack…", .file, [f(5, [c, o])], sep: true)
        add(.unpack, "Unpack…", .file, [f(6, [c, o])])

        add(.copyFiles, "Copy Files", .edit, [ch("c", m)])
        add(.pasteFiles, "Paste Files", .edit, [ch("v", m)])
        add(.copyFullPath, "Copy Path as Text", .edit, [ch("c", [m, o]), K(.insert, [c, o])])
        add(.copyName, "Copy Name as Text", .edit, [K(.insert, [c, o, s])])
        add(.selectByMask, "Select…", .edit, [K(.numPlus), ch("=", c)], sep: true)
        add(.deselectByMask, "Deselect…", .edit, [K(.numMinus), ch("-", c)])
        add(.invertByMask, "Invert Selection…", .edit, [K(.numStar), ch("8", c)])
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
        add(.occupiedSpace, "Occupied Space", .commands, [f(10, [c, o])])
        add(.openTerminal, "Open Terminal Here", .commands, [ch("/", c), K(.numSlash)], sep: true)
        add(.revealInFinder, "Show in Finder", .commands, [f(3, s)])
        add(.userMenu, "User Menu…", .commands, [f(9)], sep: true)

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
        add(.insertPathToCommandLine, "Insert Path", nil, [K(.space, c)])
        add(.insertLeftPathToCommandLine, "Insert Left Path", nil, [ch("[", c)])
        add(.insertRightPathToCommandLine, "Insert Right Path", nil, [ch("]", c)])
        return list
    }()

    private static let byCommand: [Command: CommandSpec] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.command, $0) })
}

/// Chord → command lookup. Later stages let the user override bindings.
public struct KeyMap: Sendable {
    public private(set) var bindings: [KeyChord: Command]

    public init(overrides: [KeyChord: Command] = [:]) {
        var map: [KeyChord: Command] = [:]
        for spec in CommandRegistry.all {
            for chord in spec.chords where map[chord] == nil { map[chord] = spec.command }
        }
        map.merge(overrides) { _, new in new }
        bindings = map
    }

    public func command(for chord: KeyChord) -> Command? { bindings[chord] }

    public static let standard = KeyMap()
}
