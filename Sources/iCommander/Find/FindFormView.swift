// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import CommanderCore
import SwiftUI

/// Upper part of the find window: what to find and where.
struct FindFormView: View {
    @Bindable var form: FindForm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("Named:").gridColumnAlignment(.trailing)
                    HistoryField(text: $form.name, history: form.nameHistory.entries,
                                 prompt: String(localized: "All files (masks *.txt;*.md|tmp*)"), onSubmit: form.onFind)
                    HStack {
                        Toggle("Subfolders", isOn: $form.subdirectories)
                        Toggle("Hidden Files", isOn: $form.includeHidden)
                        Toggle("Inside Packages", isOn: $form.searchPackages)
                    }
                    .fixedSize()
                }
                GridRow {
                    Text("Look in:")
                    HistoryField(text: $form.lookIn, history: form.lookInHistory.entries,
                                 prompt: String(localized: "Folders separated by ;"), onSubmit: form.onFind)
                    Button("Choose…", action: form.onChooseFolder)
                }
                GridRow {
                    Text("Containing:")
                    HistoryField(text: $form.containing, history: form.textHistory.entries,
                                 prompt: form.hex ? String(localized: "Bytes, e.g. 4A 6F \"text\" 00") : String(localized: "Text in the file"),
                                 onSubmit: form.onFind)
                    HStack {
                        Toggle("Case Sensitive", isOn: $form.caseSensitive).disabled(form.hex)
                        Toggle("Whole Words", isOn: $form.wholeWords).disabled(form.hex)
                        Toggle("Hex", isOn: $form.hex)
                        Toggle("Regular Expression", isOn: $form.regex)
                    }
                    .fixedSize()
                }
            }
            DisclosureGroup("More Options", isExpanded: $form.showAdvanced) {
                advanced.padding(.top, 6)
            }
            HStack {
                Toggle("Find Duplicates:", isOn: $form.findDuplicates)
                Toggle("Same Name", isOn: $form.duplicateName).disabled(!form.findDuplicates)
                Toggle("Same Size", isOn: $form.duplicateSize).disabled(!form.findDuplicates || form.duplicateContent)
                Toggle("Same Content", isOn: $form.duplicateContent).disabled(!form.findDuplicates)
                Spacer()
                if form.isSearching {
                    Button("Stop", action: form.onStop)
                } else {
                    Button("Find", action: form.onFind).keyboardShortcut(.defaultAction)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(14)
    }

    private var advanced: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("Size:").gridColumnAlignment(.trailing)
                HStack {
                    Toggle("at least", isOn: $form.useMinSize)
                    sizeField($form.minSize, unit: $form.minUnit).disabled(!form.useMinSize)
                    Toggle("at most", isOn: $form.useMaxSize)
                    sizeField($form.maxSize, unit: $form.maxUnit).disabled(!form.useMaxSize)
                }
            }
            GridRow {
                Text("Modified:")
                HStack {
                    Toggle("from", isOn: $form.useFrom)
                    DatePicker("", selection: $form.from).labelsHidden().disabled(!form.useFrom)
                    Toggle("to", isOn: $form.useTo)
                    DatePicker("", selection: $form.to).labelsHidden().disabled(!form.useTo)
                }
            }
            GridRow {
                Text("Kind:")
                Picker("", selection: $form.kind) {
                    Text("Files and Folders").tag(SearchCriteria.Kind.all)
                    Text("Files").tag(SearchCriteria.Kind.files)
                    Text("Folders").tag(SearchCriteria.Kind.folders)
                }
                .labelsHidden()
                .fixedSize()
            }
            GridRow {
                Text("Skip folders:")
                TextField("", text: $form.excluded, prompt: Text("e.g. node_modules;.git;~/Library"))
            }
        }
    }

    private func sizeField(_ value: Binding<Int64>, unit: Binding<FindForm.SizeUnit>) -> some View {
        HStack(spacing: 4) {
            TextField("", value: value, format: .number).frame(width: 70)
            Picker("", selection: unit) {
                ForEach(FindForm.SizeUnit.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// Text field with a menu of earlier entries.
private struct HistoryField: View {
    @Binding var text: String
    let history: [String]
    let prompt: String
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            TextField("", text: $text, prompt: Text(prompt))
                .onSubmit(onSubmit)
                .frame(minWidth: 220, maxWidth: .infinity)
            Menu {
                ForEach(history, id: \.self) { entry in
                    Button(entry) { text = entry }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(history.isEmpty)
            .help(String(localized: "Recent"))
        }
    }
}
