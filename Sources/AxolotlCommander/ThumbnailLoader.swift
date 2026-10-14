// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import QuickLookThumbnailing

/// Makes the previews of a panel's Thumbnails view with the system's thumbnail service (spec 025): a few
/// requests at a time, the visible cells first, cancelled when their cells scroll away. The pictures stay in
/// memory only; nothing is written to disk.
@MainActor
final class ThumbnailLoader {
    /// Shared by both panels: 256 MB of decoded pictures.
    private static var cache = ThumbnailCache<NSImage>(costLimit: 256 << 20)
    /// Items the service could not preview; they keep their icon and are not asked again.
    private static var failed = Set<ThumbnailKey>()

    /// Called with each made preview.
    var onImage: ((ThumbnailKey, NSImage) -> Void)?
    /// The backing scale of the window, for sharp previews on Retina screens.
    var scale: CGFloat = 2

    private var queue = ThumbnailQueue(limit: 4)
    private var requests: [ThumbnailKey: QLThumbnailGenerator.Request] = [:]
    private var urls: [ThumbnailKey: URL] = [:]

    static func cached(_ key: ThumbnailKey) -> NSImage? { cache.value(for: key) }

    /// The previews wanted now, most important first; whatever is not wanted any more is cancelled.
    func want(_ wanted: [(key: ThumbnailKey, url: URL)]) {
        let missing = wanted.filter { !Self.cache.contains($0.key) && !Self.failed.contains($0.key) }
        urls = Dictionary(missing.map { ($0.key, $0.url) }, uniquingKeysWith: { first, _ in first })
        let (start, cancel) = queue.want(missing.map(\.key))
        for key in cancel {
            if let request = requests.removeValue(forKey: key) { QLThumbnailGenerator.shared.cancel(request) }
        }
        start.forEach(begin)
    }

    private func begin(_ key: ThumbnailKey) {
        guard let url = urls[key] else {
            queue.finished(key).forEach(begin)
            return
        }
        let side = CGFloat(key.size.points)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: side, height: side), scale: scale,
                                                   representationTypes: [.icon, .thumbnail])
        requests[key] = request
        let id = ObjectIdentifier(request)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let picture = representation.map { Picture(image: $0.cgImage) }
            Task { @MainActor in self?.finished(key, request: id, picture: picture) }
        }
    }

    private func finished(_ key: ThumbnailKey, request id: ObjectIdentifier, picture: Picture?) {
        // A cancelled request (or one replaced by a newer one for the same key) ends without a trace.
        guard let request = requests[key], ObjectIdentifier(request) == id else { return }
        requests[key] = nil
        if let cgImage = picture?.image {
            let image = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale,
                                                               height: CGFloat(cgImage.height) / scale))
            Self.cache.insert(image, for: key, cost: cgImage.width * cgImage.height * 4)
            onImage?(key, image)
        } else {
            if Self.failed.count > 50_000 { Self.failed.removeAll() }
            Self.failed.insert(key)
        }
        queue.finished(key).forEach(begin)
    }
}

/// A made picture handed from the service's queue to the main actor (a CGImage is immutable).
private struct Picture: @unchecked Sendable {
    let image: CGImage
}
