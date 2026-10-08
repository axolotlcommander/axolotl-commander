// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import SwiftUI

/// ⌃F2 Change Attributes: the permissions and attributes editor of Get Info, on its own.
struct AttributesSheetView: View {
    let urls: [URL]
    let edit: AttributeEdit
    /// Applies a change; nil = cancelled.
    let onClose: (AttributeChange?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: icon).resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Change Attributes").font(.headline)
                    Text(urls.count == 1 ? urls[0].lastPathComponent : String(localized: "\(urls.count) items"))
                        .foregroundStyle(.secondary).lineLimit(2)
                }
            }
            GroupBox {
                AttributesEditView(edit: edit) { onClose(edit.hasChanges ? edit.change : nil) }.padding(6)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onClose(nil) }.keyboardShortcut(.cancelAction)
                Button("Apply") { onClose(edit.hasChanges ? edit.change : nil) }
                    .keyboardShortcut(.defaultAction).disabled(!edit.hasChanges)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private var icon: NSImage {
        urls.count == 1 ? NSWorkspace.shared.icon(forFile: urls[0].path(percentEncoded: false))
            : NSImage(named: NSImage.multipleDocumentsName) ?? NSImage()
    }
}

enum AttributesSheet {
    /// `onChange` runs after attributes were changed (e.g. to refresh the panels).
    static func show(_ urls: [URL], in window: NSWindow?, onChange: (() -> Void)? = nil) {
        guard let window, !urls.isEmpty else { return }
        let summary: AttributeSummary
        do {
            summary = try AttributeSummary.read(urls)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "The attributes could not be read.")
            alert.informativeText = OperationsController.describe(error)
            Task { _ = await OperationsController.present(alert, in: window) }
            return
        }
        var sheet: NSWindow?
        let view = AttributesSheetView(urls: urls, edit: AttributeEdit(summary)) { change in
            if let sheet { window.endSheet(sheet) }
            guard let change else { return }
            Task { await PropertiesSheet.apply(change, to: urls, in: window, onChange: onChange) }
        }
        let host = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = host
        window.beginSheet(host, completionHandler: nil)
    }
}
