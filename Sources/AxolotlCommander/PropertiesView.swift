// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import OSLog
import SwiftUI

/// ⌘I sheet: size, dates, permissions, kind and link target of one item, or totals of several;
/// permissions, flags, tags and dates can be changed (Apply).
struct PropertiesView: View {
    let items: [FileProperties]
    /// nil when the attributes could not be read (then the sheet only shows information).
    let edit: AttributeEdit?
    /// Applies a change; nil = closed without changes.
    let onClose: (AttributeChange?) -> Void
    /// Recursive total including folders; nil while calculating.
    @State private var total: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                if items.count == 1 { single(items[0]) } else { multiple }
            }
            .textSelection(.enabled)
            if let edit {
                GroupBox("Permissions and Attributes") {
                    AttributesEditView(edit: edit) { onClose(edit.hasChanges ? edit.change : nil) }.padding(6)
                }
            }
            HStack {
                Button("Show in Finder") {
                    Launcher.revealInFinder(items.map(\.url), directory: items[0].url.deletingLastPathComponent())
                }
                Spacer()
                if let edit, edit.hasChanges {
                    Button("Cancel", role: .cancel) { onClose(nil) }.keyboardShortcut(.cancelAction)
                    Button("Apply") { onClose(edit.change) }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") { onClose(nil) }.keyboardShortcut(.defaultAction)
                    // Esc closes too.
                    Button("") { onClose(nil) }.keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
        .task { total = await Self.totalSize(items) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon).resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(items.count == 1 ? items[0].name : String(localized: "\(items.count) items"))
                    .font(.headline).lineLimit(2).textSelection(.enabled)
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }

    private var icon: NSImage {
        items.count == 1 ? NSWorkspace.shared.icon(forFile: items[0].url.path(percentEncoded: false))
            : NSImage(named: NSImage.multipleDocumentsName) ?? NSImage()
    }

    private var subtitle: String {
        if items.count == 1 { return items[0].kind ?? (items[0].isDirectory ? String(localized: "Folder") : String(localized: "Document")) }
        let folders = items.filter { $0.isDirectory && !$0.isPackage }.count
        return String(localized: "\(folders) folders, \(items.count - folders) files")
    }

    @ViewBuilder
    private func single(_ item: FileProperties) -> some View {
        row("Size", sizeText)
        if let allocated = item.allocatedSize, !item.isDirectory {
            row("On disk", String(localized: "\(Format.bytes(allocated)) (\(Format.grouped(allocated)) bytes)"))
        }
        row("Where", item.url.deletingLastPathComponent().path(percentEncoded: false))
        if let link = item.linkDestination { row("Link to", link) }
        GridRow { Divider().gridCellColumns(2) }
        if let date = item.created { row("Created", Self.long(date)) }
        if let date = item.modified { row("Modified", Self.long(date)) }
        if let date = item.accessed { row("Accessed", Self.long(date)) }
        GridRow { Divider().gridCellColumns(2) }
        if edit == nil { permissions(item) }
        row("Owner", [item.owner, item.group].compactMap(\.self).joined(separator: " : "))
    }

    @ViewBuilder
    private func permissions(_ item: FileProperties) -> some View {
        row("Permissions", FileProperties.permissionsString(mode: item.mode, isDirectory: item.isDirectory,
                                                            isSymlink: item.isSymlink)
            + "  " + FileProperties.octal(item.mode))
        let flags = [item.isHidden ? String(localized: "Hidden") : nil, item.isLocked ? String(localized: "Locked") : nil].compactMap(\.self)
        if !flags.isEmpty { row("Attributes", flags.joined(separator: ", ")) }
    }

    @ViewBuilder
    private var multiple: some View {
        row("Size", sizeText)
        let parents = Set(items.map { $0.url.deletingLastPathComponent() })
        if parents.count == 1, let parent = parents.first { row("Where", parent.path(percentEncoded: false)) }
    }

    private var sizeText: String {
        guard let total else { return String(localized: "Calculating…") }
        return String(localized: "\(Format.bytes(total)) (\(Format.grouped(total)) bytes)")
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).lineLimit(3).truncationMode(.middle)
        }
    }

    private static func long(_ date: Date) -> String {
        date.formatted(date: .long, time: .standard)
    }

    /// Folders (packages too) are summed recursively; links count as themselves.
    private static func totalSize(_ items: [FileProperties]) async -> Int64 {
        var sum: Int64 = 0
        for item in items {
            if Task.isCancelled { break }
            if item.isDirectory, !item.isSymlink {
                sum += await PanelModel.recursiveSize(of: item.url) ?? 0
            } else {
                sum += item.size ?? 0
            }
        }
        return sum
    }
}

enum PropertiesSheet {
    /// `onChange` runs after attributes were changed (e.g. to refresh the panel).
    static func show(_ urls: [URL], in window: NSWindow?, onChange: (() -> Void)? = nil) {
        guard let window else { return }
        let items: [FileProperties]
        do {
            items = try urls.map(FileProperties.load)
        } catch {
            log.error("properties: \(error.localizedDescription, privacy: .public)")
            Task { await showError(String(localized: "The properties could not be read."), error, in: window) }
            return
        }
        guard !items.isEmpty else { return }
        let edit = (try? AttributeSummary.read(urls)).map(AttributeEdit.init)
        var sheet: NSWindow?
        let view = PropertiesView(items: items, edit: edit) { change in
            if let sheet { window.endSheet(sheet) }
            guard let change else { return }
            Task { await apply(change, to: urls, in: window, onChange: onChange) }
        }
        let host = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = host
        window.beginSheet(host, completionHandler: nil)
    }

    static func apply(_ change: AttributeChange, to urls: [URL], in window: NSWindow, onChange: (() -> Void)?) async {
        let report: AttributeReport
        do {
            report = try await Task.detached(priority: .userInitiated) {
                try await AttributeEditor.apply(change, to: urls)
            }.value
        } catch {
            await showError(String(localized: "The attributes could not be changed."), error, in: window)
            return
        }
        onChange?()
        guard !report.failures.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Some attributes could not be changed.")
        let lines = report.failures.prefix(20).map { "\($0.url.lastPathComponent): \($0.message)" }
        alert.informativeText = lines.joined(separator: "\n")
            + (report.failures.count > 20 ? "\n" + String(localized: "…and \(report.failures.count - 20) more") : "")
        await alert.beginSheetModal(for: window)
    }

    private static func showError(_ title: String, _ error: any Error, in window: NSWindow) async {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = OperationsController.describe(error)
        _ = await OperationsController.present(alert, in: window)
    }
}
