import AppKit
import CommanderCore
import OSLog
import SwiftUI

/// ⌘I sheet: size, dates, permissions, kind and link target of one item, or totals of several.
struct PropertiesView: View {
    let items: [FileProperties]
    let onClose: () -> Void
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
            HStack {
                Button("Show in Finder") {
                    Launcher.revealInFinder(items.map(\.url), directory: items[0].url.deletingLastPathComponent())
                }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
                // Esc closes too.
                Button("", action: onClose).keyboardShortcut(.cancelAction).frame(width: 0, height: 0).opacity(0)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { total = await Self.totalSize(items) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon).resizable().frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(items.count == 1 ? items[0].name : "\(items.count) items")
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
        if items.count == 1 { return items[0].kind ?? (items[0].isDirectory ? "Folder" : "Document") }
        let folders = items.filter { $0.isDirectory && !$0.isPackage }.count
        return "\(folders) folders, \(items.count - folders) files"
    }

    @ViewBuilder
    private func single(_ item: FileProperties) -> some View {
        row("Size", sizeText)
        if let allocated = item.allocatedSize, !item.isDirectory {
            row("On disk", "\(Format.bytes(allocated)) (\(Format.grouped(allocated)) bytes)")
        }
        row("Where", item.url.deletingLastPathComponent().path(percentEncoded: false))
        if let link = item.linkDestination { row("Link to", link) }
        GridRow { Divider().gridCellColumns(2) }
        if let date = item.created { row("Created", Self.long(date)) }
        if let date = item.modified { row("Modified", Self.long(date)) }
        if let date = item.accessed { row("Accessed", Self.long(date)) }
        GridRow { Divider().gridCellColumns(2) }
        row("Permissions", FileProperties.permissionsString(mode: item.mode, isDirectory: item.isDirectory,
                                                            isSymlink: item.isSymlink)
            + "  " + FileProperties.octal(item.mode))
        row("Owner", [item.owner, item.group].compactMap(\.self).joined(separator: " : "))
        let flags = [item.isHidden ? "Hidden" : nil, item.isLocked ? "Locked" : nil].compactMap(\.self)
        if !flags.isEmpty { row("Attributes", flags.joined(separator: ", ")) }
    }

    @ViewBuilder
    private var multiple: some View {
        row("Size", sizeText)
        let parents = Set(items.map { $0.url.deletingLastPathComponent() })
        if parents.count == 1, let parent = parents.first { row("Where", parent.path(percentEncoded: false)) }
    }

    private var sizeText: String {
        guard let total else { return "Calculating…" }
        return "\(Format.bytes(total)) (\(Format.grouped(total)) bytes)"
    }

    private func row(_ label: String, _ value: String) -> some View {
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
    static func show(_ urls: [URL], in window: NSWindow?) {
        guard let window else { return }
        let items: [FileProperties]
        do {
            items = try urls.map(FileProperties.load)
        } catch {
            NSSound.beep()
            log.error("properties: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !items.isEmpty else { return }
        var sheet: NSWindow?
        let view = PropertiesView(items: items) { if let sheet { window.endSheet(sheet) } }
        let host = NSWindow(contentViewController: NSHostingController(rootView: view))
        sheet = host
        window.beginSheet(host, completionHandler: nil)
    }
}
