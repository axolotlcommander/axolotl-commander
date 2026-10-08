// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// One entry of the user menu (Salamander's "User Menu"): a command, a submenu or a separator.
public struct UserMenuItem: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case command, submenu, separator }

    public var id: UUID
    public var kind: Kind
    public var title: String
    /// Path or command name; `~` allowed; an `.app` bundle path is allowed.
    public var program: String
    /// Shell-like words with `$(Variables)`.
    public var arguments: String
    /// Initial directory, default `$(FullPath)`.
    public var directory: String
    /// Run in the terminal app instead of directly.
    public var runInTerminal: Bool
    /// Submenu items.
    public var children: [UserMenuItem]
    /// Key chord that runs the command from a panel (commands only).
    public var shortcut: KeyChord?

    public init(id: UUID = UUID(), kind: Kind = .command, title: String = "", program: String = "",
                arguments: String = "", directory: String = "$(FullPath)", runInTerminal: Bool = false,
                children: [UserMenuItem] = [], shortcut: KeyChord? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.program = program
        self.arguments = arguments
        self.directory = directory
        self.runInTerminal = runInTerminal
        self.children = children
        self.shortcut = shortcut
    }

    // Missing keys fall back to defaults so hand-edited or older files still load.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            kind: try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .command,
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
            program: try c.decodeIfPresent(String.self, forKey: .program) ?? "",
            arguments: try c.decodeIfPresent(String.self, forKey: .arguments) ?? "",
            directory: try c.decodeIfPresent(String.self, forKey: .directory) ?? "$(FullPath)",
            runInTerminal: try c.decodeIfPresent(Bool.self, forKey: .runInTerminal) ?? false,
            children: try c.decodeIfPresent([UserMenuItem].self, forKey: .children) ?? [],
            // A malformed chord drops only the shortcut, not the item.
            shortcut: (try? c.decodeIfPresent(KeyChord.self, forKey: .shortcut)) ?? nil)
    }
}

/// Everything the variables of a user menu command can refer to.
public struct UserMenuContext: Sendable {
    public var activeDirectory: URL
    public var inactiveDirectory: URL
    public var leftDirectory: URL
    public var rightDirectory: URL
    /// Item under the cursor of the active panel (nil on "..").
    public var cursor: URL?
    /// Selected items of the active panel (empty = none).
    public var selected: [URL]
    public var leftCursor: URL?
    public var rightCursor: URL?
    public var environment: [String: String]
    public var home: URL

    public init(activeDirectory: URL, inactiveDirectory: URL, leftDirectory: URL, rightDirectory: URL,
                cursor: URL? = nil, selected: [URL] = [], leftCursor: URL? = nil, rightCursor: URL? = nil,
                environment: [String: String] = [:], home: URL) {
        self.activeDirectory = activeDirectory
        self.inactiveDirectory = inactiveDirectory
        self.leftDirectory = leftDirectory
        self.rightDirectory = rightDirectory
        self.cursor = cursor
        self.selected = selected
        self.leftCursor = leftCursor
        self.rightCursor = rightCursor
        self.environment = environment
        self.home = home
    }
}

/// A fully expanded program call: no variables, no shell involved.
public struct UserMenuInvocation: Sendable, Equatable {
    public var program: String
    public var arguments: [String]
    public var directory: URL

    public init(program: String, arguments: [String], directory: URL) {
        self.program = program
        self.arguments = arguments
        self.directory = directory
    }
}

public enum UserMenuError: Error, Equatable {
    case unknownVariable(String)
    /// A per-file or list variable is used but there is no cursor item and nothing selected.
    case noFile
    case emptyProgram
    /// The arguments have an unbalanced quote or an unquoted shell metacharacter.
    case badQuoting
    /// The directory is a list variable (several directories make no sense).
    case notADirectory(String)
}

