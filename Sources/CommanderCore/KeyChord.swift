/// A key plus modifiers, independent of AppKit so the key map is testable.
public struct KeyChord: Hashable, CustomStringConvertible, Sendable, Codable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option  = Modifiers(rawValue: 1 << 1)
        public static let shift   = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public enum Key: Hashable, Sendable {
        case function(Int)          // F1…F20
        case character(Character)   // lowercased printable character
        case tab, enter, space, escape
        case backspace              // Mac "delete" key
        case forwardDelete          // Mac fn+delete, Windows Delete
        case insert                 // Help/Insert on full keyboards
        case up, down, left, right, home, end, pageUp, pageDown
        case numPlus, numMinus, numStar, numSlash, numEnter
    }

    public var key: Key
    public var modifiers: Modifiers

    public init(_ key: Key, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Chords safe to register as NSMenu key equivalents: they never collide
    /// with plain typing or text-field editing.
    public var isMenuSafe: Bool {
        if case .function = key { return true }
        return !modifiers.intersection([.control, .command, .option]).isEmpty
    }

    public var description: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        switch key {
        case .function(let n): s += "F\(n)"
        case .character(let c): s += String(c).uppercased()
        case .tab: s += "⇥"
        case .enter: s += "↩"
        case .space: s += "Space"
        case .escape: s += "⎋"
        case .backspace: s += "⌫"
        case .forwardDelete: s += "⌦"
        case .insert: s += "Ins"
        case .up: s += "↑"
        case .down: s += "↓"
        case .left: s += "←"
        case .right: s += "→"
        case .home: s += "↖"
        case .end: s += "↘"
        case .pageUp: s += "⇞"
        case .pageDown: s += "⇟"
        case .numPlus: s += "Num+"
        case .numMinus: s += "Num−"
        case .numStar: s += "Num*"
        case .numSlash: s += "Num/"
        case .numEnter: s += "Num↩"
        }
        return s
    }
}

// MARK: - Stable string form

extension KeyChord {
    private static let modifierNames: [(Modifiers, String)] = [
        (.control, "ctrl"), (.option, "opt"), (.shift, "shift"), (.command, "cmd"),
    ]
    private static let keyNames: [(Key, String)] = [
        (.tab, "tab"), (.enter, "enter"), (.space, "space"), (.escape, "escape"),
        (.backspace, "backspace"), (.forwardDelete, "forwardDelete"), (.insert, "insert"),
        (.up, "up"), (.down, "down"), (.left, "left"), (.right, "right"),
        (.home, "home"), (.end, "end"), (.pageUp, "pageUp"), (.pageDown, "pageDown"),
        (.numPlus, "numPlus"), (.numMinus, "numMinus"), (.numStar, "numStar"),
        (.numSlash, "numSlash"), (.numEnter, "numEnter"),
    ]

    /// Lossless, readable text form: modifiers in the order `ctrl+opt+shift+cmd+` followed by the key,
    /// e.g. `cmd+shift+F5`, `tab`, `numPlus`, `ctrl+opt+char:a`. A character key is `char:` plus the
    /// character itself (so `char:+` and `char:` followed by a colon round-trip); whitespace and
    /// control characters are written as `char:U+0020` (several scalars joined by `-`).
    public var storageString: String {
        var s = ""
        for (modifier, name) in Self.modifierNames where modifiers.contains(modifier) { s += name + "+" }
        switch key {
        case .function(let n): s += "F\(n)"
        case .character(let c):
            let plain = c.unicodeScalars.allSatisfy {
                !$0.properties.isWhitespace && $0.properties.generalCategory != .control
                    && $0.properties.generalCategory != .format
            }
            if plain {
                s += "char:" + String(c)
            } else {
                s += "char:U+" + c.unicodeScalars.map { hex4($0.value) }.joined(separator: "-")
            }
        default:
            s += Self.keyNames.first { $0.0 == key }?.1 ?? ""
        }
        return s
    }

    /// Parses `storageString`; nil for anything malformed.
    public init?(storageString: String) {
        var rest = Substring(storageString)
        var mods: Modifiers = []
        scan: while true {
            for (modifier, name) in Self.modifierNames where rest.hasPrefix(name + "+") {
                mods.insert(modifier)
                rest = rest.dropFirst(name.count + 1)
                continue scan
            }
            break
        }
        if rest.hasPrefix("char:") {
            let body = rest.dropFirst(5)
            if body.count == 1, let c = body.first {
                self.init(.character(c), mods)
            } else if body.hasPrefix("U+") {
                var text = ""
                for part in body.dropFirst(2).split(separator: "-", omittingEmptySubsequences: false) {
                    guard let value = UInt32(part, radix: 16), let scalar = Unicode.Scalar(value) else { return nil }
                    text.unicodeScalars.append(scalar)
                }
                guard text.count == 1, let c = text.first else { return nil }
                self.init(.character(c), mods)
            } else {
                return nil
            }
        } else if rest.hasPrefix("F"), let n = Int(rest.dropFirst()), n > 0, rest.dropFirst().allSatisfy(\.isWholeNumber) {
            self.init(.function(n), mods)
        } else if let key = Self.keyNames.first(where: { $0.1 == rest })?.0 {
            self.init(key, mods)
        } else {
            return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let chord = KeyChord(storageString: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid key chord \"\(text)\"")
        }
        self = chord
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageString)
    }
}

private func hex4(_ value: UInt32) -> String {
    let digits = String(value, radix: 16, uppercase: true)
    return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
}
