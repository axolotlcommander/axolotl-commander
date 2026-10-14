// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Tabs, hot paths, Go to Folder and highlighting of one panel.
extension PanelViewController {
    // MARK: Tabs

    func configureTabStrip() {
        tabStrip.onSelect = { [weak self] index in
            self?.activateFromClick()
            self?.switchTab { $0.select(index) }
        }
        tabStrip.onClose = { [weak self] index in self?.closeTab(at: index) }
        tabStrip.onCloseOthers = { [weak self] index in self?.closeOtherTabs(keeping: index) }
        tabStrip.onNew = { [weak self] in self?.newTab() }
        tabStrip.show(titles: tabs.tabs.map(\.title), active: tabs.active)
    }

    /// Mirrors the model into the active tab (not while another tab is being restored).
    func tabsChanged() {
        guard !isRestoringTab else { return }
        tabs.updateCurrent(model.snapshot())
        tabStrip.show(titles: tabs.tabs.map(\.title), active: tabs.active)
        router?.layoutChanged()
    }

    /// ⌃⇧T: a new tab with the same folder, sort, filter and cursor, placed after the current one.
    func newTab() {
        tabs.updateCurrent(model.snapshot())
        tabs.open(model.snapshot())
        tabsChanged()
    }

    /// Open in New Tab / Open in Background Tab: what Enter would enter, in a new tab after the
    /// current one; the current tab stays as it is.
    func openCursorInNewTab(activate: Bool) {
        Task {
            await navigate {
                let state = try await model.stateEnteringCursor()
                openTab(state, activate: activate)
            }
        }
    }

    /// The state for a tab of the other panel (Open in New Tab of Other Panel).
    func stateForNewTab() async -> PanelState? {
        do { return try await model.stateEnteringCursor() } catch {
            NSSound.beep()
            statusField.stringValue = Format.error(error)
            return nil
        }
    }

    /// Inserts a tab after the current one; an active one is shown at once.
    func openTab(_ state: PanelState, activate: Bool) {
        tabs.updateCurrent(model.snapshot())
        tabs.open(state, activate: activate)
        if activate { Task { await restoreTab(tabs.current) } } else { tabsChanged() }
    }

    /// Reopen Closed Tab (the newest) or a closed tab chosen in the tab list.
    func reopenClosedTab(at index: Int = 0) {
        guard let state = closedTabs.remove(at: index) else { NSSound.beep(); return }
        openTab(state, activate: true)
    }

    /// ⌃⇧W: the last tab of a panel stays.
    func closeTab(at index: Int) {
        guard tabs.tabs.count > 1 else { NSSound.beep(); return }
        tabs.updateCurrent(model.snapshot())
        let wasActive = index == tabs.active
        closedTabs.push(tabs.tabs[index])
        tabs.close(at: index)
        if wasActive {
            Task { await restoreTab(tabs.current) }
        } else {
            tabsChanged()
        }
    }

    func closeOtherTabs(keeping index: Int) {
        guard tabs.tabs.indices.contains(index) else { return }
        tabs.updateCurrent(model.snapshot())
        let keep = tabs.tabs[index]
        let wasActive = index == tabs.active
        for (other, state) in tabs.tabs.enumerated() where other != index { closedTabs.push(state) }
        tabs = TabList(keep)
        if wasActive { tabsChanged() } else { Task { await restoreTab(keep) } }
    }

    /// Saves the current tab first, then moves to the chosen one.
    func switchTab(_ change: (inout TabList) -> Void) {
        tabs.updateCurrent(model.snapshot())
        let before = tabs.active
        change(&tabs)
        guard tabs.active != before else { return }
        Task { await restoreTab(tabs.current) }
    }

