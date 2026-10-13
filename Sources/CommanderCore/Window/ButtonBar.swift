// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Where the button bar stands (spec 018).
public enum ButtonBarPlacement: String, CaseIterable, Sendable {
    case off, top, bottom

    public static let key = "buttonBar.placement"
    /// The place View → Show Button Bar turns the bar on at.
    public static let lastKey = "buttonBar.lastPlacement"

    public init(storage: String?) { self = storage.flatMap(Self.init(rawValue:)) ?? .off }

    /// Where Show Button Bar puts the bar: the last place used, the top by default.
    public static func shown(last: String?) -> ButtonBarPlacement {
        let place = ButtonBarPlacement(storage: last)
        return place == .off ? .top : place
    }
}

/// One button of the button bar: an app command, a program (the fields of a user menu command) or a
/// separator, shown as an icon only.
public struct ButtonBarItem: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case command, program, separator }

    public var id: UUID
    public var kind: Kind
    /// The command's name; kept as text so a command unknown to this version survives (disabled).
    public var command: String
    /// The program to run, as a user menu command (title, program, arguments, folder, terminal).
    public var program: UserMenuItem
    /// "" = the default icon, `ButtonBarIcon.appIcon` = the program's app icon, else an SF Symbol name.
    public var icon: String

    public init(id: UUID = UUID(), kind: Kind, command: String = "", program: UserMenuItem = UserMenuItem(directory: "$(FullPath)"),
                icon: String = "") {
        self.id = id
        self.kind = kind
        self.command = command
        self.program = program
        self.icon = icon
    }

    public static func command(_ command: Command, icon: String = "") -> ButtonBarItem {
        ButtonBarItem(kind: .command, command: command.rawValue, icon: icon)
    }

    public static func program(_ program: UserMenuItem, icon: String = "") -> ButtonBarItem {
        ButtonBarItem(kind: .program, program: program, icon: icon)
    }

    public static var separator: ButtonBarItem { ButtonBarItem(kind: .separator) }

    /// The command of a command button; nil for other kinds and for unknown names.
    public var resolvedCommand: Command? { kind == .command ? Command(rawValue: command) : nil }

    // Missing keys fall back to defaults so hand-edited or older files still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
                  kind: try c.decode(Kind.self, forKey: .kind),
                  command: try c.decodeIfPresent(String.self, forKey: .command) ?? "",
                  program: (try? c.decodeIfPresent(UserMenuItem.self, forKey: .program)) ?? UserMenuItem(),
                  icon: try c.decodeIfPresent(String.self, forKey: .icon) ?? "")
    }
}

/// The icon a button shows.
public enum ButtonBarIcon: Equatable, Sendable {
    case symbol(String)
    case appIcon(path: String)

    /// The stored value that means "the program's app icon".
    public static let appIcon = "@app"
    /// For commands without a toolbar icon.
    public static let genericCommand = "command"
    /// For programs that are not an app.
    public static let genericProgram = "terminal"

    /// What `item` shows: its own choice, else the default for its kind.
    public static func resolve(_ item: ButtonBarItem) -> ButtonBarIcon {
        switch item.kind {
        case .separator:
            return .symbol("")
        case .command:
            if !item.icon.isEmpty, item.icon != appIcon { return .symbol(item.icon) }
            return .symbol(item.resolvedCommand.flatMap { CommandSymbols.symbol(for: $0) } ?? genericCommand)
        case .program:
            if item.icon == appIcon || item.icon.isEmpty, let app = appPath(item.program.program) {
                return .appIcon(path: app)
            }
            return .symbol(item.icon.isEmpty || item.icon == appIcon ? genericProgram : item.icon)
        }
    }

    /// The app bundle a program path names (`/Applications/X.app`, `~/Applications/X.app`), if any.
    public static func appPath(_ program: String) -> String? {
        let path = (program as NSString).expandingTildeInPath
        return path.hasSuffix(".app") || path.hasSuffix(".app/") ? path : nil
    }
}

/// Reading and writing the buttons (UserDefaults, settings export).
public enum ButtonBarStore {
    public static let key = "buttonBar.items"

    /// What the bar holds until the user changes it.
    public static let samples: [ButtonBarItem] = [
        .command(.openTerminal), .command(.find), .command(.comparePanels), .separator,
        .command(.hotPaths), .command(.calculateSizes), .command(.revealInFinder),
    ]

    public static func encode(_ items: [ButtonBarItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(items)
    }

    /// Decodes the stored buttons; a broken entry is dropped, not the whole bar. Missing data = the samples.
    public static func decode(_ data: Data?) -> [ButtonBarItem] {
        guard let data else { return samples }
        guard let entries = try? JSONDecoder().decode([LossyItem].self, from: data) else { return samples }
        return entries.compactMap(\.item)
    }

    private struct LossyItem: Decodable {
        let item: ButtonBarItem?
        init(from decoder: any Decoder) throws { item = try? ButtonBarItem(from: decoder) }
    }
}

/// SF Symbols of commands: the toolbar's icons and the default icons of command buttons.
public enum CommandSymbols {
    public static func symbol(for command: Command) -> String? { symbols[command] }