/// Expands `$(Variables)` of a user menu item into concrete program invocations.
///
/// The arguments are split into words first (`ShellWords`), variables are expanded inside each word
/// afterwards, so values with spaces, quotes or `$` are never re-split or re-interpreted.
public enum UserMenuExpander {
    /// Variable syntax with a short description, for the "insert variable" menu of the editor.
    public static let variables: [(name: String, description: String)] = [
        ("$(FullName)", "Full path of the file"),
        ("$(Name)", "File name with extension"),
        ("$(NamePart)", "File name without extension"),
        ("$(ExtPart)", "Extension without the dot"),
        ("$(FullPath)", "Directory of the active panel"),
        ("$(FullPathInactive)", "Directory of the inactive panel"),
        ("$(FullPathLeft)", "Directory of the left panel"),
        ("$(FullPathRight)", "Directory of the right panel"),
        ("$(FileToCompareLeft)", "Item under the cursor in the left panel"),
        ("$(FileToCompareRight)", "Item under the cursor in the right panel"),
        ("$(ListOfSelectedNames)", "Names of the selected items"),
        ("$(ListOfSelectedFullNames)", "Full paths of the selected items"),
        ("$[NAME]", "Environment variable"),
        ("$$", "A literal dollar sign"),
    ]

    /// Expands `item` into one invocation, or one per selected file when it uses a per-file variable
    /// (`$(FullName)`, `$(Name)`, `$(NamePart)`, `$(ExtPart)`). Per-file variables use the cursor item
    /// when nothing is selected; list variables do the same. Throws `noFile` when there is neither.
    public static func invocations(for item: UserMenuItem, in context: UserMenuContext) throws -> [UserMenuInvocation] {
        guard item.kind == .command else { throw UserMenuError.emptyProgram }
        let program = tildeExpanded(try scan(item.program), home: context.home)
        let directorySource = item.directory.trimmingCharacters(in: .whitespaces).isEmpty
            ? "$(FullPath)" : item.directory
        let directory = tildeExpanded(try scan(directorySource), home: context.home)
        if directory.contains(where: { $0.variable?.isList == true }) {
            throw UserMenuError.notADirectory(item.directory)
        }
        let words = try splitArguments(item.arguments, home: context.home)

        let usesPerFile = program.contains { $0.variable?.isPerFile == true }
            || directory.contains { $0.variable?.isPerFile == true }
            || words.contains { $0.contains { $0.variable?.isPerFile == true } }
        let files: [URL?]
        if usesPerFile {
            let items = context.selected.isEmpty ? context.cursor.map { [$0] } ?? [] : context.selected
            if items.isEmpty { throw UserMenuError.noFile }
            files = items
        } else {
            files = [nil]
        }

        return try files.map { file in
            let programText = try expand(program, file: file, context: context)
            guard !programText.trimmingCharacters(in: .whitespaces).isEmpty else { throw UserMenuError.emptyProgram }
            var arguments: [String] = []
            for word in words {
                if word.count == 1, case .variable(let v) = word[0], v.isList {
                    arguments += try listItems(v, context: context)
                } else {
                    arguments.append(try expand(word, file: file, context: context))
                }
            }
            let directoryText = try expand(directory, file: file, context: context)
            return UserMenuInvocation(program: programText, arguments: arguments,
                                      directory: resolveDirectory(directoryText, context: context))
        }
    }

    /// One shell command line (quoted with `ShellQuote`) that runs `invocation` in a terminal:
    /// `cd <dir> && <prog> <args>`. An `.app` bundle is started with `open`.
    public static func shellCommand(_ invocation: UserMenuInvocation) -> String {
        var parts: [String]
        if invocation.program.hasSuffix(".app") || invocation.program.hasSuffix(".app/") {
            parts = ["open", ShellQuote.quote(invocation.program)]
            if !invocation.arguments.isEmpty { parts.append("--args") }
        } else {
            parts = [ShellQuote.quote(invocation.program)]
        }
        parts += invocation.arguments.map(ShellQuote.quote)
        return "cd \(ShellQuote.quote(invocation.directory.path)) && " + parts.joined(separator: " ")
    }

    // MARK: Parsing

    private enum Variable {
        case fullName, name, namePart, extPart
        case fullPath, fullPathLeft, fullPathRight, fullPathInactive
        case fileToCompareLeft, fileToCompareRight
        case listNames, listFullNames

        static let byName: [String: Variable] = [
            "fullname": .fullName, "name": .name, "namepart": .namePart, "extpart": .extPart,
            "fullpath": .fullPath, "fullpathleft": .fullPathLeft, "fullpathright": .fullPathRight,
            "fullpathinactive": .fullPathInactive,
            "filetocompareleft": .fileToCompareLeft, "filetocompareright": .fileToCompareRight,
            "listofselectednames": .listNames, "listofselectedfullnames": .listFullNames,
        ]

