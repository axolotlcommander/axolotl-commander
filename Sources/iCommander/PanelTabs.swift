import AppKit
import CommanderCore

/// Tabs, hot paths, Go to Folder and highlighting of one panel.
extension PanelViewController {
    // MARK: Tabs

    func configureTabStrip() {
        tabStrip.onSelect = { [weak self] index in self?.switchTab { $0.select(index) } }
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

    /// ⌃⇧W: the last tab of a panel stays.
    func closeTab(at index: Int) {
        guard tabs.tabs.count > 1 else { NSSound.beep(); return }
        tabs.updateCurrent(model.snapshot())
        let wasActive = index == tabs.active
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
            fallback.location = PanelState.nearestExisting(state.location) { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            fallback.cursorName = nil
            do { try await model.restore(fallback) } catch { statusField.stringValue = Format.error(error) }
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
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: pathField.bounds.height + 2), in: pathField)
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
            let url = try PathRules.resolve(hotPath.path, relativeTo: model.location)
            Task { await navigate { try await model.go(to: url) } }
        } catch {
            NSSound.beep()
            statusField.stringValue = Format.error(error)
        }
    }

    func setHotPath(_ slot: Int) {
        let path = model.location.displayPath
        AppSettings.shared.hotPaths.set(slot, HotPath(path: path))
        statusField.stringValue = String(localized: "Hot path \(slot + 1) (⌃\(HotPaths.digit(forSlot: slot) ?? 0)): \(path)")
    }

    // MARK: Go to Folder

    /// ⇧F7 / ⌘⇧G with a history of folders.
    func askGoToFolder() async {
        guard let text = await GoToFolder.ask(initial: "", in: view.window) else { return }
        do {
            let url = try PathRules.resolve(text, relativeTo: model.location)
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
        if viewMode == .brief { reloadBrief() }
    }

    /// Marked items use the mark color; others the first matching highlight rule.
    func textColor(for item: FileItem, marked: Bool) -> NSColor {
        let appearance = AppSettings.shared.appearance
        if marked { return appearance.markColor.nsColor }
        if let color = appearance.color(for: item, rules: model.rules) { return color.nsColor }
        return item.isHidden ? .secondaryLabelColor : .labelColor
    }
}
