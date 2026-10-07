import AppKit
import CommanderCore
import SwiftUI

/// Edits of the Get Info sheet: permissions, locked and hidden flags, Finder tags and dates, for one
/// item or several (a mixed state leaves the attribute of each item as it is).
@Observable final class AttributeEdit {
    let summary: AttributeSummary
    var bits: [Int: TriState]
    var locked: TriState
    var hidden: TriState
    /// Tag → state; `.mixed` = only some items have it (left alone).
    var tags: [(name: String, state: TriState)]
    var newTag = ""
    var setModified = false
    var setCreated = false
    var setAccessed = false
    var modified: Date
    var created: Date
    var accessed: Date
    var recursive = false
    /// 0 = files and folders, 1 = files only, 2 = folders only (inside selected folders).
    var nestedKind = 0

    init(_ summary: AttributeSummary) {
        self.summary = summary
        bits = summary.modeBits
        locked = summary.locked
        hidden = summary.hidden
        tags = summary.tags.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value == summary.count ? TriState.on : .mixed) }
        let now = Date()
        modified = summary.modified ?? now
        created = summary.created ?? now
        accessed = summary.accessed ?? now
    }

    var change: AttributeChange {
        var change = AttributeChange()
        for (bit, state) in bits where state != summary.modeBits[bit] {
            if state == .on { change.setMode |= bit } else if state == .off { change.clearMode |= bit }
        }
        if locked != summary.locked, locked != .mixed { change.locked = locked == .on }
        if hidden != summary.hidden, hidden != .mixed { change.hidden = hidden == .on }
        for tag in tags {
            let had = summary.tags[tag.name] ?? 0
            if tag.state == .on, had < summary.count { change.addTags.append(tag.name) }
            if tag.state == .off, had > 0 { change.removeTags.append(tag.name) }
        }
        if setModified { change.modified = modified }
        if setCreated { change.created = created }
        if setAccessed { change.accessed = accessed }
        if summary.containsFolders, recursive {
            change.recursive = true
            change.includeFiles = nestedKind != 2
            change.includeFolders = nestedKind != 1
        }
        return change
    }

    /// The change is worth applying (recursion alone changes nothing).
    var hasChanges: Bool {
        var change = change
        change.recursive = false
        return !change.isEmpty
    }

    /// "0755" when no bit is mixed.
    var octal: String? {
        guard !bits.values.contains(.mixed) else { return nil }
        return FileProperties.octal(bits.filter { $0.value == .on }.keys.reduce(0, |))
    }

    func setOctal(_ text: String) {
        guard text.count <= 4, let value = Int(text, radix: 8) else { return }
        for bit in AttributeSummary.modeBitValues { bits[bit] = value & bit != 0 ? .on : .off }
    }

    func addTag() {
        let name = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        newTag = ""
        guard !name.isEmpty else { return }
        if let index = tags.firstIndex(where: { $0.name == name }) { tags[index].state = .on } else { tags.append((name, .on)) }
    }
}

struct AttributesEditView: View {
    @Bindable var edit: AttributeEdit
    @State private var octalText = ""

