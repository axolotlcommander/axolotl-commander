// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import SwiftUI

/// Input of the New Symbolic Link / New Hard Link / Edit Symbolic Link sheet.
@MainActor @Observable final class LinkSheetModel {
    enum Mode { case symbolic, hard, edit }

    static let relativeKey = "links.relativePath"

    let mode: Mode
    /// Number of items to link; with more than one, `destination` is a folder.
    let count: Int
    /// Folder of the edited link (edit mode), for converting between relative and absolute.
    let linkFolder: String?
    var target: String
    /// Full path of the new link (one item), the folder for several items, or the edited link.
    var destination: String
    var relative: Bool {
        didSet {
            guard mode == .edit, let linkFolder, relative != oldValue, !target.isEmpty else { return }
            target = relative
                ? LinkPaths.storedTarget(typed: target, linkFolder: linkFolder, relative: true)
                : LinkPaths.absolute(target, linkFolder: linkFolder)
        }
    }
    /// Inline problem shown under the fields; the sheet stays open.
    var message: String?
    var busy = false

    init(mode: Mode, count: Int, target: String, destination: String, relative: Bool, linkFolder: String? = nil) {
        self.mode = mode
        self.count = count
        self.target = target
        self.destination = destination
        self.relative = relative
        self.linkFolder = linkFolder
    }

    var title: String {
        switch mode {
        case .symbolic: String(localized: "New Symbolic Link")
        case .hard: String(localized: "New Hard Link")
        case .edit: String(localized: "Edit Symbolic Link")
        }
    }
}

struct LinkSheetView: View {
    @Bindable var model: LinkSheetModel
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.title).font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Target:").gridColumnAlignment(.trailing)
                    if model.count > 1 {
                        Text("\(model.count) items").foregroundStyle(.secondary)
                    } else if model.mode == .hard {
                        Text(model.target).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
                    } else {
                        TextField("Target:", text: $model.target).labelsHidden().frame(minWidth: 380, maxWidth: .infinity).accessibilityLabel(Text("Target"))
                            .onSubmit(onConfirm)
                    }
                }
                GridRow {
                    Text(destinationLabel)
                    if model.mode == .edit {
                        Text(model.destination).textSelection(.enabled).lineLimit(3).truncationMode(.middle)
                    } else {
                        TextField(destinationLabel, text: $model.destination).labelsHidden().frame(minWidth: 380, maxWidth: .infinity)
                            .accessibilityLabel(Text(destinationLabel)).onSubmit(onConfirm)
                    }
                }
                if model.mode != .hard {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Toggle("Relative path", isOn: $model.relative)
                    }
                }
            }
            if let message = model.message {
                Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Button(model.mode == .edit ? "Apply" : "Create", action: onConfirm)
                    .keyboardShortcut(.defaultAction).disabled(model.busy)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onChange(of: model.target) { model.message = nil }
        .onChange(of: model.destination) { model.message = nil }
    }

    private var destinationLabel: String {
        switch model.mode {
        case .edit: String(localized: "Link:")
        case _ where model.count > 1: String(localized: "Create links in:")
        default: String(localized: "Link name:")
        }
    }
}

enum LinkSheet {
    /// Shows the sheet; `confirm` returns true to close it (false keeps it open, e.g. with
    /// `model.message` set). The relative choice of new symbolic links is remembered.
    @MainActor static func present(_ model: LinkSheetModel, in window: NSWindow,
                                   confirm: @escaping @MainActor (LinkSheetModel) async -> Bool) {
        var sheet: NSWindow?
        let view = LinkSheetView(model: model) {
            if let sheet { window.endSheet(sheet) }
        } onConfirm: {
            guard !model.busy else { return }
            model.busy = true
            Task { @MainActor in
                let done = await confirm(model)
                model.busy = false
                guard done, let sheet else { return }
                if model.mode != .hard { UserDefaults.standard.set(model.relative, forKey: LinkSheetModel.relativeKey) }
                window.endSheet(sheet)
            }
        }
        let host = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = host
        window.beginSheet(host, completionHandler: nil)
    }
}