    /// The commands the window toolbar offers in Customize Toolbar.
    public static let toolbar: [Command: String] = [
        .goBack: "chevron.left", .goForward: "chevron.right", .goParent: "arrow.turn.left.up",
        .goHome: "house", .goRoot: "externaldrive", .refresh: "arrow.clockwise", .toggleHidden: "eye",
        .quickLook: "eye.square", .properties: "info.circle", .makeDirectory: "folder.badge.plus",
        .openTerminal: "terminal", .revealInFinder: "macwindow", .comparePanels: "rectangle.split.2x1",
        .maximizePanel: "arrow.up.left.and.arrow.down.right", .calculateSizes: "sum",
        .find: "magnifyingglass", .hotPaths: "star", .newTab: "plus.square.on.square",
        .filter: "line.3.horizontal.decrease.circle", .changeDirectory: "arrow.right.circle",
        .copy: "doc.on.doc", .move: "arrow.right.doc.on.clipboard", .delete: "trash",
        .connectToServer: "network", .disconnect: "eject",
        .newSymbolicLink: "link.badge.plus", .newHardLink: "link", .editSymbolicLink: "pencil.line",
        .pasteAsSymbolicLink: "doc.on.clipboard", .goToLinkTarget: "arrowshape.turn.up.right",
        .changeAttributes: "lock.doc",
    ]

    /// More defaults for buttons only.
    private static let more: [Command: String] = [
        .view: "doc.text.magnifyingglass", .edit: "square.and.pencil", .rename: "character.cursor.ibeam",
        .deletePermanently: "trash.slash", .pack: "archivebox", .unpack: "archivebox.circle",
        .selectAll: "checkmark.circle", .invertAll: "circle.lefthalf.filled", .help: "questionmark.circle",
        .swapPanels: "arrow.left.arrow.right", .sortByName: "textformat", .sortBySize: "arrow.up.arrow.down",
        .sortByDate: "calendar", .sortByExtension: "doc.badge.ellipsis", .closeTab: "xmark.square",
        .quickView: "rectangle.righthalf.inset.filled", .userMenu: "list.bullet.rectangle",
        .occupiedSpace: "chart.pie", .settings: "gearshape", .commandLineHistory: "clock.arrow.circlepath",
        .copyAs: "plus.rectangle.on.rectangle", .testArchives: "checkmark.seal", .changeCase: "textformat.size",
        .batchRename: "pencil.and.list.clipboard", .compareFiles: "doc.on.doc.fill",
    ]

    private static let symbols: [Command: String] = toolbar.merging(more) { first, _ in first }
}

/// How the button bar lays out its buttons (spec 018): side by side from the left; what does not fit
/// goes into a » menu at the end.
public enum ButtonBarLayout {
    public static let buttonWidth = 28.0
    public static let separatorWidth = 9.0
    public static let overflowWidth = 22.0
    public static let gap = 2.0

    public static func width(of item: ButtonBarItem) -> Double {
        item.kind == .separator ? separatorWidth : buttonWidth
    }

    /// The width all `items` take side by side.
    public static func naturalWidth(_ items: [ButtonBarItem]) -> Double {
        guard !items.isEmpty else { return 0 }
        return items.map(width(of:)).reduce(0, +) + gap * Double(items.count - 1)
    }

    /// How many leading `items` are shown in `available` points; the rest goes into ». When not all
    /// fit, room is kept for the » button, and separators at the cut are not shown.
    public static func visibleCount(_ items: [ButtonBarItem], in available: Double) -> Int {
        if naturalWidth(items) <= available { return items.count }
        let room = available - overflowWidth - gap
        var used = 0.0
        var count = 0
        for item in items {
            let next = used + (count == 0 ? 0 : gap) + width(of: item)
            if next > room { break }
            used = next
            count += 1
        }
        while count > 0, items[count - 1].kind == .separator { count -= 1 }
        return count
    }

