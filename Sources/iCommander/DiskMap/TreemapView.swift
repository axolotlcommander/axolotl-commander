import AppKit
import CommanderCore
import UniformTypeIdentifiers

/// Kinds of files the disk map colors differently.
enum DiskMapKind: CaseIterable {
    case folder, image, video, audio, archive, code, document, application, other

    static func of(_ node: DiskUsageNode) -> DiskMapKind {
        if node.isPackage { return node.url.pathExtension.lowercased() == "app" ? .application : .other }
        if node.isDirectory { return .folder }
        guard let type = UTType(filenameExtension: node.url.pathExtension) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archive }
        if type.conforms(to: .sourceCode) || type.conforms(to: .script) || type.conforms(to: .json) { return .code }
        if type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .presentation)
            || type.conforms(to: .spreadsheet) { return .document }
        if type.conforms(to: .executable) || type.conforms(to: .application) { return .application }
        return .other
    }

    var title: String {
        switch self {
        case .folder: String(localized: "Folders")
        case .image: String(localized: "Images")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .archive: String(localized: "Archives and disk images")
        case .code: String(localized: "Source code")
        case .document: String(localized: "Documents")
        case .application: String(localized: "Applications")
        case .other: String(localized: "Other")
        }
    }

    var color: NSColor {
        switch self {
        case .folder: .systemGray
        case .image: .systemGreen
        case .video: .systemPurple
        case .audio: .systemPink
        case .archive: .systemOrange
        case .code: .systemBlue
        case .document: .systemTeal
        case .application: .systemRed
        case .other: .systemBrown
        }
    }
}

/// The treemap of one folder of a scan: folders as framed boxes with a title, files as colored tiles.
/// Click selects, double click (or Return) enters a folder, ⌫ or ⌘↑ goes up.
final class TreemapView: NSView {
    private static let header = 15.0
    private static let inset = 2.0
    private static let maxDepth = 6

    /// The whole scan; `location` is the index path of the shown folder in it.
    var root: DiskUsageNode? { didSet { location = []; selected = nil; relayout() } }
    private(set) var location: [Int] = []
    /// Index path (from the root) of the selected cell.
    private(set) var selected: [Int]? { didSet { if selected != oldValue { needsDisplay = true; onSelect?() } } }
    private var hovered: [Int]? { didSet { if hovered != oldValue { needsDisplay = true; onHover?() } } }
    private var cells: [Treemap.Cell] = []
    private var kinds: [[Int]: DiskMapKind] = [:]

    var onSelect: (() -> Void)?
    var onHover: (() -> Void)?
    var onLocationChange: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    var shownNode: DiskUsageNode? { root.flatMap { DiskUsage.node(at: location, in: $0) } }
    var selectedNode: DiskUsageNode? { selected.flatMap { path in root.flatMap { DiskUsage.node(at: path, in: $0) } } }
    var hoveredNode: DiskUsageNode? { hovered.flatMap { path in root.flatMap { DiskUsage.node(at: path, in: $0) } } }

    func show(_ path: [Int]) {
        guard let root, let node = DiskUsage.node(at: path, in: root), node.isDirectory else { return }
        location = path
        selected = nil
        hovered = nil
        relayout()
        onLocationChange?()
    }

    func goUp() {
        guard !location.isEmpty else { NSSound.beep(); return }
        let previous = location
        show(Array(location.dropLast()))
        selected = previous
    }

    /// Enters the selected folder (or the folder holding the selected file).
    func enterSelection() {
        guard let path = selected, let node = selectedNode else { return }
        if node.isDirectory, !node.children.isEmpty { show(path) } else if path.count > location.count + 1 { show(Array(path.dropLast())) }
    }

    // MARK: Layout

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    private func relayout() {
        guard let node = shownNode else { cells = []; needsDisplay = true; return }
        let rect = TreemapRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        cells = Treemap.cells(for: node, in: rect, maxDepth: Self.maxDepth, inset: Self.inset,
                              header: Self.header, minSide: 4)
        kinds = [:]
        for cell in cells {
            if let child = DiskUsage.node(at: cell.path, in: node) { kinds[cell.path] = DiskMapKind.of(child) }
        }
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        dirtyRect.fill()
        guard let node = shownNode else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        for cell in cells {
            let rect = NSRect(x: cell.rect.x, y: cell.rect.y, width: cell.rect.width, height: cell.rect.height)
            guard rect.intersects(dirtyRect), rect.width >= 1, rect.height >= 1 else { continue }
            let kind = kinds[cell.path] ?? .other
            let shade = max(0.35, 1 - Double(cell.depth) * 0.1)
            if kind == .folder {
                NSColor(white: 0.18 + 0.06 * Double(min(cell.depth, 5)), alpha: 1).setFill()
                rect.fill()
                if rect.height > Self.header + 2, rect.width > 30, let child = DiskUsage.node(at: cell.path, in: node) {
                    let title = "\(child.name)  \(Format.bytes(child.allocatedSize))" as NSString
                    title.draw(with: NSRect(x: rect.minX + 4, y: rect.minY + 1, width: rect.width - 8, height: Self.header - 2),
                               options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
                }
            } else {
                let base = kind.color.blended(withFraction: 1 - shade, of: .black) ?? kind.color
                if let gradient = NSGradient(starting: base.blended(withFraction: 0.25, of: .white) ?? base, ending: base) {
                    gradient.draw(in: rect, angle: 90)
                }
                NSColor.black.withAlphaComponent(0.35).setStroke()
                NSBezierPath(rect: rect.insetBy(dx: 0.25, dy: 0.25)).stroke()
                if rect.width > 50, rect.height > 14, let child = DiskUsage.node(at: cell.path, in: node) {
                    (child.name as NSString).draw(with: rect.insetBy(dx: 3, dy: 2),
                                                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                                  attributes: attributes)
                }
            }
        }
        for (path, color, width) in [(hovered, NSColor.white.withAlphaComponent(0.7), 1.5),
                                     (selected, NSColor.controlAccentColor, 3.0)] {
            guard let path, path.starts(with: location),
                  let cell = cells.first(where: { $0.path == Array(path.dropFirst(location.count)) }) else { continue }
            color.setStroke()
            let outline = NSBezierPath(rect: NSRect(x: cell.rect.x, y: cell.rect.y, width: cell.rect.width,
                                                    height: cell.rect.height).insetBy(dx: width / 2, dy: width / 2))
            outline.lineWidth = width
            outline.stroke()
        }
    }

    // MARK: Mouse, keys

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    private func path(at event: NSEvent) -> [Int]? {
        let point = convert(event.locationInWindow, from: nil)
        return Treemap.hit(cells, x: point.x, y: point.y).map { location + $0.path }
    }

    override func mouseMoved(with event: NSEvent) { hovered = path(at: event) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        selected = path(at: event)
        if event.clickCount == 2 { enterSelection() }
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        switch event.specialKey {
        case .carriageReturn?, .enter?: if plain { enterSelection() } else { super.keyDown(with: event) }
        case .backspace?: if plain { goUp() } else { super.keyDown(with: event) }
        case .upArrow? where event.modifierFlags.contains(.command): goUp()
        default: super.keyDown(with: event)
        }
    }
}
