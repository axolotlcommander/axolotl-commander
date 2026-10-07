import AppKit
import CommanderCore

/// The key maps in use: factory chords with the user's changes (Settings → Keyboard).
enum KeyMaps {
    static let defaultsKey = "keys.bindings"
    static let didChange = Notification.Name("KeyBindingsDidChange")

    private(set) static var bindings: KeyBindings = UserDefaults.standard.data(forKey: defaultsKey)
        .flatMap { try? JSONDecoder().decode(KeyBindings.self, from: $0) } ?? .factory
    private(set) static var panel = KeyMap(context: .panel, bindings: bindings)
    private(set) static var viewer = KeyMap(context: .viewer, bindings: bindings)
    private(set) static var find = KeyMap(context: .find, bindings: bindings)
    private(set) static var compare = KeyMap(context: .compare, bindings: bindings)

    static func map(for context: CommandContext) -> KeyMap {
        switch context {
        case .panel: panel
        case .viewer: viewer
        case .find: find
        case .compare: compare
        }
    }

    /// Stores new bindings and updates the maps and the menu bar.
    static func update(_ new: KeyBindings) {
        guard new != bindings else { return }
        bindings = new
        if new == .factory {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(try? JSONEncoder().encode(new), forKey: defaultsKey)
        }
        panel = KeyMap(context: .panel, bindings: new)
        viewer = KeyMap(context: .viewer, bindings: new)
        find = KeyMap(context: .find, bindings: new)
        compare = KeyMap(context: .compare, bindings: new)
        MainMenuBuilder.refreshKeyEquivalents()
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// The chord a menu item shows for `command`: its first menu-safe effective chord.
    static func menuChord(for command: Command, in context: CommandContext) -> KeyChord? {
        map(for: context).chords(for: command).first(where: \.isMenuSafe)
    }

    /// The menu bar already answers `chord` for `command` (its item shows that chord), so a window's
    /// own key handling must leave it alone. Further chords of the command (F2 next to ⌃W…) are not.
    static func menuHandles(_ chord: KeyChord, for command: Command, in context: CommandContext) -> Bool {
        CommandRegistry.spec(command).menu != nil && menuChord(for: command, in: context) == chord
    }
}
