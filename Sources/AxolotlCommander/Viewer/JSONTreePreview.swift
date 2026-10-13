// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Outline of the JSON tree: viewer keys first, then → ← (⌥ for a whole subtree) and Return.
final class JSONOutlineView: NSOutlineView {
    var onKey: ((NSEvent) -> Bool)?
    var onToggle: ((_ expand: Bool?, _ subtree: Bool) -> Bool)?
    /// ⌘C: the value of the selected node.
    var onCopy: (() -> Bool)?

    @objc func copy(_ sender: Any?) {
        if onCopy?() != true { NSSound.beep() }
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let handled: Bool
        switch (event.specialKey, modifiers) {
        case (.rightArrow?, []): handled = onToggle?(true, false) ?? false
        case (.leftArrow?, []): handled = onToggle?(false, false) ?? false
        case (.rightArrow?, [.option]): handled = onToggle?(true, true) ?? false
        case (.leftArrow?, [.option]): handled = onToggle?(false, true) ?? false
        case (.carriageReturn?, []), (.enter?, []): handled = onToggle?(nil, false) ?? false
        default: handled = false
        }
        if !handled { super.keyDown(with: event) }
    }
}

/// The JSON preview (spec 019): keys, values and types as a tree, large containers in groups of 100.
final class JSONTreePreview: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// One row: a node, or a group of a large container's children.
    final class Item {
        let node: Int
        /// Child positions `lower..<upper` of `node` when this row is a group.
        let group: Range<Int>?
        init(node: Int, group: Range<Int>? = nil) {
            self.node = node
            self.group = group
        }
    }

    static let groupSize = 100

    private let scroll = NSScrollView()
    private let outline = JSONOutlineView()
    private let spinner = NSProgressIndicator()
    private(set) var document: JSONDocument?
    private var roots: [Item] = []
    private var nodeItems: [Int: Item] = [:]
    private var groupItems: [Int: [Int: Item]] = [:]
    private var childCache: [Int: [Int]] = [:]

    var keyView: NSView { outline }
    var onKey: ((NSEvent) -> Bool)? {
        get { outline.onKey }
        set { outline.onKey = newValue }
    }
    var onSelectionChange: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let columns: [(String, String, CGFloat)] = [
            ("key", String(localized: "Key"), 240), ("value", String(localized: "Value"), 380),
            ("type", String(localized: "Type"), 90),
        ]
        for (id, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            column.minWidth = 40
            outline.addTableColumn(column)
        }
        outline.outlineTableColumn = outline.tableColumns[0]
        outline.dataSource = self
        outline.delegate = self
        outline.usesAlternatingRowBackgroundColors = true
        outline.style = .fullWidth
        outline.rowSizeStyle = .small
        outline.allowsMultipleSelection = false
        outline.autosaveExpandedItems = false
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.onToggle = { [weak self] in self?.toggle(expand: $0, subtree: $1) ?? false }
        outline.onCopy = { [weak self] in self?.copyValue() ?? false }
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false
        for view in [scroll, spinner] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Content

    /// Shown while the tree is built off the main actor.
    func showBuilding() {
        clear()
        spinner.startAnimation(nil)
    }

    func show(_ document: JSONDocument) {
        spinner.stopAnimation(nil)
        self.document = document
        nodeItems = [:]
        groupItems = [:]
        childCache = [:]
        let root = document.nodes.isEmpty ? nil : 0
        if let root, isContainer(root) || document.isLines {
            roots = rows(of: root)
        } else {
            roots = root.map { [item(for: $0)] } ?? []
        }
        outline.reloadData()
        // The first two levels: the top rows and their children.
        for item in roots { outline.expandItem(item) }
        if !roots.isEmpty { outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        outline.scrollRowToVisible(0)
    }

    func clear() {
        spinner.stopAnimation(nil)
        document = nil
        roots = []
        nodeItems = [:]
        groupItems = [:]
        childCache = [:]
        outline.reloadData()
    }

    var nodeCount: Int { document.map { $0.isLines ? $0.nodes.count - 1 : $0.nodes.count } ?? 0 }

    /// The node of the selected row (nil for a group or no selection).
    var selectedNode: Int? {
        guard let item = outline.item(atRow: outline.selectedRow) as? Item, item.group == nil else { return nil }
        return item.node
    }

    var selectedPath: String? { selectedNode.flatMap { node in document?.path(of: node) } }

    // MARK: Tree

    private func isContainer(_ node: Int) -> Bool {
        guard let document else { return false }
        return [.object, .array].contains(document.nodes[node].kind) || document.isLines && node == 0
    }

    private func children(of node: Int) -> [Int] {
        if let cached = childCache[node] { return cached }
        let list = document?.children(of: node) ?? []
        childCache[node] = list
        return list
    }

    private func item(for node: Int) -> Item {
        if let item = nodeItems[node] { return item }
        let item = Item(node: node)
        nodeItems[node] = item
        return item
    }

    private func groupItem(of node: Int, lower: Int, count: Int) -> Item {
        if let item = groupItems[node]?[lower] { return item }
        let item = Item(node: node, group: lower..<min(lower + Self.groupSize, count))
        groupItems[node, default: [:]][lower] = item
        return item
    }

    /// The rows under a node: its children, or groups of them when there are many.
    private func rows(of node: Int) -> [Item] {
        let list = children(of: node)
        guard list.count > Self.groupSize else { return list.map { item(for: $0) } }
        return stride(from: 0, to: list.count, by: Self.groupSize).map { groupItem(of: node, lower: $0, count: list.count) }
    }

    private func rows(of item: Item) -> [Item] {
        guard let group = item.group else { return rows(of: item.node) }
        let list = children(of: item.node)
        return list[group].map { self.item(for: $0) }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let item = item as? Item else { return roots.count }
        if item.group != nil { return item.group!.count }
        let count = document?.nodes[item.node].childCount ?? 0
        return count > Self.groupSize ? (count + Self.groupSize - 1) / Self.groupSize : count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let item = item as? Item else { return roots[index] }
        return rows(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? Item else { return false }
        return item.group != nil || isContainer(item.node) && (document?.nodes[item.node].childCount ?? 0) > 0
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? Item, let column = tableColumn, let document else { return nil }
        let id = column.identifier
        let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? makeCell(id)
        let field = cell.textField!
        field.textColor = .labelColor
        field.toolTip = nil
        let node = document.nodes[item.node]
        if let group = item.group {
            let open = node.kind == .object ? "{" : "["
            let close = node.kind == .object ? "}" : "]"
            field.stringValue = switch id.rawValue {
            case "key": "\(open)\(group.lowerBound) … \(group.upperBound - 1)\(close)"
            default: ""
            }
            field.textColor = .secondaryLabelColor
            return cell
        }
        switch id.rawValue {
        case "key":
            field.stringValue = keyLabel(item.node)
            if node.isDuplicate {
                field.textColor = .systemOrange
                field.toolTip = String(localized: "Duplicate key: an earlier member has the same name.")
            }
        case "value":
            switch node.kind {
            case .object: field.stringValue = "{ \(node.childCount) }"; field.textColor = .secondaryLabelColor
            case .array: field.stringValue = "[ \(node.childCount) ]"; field.textColor = .secondaryLabelColor
            case .error:
                field.stringValue = node.error.map(Self.message) ?? ""
                field.textColor = .systemRed
                field.toolTip = document.valueText(item.node)
            case .string:
                field.stringValue = document.valueText(item.node)
                field.textColor = SyntaxColors.color(for: .string)
            case .number:
                field.stringValue = document.valueText(item.node)
                field.textColor = SyntaxColors.color(for: .number)
            case .bool, .null:
                field.stringValue = document.valueText(item.node)
                field.textColor = SyntaxColors.color(for: .keyword)
            }
        default:
            field.stringValue = Self.typeName(node.kind)
            field.textColor = .secondaryLabelColor
        }
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = id
        let field = NSTextField(labelWithString: "")
        field.lineBreakMode = .byTruncatingTail
        field.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private func keyLabel(_ node: Int) -> String {
        guard let document else { return "" }
        if let key = document.keyText(node) { return key }
        let info = document.nodes[node]
        if info.parent < 0 { return "$" }
        if document.isLines, info.parent == 0 { return String(localized: "Line \(info.line)") }
        return "[\(info.index)]"
    }

    static func typeName(_ kind: JSONKind) -> String {
        switch kind {
        case .object: String(localized: "object")
        case .array: String(localized: "array")
        case .string: String(localized: "string")
        case .number: String(localized: "number")
        case .bool: String(localized: "boolean")
        case .null: "null"
        case .error: String(localized: "error")
        }
    }

    static func message(_ error: JSONParseError) -> String {
        let reason = switch error.reason {
        case .unexpectedEnd: String(localized: "the text ends too early")
        case .unexpectedCharacter: String(localized: "unexpected character")
        case .unterminatedString: String(localized: "a string is not closed")
        case .invalidEscape: String(localized: "invalid escape sequence")
        case .invalidNumber: String(localized: "invalid number")
        case .controlCharacter: String(localized: "control character in a string")
        case .unsupportedJSON5: String(localized: "JSON5 syntax is not supported")
        case .trailingData: String(localized: "more text after the end")
        case .emptyDocument: String(localized: "the file is empty")
        }
        return String(localized: "line \(error.line), column \(error.column): \(reason)")
    }

    func outlineViewSelectionDidChange(_ notification: Notification) { onSelectionChange?() }

    // MARK: Keys and commands

    /// → / ← / Return on the selected row; `expand` nil toggles. False lets the outline handle the key.
    private func toggle(expand: Bool?, subtree: Bool) -> Bool {
        let row = outline.selectedRow
        guard row >= 0, let item = outline.item(atRow: row) else { return false }
        let expandable = outline.isExpandable(item)
        let expanded = outline.isItemExpanded(item)
        switch expand {
        case nil:
            guard expandable else { NSSound.beep(); return true }
            if expanded { outline.collapseItem(item) } else { outline.expandItem(item) }
        case true?:
            guard expandable else { return true }
            if subtree {
                outline.expandItem(item, expandChildren: true)
            } else if expanded {
                outline.selectRowIndexes(IndexSet(integer: row + 1), byExtendingSelection: false)
                outline.scrollRowToVisible(row + 1)
            } else {
                outline.expandItem(item)
            }
        case false?:
            if expandable, expanded || subtree {
                outline.collapseItem(item, collapseChildren: subtree)
            } else if let parent = outline.parent(forItem: item) {
                let parentRow = outline.row(forItem: parent)
                outline.selectRowIndexes(IndexSet(integer: parentRow), byExtendingSelection: false)
                outline.scrollRowToVisible(parentRow)
            }
        }
        return true
    }

    func expandAll() { outline.expandItem(nil, expandChildren: true) }

    func collapseAll() {
        outline.collapseItem(nil, collapseChildren: true)
        if outline.numberOfRows > 0 { outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        outline.scrollRowToVisible(0)
    }

    func copyValue() -> Bool {
        guard let node = selectedNode, let document else { return false }
        copy(document.copyValue(of: node))
        return true
    }

    func copyPath() -> Bool {
        guard let path = selectedPath else { return false }
        copy(path)
        return true
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Finds the next match of keys and values after the selected node; false when nothing matches.
    func find(_ text: String, ignoreCase: Bool, backward: Bool) -> Bool {
        guard let document else { return false }
        let from = selectedNode ?? (outline.item(atRow: max(outline.selectedRow, 0)) as? Item)?.node ?? 0
        guard let found = document.search(text, from: from, backward: backward, ignoreCase: ignoreCase) else { return false }
        reveal(found)
        return true
    }

    /// Expands the parents (and groups) of a node and selects it.
    func reveal(_ node: Int) {
        guard let document else { return }
        // From the top: every ancestor is shown once its parent is expanded.
        for level in document.ancestors(of: node).reversed() {
            if let row = row(for: level, in: document), let item = outline.item(atRow: row) { outline.expandItem(item) }
        }
        if let row = row(for: node, in: document) {
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        }
    }

    /// The row of a node, expanding the group that holds it when its parent is grouped.
    private func row(for node: Int, in document: JSONDocument) -> Int? {
        let info = document.nodes[node]
        if info.parent >= 0 {
            let siblings = document.nodes[info.parent].childCount
            if siblings > Self.groupSize {
                let lower = info.index / Self.groupSize * Self.groupSize
                let group = groupItem(of: info.parent, lower: lower, count: siblings)
                if outline.row(forItem: group) >= 0 { outline.expandItem(group) }
            }
        }
        let row = outline.row(forItem: item(for: node))
        return row >= 0 ? row : nil
    }
}
