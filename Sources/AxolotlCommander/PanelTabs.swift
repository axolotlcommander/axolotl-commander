// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Tabs, hot paths, Go to Folder and highlighting of one panel.
extension PanelViewController {
    /// Settings → Panels "Open new tabs next to the current tab"; off: new tabs go after the last tab.
    static var nextToCurrent: Bool { PanelBehavior(defaults: .standard).newTabsNextToCurrent }

    // MARK: Tabs

    func configureTabStrip() {
        tabStrip.onSelect = { [weak self] index in
            self?.activateFromClick()
            self?.switchTab { $0.select(index) }
        }
        tabStrip.onClose = { [weak self] index in self?.closeTab(at: index) }
        tabStrip.onCloseOthers = { [weak self] index in self?.closeOtherTabs(keeping: index) }
        tabStrip.onCloseToTheRight = { [weak self] index in self?.closeTabsToTheRight(of: index) }
        tabStrip.onNew = { [weak self] in self?.newTab() }
        tabStrip.onDuplicate = { [weak self] index in self?.duplicateTab(at: index) }
        tabStrip.onCopyToOtherPanel = { [weak self] index in
            guard let self else { return }
            router?.copyTabToOtherPanel(at: index, from: self)
        }
        tabStrip.onLock = { [weak self] index, mode in self?.toggleLock(mode, at: index) }
        tabStrip.onReopen = { [weak self] in self?.reopenClosedTab() }
        showTabs()
    }

    /// Shows the tabs in the strip, with the lock marks and their tooltips.
    func showTabs() {
        let items = tabs.tabs.map { state in
            let path = state.location.displayPath
            let toolTip = switch state.lock?.mode {
            case .locked: String(localized: "Locked: \(state.lock?.folder.displayPath ?? path)")
            case .allowsChanges: String(localized: "Locked, folder changes allowed: \(state.lock?.folder.displayPath ?? path)")
            case nil: path
            }
            return TabStrip.Item(title: state.title, lock: state.lock?.mode, toolTip: toolTip)
        }
        tabStrip.show(items, active: tabs.active, canReopen: !closedTabs.isEmpty)
    }

    /// Mirrors the model into the active tab (not while another tab is being restored). In a locked tab a
    /// folder change opens the new folder in a new tab after it, and the locked tab keeps its folder.
    func tabsChanged() {
        guard !isRestoringTab else { return }
        let snapshot = model.snapshot()
        let stored = tabs.current
        if stored.lock?.mode == .locked, Self.place(of: snapshot) != Self.place(of: stored) {
            var keeping = stored
            // The cursor the locked tab had when it was left, from the model's history.
            if let left = model.historyPlaces.back.last, left.url == stored.location, stored.results == nil,
               stored.branch == nil {
                keeping.cursorName = left.cursorName
            }
            tabs.split(keeping: keeping, opened: snapshot, nextToCurrent: Self.nextToCurrent)
        } else {
            tabs.updateCurrent(snapshot)
        }
        showTabs()
        router?.layoutChanged()
    }

    /// Shows a state from elsewhere (Swap Panels, Same Folder as Other of a flat listing); a locked tab keeps
    /// its folder and the state opens in a new tab.
    func show(_ state: PanelState) async {
        tabs.updateCurrent(model.snapshot())
        if tabs.current.lock?.mode == .locked, Self.place(of: state) != Self.place(of: tabs.current) {
            var opened = state
            opened.lock = nil
            tabs.open(opened, activate: true, nextToCurrent: Self.nextToCurrent)
        }
        await restoreTab(state)
    }

    /// What a locked tab must keep: its folder and whether it shows search results or a branch.
    private static func place(of state: PanelState) -> [AnyHashable] {
        [state.location, state.results?.title, state.results?.root, state.branch]
    }

    /// Lock Tab / Lock Tab, Allow Folder Changes; choosing the mode a tab already has unlocks it.
    func toggleLock(_ mode: TabLock.Mode, at index: Int? = nil) {
        tabs.updateCurrent(model.snapshot())
        let index = index ?? tabs.active
        guard tabs.tabs.indices.contains(index) else { return }
        tabs.setLock(tabs.tabs[index].lock?.mode == mode ? nil : mode, at: index)
        tabsChanged()
    }

    /// Duplicate Tab: an unlocked copy right after the tab, active.
    func duplicateTab(at index: Int? = nil) {
        tabs.updateCurrent(model.snapshot())
        tabs.duplicate(at: index ?? tabs.active, nextToCurrent: Self.nextToCurrent)
        Task { await restoreTab(tabs.current) }
    }

