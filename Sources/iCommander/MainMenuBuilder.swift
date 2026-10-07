import AppKit
import CommanderCore

extension NSMenuItem {
    var command: Command? { (representedObject as? String).flatMap(Command.init(rawValue:)) }
}

/// Builds the menu bar from `CommandRegistry`. Every item is nil-targeted, so
/// the responder chain decides who performs and validates it. The menus swap
/// between panel and viewer items as the key window changes.
enum MainMenuBuilder {
    /// Commands bound to standard AppKit selectors so text fields keep native behavior.
    static let standardSelectors: [Command: Selector] = [
        .copyFiles: #selector(NSText.copy(_:)),
        .pasteFiles: #selector(NSText.paste(_:)),
        .selectAll: #selector(NSText.selectAll(_:)),
        .viewerCopy: #selector(NSText.copy(_:)),
        .viewerSelectAll: #selector(NSText.selectAll(_:)),
        .findCopyFiles: #selector(NSText.copy(_:)),
        .findSelectAll: #selector(NSText.selectAll(_:)),
    ]

    /// Menus whose items depend on the context; the rest hold app-scope items only.
    private static let contextMenus: Set<MenuID> = [.file, .edit, .view, .go, .left, .right, .commands, .options]
    private static var holders: [MenuID: NSMenuItem] = [:]
    private static var context: CommandContext = .panel
    private static var observer: (any NSObjectProtocol)?

    /// Keeps the menu bar in step with the key window.
    static func trackKeyWindow() {
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                          object: nil, queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                // Sheets and panels keep the context of the window they belong to.
                guard let window, window.sheetParent == nil, !(window is NSPanel) else { return }
                switch window.windowController {
                case is ViewerWindowController: update(.viewer)
                case is FindWindowController: update(.find)
                case is MainWindowController: update(.panel)
                default: break
                }
            }
        }
    }

    static func update(_ newContext: CommandContext) {
        guard newContext != context else { return }
        context = newContext
        for id in contextMenus {
            guard let holder = holders[id], let menu = holder.submenu else { continue }
            populate(menu, id)
            holder.isHidden = menu.items.isEmpty
        }
    }

    private static func populate(_ menu: NSMenu, _ id: MenuID) {
        menu.removeAllItems()
        for spec in CommandRegistry.items(in: id, context: context) {
            if spec.separatorBefore, !menu.items.isEmpty { menu.addItem(.separator()) }
            menu.addItem(spec.command == .viewerEncoding ? encodingItem(spec) : item(for: spec))
        }
    }

    /// View → Text Encoding: automatic detection, every encoding, set as default.
    private static func encodingItem(_ spec: CommandSpec) -> NSMenuItem {
        let holder = NSMenuItem(title: spec.localizedTitle, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: holder.title)
        menu.addItem(item(for: CommandRegistry.spec(.viewerAutoEncoding)))
        menu.addItem(.separator())
        for (index, encoding) in TextEncoding.allCases.enumerated() {
            let item = NSMenuItem(title: encoding.title, action: #selector(ViewerWindowController.selectEncoding(_:)),
                                  keyEquivalent: "")
            item.tag = index
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(item(for: CommandRegistry.spec(.viewerSetDefaultEncoding)))
        holder.submenu = menu
        return holder
    }

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
            populate(menu, id)
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
            holders[id] = holder
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
