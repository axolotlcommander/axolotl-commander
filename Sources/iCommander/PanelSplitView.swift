import AppKit

/// Split between the two panels. Double-clicking the divider makes both panels equally wide,
/// as in the Windows commander.
final class PanelSplitView: NSSplitView {
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, let first = arrangedSubviews.first, !first.isHidden,
           abs(point.x - first.frame.maxX - dividerThickness / 2) <= 4 {
            equalize()
            return
        }
        super.mouseDown(with: event)
    }

    func equalize() {
        setPosition(((bounds.width - dividerThickness) / 2).rounded(), ofDividerAt: 0)
    }
}

final class PanelSplitViewController: NSSplitViewController {
    init() {
        super.init(nibName: nil, bundle: nil)
        let view = PanelSplitView()
        view.isVertical = true
        view.dividerStyle = .thin
        splitView = view
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
