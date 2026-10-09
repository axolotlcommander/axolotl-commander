// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

extension CSVSeparator {
    var title: String {
        switch self {
        case .semicolon: String(localized: "Semicolon")
        case .comma: String(localized: "Comma")
        case .tab: String(localized: "Tab")
        case .bar: String(localized: "Vertical Bar")
        }
    }
}

/// The table of the table preview: viewer keys first, ⌘C copies the selected rows.
final class CSVTableView: NSTableView {
    var onKey: ((NSEvent) -> Bool)?
    var onCopy: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    @objc func copy(_ sender: Any?) { onCopy?() }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) { return selectedRow >= 0 }
        return super.validateUserInterfaceItem(item)
    }
}

/// The line between the row numbers and the table (a separator box would pull the view to its own height).
private final class DividerView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        dirtyRect.fill()
    }
}

/// The row numbers' scroll view: it follows the table and hands wheel scrolling to it.
private final class GutterScrollView: NSScrollView {
    weak var target: NSScrollView?
    override func scrollWheel(with event: NSEvent) { target?.scrollWheel(with: event) }
}

/// A separated-values file as a table (the viewer's Preview mode for .csv, .tsv and .tab).
/// Only row positions are kept; rows are split from the file's bytes when they are drawn.
/// Row numbers stay in place at the left, rows with an unusual field count are marked, and the
/// rows can be sorted by a column once the file is fully read.
final class TablePreview: NSView, NSTableViewDataSource, NSTableViewDelegate {
    /// Above this size, sorting asks first: it keeps a column's values in memory.
    static let largeSortSize = 256 * 1024 * 1024
    private static let cacheLimit = 512
    private static let shownCharacters = 1_000
    private static let tooltipCharacters = 10_000

    let table = CSVTableView()
    private let scroll = NSScrollView()
    private let gutter = NSTableView()
    private let gutterScroll = GutterScrollView()
    private var gutterWidth: NSLayoutConstraint!

    var onKey: ((NSEvent) -> Bool)? {
        get { table.onKey }
        set { table.onKey = newValue }
    }
    /// The status text changed (rows read, malformed rows, a message).
    var onStatusChange: (() -> Void)?

    private var data = Data()
    private var encoding = TextEncoding.utf8
    private var contentStart = 0
    private var preferTab = false
    /// Identifies the loaded file (the viewer's load generation).
    private var token: Int?
    private(set) var dialect = CSVDialect(separator: nil, encoding: .utf8)
    private(set) var index = CSVIndex()
    private var sample = CSVSample.make(Data(), dialect: CSVDialect(separator: nil, encoding: .utf8))

    /// The user's separator for this file; nil = detected.
    private(set) var separatorChoice: CSVSeparator?
    /// The user's header setting for this file; nil = detected.
    private var headerChoice: Bool?
    var hasHeader: Bool { (headerChoice ?? sample.hasHeader) && index.rowCount > 0 }
    private var firstDataRow: Int { hasHeader ? 1 : 0 }

    private(set) var malformed: [Int] = []
    private(set) var expectedFields = 0
    private var sort: (column: Int, ascending: Bool)?
    private var sortedRows: [Int]?
    private(set) var malformedOnly = false
    private var largeSortConfirmed = false
    /// Displayed file rows, in order.
    private var rows = CSVRowList.range(0..<0)
    private var cache: [Int: [String]] = [:]
    /// The cell found last; highlighted until the selection changes.
    private var found: (row: Int, column: Int)?
    private var selectingFound = false
    private var pendingFraction: Double?

    private var indexTask: Task<Void, Never>?
    private var sortTask: Task<Void, Never>?
    private var findTask: Task<Void, Never>?
    /// A transient status message (searching, sorting, not found, the sorting notice).
    private(set) var message: String?