        var isPerFile: Bool {
            switch self {
            case .fullName, .name, .namePart, .extPart: true
            default: false
            }
        }
        var isList: Bool { self == .listNames || self == .listFullNames }
    }

    private enum Piece {
        case literal(String)
        case variable(Variable)
        case environment(String)

        var variable: Variable? {
            if case .variable(let v) = self { v } else { nil }
        }
    }

    /// Splits `text` into literal text and variable references. `$$` and a lone `$` are literal dollars.
    private static func scan(_ text: String) throws -> [Piece] {
        var pieces: [Piece] = []
        var literal = ""
        func flush() {
            if !literal.isEmpty { pieces.append(.literal(literal)); literal = "" }
        }
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            guard c == "$" else { literal.append(c); continue }
            switch chars.first {
            case "$":
                chars.removeFirst()
                literal.append("$")
            case "(", "[":
                let open = chars.removeFirst()
                let close: Character = open == "(" ? ")" : "]"
                guard let end = chars.firstIndex(of: close) else {
                    throw UserMenuError.unknownVariable("$" + String(open) + String(chars))
                }
                let name = String(chars[chars.startIndex..<end])
                chars = chars[chars.index(after: end)...]
                flush()
                if open == "[" {
                    pieces.append(.environment(name))
                } else if let v = Variable.byName[name.trimmingCharacters(in: .whitespaces).lowercased()] {
                    pieces.append(.variable(v))
                } else {
                    throw UserMenuError.unknownVariable("$(\(name))")
                }
            default:
                literal.append("$")
            }
        }
        flush()
        return pieces
    }

    /// Words of `arguments`, each as pieces. Variables are swapped for private-use placeholder
    /// characters before `ShellWords.split` (which rejects `$`) and restored afterwards.
    private static func splitArguments(_ arguments: String, home: URL) throws -> [[Piece]] {
        var table: [Piece] = []
        var marked = ""
        func mark(_ piece: Piece) throws {
            guard table.count < 0x1800, let scalar = Unicode.Scalar(UInt32(0xE000 + table.count)) else {
                throw UserMenuError.badQuoting
            }
            table.append(piece)
            marked.unicodeScalars.append(scalar)
        }
        for piece in try scan(arguments) {
            if case .literal(let text) = piece {
                for ch in text {
                    if ch == "$" || ch.unicodeScalars.contains(where: { (0xE000...0xF8FF).contains($0.value) }) {
                        try mark(.literal(String(ch)))
                    } else {
                        marked.append(ch)
                    }
                }
            } else {
                try mark(piece)
            }
        }
        guard let words = ShellWords.split(marked, home: home) else { throw UserMenuError.badQuoting }
        return words.map { word in
            var pieces: [Piece] = []
            var literal = ""
            for ch in word {
                if ch.unicodeScalars.count == 1, let value = ch.unicodeScalars.first?.value,
                   (0xE000...0xF8FF).contains(value), Int(value) - 0xE000 < table.count {
                    let piece = table[Int(value) - 0xE000]
                    if case .literal(let text) = piece {
                        literal += text
                    } else {
                        if !literal.isEmpty { pieces.append(.literal(literal)); literal = "" }
                        pieces.append(piece)
                    }
                } else {
                    literal.append(ch)
                }
            }
            if !literal.isEmpty { pieces.append(.literal(literal)) }
            return pieces
        }
    }

    /// A leading literal `~` or `~/` becomes the home directory.
    private static func tildeExpanded(_ pieces: [Piece], home: URL) -> [Piece] {
        guard case .literal(let text)? = pieces.first, text == "~" || text.hasPrefix("~/") else { return pieces }
        var result = pieces
        result[0] = .literal(home.path + text.dropFirst())
        return result
    }

    // MARK: Expansion

    private static func expand(_ pieces: [Piece], file: URL?, context: UserMenuContext) throws -> String {
        var result = ""
        for piece in pieces {
            switch piece {
            case .literal(let text): result += text
            case .environment(let name): result += context.environment[name] ?? ""
            case .variable(let v): result += try value(of: v, file: file, context: context)
            }
        }
        return result
    }

    private static func listItems(_ v: Variable, context: UserMenuContext) throws -> [String] {
        let items = context.selected.isEmpty ? context.cursor.map { [$0] } ?? [] : context.selected
        if items.isEmpty { throw UserMenuError.noFile }
        return items.map { v == .listNames ? $0.lastPathComponent : $0.path }
    }

    private static func value(of v: Variable, file: URL?, context: UserMenuContext) throws -> String {
        switch v {
        case .fullPath: return directoryPath(context.activeDirectory)
        case .fullPathInactive: return directoryPath(context.inactiveDirectory)
        case .fullPathLeft: return directoryPath(context.leftDirectory)
        case .fullPathRight: return directoryPath(context.rightDirectory)
        case .fileToCompareLeft:
            guard let url = context.leftCursor else { throw UserMenuError.noFile }
            return url.path
        case .fileToCompareRight:
            guard let url = context.rightCursor else { throw UserMenuError.noFile }
            return url.path
        case .fullName, .name, .namePart, .extPart:
            guard let file else { throw UserMenuError.noFile }
            let name = file.lastPathComponent
            var base = name
            var ext = ""
            if let dot = name.lastIndex(of: "."), dot != name.startIndex, name.index(after: dot) != name.endIndex {
                base = String(name[..<dot])
                ext = String(name[name.index(after: dot)...])
            }
            switch v {
            case .fullName: return file.path
            case .name: return name
            case .namePart: return base
            default: return ext
            }
        case .listNames, .listFullNames:
            return try listItems(v, context: context).joined(separator: " ")
        }
    }

    /// Path without a trailing slash (except for the root).
    private static func directoryPath(_ url: URL) -> String {
        let path = url.path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    /// Absolute directory URL; a relative path is relative to the active directory. `.` and `..` are
    /// resolved textually (no file system access).
    private static func resolveDirectory(_ text: String, context: UserMenuContext) -> URL {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let full = trimmed.hasPrefix("/") ? trimmed : directoryPath(context.activeDirectory) + "/" + trimmed
        var stack: [Substring] = []
        for component in full.split(separator: "/", omittingEmptySubsequences: true) {
            if component == "." { continue }
            if component == ".." { _ = stack.popLast(); continue }
            stack.append(component)
        }
        return URL(fileURLWithPath: "/" + stack.joined(separator: "/"), isDirectory: true)
    }
}

