// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import UniformTypeIdentifiers

/// Export Settings… and Import Settings…: the whole setup in one JSON file
/// (`specs/010-keyboard-schemes/contracts/keyboard-ui.md`).
enum SettingsTransfer {
    static let toolbarKey = SettingsCatalog.toolbarKey

    /// Everything that is exported and may be imported (`SettingsCatalog.app` in the core, where tests
    /// guard it).
    static let catalog = SettingsCatalog.app

    /// Import replaces settings live; not while a main window shows a sheet.
    static var canImport: Bool {
        !NSApp.windows.contains { $0.windowController is MainWindowController && $0.attachedSheet != nil }
    }

    // MARK: Export

    static func export(from window: NSWindow?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Axolotl Commander Settings.json"
        run(panel, on: window) {
            guard let url = panel.url else { return }
            do {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
                let data = try SettingsArchive.export(from: .standard, catalog: catalog, appVersion: version)
                try data.write(to: url, options: .atomic)
            } catch {
                show(message: String(localized: "The settings could not be exported."),
                     info: error.localizedDescription, on: window)
            }
        }
    }

    // MARK: Import

    static func importSettings(from window: NSWindow?) {
        guard canImport else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        run(panel, on: window) {
            guard let url = panel.url else { return }
            let contents: SettingsContents
            do {
                contents = try SettingsArchive.read(Data(contentsOf: url))
            } catch {
                show(message: String(localized: "This file is not an Axolotl Commander settings file."),
                     info: url.lastPathComponent, on: window)
                return
            }
            // Let the open panel's sheet close before the next one.
            DispatchQueue.main.async { confirm(contents, on: window) }
        }
    }

    private static func confirm(_ contents: SettingsContents, on window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Import settings?")
        var info = String(localized: "The checked parts replace your current settings.")
        if contents.isNewer {
            info += "\n" + String(localized: "The file comes from a newer version; parts this version does not know are skipped.")
        }
        alert.informativeText = info
        let importButton = alert.addButton(withTitle: String(localized: "Import"))
        alert.addButton(withTitle: String(localized: "Cancel"))

        let sections = contents.availableSections
        let boxes = sections.map { NSButton(checkboxWithTitle: title(of: $0), target: nil, action: nil) }
        let toggler = CheckboxWatcher(boxes: boxes, button: importButton)
        for box in boxes {
            box.state = .on
            box.target = toggler
            box.action = #selector(CheckboxWatcher.changed)
        }
        let stack = NSStackView(views: boxes)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setFrameSize(stack.fittingSize)
        alert.accessoryView = stack

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            withExtendedLifetime(toggler) {}
            guard response == .alertFirstButtonReturn else { return }
            let chosen = Set(zip(sections, boxes).filter { $0.1.state == .on }.map(\.0))
            let report = SettingsArchive.apply(contents, sections: chosen, to: .standard, catalog: catalog)
            reloadAfterImport(report.applied)
            DispatchQueue.main.async { summarize(report, on: window) }
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: finish) } else { finish(alert.runModal()) }
    }

    /// Enables Import only while at least one part is checked.
    private final class CheckboxWatcher: NSObject {
        let boxes: [NSButton]
        let button: NSButton
        init(boxes: [NSButton], button: NSButton) {
            self.boxes = boxes
            self.button = button
        }
        @objc func changed() { button.isEnabled = boxes.contains { $0.state == .on } }
    }

    /// Caches and windows pick up what the import wrote; plain preferences update through
    /// `@AppStorage` and the UserDefaults observers on their own.
    private static func reloadAfterImport(_ sections: [SettingsSection]) {
        for section in sections {
            switch section {
            case .keyboard: KeyMaps.reload()
            case .appearance, .hotPaths, .connections, .preferences: AppSettings.shared.reload()
            case .userMenu: UserMenuDefaults.reload()
            case .toolbar:
                guard let configuration = UserDefaults.standard.dictionary(forKey: toolbarKey) else { break }
                for window in NSApp.windows where window.windowController is MainWindowController {
                    if let toolbar = window.toolbar { MainToolbar.apply(configuration, to: toolbar) }
                }
            }
        }
    }

    private static func summarize(_ report: ImportReport, on window: NSWindow?) {
        var lines: [String] = []
        if report.newerFormat {
            lines.append(String(localized: "The file comes from a newer version; parts this version does not know are skipped."))
        }
        if !report.skipped.isEmpty {
            lines.append(String(localized: "Skipped:"))
            lines += report.skipped.map { "• \(sectionName($0.section)): \($0.item) – \(reasonText($0.reason))" }
        }
        let text = lines.joined(separator: "\n")
        // A long list scrolls instead of growing the alert past the screen.
        guard lines.count > 12 else {
            show(message: String(localized: "Settings imported."), info: text, on: window)
            return
        }
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 420, height: 220)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        if let view = scroll.documentView as? NSTextView {
            view.isEditable = false
            view.string = text
            view.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        }
        show(message: String(localized: "Settings imported."), info: "", accessory: scroll, on: window)
    }

    // MARK: Texts

    static func title(of section: SettingsSection) -> String {
        switch section {
        case .keyboard: String(localized: "Keyboard")
        case .preferences: String(localized: "Preferences")
        case .appearance: String(localized: "Appearance")
        case .hotPaths: String(localized: "Hot Paths")
        case .userMenu: String(localized: "User Menu")
        case .connections: String(localized: "Saved Servers")
        case .toolbar: String(localized: "Toolbar")
        }
    }

    private static func sectionName(_ name: String) -> String {
        SettingsSection(rawValue: name).map(title(of:)) ?? name
    }

    private static func reasonText(_ reason: SkipReason) -> String {
        switch reason {
        case .unknownSection: String(localized: "unknown part")
        case .unknownKey: String(localized: "unknown setting")
        case .unknownCommand: String(localized: "unknown command")
        case .malformedChord: String(localized: "invalid shortcut")
        case .wrongType: String(localized: "wrong kind of value")
        case .outOfRange: String(localized: "value out of range")
        case .unknownScheme: String(localized: "unknown key scheme")
        case .invalidEntry: String(localized: "invalid entry")
        }
    }

    // MARK: Helpers

    private static func run(_ panel: NSSavePanel, on window: NSWindow?, then done: @escaping () -> Void) {
        if let window {
            panel.beginSheetModal(for: window) { if $0 == .OK { done() } }
        } else if panel.runModal() == .OK {
            done()
        }
    }

    private static func show(message: String, info: String, accessory: NSView? = nil, on window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.accessoryView = accessory
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}