    /// Restores a saved state; a folder that has disappeared falls back to its nearest existing parent.
    func restoreTab(_ state: PanelState) async {
        isRestoringTab = true
        endQuickFilterTyping()
        defer {
            isRestoringTab = false
            updateSortIndicator()
            tabsChanged()
        }
        do {
            try await model.restore(state)
        } catch is CancellationError {
        } catch {
            var fallback = state
            // A server that can't be reached (or a cancelled login) leaves the tab at home.
            fallback.location = RemoteURL.isRemote(state.location) ? FileManager.default.homeDirectoryForCurrentUser
                : PanelState.nearestExisting(state.location) { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            fallback.cursorName = nil
            do { try await model.restore(fallback) } catch { statusField.stringValue = Format.error(error) }
        }
    }

    /// Tab List…: the open tabs (the active one checked), then the recently closed ones.
    func showTabList() {
        tabs.updateCurrent(model.snapshot())
        let menu = NSMenu()
        func entry(_ state: PanelState, tag: Int, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: state.title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.toolTip = state.location.displayPath
            return item
        }
        for (index, state) in tabs.tabs.enumerated() {
            let item = entry(state, tag: index, action: #selector(tabChosen(_:)))
            item.state = index == tabs.active ? .on : .off
            menu.addItem(item)
        }
        if !closedTabs.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: String(localized: "Recently Closed")))
            for (index, state) in closedTabs.items.enumerated() {
                menu.addItem(entry(state, tag: index, action: #selector(closedTabChosen(_:))))
            }
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: pathBar.bounds.height + 2), in: pathBar)
    }

    @objc private func tabChosen(_ sender: NSMenuItem) { switchTab { $0.select(sender.tag) } }
    @objc private func closedTabChosen(_ sender: NSMenuItem) { reopenClosedTab(at: sender.tag) }

    // MARK: Folder history

    /// Go → Folder History…: the panel's Back / Forward history and the recent typed paths as a
    /// filterable list; Return opens here, ⌘Return in a new tab, ⌥Return in the other panel.
    func showFolderHistory() {
        guard let window = view.window else { return }
        let history = model.historyPlaces
        let entries = FolderHistory.entries(back: history.back, current: model.location, forward: history.forward,
                                            recent: AppSettings.shared.recentPaths.paths, display: \.displayPath)
        let rows = entries.map { entry in
            let symbol = switch entry.target {
            case .location: entry.isCurrent ? "folder.fill" : "folder"
            case .typed: "clock"
            }
            return HistoryListSheet.Row(text: entry.text, symbol: symbol, isCurrent: entry.isCurrent)
        }
        let hint = String(localized: "Return opens here, ⌘Return in a new tab, ⌥Return in the other panel.")
        HistoryListSheet.present(on: window, title: String(localized: "Folder History"), rows: rows,
                                 selection: FolderHistory.initialSelection(in: entries), hint: hint,
                                 allowsModifiers: true) { [weak self] index, choice in
            guard let self else { return }
            let target = entries[index].target
            switch choice {
            case .plain:
                // The current folder: nothing to open.
                if !entries[index].isCurrent { open(target) }
            case .command: openNewTab { $0.open(target) }
            case .option: router?.openInOtherPanel(target, from: self)
            }
        }
    }

    /// Opens a folder history entry the way Back (a place) or Go to Folder (a typed path) does.
    func open(_ target: FolderHistory.Target, takeFocus: Bool = true) {
        switch target {
        case .location(let url): go(to: url)
        case .typed(let path): goTo(typed: path, takeFocus: takeFocus)
        }
    }

    /// A new active tab showing the current folder; `then` runs once it is shown.
    private func openNewTab(then action: @escaping (PanelViewController) -> Void) {
        tabs.updateCurrent(model.snapshot())
        tabs.open(model.snapshot(), activate: true)
        Task {
            await restoreTab(tabs.current)
            action(self)
        }
    }

    // MARK: Hot paths

