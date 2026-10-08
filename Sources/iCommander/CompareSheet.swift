// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import AppKit
import CommanderCore
import SwiftUI

/// ⌃F10 options; Enter compares with the remembered options.
struct CompareOptionsView: View {
    @Bindable var settings = AppSettings.shared
    let onCompare: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare Panels").font(.headline)
            Text("Files only in one panel are always selected. For files in both:")
                .foregroundStyle(.secondary)
            Toggle("Select the newer file (date and time)", isOn: $settings.comparison.compareDate)
            Toggle("Select the larger file", isOn: $settings.comparison.compareSize)
            Toggle("Select folders found in one panel only", isOn: $settings.comparison.selectDirectoriesOnlyInOnePanel)
            Form {
                TextField("Ignore files:", text: optional(\.ignoreFiles), prompt: Text("e.g. .DS_Store;*.tmp"))
                TextField("Ignore folders:", text: optional(\.ignoreDirectories), prompt: Text("e.g. .git;node_modules"))
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Compare", action: onCompare).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func optional(_ path: WritableKeyPath<ComparisonOptions, String?>) -> Binding<String> {
        Binding(get: { settings.comparison[keyPath: path] ?? "" },
                set: { settings.comparison[keyPath: path] = $0.isEmpty ? nil : $0 })
    }
}

enum CompareSheet {
    static func show(in window: NSWindow?, onCompare: @escaping () -> Void) {
        guard let window else { return }
        var sheet: NSWindow?
        let view = CompareOptionsView(
            onCompare: { if let sheet { window.endSheet(sheet) }; onCompare() },
            onCancel: { if let sheet { window.endSheet(sheet) } })
        let host = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = host
        window.beginSheet(host, completionHandler: nil)
    }
}
