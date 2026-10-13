// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import SwiftUI

/// Settings → Keyboard: the key scheme and every command with its shortcuts; a shortcut can be
/// recorded, removed or reset to the scheme's (all at once too).
struct KeyboardSettings: View {
    private struct Row: Identifiable {
        var id: Command { command }
        let command: Command
        let title: String
        let place: String
        let chords: [KeyChord]
        /// Chords the command would have that another command's chord took.
        let lost: [KeyChord]
        let source: ChordSource
        var customized: Bool { source == .user }
    }

    @State private var context: CommandContext = .panel
    @State private var search = ""
    @State private var selection: Command?
    @State private var bindings = KeyMaps.bindings
    @State private var recorder = ChordRecorder()
    @State private var conflict: (chord: KeyChord, others: [Command])?
    @State private var standardFunctionKeys = FunctionKeys.areStandard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Picker("Key scheme:", selection: schemeBinding) {
                    ForEach(KeyScheme.allCases, id: \.self) { Text($0.localizedTitle).tag($0) }
                }
                .fixedSize()
                // The scheme changes keys only; the behavior options are separate (spec 011).
                Text("Space, typing into the command line, ⌃← / ⌃→ and the volume buttons are set in General → Panels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Picker("", selection: $context) {
                    Text("Panels").tag(CommandContext.panel)
                    Text("Viewer").tag(CommandContext.viewer)
                    Text("Find").tag(CommandContext.find)
                    Text("Compare").tag(CommandContext.compare)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                TextField("Search", text: $search, prompt: Text("Search commands or keys")).frame(width: 220)
            }
            functionKeyState
            Table(rows, selection: $selection) {
                TableColumn("Command") { row in
                    Text(row.title).fontWeight(row.customized ? .semibold : .regular)
                }
                TableColumn("Menu") { row in Text(row.place).foregroundStyle(.secondary) }.width(110)
                TableColumn("Shortcut") { row in
                    HStack(spacing: 0) {
                        Text(row.chords.map(\.description).joined(separator: "   "))
                            .foregroundStyle(row.customized ? Color.accentColor : .primary)
                        if !row.lost.isEmpty {
                            Text((row.chords.isEmpty ? "" : "   ") + row.lost.map(\.description).joined(separator: "   "))
                                .strikethrough().foregroundStyle(.secondary)
                        }
                    }
                    .monospaced()
                }.width(170)
                TableColumn("Source") { row in
                    Text(Self.sourceTitle(row.source)).foregroundStyle(row.customized ? Color.accentColor : .secondary)
                }.width(70)
            }
            editor
        }
        .padding()
        .onDisappear { stopRecording() }
        // Re-read when coming back from System Settings.
        .onAppear { standardFunctionKeys = FunctionKeys.areStandard }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            standardFunctionKeys = FunctionKeys.areStandard
        }
        .onChange(of: selection) { stopRecording() }
        // An import may change the bindings while the window is open.
        .onReceive(NotificationCenter.default.publisher(for: KeyMaps.didChange)) { _ in
            if bindings != KeyMaps.bindings { bindings = KeyMaps.bindings }
        }
    }

    private var schemeBinding: Binding<KeyScheme> {
        Binding(get: { bindings.scheme }, set: { scheme in update { $0.scheme = scheme } })
    }

    private static func sourceTitle(_ source: ChordSource) -> String {
        switch source {
        case .defaults: String(localized: "Default")
        case .scheme: String(localized: "Scheme")
        case .user: String(localized: "Changed")
        }
    }

    private var map: KeyMap { KeyMap(context: context, bindings: bindings) }

    private var rows: [Row] {
        let map = map
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return CommandRegistry.all.filter { context.includes($0.scope) }
            .map { spec in
                Row(command: spec.command, title: spec.localizedTitle.replacingOccurrences(of: "…", with: ""),
                    place: spec.menu.map(Self.menuTitle) ?? String(localized: "Keyboard only"),
                    chords: map.chords(for: spec.command),
                    lost: bindings.chords(for: spec.command).filter { map.command(for: $0) != spec.command },
                    source: bindings.source(for: spec.command))
            }
            .filter { row in
                query.isEmpty || row.title.lowercased().contains(query) || row.place.lowercased().contains(query)
                    || row.chords.contains { $0.description.lowercased().contains(query) }
            }
    }

    static func menuTitle(_ menu: MenuID) -> String {
        switch menu {
        case .app: "Axolotl Commander"
        case .file: String(localized: "File")
        case .edit: String(localized: "Edit Menu")
        case .view: String(localized: "View Menu")
        case .go: String(localized: "Go")
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        case .commands: String(localized: "Commands")
        case .options: String(localized: "Options")
        case .window: String(localized: "Window")
        case .help: String(localized: "Help")
        }
    }

    /// Whether F1–F12 need fn on this Mac; the system setting is only shown, never changed here.
    private var functionKeyState: some View {
        HStack(spacing: 8) {
            Image(systemName: standardFunctionKeys ? "checkmark.circle" : "info.circle")
                .foregroundStyle(standardFunctionKeys ? Color.green : Color.secondary)
            Text(standardFunctionKeys
                 ? String(localized: "F1–F12 work as standard function keys.")
                 : String(localized: "F1–F12 control brightness, volume and media; hold fn for commands, or change it in System Settings."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Open Keyboard Settings") { FunctionKeys.openKeyboardSettings() }
        }
    }

    @ViewBuilder private var editor: some View {
        HStack(alignment: .center, spacing: 8) {
            if let command = selection {
                let chords = map.chords(for: command)
                ForEach(chords, id: \.self) { chord in
                    ChordChip(chord: chord) { removeChord(chord, from: command) }
                }
                Button(recorder.isRecording ? String(localized: "Press keys…") : String(localized: "Add Shortcut")) {
                    recorder.isRecording ? stopRecording() : startRecording(for: command)
                }
                Button("Reset") { update { $0.reset(command) } }.disabled(!bindings.isCustomized(command))
                let lost = bindings.chords(for: command).filter { map.command(for: $0).map { $0 != command } ?? false }
                ForEach(lost, id: \.self) { chord in
                    Text("\(chord.description) is used by \(CommandRegistry.spec(map.command(for: chord)!).localizedTitle).")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Text("Select a command to change its shortcuts.").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset All…") { resetAll() }.disabled(bindings.overrides.isEmpty)
        }
        .frame(minHeight: 26)
        if let conflict, let command = selection {
            HStack {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text("\(conflict.chord.description) is used by \(conflict.others.map { CommandRegistry.spec($0).localizedTitle }.joined(separator: ", ")).")
                Button("Use Anyway") { assign(conflict.chord, to: command, force: true) }
                Button("Cancel") { self.conflict = nil }
            }
        }
        Text("Shortcuts with ⌘, ⌃, ⌥ or function keys also appear in the menus. Some ⌃ and F-key shortcuts may be taken by macOS (System Settings → Keyboard → Keyboard Shortcuts).")
            .font(.caption).foregroundStyle(.secondary)
        Text("⌃←, ⌃→, ⌃↑ and ⌃↓ reach the app only when the Mission Control shortcuts for them are turned off in System Settings → Keyboard → Keyboard Shortcuts.")
            .font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Changes

    private func update(_ change: (inout KeyBindings) -> Void) {
        var new = bindings
        change(&new)
        bindings = new
        KeyMaps.update(new)
    }

    private func removeChord(_ chord: KeyChord, from command: Command) {
        update { $0.set(map.chords(for: command).filter { $0 != chord }, for: command) }
    }

    private func assign(_ chord: KeyChord, to command: Command, force: Bool) {
        let others = bindings.conflicts(chord, for: command)
        if !others.isEmpty, !force {
            conflict = (chord, others)
            return
        }
        conflict = nil
        update { bindings in
            // The chord moves: other commands lose it (their remaining chords stay).
            for other in others {
                bindings.set(bindings.chords(for: other).filter { $0 != chord }, for: other)
            }
            var chords = map.chords(for: command)
            if !chords.contains(chord) { chords.append(chord) }
            bindings.set(chords, for: command)
        }
    }

    private func resetAll() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Reset all shortcuts to the selected key scheme?")
        alert.informativeText = String(localized: "Your changes to every command are removed; the key scheme stays.")
        alert.addButton(withTitle: String(localized: "Reset All"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        update { $0.resetAll() }
    }

    // MARK: Recording

    private func startRecording(for command: Command) {
        conflict = nil
        recorder.start { assign($0, to: command, force: false) }
    }

    private func stopRecording() { recorder.stop() }
}

extension KeyScheme {
    var localizedTitle: String {
        switch self {
        case .axolotl: "Axolotl"
        case .classicCommander: String(localized: "Classic Commander")
        }
    }
}