    /// ⇧F9: defined hot paths, plus saving the current folder.
    func showHotPathsMenu() {
        let menu = NSMenu()
        let hotPaths = AppSettings.shared.hotPaths
        for (slot, hotPath) in hotPaths.defined {
            let item = NSMenuItem(title: hotPath.name, action: #selector(hotPathChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = slot
            item.toolTip = hotPath.path
            if let digit = HotPaths.digit(forSlot: slot) {
                item.keyEquivalent = String(digit)
                item.keyEquivalentModifierMask = .control
            }
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            menu.addItem(item)
        }
        if hotPaths.defined.isEmpty {
            let empty = NSMenuItem(title: String(localized: "No Hot Paths"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        menu.addItem(.separator())
        let add = NSMenuItem(title: String(localized: "Add Current Folder"), action: #selector(addCurrentHotPath), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        let setMenu = NSMenu()
        for slot in 0..<HotPaths.shortcutSlots {
            let digit = HotPaths.digit(forSlot: slot) ?? 0
            let title = "\(slot + 1)" + (hotPaths[slot].map { "  —  \($0.name)" } ?? "")
            let item = NSMenuItem(title: title, action: #selector(setHotPathChosen(_:)), keyEquivalent: String(digit))
            item.keyEquivalentModifierMask = [.control, .shift]
            item.target = self
            item.tag = slot
            setMenu.addItem(item)
        }
        let set = NSMenuItem(title: String(localized: "Set Current Folder As"), action: nil, keyEquivalent: "")
        set.submenu = setMenu
        menu.addItem(set)
        let edit = NSMenuItem(title: String(localized: "Edit Hot Paths…"), action: #selector(editHotPaths), keyEquivalent: "")
        edit.target = self
        menu.addItem(edit)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: pathBar.bounds.height + 2), in: pathBar)
    }

    @objc private func hotPathChosen(_ sender: NSMenuItem) { goToHotPath(sender.tag) }
    @objc private func setHotPathChosen(_ sender: NSMenuItem) { setHotPath(sender.tag) }
    @objc private func editHotPaths() { (NSApp.delegate as? AppDelegate)?.showSettings(tab: .hotPaths) }

    @objc private func addCurrentHotPath() {
        let path = model.location.displayPath
        if let slot = AppSettings.shared.hotPaths.add(HotPath(path: path)) {
            statusField.stringValue = String(localized: "Hot path \(slot + 1): \(path)")
        } else {
            NSSound.beep()
            statusField.stringValue = String(localized: "All \(HotPaths.capacity) hot paths are in use.")
        }
    }

    func goToHotPath(_ slot: Int) {
        guard let hotPath = AppSettings.shared.hotPaths[slot] else {
            NSSound.beep()
            statusField.stringValue = String(localized: "Hot path \(slot + 1) is not set — ⌃⇧\(HotPaths.digit(forSlot: slot) ?? 0) saves this folder.")
            return
        }
        do {
            let url = try PathInput.resolve(hotPath.path, relativeTo: model.location, absoluteIsLocal: true)
            Task { await navigate { try await model.go(to: url) } }
        } catch {
            NSSound.beep()
            statusField.stringValue = Format.error(error)
        }
    }

    /// Saves `path` (the current folder by default) in hot path `slot`.
    func setHotPath(_ slot: Int, path: String? = nil) {
        let path = path ?? model.location.displayPath
        AppSettings.shared.hotPaths.set(slot, HotPath(path: path))
        statusField.stringValue = String(localized: "Hot path \(slot + 1) (⌃\(HotPaths.digit(forSlot: slot) ?? 0)): \(path)")
    }

    // MARK: Go to Folder

    /// ⇧F7 / ⌘⇧G with a history of folders.
    func askGoToFolder() async {
        guard let text = await GoToFolder.ask(initial: "", in: view.window) else { return }
        do {
            let url = try PathInput.resolve(text, relativeTo: model.location)
            try await model.go(to: url)
            AppSettings.shared.recentPaths.add(url.displayPath)
        } catch is CancellationError {
        } catch {
            NSSound.beep()
            statusField.stringValue = Format.error(error)
        }
    }

    // MARK: Colors

    func observeAppearance() {
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged),
                                               name: .appearanceChanged, object: nil)
    }

    @objc private func appearanceChanged() {
        tableView.reloadData()
        reloadGrid()
    }

    /// Marked items are bold unless Settings → Appearance turns it off.
    func textFont(marked: Bool) -> NSFont {
        marked && AppSettings.shared.appearance.markBold
            ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
    }

    /// Marked items use the mark color; others the first matching highlight rule.
    func textColor(for item: FileItem, marked: Bool) -> NSColor {
        let appearance = AppSettings.shared.appearance
        if marked { return appearance.markColor.nsColor }
        if let color = appearance.color(for: item, rules: model.rules) { return color.nsColor }
        return item.isHidden ? .secondaryLabelColor : .labelColor
    }
}
