// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import AppKit
import CommanderCore
import Quartz

/// Quick Look for F3 / ⌘Y: previews the marked items, or follows the cursor when nothing is marked.
/// The panel controller is found through the responder chain (table → panel view controller).
extension PanelViewController: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    private var quickLookPanel: QLPreviewPanel? {
        QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
    }

    /// True while the Quick Look panel is shown for this panel.
    var isQuickLooking: Bool {
        guard let panel = quickLookPanel, panel.isVisible else { return false }
        return (panel.currentController as AnyObject?) === self
    }

    func toggleQuickLook() {
        if let panel = quickLookPanel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        previewURLs = targets().map(\.url)
        guard !previewURLs.isEmpty else { NSSound.beep(); return }
        QLPreviewPanel.shared()?.makeKeyAndOrderFront(nil)
    }

    /// Called after the cursor or selection changed.
    func updateQuickLook() {
        guard isQuickLooking, let panel = quickLookPanel else { return }
        let urls = targets().map(\.url)
        guard urls != previewURLs else { return }
        previewURLs = urls
        panel.reloadData()
    }

    // QLPreviewPanelController is a nonisolated NSObject category; Quick Look calls it on the main thread.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURLs[index] as NSURL
    }

    /// Keys typed while the preview is key go to the panel, so arrows move the cursor
    /// and the preview follows. Esc, F3 and ⌘Y close it.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        if let chord = KeyChord(event: event) {
            let command = KeyMaps.panel.command(for: chord)
            if chord.key == .escape || command == .view || command == .quickLook {
                panel.orderOut(nil)
                return true
            }
        }
        listView.keyDown(with: event)
        return true
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let url = item as? URL ?? (item as? NSURL) as URL?,
              let row = model.items.firstIndex(where: { $0.url == url }),
              let window = view.window else { return .zero }
        let rect = viewMode == .brief
            ? briefView.convert(briefView.frameForItem(at: row), to: nil)
            : tableView.convert(tableView.frameOfCell(atColumn: 0, row: row), to: nil)
        return window.convertToScreen(rect)
    }
}
