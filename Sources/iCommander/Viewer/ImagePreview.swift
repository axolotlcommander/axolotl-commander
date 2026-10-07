import AppKit
import CommanderCore
import ImageIO

/// Keeps a document smaller than the visible area in its middle.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }
        let frame = document.frame
        if rect.width > frame.width { rect.origin.x = (frame.width - rect.width) / 2 }
        if rect.height > frame.height { rect.origin.y = (frame.height - rect.height) / 2 }
        return rect
    }
}

/// The picture itself; it holds the keyboard focus of the image preview.
final class PictureView: NSImageView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if (enclosingScrollView as? ImagePreview)?.handleKey(event) != true { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { (enclosingScrollView as? ImagePreview)?.toggleFit() }
    }
}

/// The picture of the image viewer: fitted to the window until the user zooms,
/// ← → to the previous and next picture while nothing is scrolled sideways.
final class ImagePreview: NSScrollView {
    /// A decoded picture, ready for the main actor.
    private struct Decoded: @unchecked Sendable {
        var image: NSImage?
        var info: ImageInfo?
    }

    /// Larger pictures are shown downsampled (the zoom still refers to the real pixels).
    private nonisolated static let maxDecodedPixels = 16_384
    static let zoomSteps: [Double] = [0.05, 0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.5, 2, 3, 4, 6, 8, 12, 16]

    private let imageView = PictureView()
    /// The view to focus for the viewer keys.
    var keyView: NSView { imageView }
    private(set) var info: ImageInfo?
    /// True while the picture follows the window size.
    private(set) var fits = true
    private var loadTask: Task<Void, Never>?
    var onKey: ((NSEvent) -> Bool)?
    /// ← and → asking for the previous (`true`) or next picture.
    var onArrow: ((_ previous: Bool) -> Void)?
    var onZoomChange: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        contentView = CenteringClipView()
        imageView.imageScaling = .scaleAxesIndependently
        imageView.animates = true
        imageView.isEditable = false
        documentView = imageView
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = Self.zoomSteps.first!
        maxMagnification = Self.zoomSteps.last!
        backgroundColor = .underPageBackgroundColor
        drawsBackground = true
        NotificationCenter.default.addObserver(self, selector: #selector(userMagnified),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ url: URL) {
        loadTask?.cancel()
        loadTask = Task {
            let decoded = await Task.detached(priority: .userInitiated) { Self.decode(url) }.value
            guard !Task.isCancelled else { return }
            info = decoded.info
            imageView.image = decoded.image
            let size = decoded.info.map { NSSize(width: $0.width, height: $0.height) } ?? decoded.image?.size ?? .zero
            imageView.frame = NSRect(origin: .zero, size: size)
            fits = true
            fit()
        }
    }

    func clear() {
        loadTask?.cancel()
        imageView.image = nil
        info = nil
    }

    /// Animations (several frames) go through NSImage; still pictures are decoded by ImageIO
    /// with the EXIF orientation applied.
    private nonisolated static func decode(_ url: URL) -> Decoded {
        let info = ImageInfo.read(url)
        guard let info else { return Decoded(image: NSImage(contentsOf: url), info: nil) }
        if info.frames > 1, let image = NSImage(contentsOf: url) { return Decoded(image: image, info: info) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return Decoded(image: nil, info: info) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: min(max(info.width, info.height), maxDecodedPixels),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return Decoded(image: NSImage(contentsOf: url), info: info)
        }
        return Decoded(image: NSImage(cgImage: cgImage, size: NSSize(width: info.width, height: info.height)), info: info)
    }

    // MARK: Zoom

    var zoom: Double { magnification }

    /// Large pictures shrink to the window; small ones stay at 100 %.
    func fit() {
        fits = true
        let size = imageView.frame.size
        guard size.width > 0, size.height > 0 else { return }
        let area = contentSize
        let scale = min(1, area.width / size.width, area.height / size.height)
        magnification = max(scale, minMagnification)
        onZoomChange?()
    }

    func zoom(to value: Double) {
        fits = false
        let center = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        setMagnification(min(max(value, minMagnification), maxMagnification), centeredAt: center)
        onZoomChange?()
    }

    func zoomIn() { zoom(to: Self.zoomSteps.first { $0 > magnification + 0.001 } ?? maxMagnification) }
    func zoomOut() { zoom(to: Self.zoomSteps.last { $0 < magnification - 0.001 } ?? minMagnification) }

    @objc private func userMagnified() {
        fits = false
        onZoomChange?()
    }

    override func layout() {
        super.layout()
        if fits { fit() }
    }

    // MARK: Keys, mouse

    /// Nothing to scroll sideways, so ← → may switch pictures.
    private var fitsHorizontally: Bool { imageView.frame.width * magnification <= contentSize.width + 0.5 }

    /// Viewer keys first, then ← → for the previous and next picture; false lets the view scroll.
    func handleKey(_ event: NSEvent) -> Bool {
        if onKey?(event) == true { return true }
        if let key = event.specialKey, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           key == .leftArrow || key == .rightArrow, fitsHorizontally {
            onArrow?(key == .leftArrow)
            return true
        }
        return false
    }

    /// Double click: 100 % ⇄ fitted.
    func toggleFit() {
        if fits { zoom(to: 1) } else { fit() }
    }
}
