// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// F12 (spec 022): the open server connections, the network volumes mounted in macOS and the
/// ejectable disks, each with a checkbox. The arrows move, Space toggles, Return disconnects or
/// ejects what is checked, Esc cancels. The list follows mounts and connections while it is open.
@MainActor
final class DisconnectSheet: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private enum Row {
        case header(DisconnectList.Section.Title)
        case item(DisconnectList.Item)
    }

    private let sheet = KeySheetWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 300),
                                       styleMask: [.titled], backing: .buffered, defer: true)
    private let table = NSTableView()
    private let confirmButton = NSButton()
    private weak var parent: NSWindow?
    private var rows: [Row] = []
    private var checked: Set<DisconnectList.Item.ID> = []
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    static func show(for panel: PanelViewController) {
        guard let window = panel.view.window else { return }
        let servers = ServerConnectionsUI.shared.opened, volumes = VolumeList.shared.current
        guard DisconnectList.isEnabled(servers: servers, volumes: volumes) else {
            NSSound.beep()
            return
        }
        let dialog = DisconnectSheet(parent: window)
        let sections = DisconnectList.sections(servers: servers, volumes: volumes)
        if let id = DisconnectList.preChecked(panel.ejectTarget, in: sections) { dialog.checked = [id] }
        dialog.show(sections)
        dialog.sheet.owner = dialog
        window.beginSheet(dialog.sheet, completionHandler: nil)
        dialog.sheet.makeFirstResponder(dialog.table)
    }

    private init(parent: NSWindow) {
        self.parent = parent
        super.init()
        build()
        sheet.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: VolumeList.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }))
        observers.append((center, center.addObserver(forName: ServerConnectionsUI.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }))
    }

    // MARK: Layout

    private func build() {
        let heading = NSTextField(labelWithString: String(localized: "Disconnect or Eject"))
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .inset
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        confirmButton.bezelStyle = .push
        confirmButton.target = self
        confirmButton.action = #selector(confirm)
        confirmButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [NSView(), cancel, confirmButton])
        buttons.spacing = 8
        let stack = NSStackView(views: [heading, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 440),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            scroll.heightAnchor.constraint(equalToConstant: 200),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        sheet.contentView = content
        sheet.setContentSize(content.fittingSize)
    }

    private func show(_ sections: [DisconnectList.Section]) {
        rows = sections.flatMap { [Row.header($0.title)] + $0.items.map(Row.item) }
        let ids = Set(items.map(\.id))
        checked.formIntersection(ids)
        table.reloadData()
        updateButton()
        let first = rows.firstIndex { if case .item(let item) = $0 { checked.isEmpty || checked.contains(item.id) } else { false } }
        if let first, table.selectedRow < 0 || !isItem(table.selectedRow) {
            table.selectRowIndexes([first], byExtendingSelection: false)
            table.scrollRowToVisible(first)
        }
    }

    private func reload() {
        guard sheet.sheetParent != nil else { return }
        let selected = item(at: table.selectedRow)?.id
        show(DisconnectList.sections(servers: ServerConnectionsUI.shared.opened, volumes: VolumeList.shared.current))
        if let selected, let row = rows.firstIndex(where: { if case .item(let item) = $0 { item.id == selected } else { false } }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    private var items: [DisconnectList.Item] {
        rows.compactMap { if case .item(let item) = $0 { item } else { nil } }
    }

    private func item(at row: Int) -> DisconnectList.Item? {
        guard rows.indices.contains(row), case .item(let item) = rows[row] else { return nil }
        return item
    }

    private func isItem(_ row: Int) -> Bool { item(at: row) != nil }

    private func updateButton() {
        let chosen = items.filter { checked.contains($0.id) }
        confirmButton.title = DisconnectList.confirmTitle(checked: chosen)
        confirmButton.isEnabled = !chosen.isEmpty
    }

    private static func title(of section: DisconnectList.Section.Title) -> String {
        switch section {
        case .servers: String(localized: "Servers")
        case .networkVolumes: String(localized: "Network Volumes")
        case .disks: String(localized: "Disks")
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool { !isItem(row) }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { isItem(row) }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let section):
            return NSTextField(labelWithString: Self.title(of: section))
        case .item(let item):
            let box = NSButton(checkboxWithTitle: item.name, target: self, action: #selector(toggled(_:)))
            box.state = checked.contains(item.id) ? .on : .off
            box.tag = row
            box.refusesFirstResponder = true
            box.lineBreakMode = .byTruncatingMiddle
            let detail = NSTextField(labelWithString: item.detail)
            detail.textColor = .secondaryLabelColor
            detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            detail.lineBreakMode = .byTruncatingMiddle
            detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let line = NSStackView(views: [box, detail])
            line.spacing = 8
            return line
        }
    }

    @objc private func toggled(_ sender: NSButton) { toggle(sender.tag) }

    private func toggle(_ row: Int) {
        guard let item = item(at: row) else { return }
        if checked.contains(item.id) { checked.remove(item.id) } else { checked.insert(item.id) }
        table.reloadData(forRowIndexes: [row], columnIndexes: [0])
        updateButton()
    }

    // MARK: Keys

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 49:  // Space
            toggle(table.selectedRow)
            return true
        case 36, 76:  // Return, Enter
            if confirmButton.isEnabled { confirm() } else { NSSound.beep() }
            return true
        default:
            return false
        }
    }

    // MARK: Ending

    @objc private func confirm() {
        let targets: [EjectTarget] = items.filter { checked.contains($0.id) }.map {
            switch $0.kind {
            case .server(let endpoint): .server(endpoint)
            case .volume(let volume): .volume(volume)
            }
        }
        close()
        VolumeEjector.eject(targets, window: parent)
    }

    @objc private func cancel() { close() }

    private func close() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        sheet.sheetParent?.endSheet(sheet)
        sheet.owner = nil
    }
}
