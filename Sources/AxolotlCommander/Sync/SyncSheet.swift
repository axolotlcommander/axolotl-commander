// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import SwiftUI

/// ⌥⇧F10 options (spec 023): the two folders, what counts as different, the direction and deleting.
/// They are saved; Return compares, Esc cancels.
struct SyncOptionsView: View {
    @Bindable var settings = AppSettings.shared
    let left: URL
    let right: URL
    let onCompare: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Synchronize Folders").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("Left:").foregroundStyle(.secondary)
                    Text(left.displayPath).lineLimit(1).truncationMode(.middle)
                }
                GridRow {
                    Text("Right:").foregroundStyle(.secondary)
                    Text(right.displayPath).lineLimit(1).truncationMode(.middle)
                }
            }
            Toggle("Include subfolders", isOn: $settings.sync.includeSubfolders)
            Text("Files in both folders differ by:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Date and time (up to 2 seconds apart counts as equal)", isOn: $settings.sync.compareDate)
                Toggle("Ignore a difference of exactly one hour", isOn: $settings.sync.ignoreHourDifference)
                    .disabled(!settings.sync.compareDate)
                    .padding(.leading, 20)
                Toggle("Size", isOn: $settings.sync.compareSize)
                Toggle("Content (slow)", isOn: $settings.sync.compareContent)
            }
            Form {
                TextField("Ignore files:", text: optional(\.ignoreFiles), prompt: Text("e.g. .DS_Store;*.tmp"))
                TextField("Ignore folders:", text: optional(\.ignoreFolders), prompt: Text("e.g. .git;node_modules"))
                Picker("Direction:", selection: $settings.sync.direction) {
                    Text("Both ways").tag(SyncDirection.bothWays)
                    Text("Left to right").tag(SyncDirection.leftToRight)
                    Text("Right to left").tag(SyncDirection.rightToLeft)
                }
                .pickerStyle(.radioGroup)
            }
            Toggle(deleteTitle, isOn: $settings.sync.deleteMissing)
                .disabled(settings.sync.direction == .bothWays)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Compare", action: onCompare).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var deleteTitle: String {
        settings.sync.direction == .rightToLeft
            ? String(localized: "Delete items missing on the right (to the Trash)")
            : String(localized: "Delete items missing on the left (to the Trash)")
    }

    private func optional(_ path: WritableKeyPath<SyncOptions, String?>) -> Binding<String> {
        Binding(get: { settings.sync[keyPath: path] ?? "" },
                set: { settings.sync[keyPath: path] = $0.isEmpty ? nil : $0 })
    }
}

enum SyncSheet {
    static func show(in window: NSWindow, left: URL, right: URL, onCompare: @escaping () -> Void) {
        var sheet: NSWindow?
        let view = SyncOptionsView(
            left: left, right: right,
            onCompare: { if let sheet { window.endSheet(sheet) }; onCompare() },
            onCancel: { if let sheet { window.endSheet(sheet) } })
        let host = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = host
        window.beginSheet(host, completionHandler: nil)
    }
}
