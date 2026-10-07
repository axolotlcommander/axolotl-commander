import AppKit
import CommanderCore

/// Hands work to other apps: the terminal for the command line and ⌃/, Finder for ⇧F3.
enum Launcher {
    struct Terminal: Identifiable, Hashable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    static let terminalDefaultsKey = "terminal.bundleID"

    private static let knownTerminals = [
        Terminal(bundleID: "com.apple.Terminal", name: "Terminal"),
        Terminal(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        Terminal(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        Terminal(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
        Terminal(bundleID: "net.kovidgoyal.kitty", name: "kitty"),
        Terminal(bundleID: "org.alacritty", name: "Alacritty"),
        Terminal(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
    ]

    /// Terminals that are installed, Terminal.app first.
    static var installedTerminals: [Terminal] {
        knownTerminals.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    private static var terminalURL: URL? {
        let chosen = UserDefaults.standard.string(forKey: terminalDefaultsKey) ?? "com.apple.Terminal"
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: chosen)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
    }

    enum Failure: LocalizedError {
        case noTerminal
        var errorDescription: String? { "No terminal application was found." }
    }

    /// New terminal window in `directory`.
    static func openTerminal(at directory: URL) async throws {
        guard let app = terminalURL else { throw Failure.noTerminal }
        _ = try await NSWorkspace.shared.open([directory], withApplicationAt: app, configuration: .init())
    }

    /// Runs `command` in a new terminal window via a self-deleting `.command` script
    /// in the app's own temporary folder; the window stays open with a prompt.
    static func run(_ command: String, in directory: URL) async throws {
        guard let app = terminalURL else { throw Failure.noTerminal }
        let folder = FileManager.default.temporaryDirectory.appending(path: "iCommander", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appending(path: "command-\(UUID().uuidString).command")
        try TerminalScript.contents(command: command, directory: directory)
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        _ = try await NSWorkspace.shared.open([script], withApplicationAt: app, configuration: .init())
    }

    /// Finder window with `urls` selected, or showing `directory` when nothing is selected.
    static func revealInFinder(_ urls: [URL], directory: URL) {
        if urls.isEmpty {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path(percentEncoded: false))
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}
