import AppKit
import CommanderCore

/// Stored user menu items (Settings → User Menu).
enum UserMenuDefaults {
    static let key = "userMenu.items"
    static let didChange = Notification.Name("UserMenuDidChange")

    static var items: [UserMenuItem] {
        get { UserDefaults.standard.data(forKey: key).flatMap { try? UserMenuStore.decode($0) } ?? [] }
        set {
            UserDefaults.standard.set(try? UserMenuStore.encode(newValue), forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

/// F9: the user menu as a pop-up menu at the panel cursor; the chosen item runs with the panel's
/// files filled into its variables.
enum UserMenuPresenter {
    private final class Target: NSObject {
        weak var panel: PanelViewController?
        init(panel: PanelViewController) { self.panel = panel }

        @objc func run(_ sender: NSMenuItem) {
            guard let item = sender.representedObject as? UserMenuItemBox, let panel else { return }
            UserMenuPresenter.run(item.item, from: panel)
        }

        @objc func configure(_ sender: Any?) {
            (NSApp.delegate as? AppDelegate)?.showSettings(tab: .userMenu)
        }
    }

    /// NSMenuItem.representedObject must be an object.
    private final class UserMenuItemBox: NSObject {
        let item: UserMenuItem
        init(_ item: UserMenuItem) { self.item = item }
    }

    private static var target: Target?

    static func show(for panel: PanelViewController) {
        let target = Target(panel: panel)
        Self.target = target
        let menu = NSMenu(title: String(localized: "User Menu"))
        menu.autoenablesItems = false
        add(UserMenuDefaults.items, to: menu, target: target)
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let configure = NSMenuItem(title: String(localized: "Edit User Menu…"), action: #selector(Target.configure(_:)), keyEquivalent: "")
        configure.target = target
        menu.addItem(configure)

        let view = panel.listView
        var point = NSPoint(x: 20, y: 20)
        if let table = view as? NSTableView, panel.model.cursor >= 0, panel.model.cursor < table.numberOfRows {
            let row = table.rect(ofRow: panel.model.cursor)
            point = NSPoint(x: row.minX + 30, y: row.maxY)
        } else {
            point = NSPoint(x: view.visibleRect.minX + 30, y: view.visibleRect.minY + 30)
        }
        menu.popUp(positioning: menu.items.first, at: point, in: view)
    }

    private static func add(_ items: [UserMenuItem], to menu: NSMenu, target: Target) {
        for item in items {
            switch item.kind {
            case .separator:
                menu.addItem(.separator())
            case .submenu:
                let holder = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                let submenu = NSMenu(title: item.title)
                submenu.autoenablesItems = false
                add(item.children, to: submenu, target: target)
                holder.submenu = submenu
                menu.addItem(holder)
            case .command:
                let entry = NSMenuItem(title: item.title.isEmpty ? item.program : item.title,
                                       action: #selector(Target.run(_:)), keyEquivalent: "")
                entry.target = target
                entry.representedObject = UserMenuItemBox(item)
                entry.toolTip = ([item.program] + (item.arguments.isEmpty ? [] : [item.arguments])).joined(separator: " ")
                if item.runInTerminal { entry.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) }
                menu.addItem(entry)
            }
        }
    }

    // MARK: Running

    static func context(for panel: PanelViewController) -> UserMenuContext? {
        guard let router = panel.router else { return nil }
        let other = router.otherPanel(than: panel)
        func cursor(_ panel: PanelViewController) -> URL? {
            panel.model.cursorItem.flatMap { $0.isParent ? nil : $0.url }
        }
        return UserMenuContext(
            activeDirectory: panel.diskFolder, inactiveDirectory: other.diskFolder,
            leftDirectory: router.left.diskFolder, rightDirectory: router.right.diskFolder,
            cursor: cursor(panel), selected: panel.model.items.filter { panel.model.isSelected($0) }.map(\.url),
            leftCursor: cursor(router.left), rightCursor: cursor(router.right),
            environment: ProcessInfo.processInfo.environment,
            home: FileManager.default.homeDirectoryForCurrentUser)
    }

    static func run(_ item: UserMenuItem, from panel: PanelViewController) {
        guard let context = context(for: panel) else { return }
        let invocations: [UserMenuInvocation]
        do {
            invocations = try UserMenuExpander.invocations(for: item, in: context)
        } catch let error as UserMenuError {
            report(String(localized: "“\(item.title)” can’t run."), describe(error), in: panel)
            return
        } catch {
            report(String(localized: "“\(item.title)” can’t run."), Format.error(error), in: panel)
            return
        }
        Task {
            for invocation in invocations {
                do {
                    if item.runInTerminal {
                        try await Launcher.run(UserMenuExpander.shellCommand(invocation), in: invocation.directory)
                    } else {
                        try await launch(invocation)
                    }
                } catch {
                    report(String(localized: "“\(item.title)” failed."), Format.error(error), in: panel)
                    return
                }
            }
        }
    }

    static func describe(_ error: UserMenuError) -> String {
        switch error {
        case .unknownVariable(let name): String(localized: "Unknown variable \(name).")
        case .noFile: String(localized: "The command needs a file: put the cursor on one or select some.")
        case .emptyProgram: String(localized: "No program is set.")
        case .badQuoting: String(localized: "The arguments have an unbalanced quote or an unquoted special character (; | & * ? …).")
        case .notADirectory(let text): String(localized: "“\(text)” can’t be used as the initial folder.")
        }
    }

    private enum LaunchError: LocalizedError {
        case notFound(String), failed(String, Int32, String)

        var errorDescription: String? {
            switch self {
            case .notFound(let program): String(localized: "The program “\(program)” was not found.")
            case .failed(let program, let status, let output):
                String(localized: "“\(program)” ended with status \(status).") + (output.isEmpty ? "" : "\n\n" + output)
            }
        }
    }

    /// Folders searched for a bare program name; apps started from the Dock get only the system ones.
    private static let searchPath = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]

    /// Starts the program directly (no shell): an app bundle via Launch Services, anything else as
    /// a process whose error output is shown when it fails.
    private static func launch(_ invocation: UserMenuInvocation) async throws {
        let program = invocation.program
        if program.hasSuffix(".app") {
            let app = URL(fileURLWithPath: program, relativeTo: invocation.directory)
            let files = invocation.arguments.map { URL(fileURLWithPath: $0, relativeTo: invocation.directory) }
            let configuration = NSWorkspace.OpenConfiguration()
            if !files.isEmpty, files.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
                _ = try await NSWorkspace.shared.open(files, withApplicationAt: app, configuration: configuration)
            } else {
                configuration.arguments = invocation.arguments
                _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
            }
            return
        }
        let executable: URL
        if program.contains("/") {
            executable = URL(fileURLWithPath: program, relativeTo: invocation.directory)
        } else {
            let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init) + searchPath
            guard let found = path.lazy.map({ URL(fileURLWithPath: $0).appending(path: program) })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
                throw LaunchError.notFound(program)
            }
            executable = found
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw LaunchError.notFound(program) }
        let process = Process()
        process.executableURL = executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = invocation.directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status != 0 else { return }
        let data = (try? errors.fileHandleForReading.readToEnd()) ?? Data()
        let output = String(decoding: data.suffix(2000), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        throw LaunchError.failed(program, status, output)
    }

    private static func report(_ title: String, _ text: String, in panel: PanelViewController) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        if let window = panel.view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
