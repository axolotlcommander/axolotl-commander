// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import SwiftUI

/// Settings → Button Bar (spec 018): where the bar stands, its buttons and their icons.
struct ButtonBarSettings: View {
    @AppStorage(ButtonBarPlacement.key) private var placement = ButtonBarPlacement.off.rawValue
    @AppStorage(ButtonBarDefaults.selectionKey) private var requestedSelection = ""
    @State private var items = ButtonBarDefaults.items
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Button bar:", selection: $placement) {
                Text("Off").tag(ButtonBarPlacement.off.rawValue)
                Text("Top").tag(ButtonBarPlacement.top.rawValue)
                Text("Bottom, after the function keys").tag(ButtonBarPlacement.bottom.rawValue)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    List(selection: $selection) {
                        ForEach(items) { item in row(item).tag(item.id) }
                            .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    }
                    HStack(spacing: 4) {
                        Menu {
                            Button("Command") { insert(.command(.refresh)) }
                            Button("Program") { insert(.program(UserMenuItem(title: String(localized: "New Program")))) }
                            Button("Separator") { insert(.separator) }
                            Divider()
                            Button("Restore Samples") {
                                items = ButtonBarStore.samples
                                selection = nil
                            }
                        } label: { Image(systemName: "plus") }
                        .menuIndicator(.hidden).fixedSize()
                        Button { remove() } label: { Image(systemName: "minus") }.disabled(selection == nil)
                        Button { move(-1) } label: { Image(systemName: "chevron.up") }.disabled(selection == nil)
                        Button { move(1) } label: { Image(systemName: "chevron.down") }.disabled(selection == nil)
                    }
                }
                .frame(width: 240)
                Group {
                    if let index = selection.flatMap({ id in items.firstIndex { $0.id == id } }) {
                        ButtonEditor(item: $items[index])
                    } else {
                        Text("Buttons show only their icon; pointing at one shows its name. A button runs an app command or a program, like a user menu command. Drag buttons to change their order.")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding()
        .onAppear(perform: takeRequestedSelection)
        .onChange(of: requestedSelection) { takeRequestedSelection() }
        .onChange(of: items) { if items != ButtonBarDefaults.items { ButtonBarDefaults.items = items } }
        .onChange(of: placement) {
            if placement != ButtonBarPlacement.off.rawValue {
                UserDefaults.standard.set(placement, forKey: ButtonBarPlacement.lastKey)
            }
        }
        // Edits from the bar's context menu or a settings import while the tab is open.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let stored = ButtonBarDefaults.items
            if stored != items { items = stored }
        }
    }

    private func row(_ item: ButtonBarItem) -> some View {
        HStack(spacing: 6) {
            if item.kind == .separator {
                Text("— separator —").foregroundStyle(.secondary)
            } else {
                ButtonIcon(item: item).frame(width: 20)
                Text(ButtonBarDefaults.title(of: item))
                    .foregroundStyle(item.kind == .command && item.resolvedCommand == nil ? .secondary : .primary)
            }
        }
    }

    private func takeRequestedSelection() {
        guard !requestedSelection.isEmpty else { return }
        items = ButtonBarDefaults.items
        selection = UUID(uuidString: requestedSelection)
        requestedSelection = ""
    }

    /// New buttons go after the selection, or at the end.
    private func insert(_ item: ButtonBarItem) {
        let index = selection.flatMap { id in items.firstIndex { $0.id == id } }.map { $0 + 1 } ?? items.count
        items.insert(item, at: index)
        selection = item.id
    }

    private func remove() {
        guard let id = selection, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        selection = nil
    }

    private func move(_ offset: Int) {
        guard let id = selection, let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }
}

/// The icon of a button, as the bar shows it.
private struct ButtonIcon: View {
    let item: ButtonBarItem

    var body: some View {
        if let image = ButtonBarDefaults.image(for: item) {
            Image(nsImage: image)
        } else {
            Image(systemName: ButtonBarIcon.genericCommand)
        }
    }
}

private struct ButtonEditor: View {
    @Binding var item: ButtonBarItem
    @State private var choosingIcon = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch item.kind {
            case .separator:
                Text("A line between buttons.").foregroundStyle(.secondary)
            case .command:
                iconRow
                CommandChooser(command: $item.command)
            case .program:
                iconRow
                UserMenuItemEditor(item: $item.program, allItems: [], showsShortcut: false)
            }
        }
    }

    private var iconRow: some View {
        HStack(spacing: 8) {
            Text("Icon:")
            ButtonIcon(item: item).frame(width: 24, height: 20)
            Button("Choose…") { choosingIcon = true }
                .popover(isPresented: $choosingIcon, arrowEdge: .bottom) {
                    IconPicker(icon: $item.icon, isProgram: item.kind == .program)
                }
            Button("Default") { item.icon = "" }.disabled(item.icon.isEmpty)
            if item.kind == .command, item.resolvedCommand == nil {
                Text("This version does not know the command “\(item.command)”.").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

/// A searchable list of the commands a button can run.
private struct CommandChooser: View {
    @Binding var command: String
    @State private var query = ""

    private struct Row: Identifiable {
        let id: String
        let title: String
        let place: String
    }

    @MainActor private static let rows: [Row] = CommandRegistry.all
        .filter { $0.menu != nil && CommandContext.panel.includes($0.scope) }
        .map { Row(id: $0.command.rawValue, title: $0.localizedTitle.replacingOccurrences(of: "…", with: ""),
                   place: $0.menu.map { KeyboardSettings.menuTitle($0) } ?? "") }

    private var rows: [Row] {
        let words = query.lowercased().split(separator: " ")
        return Self.rows.filter { row in
            words.allSatisfy { row.title.lowercased().contains($0) || row.place.lowercased().contains($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Command:", text: $query, prompt: Text("Search commands"))
            ScrollViewReader { proxy in
                List(rows, selection: Binding(get: { command }, set: { if let new = $0 { command = new } })) { row in
                    HStack {
                        Text(row.title)
                        Spacer()
                        Text(row.place).foregroundStyle(.secondary)
                    }
                    .tag(row.id)
                    .id(row.id)
                }
                // The chosen command is in view when another button is selected.
                .onAppear { proxy.scrollTo(command, anchor: .center) }
                .onChange(of: command) { proxy.scrollTo(command, anchor: .center) }
            }
        }
    }
}

/// SF Symbols to choose from, the program's app icon, or any symbol name.
private struct IconPicker: View {
    @Binding var icon: String
    let isProgram: Bool
    @State private var query = ""

    /// The built-in list without names this system does not know.
    @MainActor private static let available = ButtonBarSymbols.all.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search", text: $query, prompt: Text("Search symbols, e.g. folder"))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 10), spacing: 4) {
                    ForEach(ButtonBarSymbols.search(query, in: Self.available), id: \.self) { name in
                        Button { icon = name } label: {
                            Image(systemName: name).frame(width: 26, height: 24)
                        }
                        .buttonStyle(.borderless)
                        .background(icon == name ? Color.accentColor.opacity(0.25) : .clear, in: .rect(cornerRadius: 4))
                        .help(name)
                    }
                }
            }
            .frame(height: 220)
            HStack {
                TextField("Symbol name:", text: $icon, prompt: Text("e.g. star.fill"))
                if isProgram {
                    Button("App Icon") { icon = ButtonBarIcon.appIcon }
                }
            }
            if !icon.isEmpty, icon != ButtonBarIcon.appIcon, NSImage(systemSymbolName: icon, accessibilityDescription: nil) == nil {
                Text("No symbol has this name.").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(width: 360)
    }
}
