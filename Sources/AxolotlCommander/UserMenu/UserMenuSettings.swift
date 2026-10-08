// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import SwiftUI

/// Settings → User Menu: the F9 items, submenus and separators, with the program, its arguments
/// (with variables) and the initial folder of each command.
struct UserMenuSettings: View {
    @State private var items = UserMenuDefaults.items
    @State private var selection: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $selection) {
                    OutlineGroup(items, children: \.outlineChildren) { item in
                        row(item).tag(item.id)
                    }
                }
                .frame(width: 230)
                HStack(spacing: 4) {
                    Menu {
                        Button("Command") { insert(UserMenuItem(title: String(localized: "New Command"))) }
                        Button("Submenu") { insert(UserMenuItem(kind: .submenu, title: String(localized: "New Submenu"))) }
                        Button("Separator") { insert(UserMenuItem(kind: .separator)) }
                    } label: { Image(systemName: "plus") }
                    .menuIndicator(.hidden).fixedSize()
                    Button { remove() } label: { Image(systemName: "minus") }.disabled(selection == nil)
                    Button { move(-1) } label: { Image(systemName: "chevron.up") }.disabled(selection == nil)
                    Button { move(1) } label: { Image(systemName: "chevron.down") }.disabled(selection == nil)
                    Spacer()
                    if items.isEmpty {
                        Button("Add Examples") { items = UserMenuStore.examples }
                    }
                }
            }
            Group {
                if let path = selection.flatMap({ items.path(of: $0) }) {
                    UserMenuItemEditor(item: Binding(get: { items[path: path] }, set: { items[path: path] = $0 }),
                                       allItems: items)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("F9 shows these items. A command runs its program with the arguments; variables such as $(FullName) are filled with the files of the active panel.")
                        Text("A command that uses a file variable runs once for every selected file.")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding()
        .onChange(of: items) { UserMenuDefaults.items = items }
    }

    private func row(_ item: UserMenuItem) -> some View {
        Group {
            switch item.kind {
            case .separator: Text("— separator —").foregroundStyle(.secondary)
            case .submenu: Label(item.title.isEmpty ? String(localized: "Submenu") : item.title, systemImage: "folder")
            case .command:
                Label(item.title.isEmpty ? String(localized: "Untitled") : item.title,
                      systemImage: item.runInTerminal ? "terminal" : "play")
            }
        }
    }

    /// New items go after the selection, or into the selected submenu.
    private func insert(_ item: UserMenuItem) {
        if let id = selection, let path = items.path(of: id) {
            if items[path: path].kind == .submenu {
                items[path: path].children.append(item)
            } else {
                items.insert(item, after: path)
            }
        } else {
            items.append(item)
        }
        selection = item.id
    }

    private func remove() {
        guard let id = selection, let path = items.path(of: id) else { return }
        items.remove(at: path)
        selection = nil
    }

    private func move(_ offset: Int) {
        guard let id = selection, let path = items.path(of: id) else { return }
        items.move(at: path, by: offset)
    }
}

private struct UserMenuItemEditor: View {
    @Binding var item: UserMenuItem
    /// The whole tree, to find other items with the same shortcut.
    let allItems: [UserMenuItem]
    @State private var recorder = ChordRecorder()
    /// A recorded chord refused because it is plain typing (quick search).
    @State private var rejected: KeyChord?