    private static let rows: [(LocalizedStringKey, Int)] = [("Owner", 6), ("Group", 3), ("Everyone", 0)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 4) {
                GridRow {
                    Text("")
                    Text("Read").foregroundStyle(.secondary)
                    Text("Write").foregroundStyle(.secondary)
                    Text("Execute").foregroundStyle(.secondary)
                }
                ForEach(Self.rows, id: \.1) { title, shift in
                    GridRow {
                        Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        ForEach([4, 2, 1], id: \.self) { value in
                            TriStateCheckbox(title: "", state: bitBinding(value << shift),
                                             allowsMixed: edit.summary.modeBits[value << shift] == .mixed)
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                TriStateCheckbox(title: String(localized: "Set user ID"), state: bitBinding(0o4000),
                                 allowsMixed: edit.summary.modeBits[0o4000] == .mixed)
                TriStateCheckbox(title: String(localized: "Set group ID"), state: bitBinding(0o2000),
                                 allowsMixed: edit.summary.modeBits[0o2000] == .mixed)
                TriStateCheckbox(title: String(localized: "Sticky"), state: bitBinding(0o1000),
                                 allowsMixed: edit.summary.modeBits[0o1000] == .mixed)
                Spacer()
                TextField("Octal", text: $octalText, prompt: Text("mixed"))
                    .frame(width: 56).monospacedDigit()
                    .onSubmit { edit.setOctal(octalText); octalText = edit.octal ?? "" }
            }
            HStack(spacing: 14) {
                TriStateCheckbox(title: String(localized: "Locked"), state: $edit.locked,
                                 allowsMixed: edit.summary.locked == .mixed)
                    .help("The item can’t be changed, renamed or deleted (uchg flag).")
                TriStateCheckbox(title: String(localized: "Hidden"), state: $edit.hidden,
                                 allowsMixed: edit.summary.hidden == .mixed)
                    .help("Hidden in Finder (hidden flag).")
            }
            Divider()
            tagEditor
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                dateRow("Modified:", isOn: $edit.setModified, date: $edit.modified, known: edit.summary.modified != nil)
                dateRow("Created:", isOn: $edit.setCreated, date: $edit.created, known: edit.summary.created != nil)
                dateRow("Accessed:", isOn: $edit.setAccessed, date: $edit.accessed, known: edit.summary.accessed != nil)
            }
            if edit.summary.containsFolders {
                HStack {
                    Toggle("Also change items inside folders:", isOn: $edit.recursive)
                    Picker("", selection: $edit.nestedKind) {
                        Text("Files and folders").tag(0)
                        Text("Files only").tag(1)
                        Text("Folders only").tag(2)
                    }
                    .labelsHidden().fixedSize().disabled(!edit.recursive)
                }
            }
        }
        .onAppear { octalText = edit.octal ?? "" }
        .onChange(of: edit.octal) { octalText = edit.octal ?? "" }
    }

    private func bitBinding(_ bit: Int) -> Binding<TriState> {
        Binding(get: { edit.bits[bit] ?? .off }, set: { edit.bits[bit] = $0 })
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tags:").foregroundStyle(.secondary)
                TextField("Add Tag", text: $edit.newTag, prompt: Text("New tag"))
                    .frame(width: 160).onSubmit { edit.addTag() }
                Button("Add") { edit.addTag() }.disabled(edit.newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !edit.tags.isEmpty {
                FlowTags(tags: $edit.tags, total: edit.summary.count)
            }
        }
    }

    @ViewBuilder
    private func dateRow(_ title: LocalizedStringKey, isOn: Binding<Bool>, date: Binding<Date>, known: Bool) -> some View {
        GridRow {
            Toggle(title, isOn: isOn).gridColumnAlignment(.leading)
            DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden().disabled(!isOn.wrappedValue)
            Button("Now") { date.wrappedValue = Date(); isOn.wrappedValue = true }
            if !known { Text("differs").font(.caption).foregroundStyle(.secondary) } else { Text("") }
        }
    }
}

/// Tags as small capsules; a click cycles on → off (→ only some items, when it was mixed).
private struct FlowTags: View {
    @Binding var tags: [(name: String, state: TriState)]
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags.indices, id: \.self) { index in
                let tag = tags[index]
                Button {
                    tags[index].state = tag.state == .on ? .off : .on
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: tag.state == .on ? "tag.fill" : tag.state == .mixed ? "tag" : "tag.slash")
                        Text(tag.name).strikethrough(tag.state == .off)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(tag.state == .off ? 0.08 : 0.18)))
                }
                .buttonStyle(.plain)
                .help(tag.state == .mixed ? "Only some items have this tag; click to give it to all." : "Click to add or remove the tag.")
            }
        }
    }
}

/// A native checkbox with an optional mixed state (shown as “–”).
struct TriStateCheckbox: NSViewRepresentable {
    let title: String
    @Binding var state: TriState
    var allowsMixed: Bool

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.toggled(_:)))
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.title = title
        button.allowsMixedState = allowsMixed
        button.state = switch state {
        case .on: .on
        case .off: .off
        case .mixed: .mixed
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: TriStateCheckbox
        init(parent: TriStateCheckbox) { self.parent = parent }

        @objc func toggled(_ sender: NSButton) {
            parent.state = switch sender.state {
            case .on: .on
            case .mixed: .mixed
            default: .off
            }
        }
    }
}