    /// The bottom row with the function keys and the buttons after them: the width of the function
    /// key part (0 without keys) and of the button part, which follows after `divider`. The keys keep
    /// their natural width when everything fits and shrink down to `minKeyWidth` each before buttons
    /// go into ».
    public static func bottomRow(width: Double, keyCount: Int, buttons: Double, edge: Double, keyGap: Double,
                                 divider: Double, minKeyWidth: Double,
                                 maxKeyWidth: Double = FunctionKeyBarLayout.maxButtonWidth) -> (keys: Double, buttons: Double) {
        guard keyCount > 0 else { return (0, max(width - 2 * edge, 0)) }
        guard buttons > 0 else { return (width, 0) }
        let n = Double(keyCount)
        let natural = 2 * edge + n * maxKeyWidth + (n - 1) * keyGap
        let minimum = 2 * edge + n * minKeyWidth + (n - 1) * keyGap
        let keys = min(natural, max(minimum, width - divider - buttons - edge))
        return (keys, max(width - keys - divider - edge, 0))
    }
}

/// SF Symbols offered by the icon picker: names fit for file manager actions, programs and places.
/// The app drops names the running system does not know.
public enum ButtonBarSymbols {
    public static let all: [String] = [
        // Files and folders
        "doc", "doc.fill", "doc.text", "doc.richtext", "doc.on.doc", "doc.on.clipboard", "doc.badge.plus",
        "doc.badge.gearshape", "doc.zipper", "doc.text.magnifyingglass", "doc.plaintext", "note.text",
        "folder", "folder.fill", "folder.badge.plus", "folder.badge.gearshape", "folder.badge.person.crop",
        "folder.badge.questionmark", "plus.rectangle.on.folder", "archivebox", "archivebox.fill", "tray",
        "tray.full", "tray.and.arrow.down", "tray.and.arrow.up", "externaldrive", "externaldrive.fill",
        "internaldrive", "opticaldiscdrive", "server.rack", "xserve", "icloud", "icloud.and.arrow.down",
        "icloud.and.arrow.up", "network", "globe", "link", "link.badge.plus", "paperclip", "shippingbox",
        // Actions
        "plus", "minus", "xmark", "checkmark", "trash", "trash.fill", "trash.slash", "pencil",
        "square.and.pencil", "pencil.and.outline", "scissors", "eraser", "paintbrush", "wand.and.stars",
        "arrow.clockwise", "arrow.counterclockwise", "arrow.uturn.backward", "arrow.uturn.forward",
        "arrow.left.arrow.right", "arrow.up.arrow.down", "arrow.right", "arrow.left", "arrow.up", "arrow.down",
        "arrow.up.right.square", "arrow.down.circle", "arrow.up.circle", "arrow.triangle.2.circlepath",
        "arrow.triangle.branch", "arrow.triangle.merge", "arrow.turn.left.up", "arrowshape.turn.up.right",
        "square.and.arrow.up", "square.and.arrow.down", "square.and.arrow.down.on.square", "rectangle.portrait.and.arrow.right",
        "magnifyingglass", "plus.magnifyingglass", "line.3.horizontal.decrease.circle", "slider.horizontal.3",
        "gearshape", "gearshape.2", "gear", "wrench.and.screwdriver", "hammer", "screwdriver", "ladybug",
        "play", "play.fill", "play.circle", "stop", "pause", "forward", "backward", "record.circle",
        "lock", "lock.open", "lock.doc", "key", "shield", "checkmark.seal", "exclamationmark.triangle",
        "eye", "eye.slash", "eye.square", "info.circle", "questionmark.circle", "bell", "flag", "tag",
        "bookmark", "star", "star.fill", "heart", "pin", "mappin", "location", "paperplane", "envelope",
        "printer", "camera", "photo", "film", "music.note", "waveform", "mic", "speaker.wave.2",
        "sum", "number", "percent", "function", "textformat", "textformat.size", "character.cursor.ibeam",
        "text.alignleft", "list.bullet", "list.number", "list.bullet.rectangle", "checklist",
        "calendar", "clock", "clock.arrow.circlepath", "timer", "hourglass", "chart.pie", "chart.bar",
        "square.grid.2x2", "square.grid.3x3", "rectangle.split.2x1", "rectangle.split.3x1",
        "rectangle.righthalf.inset.filled", "sidebar.left", "sidebar.right", "macwindow", "macwindow.on.rectangle",
        "rectangle.stack", "square.stack", "square.on.square", "plus.square.on.square", "xmark.square",
        "arrow.up.left.and.arrow.down.right", "arrow.down.right.and.arrow.up.left", "viewfinder",
        // Apps and devices
        "terminal", "terminal.fill", "apple.terminal", "chevron.left.forwardslash.chevron.right",
        "curlybraces", "command", "option", "control", "keyboard", "desktopcomputer", "laptopcomputer",
        "display", "iphone", "ipad", "applewatch", "airplayvideo", "cpu", "memorychip", "battery.100",
        "bolt", "power", "house", "building.2", "briefcase", "cart", "creditcard", "gift", "graduationcap",
        "book", "books.vertical", "newspaper", "map", "globe.europe.africa", "person", "person.2",
        "bubble.left", "quote.bubble", "lightbulb", "flame", "leaf", "sun.max", "moon", "cloud", "snowflake",
        "puzzlepiece", "cube", "shippingbox.fill", "gamecontroller", "paintpalette", "theatermasks",
        "1.circle", "2.circle", "3.circle", "4.circle", "5.circle", "a.circle", "b.circle", "c.circle",
    ]

    /// The symbols whose name contains every word of `query` (dots and spaces both separate words).
    public static func search(_ query: String, in names: [String] = all) -> [String] {
        let words = query.lowercased().split { $0 == " " || $0 == "." }.map(String.init)
        guard !words.isEmpty else { return names }
        return names.filter { name in words.allSatisfy { name.contains($0) } }
    }
}