    /// The state of a tab for Copy Tab to Other Panel: unlocked, without marks.
    func stateForCopy(at index: Int? = nil) -> PanelState? {
        tabs.updateCurrent(model.snapshot())
        let index = index ?? tabs.active
        guard tabs.tabs.indices.contains(index) else { return nil }
        var copy = tabs.tabs[index]
        copy.lock = nil
        copy.selectedNames = []
        return copy
    }

    /// ⌃⇧T: a new tab with the same folder, sort, filter and cursor, placed after the current one.
    func newTab() {
        tabs.updateCurrent(model.snapshot())
        tabs.open(model.snapshot(), nextToCurrent: Self.nextToCurrent)
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
        tabs.open(state, activate: activate, nextToCurrent: Self.nextToCurrent)
        if activate { Task { await restoreTab(tabs.current) } } else { tabsChanged() }
    }

    /// Reopen Closed Tab (the newest) or a closed tab chosen in the tab list.
    func reopenClosedTab(at index: Int = 0) {
        guard let state = closedTabs.remove(at: index) else { NSSound.beep(); return }
        tabs.updateCurrent(model.snapshot())
        tabs.open(state, activate: true, nextToCurrent: Self.nextToCurrent)
        tabs.returnCurrentToLock()
        Task { await restoreTab(tabs.current) }
    }

    /// ⌃⇧W: the last tab of a panel stays.
    func closeTab(at index: Int) {
        guard tabs.tabs.count > 1 else { NSSound.beep(); return }
        tabs.updateCurrent(model.snapshot())
        let wasActive = index == tabs.active
        closedTabs.push(tabs.tabs[index])
        tabs.close(at: index)
        if wasActive {
            tabs.returnCurrentToLock()
            Task { await restoreTab(tabs.current) }
        } else {
            tabsChanged()
        }
    }

    /// Close Other Tabs: locked tabs stay.
    func closeOtherTabs(keeping index: Int? = nil) {
        closeSeveral { $0.closeOthers(keeping: index ?? $0.active) }
    }

    /// Close Tabs to the Right: locked tabs stay.
    func closeTabsToTheRight(of index: Int? = nil) {
        closeSeveral { $0.closeToTheRight(of: index ?? $0.active) }
    }

    /// Closes the tabs `close` removes (they can be reopened); a new active tab is shown.
    private func closeSeveral(_ close: (inout TabList) -> [PanelState]) {
        tabs.updateCurrent(model.snapshot())
        let before = tabs.current
        let closed = close(&tabs)
        guard !closed.isEmpty else { NSSound.beep(); return }
        closed.forEach { closedTabs.push($0) }
        if tabs.current == before {
            tabsChanged()
        } else {
            tabs.returnCurrentToLock()
            Task { await restoreTab(tabs.current) }
        }
    }

    /// Saves the current tab first, then moves to the chosen one (a tab locked with folder changes allowed
    /// comes back on its folder).
    func switchTab(_ change: (inout TabList) -> Void) {
        tabs.updateCurrent(model.snapshot())
        let before = tabs.active
        change(&tabs)
        guard tabs.active != before else { return }
        tabs.returnCurrentToLock()
        Task { await restoreTab(tabs.current) }
    }

    /// Restores a saved state; a folder that has disappeared falls back to its nearest existing parent.
    func restoreTab(_ state: PanelState) async {
        isRestoringTab = true
        endQuickFilterTyping()
        defer {
            // The tab takes what the model shows before the strip updates, so a locked tab does not split.
            tabs.updateCurrent(model.snapshot())
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
            let location = state.location
            // Off the main thread: the folder may be on a disk that is asleep.
            fallback.location = RemoteURL.isRemote(location) ? FileManager.default.homeDirectoryForCurrentUser
                : await Task.detached {
                    PanelState.nearestExisting(location) { url in
                        var isDirectory: ObjCBool = false
                        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
                            && isDirectory.boolValue
                    }
                }.value
            fallback.cursorName = nil
            do { try await model.restore(fallback) } catch { statusField.stringValue = Format.error(error) }
            // A locked folder that is gone: the lock moves to the parent the tab shows now.
            if let lock = state.lock, lock.folder == state.location, !RemoteURL.isRemote(state.location) {
                tabs.relock(at: tabs.active, to: model.location)
            }
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
            if state.lock != nil {
                item.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: String(localized: "Locked"))
            }
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
        tabs.open(model.snapshot(), activate: true, nextToCurrent: Self.nextToCurrent)
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
