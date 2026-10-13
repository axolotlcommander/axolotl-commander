// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Hands work to other apps: the terminal for the command line and ⌃/, Finder for ⇧F3.
enum Launcher {
    /// An app the user can pick in Settings (terminal or editor).
    struct AppChoice: Identifiable, Hashable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    static let terminalDefaultsKey = "terminal.bundleID"

    private static let knownTerminals = [
        AppChoice(bundleID: "com.apple.Terminal", name: "Terminal"),
        AppChoice(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
        AppChoice(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
        AppChoice(bundleID: "com.github.wez.wezterm", name: "WezTerm"),
        AppChoice(bundleID: "net.kovidgoyal.kitty", name: "kitty"),
        AppChoice(bundleID: "org.alacritty", name: "Alacritty"),
        AppChoice(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
    ]

    /// Terminals that are installed, Terminal.app first.
    static var installedTerminals: [AppChoice] {
        knownTerminals.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    private static var terminalURL: URL? {
        let chosen = UserDefaults.standard.string(forKey: terminalDefaultsKey) ?? "com.apple.Terminal"
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: chosen)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
    }

    enum Failure: LocalizedError {
        case noTerminal
        /// The editor chosen in Settings is not installed (its name or bundle id).
        case editorMissing(String)
        var errorDescription: String? {
            switch self {
            case .noTerminal: String(localized: "No terminal application was found.")
            case .editorMissing(let name):
                String(localized: "The editor “\(name)” chosen in Settings is not installed. Choose another one in Settings → Viewer & Editor.")
            }
        }
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
        let folder = FileManager.default.temporaryDirectory.appending(path: "Axolotl Commander", directoryHint: .isDirectory)
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

    // MARK: Editor (F4)

    static let editorDefaultsKey = "editor.bundleID"
    /// Editor setting meaning "the app the system opens this file type with".
    static let systemDefaultEditor = EditorChoice.systemDefaultTag

    private static let knownEditors = [
        AppChoice(bundleID: "com.apple.TextEdit", name: "TextEdit"),
        AppChoice(bundleID: "com.coteditor.CotEditor", name: "CotEditor"),
        AppChoice(bundleID: "com.barebones.bbedit", name: "BBEdit"),
        AppChoice(bundleID: "com.sublimetext.4", name: "Sublime Text"),
        AppChoice(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
        AppChoice(bundleID: "dev.zed.Zed", name: "Zed"),
        AppChoice(bundleID: "com.panic.Nova", name: "Nova"),
        AppChoice(bundleID: "com.macromates.TextMate", name: "TextMate"),
        AppChoice(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
    ]

    /// Editors that are installed, TextEdit first.
    static var installedEditors: [AppChoice] {
        knownEditors.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
    }

    /// Opens `url` in the editor chosen in Settings (TextEdit by default).
    static func edit(_ url: URL) async throws {
        let choice = EditorChoice.resolve(chosen: UserDefaults.standard.string(forKey: editorDefaultsKey)) {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
        let configuration = NSWorkspace.OpenConfiguration()
        switch choice {
        case .systemDefault:
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
        case .missing(let bundleID):
            throw Failure.editorMissing(knownEditors.first { $0.bundleID == bundleID }?.name ?? bundleID)
        case .app(let bundleID):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                throw Failure.editorMissing(bundleID)
            }
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration)
        }
    }
}
