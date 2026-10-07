import AppKit
import CommanderCore
import SwiftUI

/// Settings → Keyboard: every command with its shortcuts; a shortcut can be recorded, removed or
/// reset to the factory one (all at once too).
struct KeyboardSettings: View {
    private struct Row: Identifiable {
        var id: Command { command }
        let command: Command
        let title: String
        let place: String
        let chords: [KeyChord]
        let customized: Bool
    }

    @State private var context: CommandContext = .panel
    @State private var search = ""
    @State private var selection: Command?
    @State private var bindings = KeyMaps.bindings
    @State private var recording = false
    @State private var monitor: Any?
    @State private var conflict: (chord: KeyChord, others: [Command])?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Table(rows, selection: $selection) {
                TableColumn("Command") { row in
                    Text(row.title).fontWeight(row.customized ? .semibold : .regular)
                }
                TableColumn("Menu") { row in Text(row.place).foregroundStyle(.secondary) }.width(110)
                TableColumn("Shortcut") { row in
                    Text(row.chords.map(\.description).joined(separator: "   "))
                        .monospaced()
                        .foregroundStyle(row.customized ? Color.accentColor : .primary)
                }.width(170)
            }
            editor
        }
        .padding()
        .onDisappear { stopRecording() }
        .onChange(of: selection) { stopRecording() }
    }

    private var map: KeyMap { KeyMap(context: context, bindings: bindings) }

    private var rows: [Row] {
        let map = map
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return CommandRegistry.all.filter { context.includes($0.scope) }
            .map { spec in
                Row(command: spec.command, title: spec.localizedTitle.replacingOccurrences(of: "…", with: ""),
                    place: spec.menu.map(Self.menuTitle) ?? String(localized: "Keyboard only"),
                    chords: map.chords(for: spec.command), customized: bindings.isCustomized(spec.command))
            }
            .filter { row in
                query.isEmpty || row.title.lowercased().contains(query) || row.place.lowercased().contains(query)
                    || row.chords.contains { $0.description.lowercased().contains(query) }
            }
    }

    private static func menuTitle(_ menu: MenuID) -> String {
        switch menu {
        case .app: "iCommander"
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

    @ViewBuilder private var editor: some View {
        HStack(alignment: .center, spacing: 8) {
            if let command = selection {
                let chords = map.chords(for: command)
                ForEach(chords, id: \.self) { chord in
                    HStack(spacing: 2) {
                        Text(chord.description).monospaced()
                        Button { removeChord(chord, from: command) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help("Remove this shortcut")
                    }
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                Button(recording ? String(localized: "Press keys…") : String(localized: "Add Shortcut")) {
                    recording ? stopRecording() : startRecording(for: command)
                }
                Button("Reset") { update { $0.reset(command) } }.disabled(!bindings.isCustomized(command))
            } else {
                Text("Select a command to change its shortcuts.").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reset All…") { resetAll() }.disabled(bindings == .factory)
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
        alert.messageText = String(localized: "Reset all shortcuts to the factory settings?")
        alert.informativeText = String(localized: "Your changes to every command are removed.")
        alert.addButton(withTitle: String(localized: "Reset All"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        update { $0.resetAll() }
    }

    // MARK: Recording

    private func startRecording(for command: Command) {
        stopRecording()
        recording = true
        conflict = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc alone cancels; any other chord is taken.
            if event.keyCode == 53, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                stopRecording()
                return nil
            }
            guard let chord = KeyChord(event: event) else { return event }
            stopRecording()
            assign(chord, to: command, force: false)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