/// JSON persistence of the user menu and the example items shown on first use.
public enum UserMenuStore {
    public static func encode(_ items: [UserMenuItem]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(items)
    }

    public static func decode(_ data: Data) throws -> [UserMenuItem] {
        try JSONDecoder().decode([UserMenuItem].self, from: data)
    }

    /// Every command item of the tree, depth first in menu order (submenus included).
    public static func commands(in items: [UserMenuItem]) -> [UserMenuItem] {
        items.flatMap { item -> [UserMenuItem] in
            switch item.kind {
            case .command: [item]
            case .submenu: commands(in: item.children)
            case .separator: []
            }
        }
    }

    /// The command item whose shortcut is `chord`; the first one in menu order wins.
    public static func command(for chord: KeyChord, in items: [UserMenuItem]) -> UserMenuItem? {
        commands(in: items).first { $0.shortcut == chord }
    }

    /// Whether `chord` can be a user menu shortcut: a character key needs ⌘, ⌃ or ⌥, because
    /// plain (and shifted) typing in a panel is quick search.
    public static func isAssignable(_ chord: KeyChord) -> Bool {
        if case .character = chord.key {
            return !chord.modifiers.isDisjoint(with: [.command, .control, .option])
        }
        return true
    }

    /// Harmless starter items.
    public static let examples: [UserMenuItem] = [
        UserMenuItem(title: "Open in TextEdit", program: "/usr/bin/open",
                     arguments: "-a TextEdit $(ListOfSelectedFullNames)"),
        UserMenuItem(title: "Show disk usage here", program: "du", arguments: "-sh $(FullName)",
                     runInTerminal: true),
        UserMenuItem(kind: .submenu, title: "Git", children: [
            UserMenuItem(title: "Status", program: "git", arguments: "status", runInTerminal: true),
            UserMenuItem(title: "Log", program: "git", arguments: "log --oneline -20", runInTerminal: true),
        ]),
    ]
}
