import AppKit
import CommanderCore

extension NSMenuItem {
    var command: Command? { (representedObject as? String).flatMap(Command.init(rawValue:)) }
}

/// Builds the menu bar from `CommandRegistry`. Every item is nil-targeted, so
/// the responder chain decides who performs and validates it.
enum MainMenuBuilder {
    /// Commands bound to standard AppKit selectors so text fields keep native behavior.
    static let standardSelectors: [Command: Selector] = [
        .copyFiles: #selector(NSText.copy(_:)),
        .pasteFiles: #selector(NSText.paste(_:)),
        .selectAll: #selector(NSText.selectAll(_:)),
    ]

    static func build() -> NSMenu {
        let bar = NSMenu()
        let titles: [MenuID: String] = [
            .app: "iCommander", .file: String(localized: "File"), .edit: String(localized: "Edit Menu"),
            .view: String(localized: "View Menu"), .go: String(localized: "Go"),
            .left: String(localized: "Left"), .right: String(localized: "Right"),
            .commands: String(localized: "Commands"), .options: String(localized: "Options"),
            .window: String(localized: "Window"), .help: String(localized: "Help"),
        ]
        for id in MenuID.allCases {
            let menu = NSMenu(title: titles[id]!)
            for spec in CommandRegistry.items(in: id) {
                if spec.separatorBefore, !menu.items.isEmpty { menu.addItem(.separator()) }
                menu.addItem(item(for: spec))
            }
            switch id {
            case .app:
                menu.insertItem(.separator(), at: 2)
                menu.insertItem(withTitle: String(localized: "Hide iCommander"), action: #selector(NSApplication.hide(_:)),
                                keyEquivalent: "h", at: 3)
                menu.insertItem(withTitle: String(localized: "Show All"), action: #selector(NSApplication.unhideAllApplications(_:)),
                                keyEquivalent: "", at: 4)
            case .window:
                menu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
                menu.addItem(withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
                menu.addItem(withTitle: String(localized: "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
                NSApp.windowsMenu = menu
            case .help:
                NSApp.helpMenu = menu
            default: break
            }
            let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            bar.addItem(holder)
        }
        return bar
    }

    private static func item(for spec: CommandSpec) -> NSMenuItem {
        let action = standardSelectors[spec.command] ?? #selector(AppDelegate.performCommand(_:))
        let item = NSMenuItem(title: spec.localizedTitle, action: action, keyEquivalent: "")
        item.representedObject = spec.command.rawValue
        if let chord = spec.chords.first(where: \.isMenuSafe), let (key, mask) = chord.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = mask
        }
        return item
    }
}
