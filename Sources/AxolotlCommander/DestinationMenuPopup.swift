// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The destination menu of the Copy / Move, Split and Combine dialogs: the other panel, the tabs, hot paths
/// and recent destinations, in sections. The chosen folder's path goes to `onChoose`.
@MainActor
final class DestinationMenuPopup: NSObject {
    private let onChoose: (String) -> Void

    init(onChoose: @escaping (String) -> Void) {
        self.onChoose = onChoose
    }

    /// Pops the menu up under `view`; beeps when there is nothing to offer.
    func show(_ entries: [DestinationMenu.Entry], under view: NSView) {
        guard !entries.isEmpty else {
            NSSound.beep()
            return
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        var section: DestinationMenu.Section?
        for entry in entries {
            if entry.section != section {
                if section != nil { menu.addItem(.separator()) }
                menu.addItem(.sectionHeader(title: Self.title(of: entry.section)))
                section = entry.section
            }
            let item = NSMenuItem(title: entry.title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.path
            if entry.title != entry.path { item.toolTip = entry.path }
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    private static func title(of section: DestinationMenu.Section) -> String {
        switch section {
        case .otherPanel: String(localized: "Other Panel")
        case .tabs: String(localized: "Tabs")
        case .hotPaths: String(localized: "Hot Paths")
        case .recent: String(localized: "Recent Destinations")
        }
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let folder = sender.representedObject as? String else { return }
        onChoose(folder)
    }

    /// The "⌄" button next to a "To:" field.
    static func button(target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: String(localized: "Destinations"))
        button.bezelStyle = .push
        button.target = target
        button.action = action
        button.toolTip = String(localized: "Destinations (⌥↓)")
        button.refusesFirstResponder = true
        return button
    }
}
