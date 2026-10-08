// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import AppKit
import CommanderCore
import UniformTypeIdentifiers

/// Right click or ⇧F10 in a panel: a Finder-like menu. On an item it works on that item or, when
/// the item is marked, on all marked items; a click on an unmarked item clears the marks first, as in
/// Finder. On empty space (or "..") it offers what can be done in the folder itself.
extension PanelViewController {
    /// The menu for a right click at the row `index` (nil = empty space).
    func contextMenu(at index: Int?) -> NSMenu? {
        view.window?.makeFirstResponder(listView)
        if let index, model.items.indices.contains(index), !model.items[index].isParent {
            let item = model.items[index]
            if !model.isSelected(item), !model.selectedItems.isEmpty { model.deselectAll() }
            model.moveCursor(to: index)
            modelChanged()
            return plain(itemMenu())
        }
        if let index, model.items.indices.contains(index) { model.moveCursor(to: index); modelChanged() }
        return plain(folderMenu())
    }

    /// Menu bar symbols (Copy, Paste…) would indent only some sections of a context menu.
    private func plain(_ menu: NSMenu) -> NSMenu {
        for item in menu.items where item.command != nil { item.image = nil }
        return menu
    }

    /// Local files for the Services menu (the marked items or the one under the cursor).
    func serviceURLs() -> [URL] {
        model.archive == nil && model.remote == nil ? targets().map(\.url) : []
    }

    /// ⇧F10: the menu of the cursor item, shown at its row.
    func showContextMenu() {
        let index = model.cursorItem?.isParent == false ? model.cursor : nil
        guard let menu = contextMenu(at: index) else { return }
        popUpAtCursor(menu)
    }

    /// ⌃⇧F3 / ⌃⇧F4 (Salamander's View With / Edit With): the apps that open the target files, as a
    /// menu at the cursor row; viewing also offers the built-in viewer and Quick Look, editing the
    /// configured editor.
    func showOpenWithMenu(viewing: Bool) {
        let urls = targets().map(\.url)
        guard !urls.isEmpty else { return }
        let menu = NSMenu()
        for command: Command in viewing ? [.view, .quickLook] : [.edit] { menu.addItem(MainMenuBuilder.commandItem(command)) }
        menu.addItem(.separator())
        for entry in openWithEntries(urls) { menu.addItem(entry) }
        popUpAtCursor(plain(menu))
    }

    private func popUpAtCursor(_ menu: NSMenu) {
        let rect: NSRect = switch viewMode {
        case .detailed: tableView.rect(ofRow: model.cursor)
        case .brief: briefView.frameForItem(at: model.cursor)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: rect.minX + 24, y: rect.maxY), in: listView)
    }

    private func itemMenu() -> NSMenu {
        let menu = NSMenu()
        let items = targets()
        let local = model.archive == nil && model.remote == nil
        menu.addItem(MainMenuBuilder.commandItem(.open))
        if local, !items.isEmpty, items.allSatisfy({ !$0.isDirectory || $0.isPackage }) {
            menu.addItem(openWithItem(items.map(\.url)))
        }
        if items.count == 1, items[0].isDirectory, !items[0].isPackage {
            menu.addItem(MainMenuBuilder.commandItem(side == .left ? .openInRightPanel : .openInLeftPanel))
        }
        menu.addItem(.separator())
        for command: Command in [.view, .edit, .quickLook] { menu.addItem(MainMenuBuilder.commandItem(command)) }
        menu.addItem(.separator())
        for command: Command in [.copy, .move, .rename, .delete] { menu.addItem(MainMenuBuilder.commandItem(command)) }
        menu.addItem(.separator())
        for command: Command in [.properties, .pack, .copyFiles, .copyFullPath] {
            menu.addItem(MainMenuBuilder.commandItem(command))
        }
        menu.addItem(.separator())
        menu.addItem(MainMenuBuilder.commandItem(.revealInFinder))
        if local {
            let share = NSSharingServicePicker(items: items.map { $0.url as NSURL }).standardShareMenuItem
            menu.addItem(share)
        }
        return menu
    }

    private func folderMenu() -> NSMenu {
        let menu = NSMenu()
        for command: Command in [.makeDirectory, .newFile, .pasteFiles] { menu.addItem(MainMenuBuilder.commandItem(command)) }
        menu.addItem(.separator())
        let sort = NSMenuItem(title: String(localized: "Sort By"), action: nil, keyEquivalent: "")
        sort.submenu = NSMenu()
        for command: Command in [.sortByName, .sortByExtension, .sortByDate, .sortBySize] {
            sort.submenu?.addItem(MainMenuBuilder.commandItem(command))
        }
        menu.addItem(sort)
        for command: Command in [.toggleHidden, .refresh] { menu.addItem(MainMenuBuilder.commandItem(command)) }
        menu.addItem(.separator())
        let folder = model.location
        if model.results == nil {
            menu.addItem(actionItem(String(localized: "Get Info")) { [weak self] in
                PropertiesSheet.show([folder], in: self?.view.window) { Task { await self?.model.refresh() } }
            })
        }
        menu.addItem(MainMenuBuilder.commandItem(.openTerminal))
        menu.addItem(actionItem(String(localized: "Show in Finder")) { [weak self] in
            guard let self else { return }
            NSWorkspace.shared.open(diskFolder)
        })
        return menu
    }

    /// Open With: the apps that can open the first file, the default one first, then “Other…”.
    private func openWithItem(_ urls: [URL]) -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Open With"), action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for entry in openWithEntries(urls) { menu.addItem(entry) }
        item.submenu = menu
        return item
    }

    private func openWithEntries(_ urls: [URL]) -> [NSMenuItem] {
        var menu: [NSMenuItem] = []
        let workspace = NSWorkspace.shared
        let preferred = urls.first.flatMap { workspace.urlForApplication(toOpen: $0) }
        var apps = urls.first.map { workspace.urlsForApplications(toOpen: $0) } ?? []
        if let preferred {
            apps.removeAll { $0.standardizedFileURL == preferred.standardizedFileURL }
            apps.insert(preferred, at: 0)
        }
        var seen = Set<String>()
        for app in apps {
            let name = FileManager.default.displayName(atPath: app.path(percentEncoded: false))
            guard seen.insert(name).inserted else { continue }
            let title = app == preferred ? String(localized: "\(name) (default)") : name
            let entry = actionItem(title) { Self.open(urls, with: app) }
            entry.image = workspace.icon(forFile: app.path(percentEncoded: false))
            entry.image?.size = NSSize(width: 16, height: 16)
            menu.append(entry)
            if app == preferred, apps.count > 1 { menu.append(.separator()) }
        }
        if !menu.isEmpty { menu.append(.separator()) }
        menu.append(actionItem(String(localized: "Other…")) {
            let panel = NSOpenPanel()
            panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
            panel.allowedContentTypes = [.application]
            panel.prompt = String(localized: "Open")
            guard panel.runModal() == .OK, let app = panel.url else { return }
            Self.open(urls, with: app)
        })
        return menu
    }

    private static func open(_ urls: [URL], with app: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor in NSAlert(error: error).runModal() }
        }
    }
}

/// A menu item that runs a closure (the item keeps the closure alive; its target is weak).
@MainActor func actionItem(_ title: String, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
    let action = MenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    return item
}

private final class MenuAction: NSObject {
    private let handler: @MainActor () -> Void
    init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}
