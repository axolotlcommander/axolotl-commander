// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import CommanderCore
import SwiftUI

enum SettingsTab: String { case general, viewer, appearance, hotPaths, userMenu, keyboard }

struct SettingsView: View {
    @AppStorage(Launcher.terminalDefaultsKey) private var terminal = "com.apple.Terminal"
    @AppStorage("settings.tab") private var tab = SettingsTab.general.rawValue

    var body: some View {
        TabView(selection: $tab) {
            Form {
                Picker("Terminal:", selection: $terminal) {
                    ForEach(Launcher.installedTerminals) { Text($0.name).tag($0.bundleID) }
                }
                Text("Used by Open Terminal Here (⌃/) and by commands typed in the command line.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsTab.general.rawValue)

            ViewerSettings()
                .tabItem { Label("Viewer & Editor", systemImage: "doc.text.magnifyingglass") }
                .tag(SettingsTab.viewer.rawValue)

            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
                .tag(SettingsTab.appearance.rawValue)

            HotPathSettings()
                .tabItem { Label("Hot Paths", systemImage: "star") }
                .tag(SettingsTab.hotPaths.rawValue)

            UserMenuSettings()
                .tabItem { Label("User Menu", systemImage: "filemenu.and.selection") }
                .tag(SettingsTab.userMenu.rawValue)

            KeyboardSettings()
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(SettingsTab.keyboard.rawValue)
        }
        .frame(width: 720, height: 500)
        .onExitCommand { NSApp.keyWindow?.close() }
    }
}

/// F3 viewer defaults and the F4 editor.
private struct ViewerSettings: View {
    @AppStorage(Launcher.editorDefaultsKey) private var editor = "com.apple.TextEdit"
    @AppStorage(ViewerDefaults.encodingKey) private var encoding = ViewerDefaults.fallbackEncoding.rawValue
    @AppStorage(ViewerDefaults.wrapKey) private var wrap = true
    @AppStorage(ViewerDefaults.highlightKey) private var highlight = true
    @AppStorage(ViewerDefaults.fontSizeKey) private var fontSize = ViewerDefaults.defaultFontSize

    var body: some View {
        Form {
            Section("Viewer (F3)") {
                Picker("Text encoding when not detected:", selection: $encoding) {
                    ForEach(TextEncoding.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                Text("A byte order mark or valid UTF-8 always wins; this encoding is used for other text.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Wrap lines", isOn: $wrap)
                Toggle("Highlight syntax in source code", isOn: $highlight)
                Stepper(value: $fontSize, in: ViewerDefaults.fontSizes) {
                    Text("Font size: \(Int(fontSize)) pt")
                }
            }
            Section("Editor (F4)") {
                Picker("Editor:", selection: $editor) {
                    ForEach(Launcher.installedEditors) { Text($0.name).tag($0.bundleID) }
                    Divider()
                    Text("Default App for the File Type").tag(Launcher.systemDefaultEditor)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Mark color and highlighting rules (first matching rule from the top wins).
private struct AppearanceSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var selection: HighlightRule.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Selected items:", selection: $settings.appearance.markColor) {
                ForEach(SystemColor.allCases, id: \.self) { ColorLabel(color: $0).tag($0) }
            }
            .frame(width: 260)
            Text("Highlighting — the first matching rule from the top wins:").font(.headline)
            Table($settings.appearance.highlights, selection: $selection) {
                TableColumn("On") { $rule in Toggle("", isOn: $rule.isEnabled).labelsHidden() }.width(28)
                TableColumn("Masks") { $rule in TextField("", text: $rule.masks, prompt: Text("*.md;*.txt")) }
                TableColumn("Folders") { $rule in TristatePicker(value: $rule.directory) }.width(72)
                TableColumn("Hidden") { $rule in TristatePicker(value: $rule.hidden) }.width(72)
                TableColumn("Links") { $rule in TristatePicker(value: $rule.symlink) }.width(72)
                TableColumn("Color") { $rule in
                    Picker("", selection: $rule.color) {
                        ForEach(SystemColor.allCases, id: \.self) { ColorLabel(color: $0).tag($0) }
                    }
                    .labelsHidden()
                }
                .width(110)
            }
            HStack {
                Button("Add", systemImage: "plus") {
                    let rule = HighlightRule(masks: "*.md", color: .blue)
                    settings.appearance.highlights.append(rule)
                    selection = rule.id
                }
                Button("Remove", systemImage: "minus") {
                    settings.appearance.highlights.removeAll { $0.id == selection }
                }
                .disabled(selection == nil)
                Button("Move Up", systemImage: "chevron.up") { move(-1) }.disabled(selection == nil)
                Button("Move Down", systemImage: "chevron.down") { move(1) }.disabled(selection == nil)
                Spacer()
                Button("Restore Defaults") { settings.appearance = PanelAppearance() }
            }
            .labelStyle(.iconOnly)
        }
        .padding()
    }

    private func move(_ delta: Int) {
        var rules = settings.appearance.highlights
        guard let index = rules.firstIndex(where: { $0.id == selection }),
              rules.indices.contains(index + delta) else { return }
        rules.swapAt(index, index + delta)
        settings.appearance.highlights = rules
    }
}

private struct ColorLabel: View {
    let color: SystemColor
    var body: some View {
        Label {
            Text(color.title)
        } icon: {
            Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: color.nsColor))
        }
    }
}

private struct TristatePicker: View {
    @Binding var value: Tristate
    var body: some View {
        Picker("", selection: $value) {
            Text("Any").tag(Tristate.any)
            Text("Yes").tag(Tristate.yes)
            Text("No").tag(Tristate.no)
        }
        .labelsHidden()
    }
}

/// Thirty hot paths; the first ten have shortcuts ⌃1…⌃0 (⌃⇧ digit saves the current folder).
private struct HotPathSettings: View {
    @Bindable private var settings = AppSettings.shared
    @State private var selection: Int?

    private struct Row: Identifiable {
        let id: Int
        var shortcut: String { HotPaths.digit(forSlot: id).map { "⌃\($0)" } ?? "" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Table((0..<HotPaths.capacity).map(Row.init), selection: $selection) {
                TableColumn("#") { Text("\($0.id + 1)").monospacedDigit().foregroundStyle(.secondary) }.width(24)
                TableColumn("Key") { Text($0.shortcut).foregroundStyle(.secondary) }.width(32)
                TableColumn("Name") { row in TextField("", text: field(row.id, \.name)) }.width(150)
                TableColumn("Path") { row in
                    TextField("", text: field(row.id, \.path), prompt: Text("/path/to/folder"))
                }
            }
            HStack {
                Button("Clear", systemImage: "minus") {
                    if let selection { settings.hotPaths.set(selection, nil) }
                }
                .disabled(selection == nil || selection.flatMap { settings.hotPaths[$0] } == nil)
                Button("Move Up", systemImage: "chevron.up") { move(-1) }.disabled(selection == nil)
                Button("Move Down", systemImage: "chevron.down") { move(1) }.disabled(selection == nil)
                Spacer()
                Text("⇧F9 lists hot paths and saves the current folder.").font(.caption).foregroundStyle(.secondary)
            }
            .labelStyle(.iconOnly)
        }
        .padding()
    }

    /// Editing a field of an empty slot creates the hot path; clearing the path removes it.
    private func field(_ slot: Int, _ key: WritableKeyPath<HotPath, String>) -> Binding<String> {
        Binding(
            get: { settings.hotPaths[slot]?[keyPath: key] ?? "" },
            set: { value in
                var hotPath = settings.hotPaths[slot] ?? HotPath(name: "", path: "")
                hotPath[keyPath: key] = value
                if key == \HotPath.path, hotPath.path.isEmpty {
                    settings.hotPaths.set(slot, nil)
                } else {
                    settings.hotPaths.set(slot, hotPath)
                }
            })
    }

    private func move(_ delta: Int) {
        guard let selection, (0..<HotPaths.capacity).contains(selection + delta) else { return }
        settings.hotPaths.move(from: selection, to: selection + delta)
        self.selection = selection + delta
    }
}
