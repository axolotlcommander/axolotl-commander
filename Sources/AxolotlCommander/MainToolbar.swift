// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// One toolbar with commands that already exist; every button runs a registry command,
/// so it is enabled exactly when the menu item is.
enum MainToolbar {
    /// The default set in named groups, so adding a button does not shift the others.
    static let navigationGroup: [Command] = [.goBack, .goForward, .goParent, .goHome]
    static let viewGroup: [Command] = [.refresh, .toggleHidden]
    static let fileToolsGroup: [Command] = [.quickLook, .properties, .makeDirectory, .openTerminal, .revealInFinder]
    static let windowLayoutGroup: [Command] = [.comparePanels, .maximizePanel]

    static var defaultItems: [Command] { navigationGroup + viewGroup + fileToolsGroup + windowLayoutGroup }

    static let symbols: [Command: String] = [
        .goBack: "chevron.left", .goForward: "chevron.right", .goParent: "arrow.turn.left.up",
        .goHome: "house", .goRoot: "externaldrive", .refresh: "arrow.clockwise", .toggleHidden: "eye",
        .quickLook: "eye.square", .properties: "info.circle", .makeDirectory: "folder.badge.plus",
        .openTerminal: "terminal", .revealInFinder: "macwindow", .comparePanels: "rectangle.split.2x1",
        .maximizePanel: "arrow.up.left.and.arrow.down.right", .calculateSizes: "sum",
        .find: "magnifyingglass", .hotPaths: "star", .newTab: "plus.square.on.square",
        .filter: "line.3.horizontal.decrease.circle", .changeDirectory: "arrow.right.circle",
        .copy: "doc.on.doc", .move: "arrow.right.doc.on.clipboard", .delete: "trash",
        .connectToServer: "network", .disconnect: "eject",
    ]

    static func make(delegate: any NSToolbarDelegate) -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        return toolbar
    }

    static func identifier(_ command: Command) -> NSToolbarItem.Identifier { .init("cmd." + command.rawValue) }

    static func command(_ identifier: NSToolbarItem.Identifier) -> Command? {
        guard identifier.rawValue.hasPrefix("cmd.") else { return nil }
        return Command(rawValue: String(identifier.rawValue.dropFirst(4)))
    }
}

extension MainWindowController: NSToolbarDelegate, NSToolbarItemValidation {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        func ids(_ group: [Command]) -> [NSToolbarItem.Identifier] { group.map(MainToolbar.identifier) }
        // Navigation and view | file tools, with a flexible space before the window-layout buttons.
        return ids(MainToolbar.navigationGroup) + ids(MainToolbar.viewGroup) + [.space]
            + ids(MainToolbar.fileToolsGroup) + [.flexibleSpace] + ids(MainToolbar.windowLayoutGroup)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        MainToolbar.symbols.keys.sorted { $0.rawValue < $1.rawValue }.map(MainToolbar.identifier)
            + [.space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let command = MainToolbar.command(itemIdentifier) else { return nil }
        let spec = CommandRegistry.spec(command)
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        let title = spec.localizedTitle.replacingOccurrences(of: "…", with: "")
        item.label = title
        item.paletteLabel = title
        let shortcut = KeyMaps.panel.chords(for: command).first.map { " (\($0.description))" } ?? ""
        item.toolTip = title + shortcut
        item.image = NSImage(systemSymbolName: MainToolbar.symbols[command] ?? "questionmark",
                             accessibilityDescription: title)
        item.isBordered = true
        item.target = self
        item.action = #selector(toolbarCommand(_:))
        return item
    }

    @objc func toolbarCommand(_ sender: NSToolbarItem) {
        guard let command = MainToolbar.command(sender.itemIdentifier) else { return }
        // Panel commands need the panel focused; a click while a text field edits returns focus first.
        if !panelHasFocus { activate(activeSide) }
        perform(command)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard let command = MainToolbar.command(item.itemIdentifier) else { return false }
        if command == .maximizePanel {
            item.image = NSImage(systemSymbolName: maximizedSide == nil ? "arrow.up.left.and.arrow.down.right"
                                                                          : "arrow.down.right.and.arrow.up.left",
                                 accessibilityDescription: item.label)
        }
        if command == .toggleHidden {
            item.image = NSImage(systemSymbolName: activePanel.showsHidden ? "eye.fill" : "eye",
                                 accessibilityDescription: item.label)
        }
        // Panel commands are only available with a panel focused; the button activates it first.
        return CommandRegistry.spec(command).scope == .app || canPerformIgnoringFocus(command)
    }
}