    var fontSize: Double = 12 {
        didSet { applyFont() }
    }
    private var font: NSFont { .systemFont(ofSize: fontSize) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for view in [table, gutter] as [NSTableView] {
            view.style = .plain
            view.usesAlternatingRowBackgroundColors = true
            view.columnAutoresizingStyle = .noColumnAutoresizing
            view.dataSource = self
            view.delegate = self
        }
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.gridStyleMask = [.solidVerticalGridLineMask]
        table.onCopy = { [weak self] in self?.copySelection() }
        gutter.refusesFirstResponder = true
        gutter.allowsColumnReordering = false
        gutter.allowsColumnResizing = false
        let number = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        number.title = ""
        gutter.addTableColumn(number)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        gutterScroll.documentView = gutter
        gutterScroll.hasVerticalScroller = false
        gutterScroll.hasHorizontalScroller = false
        gutterScroll.borderType = .noBorder
        gutterScroll.target = scroll

        let divider = DividerView()
        for view in [gutterScroll, divider, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        gutterWidth = gutterScroll.widthAnchor.constraint(equalToConstant: 48)
        NSLayoutConstraint.activate([
            gutterScroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutterScroll.topAnchor.constraint(equalTo: topAnchor),
            gutterScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            gutterWidth,
            divider.leadingAnchor.constraint(equalTo: gutterScroll.trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            scroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(tableScrolled),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        applyFont()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The view to focus for the viewer keys.
    var keyView: NSView { table }
    private var wantsFocus = false

    /// Focuses the table, or does so once it has columns.
    func focus() {
        wantsFocus = window?.makeFirstResponder(table) != true
    }

    // MARK: Loading

    /// Shows a file. The same file (`token`) in the same encoding keeps its table and only scrolls.
    func show(_ data: Data, encoding: TextEncoding, contentStart: Int, preferTab: Bool, token: Int, at fraction: Double) {
        let same = token == self.token && encoding == self.encoding && contentStart == self.contentStart
        self.data = data
        self.encoding = encoding
        self.contentStart = contentStart
        self.preferTab = preferTab
        self.token = token
        if !same { reload() }
        scroll(toFraction: fraction)
    }

    /// The next file starts with detected settings again.
    func resetChoices() {
        separatorChoice = nil
        headerChoice = nil
        malformedOnly = false
        largeSortConfirmed = false
    }

    func setSeparator(_ separator: CSVSeparator?) {
        separatorChoice = separator
        let position = topFraction
        reload()
        scroll(toFraction: position)
    }

    func toggleHeader() {
        headerChoice = !hasHeader
        resetSort()
        refreshTitles()
        recomputeMalformed()
        updateRows()
        reloadTables()
        onStatusChange?()
    }

    func clear() {
        cancelTasks()
        token = nil
        data = Data()
        index = CSVIndex()
        cache = [:]
        malformed = []
        resetSort()
        updateRows()
        removeColumns()
        reloadTables()
    }

    private func cancelTasks() {
        indexTask?.cancel()
        sortTask?.cancel()
        findTask?.cancel()
        indexTask = nil
        sortTask = nil
        findTask = nil
        message = nil
    }

    private func reload() {
        cancelTasks()
        cache = [:]
        found = nil
        pendingFraction = nil
        resetSort()
        if let separatorChoice {
            sample = CSVSample.make(data, dialect: CSVDialect(separator: separatorChoice, encoding: encoding,
                                                              contentStart: contentStart))
        } else {
            sample = CSVSample.detect(data, encoding: encoding, contentStart: contentStart, preferTab: preferTab)
        }
        dialect = CSVDialect(separator: sample.separator, encoding: encoding, contentStart: contentStart)
        index = CSVIndex(start: min(contentStart, data.count))
        malformed = []
        expectedFields = 0
        removeColumns()
        // The sampled rows give the columns at once (and a table without columns takes no focus).
        ensureColumns(sample.rows.map(\.count).max() ?? 0)
        updateRows()
        reloadTables()
        let data = data, dialect = dialect
        indexTask = Task { [weak self] in
            for await snapshot in CSVIndexer.stream(data, dialect: dialect) {
                guard !Task.isCancelled, let self else { return }
                self.apply(snapshot)
            }
        }
        onStatusChange?()
    }

    private func apply(_ snapshot: CSVIndex) {
        let hadHeader = hasHeader
        index = snapshot
        ensureColumns(index.maxFields)
        if wantsFocus, window?.makeFirstResponder(table) == true { wantsFocus = false }
        if hasHeader != hadHeader { refreshTitles() }
        recomputeMalformed()
        updateRows()
        if case .list = rows {
            reloadTables()
        } else {
            table.noteNumberOfRowsChanged()
            gutter.noteNumberOfRowsChanged()
            // Markers can change while reading (the expected field count is still settling).
            gutter.reloadData()
            updateGutterWidth()
        }
        if let fraction = pendingFraction { scroll(toFraction: fraction) }
        if snapshot.isComplete { indexTask = nil }
        onStatusChange?()
    }

    private func recomputeMalformed() {
        malformed = index.malformedRows(excludingFirst: hasHeader)
        expectedFields = index.expectedFields(excludingFirst: hasHeader)
    }

    /// Rebuilds the displayed rows from the sort and the filter.
    private func updateRows() {
        if malformedOnly {
            if let sortedRows {
                let marked = Set(malformed)
                rows = .list(sortedRows.filter(marked.contains))
            } else {
                rows = .list(malformed)
            }
        } else if let sortedRows {
            rows = .list(sortedRows)
        } else {
            rows = .range(firstDataRow..<max(firstDataRow, index.rowCount))
        }
    }

    private func reloadTables() {
        table.reloadData()
        gutter.reloadData()
        updateGutterWidth()
    }

    // MARK: Columns

    private func removeColumns() {
        for column in table.tableColumns { table.removeTableColumn(column) }
    }

    private func ensureColumns(_ count: Int) {
        guard table.tableColumns.count < count else { return }
        for number in table.tableColumns.count..<count {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(number)))
            column.title = title(of: number)
            column.width = width(of: number)
            column.minWidth = 24
            column.maxWidth = 10_000
            column.headerCell.alignment = sample.numericColumns.contains(number) ? .right : .left
            table.addTableColumn(column)
        }
    }

    private func refreshTitles() {
        for column in table.tableColumns {
            if let number = Int(column.identifier.rawValue) { column.title = title(of: number) }
        }
        table.headerView?.needsDisplay = true
    }

    private func title(of column: Int) -> String {
        if hasHeader, let header = sample.rows.first, column < header.count {
            return Self.shown(header[column], limit: 200)
        }
        return String(column + 1)
    }

    /// From the title and the sampled cells, between 40 and 400 points.
    private func width(of column: Int) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var widest = (title(of: column) as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: fontSize)]).width
        for row in sample.rows.prefix(200) where column < row.count {
            let text = Self.shown(row[column], limit: 80)
            widest = max(widest, (text as NSString).size(withAttributes: attributes).width)
        }
        return min(max(ceil(widest) + 16, 40), 400)
    }