    var body: some View {
        Form {
            switch item.kind {
            case .separator:
                Text("A line between items.").foregroundStyle(.secondary)
            case .submenu:
                TextField("Title:", text: $item.title)
            case .command:
                TextField("Title:", text: $item.title)
                HStack {
                    TextField("Program:", text: $item.program, prompt: Text("/usr/bin/open, git, ~/bin/tool"))
                    Button("Choose…") { choose() }
                }
                HStack {
                    TextField("Arguments:", text: $item.arguments, prompt: Text("$(FullName)"))
                        .font(.body.monospaced())
                    variableMenu { item.arguments += (item.arguments.isEmpty || item.arguments.hasSuffix(" ") ? "" : " ") + $0 }
                }
                HStack {
                    TextField("Initial folder:", text: $item.directory, prompt: Text("$(FullPath)"))
                    variableMenu { item.directory = $0 }
                }
                Toggle("Run in Terminal", isOn: $item.runInTerminal)
                shortcutRow
                Text("Arguments are split like in a shell; quote special characters (; | & * ?). Variables are filled in after the split, so names with spaces need no quotes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: item.id) {
            recorder.stop()
            rejected = nil
        }
        .onDisappear { recorder.stop() }
    }

    // MARK: Shortcut

    @ViewBuilder private var shortcutRow: some View {
        LabeledContent("Shortcut:") {
            HStack(spacing: 8) {
                if let chord = item.shortcut {
                    ChordChip(chord: chord)
                } else {
                    Text("None").foregroundStyle(.secondary)
                }
                Button(recorder.isRecording ? String(localized: "Press keys…") : String(localized: "Record Shortcut")) {
                    recorder.isRecording ? recorder.stop() : record()
                }
                Button("Clear") {
                    item.shortcut = nil
                    rejected = nil
                }
                .disabled(item.shortcut == nil)
            }
        }
        if let rejected {
            Text("\(rejected.description) types into quick search. Use a shortcut with ⌘, ⌃ or ⌥, or a function key.")
                .font(.caption).foregroundStyle(.red)
        }
        ForEach(shortcutWarnings, id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private func record() {
        rejected = nil
        recorder.start { chord in
            if UserMenuStore.isAssignable(chord) {
                item.shortcut = chord
            } else {
                rejected = chord
            }
        }
    }

    /// Who else uses the shortcut: a panel command (a menu item with a ⌘/⌃/⌥ or F-key chord is
    /// matched first) or another user menu item (the first one in the menu runs).
    private var shortcutWarnings: [String] {
        guard let chord = item.shortcut else { return [] }
        var warnings: [String] = []
        if let command = KeyMaps.panel.command(for: chord) {
            let title = CommandRegistry.spec(command).localizedTitle.replacingOccurrences(of: "…", with: "")
            warnings.append(String(localized: "\(chord.description) is also the shortcut of the command “\(title)”."))
        }
        let others = UserMenuStore.commands(in: allItems).filter { $0.id != item.id && $0.shortcut == chord }
        if !others.isEmpty {
            let titles = others.map { "“\($0.title.isEmpty ? $0.program : $0.title)”" }.joined(separator: ", ")
            warnings.append(String(localized: "\(chord.description) is also used by \(titles) in the user menu; the first one in the menu runs."))
        }
        return warnings
    }

    private func variableMenu(_ insert: @escaping (String) -> Void) -> some View {
        Menu("Insert") {
            ForEach(UserMenuExpander.variables, id: \.name) { variable in
                Button("\(variable.name) — \(String(localized: String.LocalizationValue(variable.description)))") { insert(variable.name) }
            }
        }
        .fixedSize()
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        item.program = url.path(percentEncoded: false)
        if item.title.isEmpty || item.title == String(localized: "New Command") {
            item.title = url.deletingPathExtension().lastPathComponent
        }
    }
}

// MARK: Tree editing

private extension UserMenuItem {
    /// Children for the outline; nil for leaves so they get no disclosure triangle.
    var outlineChildren: [UserMenuItem]? { kind == .submenu ? children : nil }
}

private extension Array where Element == UserMenuItem {
    /// Index path of the item with `id`.
    func path(of id: UUID) -> [Int]? {
        for (index, item) in enumerated() {
            if item.id == id { return [index] }
            if let rest = item.children.path(of: id) { return [index] + rest }
        }
        return nil
    }

    subscript(path path: [Int]) -> UserMenuItem {
        get { path.count == 1 ? self[path[0]] : self[path[0]].children[path: [Int](path.dropFirst())] }
        set {
            if path.count == 1 { self[path[0]] = newValue } else { self[path[0]].children[path: [Int](path.dropFirst())] = newValue }
        }
    }

    mutating func insert(_ item: UserMenuItem, after path: [Int]) {
        if path.count == 1 { insert(item, at: path[0] + 1) } else { self[path[0]].children.insert(item, after: [Int](path.dropFirst())) }
    }

    mutating func remove(at path: [Int]) {
        if path.count == 1 { remove(at: path[0]) } else { self[path[0]].children.remove(at: [Int](path.dropFirst())) }
    }

    mutating func move(at path: [Int], by offset: Int) {
        if path.count == 1 {
            let target = path[0] + offset
            guard indices.contains(target) else { return }
            swapAt(path[0], target)
        } else {
            self[path[0]].children.move(at: [Int](path.dropFirst()), by: offset)
        }
    }
}
