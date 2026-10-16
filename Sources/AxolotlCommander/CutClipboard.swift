// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The files cut with Cut Files (spec 033). The pasteboard holds them as an ordinary file list; this app
/// remembers that they were cut, for as long as the pasteboard keeps what Cut wrote. The pasteboard has no
/// change notification, so its change count is checked once a second while a cut exists and when the app
/// becomes active.
@MainActor
final class CutClipboard {
    static let shared = CutClipboard()
    /// Posted when the cut items change: the panels redraw them.
    static let didChangeNotification = Notification.Name("CutClipboardDidChange")

    private var cutSet: CutSet?
    private var timer: Timer?
    private var activation: (any NSObjectProtocol)?
    private var pasteboard: NSPasteboard { .general }

    func cut(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        write(urls)
        changed()
    }

    func isCut(_ url: URL) -> Bool {
        cutSet?.contains(url, changeCount: pasteboard.changeCount) == true
    }

    func pasteAction(for urls: [URL], destination: URL) -> CutSet.PasteAction {
        cutSet?.pasteAction(for: urls, destination: destination, changeCount: pasteboard.changeCount) ?? .copy
    }

    /// After a paste moved the cut items: the ones still at their place stay cut, the rest leave the
    /// pasteboard. Nothing changes when the pasteboard got new content meanwhile.
    func settle() {
        guard let cutSet, cutSet.isActive(changeCount: pasteboard.changeCount) else { return check() }
        let rest = cutSet.remaining { (try? FileManager.default.attributesOfItem(atPath: $0.path(percentEncoded: false))) != nil }
        if rest.isEmpty {
            pasteboard.clearContents()
            self.cutSet = nil
            stopWatching()
        } else {
            write(rest)
        }
        changed()
    }

    private func write(_ urls: [URL]) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        cutSet = CutSet(urls: urls, changeCount: pasteboard.changeCount)
        startWatching()
    }

    /// The pasteboard changed elsewhere: the cut ends.
    func check() {
        guard let cutSet, !cutSet.isActive(changeCount: pasteboard.changeCount) else { return }
        self.cutSet = nil
        stopWatching()
        changed()
    }

    private func startWatching() {
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { CutClipboard.shared.check() }
            }
        }
        if activation == nil {
            activation = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { CutClipboard.shared.check() }
            }
        }
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        if let activation { NotificationCenter.default.removeObserver(activation) }
        activation = nil
    }

    private func changed() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