    private func applyFont() {
        let height = ceil(NSLayoutManager().defaultLineHeight(for: font)) + 4
        table.rowHeight = height
        gutter.rowHeight = height
        reloadTables()
    }

    private func updateGutterWidth() {
        let last = max(index.rowCount, 1)
        let digits = CGFloat(String(last).count)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)]
        let digit = ("0" as NSString).size(withAttributes: attributes).width
        let marker = malformed.isEmpty ? 0 : ("⚠ " as NSString).size(withAttributes: attributes).width
        // Digits with group separators, the marker and the cell's insets.
        let width = ceil((digits + digits / 3) * digit + marker + 20)
        guard abs(gutterWidth.constant - width) > 0.5 else { return }
        gutterWidth.constant = width
        gutter.tableColumns.first?.width = width - gutter.intercellSpacing.width
    }

    // MARK: Rows

    private func fields(of row: Int) -> [String] {
        if let cached = cache[row] { return cached }
        if cache.count >= Self.cacheLimit { cache.removeAll(keepingCapacity: true) }
        let fields = CSVRow.fields(in: data, index: index, row: row, dialect: dialect)
        cache[row] = fields
        return fields
    }

    /// One line: line breaks as ↵, long text cut.
    private static func shown(_ text: String, limit: Int = shownCharacters) -> String {
        var result = text.utf8.count > limit * 4 || text.count > limit ? String(text.prefix(limit)) + "…" : text
        if result.contains(where: \.isNewline) {
            result = result.replacingOccurrences(of: "\r\n", with: "↵")
                .replacingOccurrences(of: "\r", with: "↵").replacingOccurrences(of: "\n", with: "↵")
        }
        return result
    }

    private static func tooltip(_ text: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard text.utf8.count > tooltipCharacters, text.count > tooltipCharacters else { return text }
        return String(text.prefix(tooltipCharacters)) + "\n" + String(localized: "… (the field is longer)")
    }

    /// The row number shown for a file row (data rows count from 1, the header is not counted).
    func displayNumber(of row: Int) -> Int { row + 1 - firstDataRow }

    func isMalformed(_ row: Int) -> Bool {
        var low = 0, high = malformed.count
        while low < high {
            let mid = (low + high) / 2
            if malformed[mid] < row { low = mid + 1 } else { high = mid }
        }
        return low < malformed.count && malformed[low] == row
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row position: Int) -> NSView? {
        guard position < rows.count else { return nil }
        let row = rows[position]
        let field = cellField(in: tableView)
        if tableView === gutter {
            let number = Format.grouped(Int64(displayNumber(of: row)))
            if isMalformed(row) {
                let count = Int(index.fieldCounts[row])
                field.stringValue = "⚠ " + number
                field.textColor = .systemOrange
                if count == expectedFields {
                    // Marked for its unclosed quote, not for its field count.
                    field.toolTip = String(localized: "Row \(number) opens a quote that is never closed; the quote is read as text.")
                    field.setAccessibilityLabel(String(localized: "Row \(number), malformed: unclosed quote"))
                } else {
                    field.toolTip = String(localized: "Row \(number) has \(count) fields; most rows have \(expectedFields).")
                    field.setAccessibilityLabel(String(localized: "Row \(number), malformed: \(count) of \(expectedFields) fields"))
                }
            } else {
                field.stringValue = number
                field.textColor = .secondaryLabelColor
                field.toolTip = nil
                field.setAccessibilityLabel(String(localized: "Row \(number)"))
            }
            field.alignment = .right
            field.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
            return field
        }
        guard let tableColumn, let column = Int(tableColumn.identifier.rawValue) else { return nil }
        let cells = fields(of: row)
        let text = column < cells.count ? cells[column] : ""
        field.stringValue = Self.shown(text)
        field.toolTip = Self.tooltip(text)
        field.textColor = .labelColor
        field.font = font
        field.alignment = sample.numericColumns.contains(column) ? .right : .left
        let isFound = found.map { $0.row == row && $0.column == column } ?? false
        field.drawsBackground = isFound
        field.backgroundColor = isFound ? .findHighlightColor : .clear
        return field
    }

    private func cellField(in tableView: NSTableView) -> NSTextField {
        let id = NSUserInterfaceItemIdentifier("cell")
        if let field = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField { return field }
        let field = NSTextField(labelWithString: "")
        field.identifier = id
        field.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        field.maximumNumberOfLines = 1
        return field
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard tableView === gutter else { return true }
        // A click on a row number selects that row of the table.
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        window?.makeFirstResponder(table)
        return false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (notification.object as? NSTableView) === table else { return }
        gutter.selectRowIndexes(table.selectedRowIndexes, byExtendingSelection: false)
        if !selectingFound, let previous = found {
            found = nil
            reload(fileRow: previous.row)
        }
        onStatusChange?()
    }

    private func reload(fileRow row: Int) {
        guard let position = rows.position(of: row) else { return }
        table.reloadData(forRowIndexes: IndexSet(integer: position), columnIndexes: IndexSet(0..<table.numberOfColumns))
    }

    @objc private func tableScrolled(_ note: Notification) {
        let origin = scroll.contentView.bounds.origin
        gutterScroll.contentView.scroll(to: NSPoint(x: 0, y: origin.y))
        gutterScroll.reflectScrolledClipView(gutterScroll.contentView)
    }

    // MARK: Selection and position

    /// File rows of the selection, in display order.
    private var selectedFileRows: [Int] { table.selectedRowIndexes.filter { $0 < rows.count }.map { rows[$0] } }

    /// Selects a file row and scrolls it into view; false when it is not shown.
    @discardableResult
    func select(fileRow row: Int) -> Bool {
        guard let position = rows.position(of: row) else { return false }
        table.selectRowIndexes(IndexSet(integer: position), byExtendingSelection: false)
        table.scrollRowToVisible(position)
        return true
    }

    /// Go to Row: a row number as shown (in a filtered view, the nearest shown row).
    func goTo(rowNumber number: Int) -> Bool {
        let row = number - 1 + firstDataRow
        guard number > 0, row < index.rowCount else { return false }
        if select(fileRow: row) { return true }
        guard malformedOnly, sortedRows == nil, !malformed.isEmpty else { return false }
        let nearest = malformed.min { abs($0 - row) < abs($1 - row) } ?? malformed[0]
        return select(fileRow: nearest)
    }

    /// Where the first visible row starts, as a fraction of the file.
    var topFraction: Double {
        guard !data.isEmpty, rows.count > 0 else { return 0 }
        let position = min(max(table.rows(in: table.visibleRect).location, 0), rows.count - 1)
        return Double(index.rowStarts[rows[position]]) / Double(data.count)
    }

    /// Puts the row holding `fraction` of the file at the top, once it has been read.
    private func scroll(toFraction fraction: Double) {
        guard fraction > 0, !data.isEmpty else { pendingFraction = nil; return }
        let offset = Int(fraction * Double(data.count))
        guard index.isComplete || (index.rowStarts.last ?? 0) > offset else {
            pendingFraction = fraction
            return
        }
        pendingFraction = nil
        let row = index.row(containing: offset)
        guard let position = rows.position(of: max(row, firstDataRow)) else { return }
        // Past the row first, then back: the row ends up at the top of the view.
        let visible = table.rows(in: table.visibleRect).length
        table.scrollRowToVisible(min(position + max(visible - 1, 0), rows.count - 1))
        table.scrollRowToVisible(position)
    }

    // MARK: Malformed rows

    /// The next (or previous) malformed row in display order from the selection, if any.
    private func malformedTarget(backward: Bool) -> Int? {
        guard !malformed.isEmpty, rows.count > 0 else { return nil }
        let position = table.selectedRow
        if sortedRows == nil {
            let current = position >= 0 && position < rows.count ? rows[position] : (backward ? Int.max : -1)
            return backward ? malformed.last(where: { $0 < current }) : malformed.first(where: { $0 > current })
        }
        let stride = backward ? Swift.stride(from: (position < 0 ? rows.count : position) - 1, through: 0, by: -1)
                              : Swift.stride(from: position + 1, through: rows.count - 1, by: 1)
        for at in stride where isMalformed(rows[at]) { return rows[at] }
        return nil
    }

    func canMoveToMalformed(backward: Bool) -> Bool { malformedTarget(backward: backward) != nil }

    func moveToMalformed(backward: Bool) -> Bool {
        guard let row = malformedTarget(backward: backward) else { return false }
        return select(fileRow: row)
    }

    func toggleMalformedOnly() {
        let selection = selectedFileRows
        malformedOnly.toggle()
        updateRows()
        reloadTables()
        restore(selection)
        onStatusChange?()
    }

    private func restore(_ selection: [Int]) {
        let wanted = selection.prefix(1_000)
        var positions = IndexSet()
        if case .list(let list) = rows, wanted.count > 1 {
            // One pass instead of a search per row.
            let lookup = Set(wanted)
            for (position, row) in list.enumerated() where lookup.contains(row) { positions.insert(position) }
        } else {
            positions = IndexSet(wanted.compactMap { rows.position(of: $0) })
        }
        table.selectRowIndexes(positions, byExtendingSelection: false)
        if let first = positions.first { table.scrollRowToVisible(first) }
    }

    // MARK: Sorting

    private func resetSort() {
        sortTask?.cancel()
        sortTask = nil
        sort = nil
        sortedRows = nil
        for column in table.tableColumns { table.setIndicatorImage(nil, in: column) }
        table.highlightedTableColumn = nil
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard tableView === table, let column = Int(tableColumn.identifier.rawValue) else { return }
        guard index.isComplete else {
            setMessage(String(localized: "Sorting is available once the file is fully loaded."))
            return
        }
        let next: (column: Int, ascending: Bool)? = switch sort {
        case let current? where current.column == column: current.ascending ? (column, false) : nil
        default: (column, true)
        }
        guard let next else {
            let selection = selectedFileRows
            resetSort()
            updateRows()
            reloadTables()
            restore(selection)
            return
        }
        if data.count > Self.largeSortSize, !largeSortConfirmed {
            confirmLargeSort(title: tableColumn.title) { [weak self] in
                self?.largeSortConfirmed = true
                self?.startSort(next)
            }
            return
        }
        startSort(next)
    }

    private func confirmLargeSort(title: String, then proceed: @escaping () -> Void) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Sort by “\(title)”?")
        alert.informativeText = String(localized: "Sorting keeps this column's values in memory and may use a lot of it.")
        alert.addButton(withTitle: String(localized: "Sort"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { proceed() }
        }
    }

    private func startSort(_ next: (column: Int, ascending: Bool)) {
        sortTask?.cancel()
        setMessage(String(localized: "Sorting…"))
        let data = data, index = index, dialect = dialect
        let range = firstDataRow..<max(firstDataRow, index.rowCount)
        let numeric = sample.numericColumns.contains(next.column)
        sortTask = Task { [weak self] in
            let work = Task.detached(priority: .userInitiated) {
                try await CSVSort.order(data, index: index, dialect: dialect, rows: range, column: next.column,
                                        numeric: numeric, ascending: next.ascending)
            }
            let order = await withTaskCancellationHandler { try? await work.value } onCancel: { work.cancel() }
            guard let self, !Task.isCancelled, let order else { return }
            let selection = self.selectedFileRows
            self.sort = next
            self.sortedRows = order.map(Int.init)
            for column in self.table.tableColumns {
                let sorted = Int(column.identifier.rawValue) == next.column
                self.table.setIndicatorImage(sorted ? NSImage(named: next.ascending ? "NSAscendingSortIndicator"
                                                                                    : "NSDescendingSortIndicator") : nil,
                                             in: column)
                if sorted { self.table.highlightedTableColumn = column }
            }
            self.updateRows()
            self.reloadTables()
            self.restore(selection)
            self.sortTask = nil
            self.setMessage(nil)
        }
    }

    // MARK: Find, copy, cancel

    /// Finds the next (previous) cell containing `query` in display order; beeps when there is none.
    func find(_ query: String, ignoreCase: Bool, backward: Bool) {
        guard !query.isEmpty, rows.count > 0 else { return }
        findTask?.cancel()
        setMessage(String(localized: "Searching…"))
        let data = data, index = index, dialect = dialect, rows = rows, start = table.selectedRow
        // From the cell found last when it is in the selected row, so F3 goes on within that row.
        let column = start >= 0 && start < rows.count ? found.flatMap { $0.row == rows[start] ? $0.column : nil } : nil
        let report: @Sendable (Int) -> Void = { [weak self] percent in
            Task { @MainActor in
                guard let self, self.findTask != nil else { return }
                self.setMessage(String(localized: "Searching…") + " \(percent) %")
            }
        }
        findTask = Task { [weak self] in
            let work = Task.detached(priority: .userInitiated) { () -> CSVSearch.Match? in
                var reported = ContinuousClock.now
                return try CSVSearch.find(query, ignoreCase: ignoreCase, in: data, index: index, dialect: dialect,
                                          rows: rows, from: start, column: column, backward: backward) { done in
                    guard ContinuousClock.now - reported > .milliseconds(200) else { return }
                    reported = .now
                    report(Int(done * 100))
                }
            }
            let result = await withTaskCancellationHandler { try? await work.value } onCancel: { work.cancel() }
            guard let self, !Task.isCancelled else { return }
            self.findTask = nil
            guard let match = result ?? nil, match.position < self.rows.count else {
                NSSound.beep()
                self.setMessage(String(localized: "Not found."))
                return
            }
            let row = self.rows[match.position]
            let previous = self.found
            self.found = (row, match.column)
            self.selectingFound = true
            self.select(fileRow: row)
            self.selectingFound = false
            if let previous { self.reload(fileRow: previous.row) }
            self.reload(fileRow: row)
            if let column = self.table.tableColumns.firstIndex(where: { $0.identifier.rawValue == String(match.column) }) {
                self.table.scrollColumnToVisible(column)
            }
            self.setMessage(nil)
        }
    }

    /// ⌘C: the selected rows as tab-separated text.
    func copySelection() {
        let selected = selectedFileRows
        guard !selected.isEmpty else { return }
        let literal = index.literalQuotes
        let text = CSVClipboard.tsv(selected.map {
            CSVRow.fields(in: data, range: index.range(ofRow: $0), dialect: dialect, literalQuotes: literal)
        })
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Esc: stops a running search or sort; false when nothing was running.
    func cancelWork() -> Bool {
        guard findTask != nil || sortTask != nil else { return false }
        findTask?.cancel()
        sortTask?.cancel()
        findTask = nil
        sortTask = nil
        setMessage(nil)
        return true
    }

    private func setMessage(_ text: String?) {
        message = text
        onStatusChange?()
    }

    // MARK: Status

    /// Rows, columns, malformed rows and an unclosed quote, for the viewer's status bar.
    var statusParts: [String] {
        let dataRows = Format.grouped(Int64(max(index.rowCount - firstDataRow, 0)))
        var parts = [index.isComplete ? String(localized: "\(dataRows) rows") : String(localized: "counting… \(dataRows) rows"),
                     String(localized: "\(index.maxFields) columns")]
        if !malformed.isEmpty {
            parts.append(String(localized: "\(Format.grouped(Int64(malformed.count))) malformed rows (expected \(expectedFields) fields)"))
        }
        if let quote = index.unclosedQuotes.first {
            parts.append(String(localized: "unclosed quote in row \(Format.grouped(Int64(displayNumber(of: quote.row))))"))
        }
        if let message { parts.append(message) }
        return parts
    }

    var hasRows: Bool { rows.count > 0 }
    var hasSelection: Bool { table.selectedRow >= 0 }
}
