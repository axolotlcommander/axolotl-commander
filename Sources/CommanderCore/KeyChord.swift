/// A key plus modifiers, independent of AppKit so the key map is testable.
public struct KeyChord: Hashable, CustomStringConvertible, Sendable {
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
