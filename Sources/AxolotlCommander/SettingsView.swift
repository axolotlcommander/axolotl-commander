// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import CommanderCore
import SwiftUI

enum SettingsTab: String { case general, panels, viewer, appearance, hotPaths, userMenu, buttonBar, keyboard }

struct SettingsView: View {
    @AppStorage(Launcher.terminalDefaultsKey) private var terminal = "com.apple.Terminal"
    @AppStorage("settings.tab") private var tab = SettingsTab.general.rawValue
    @AppStorage(MainWindowController.showCommandLineKey) private var showCommandLine = true
    @AppStorage(MainWindowController.showFunctionKeyBarKey) private var showFunctionKeyBar = true
    @AppStorage(DriveRowSettings.showVolumeBarKey) private var showVolumeBar = DriveRowSettings().showVolumeBar
    @AppStorage(DriveRowSettings.showRowKey) private var showDriveRow = DriveRowSettings().showRow
    @AppStorage(DriveRowSettings.freeSpaceElsewhereKey) private var freeSpaceElsewhere = DriveRowSettings().freeSpaceElsewhere
    @AppStorage(FunctionKeyChoice.key) private var hiddenFunctionKeys = ""
    @AppStorage(PanelBehavior.spaceKey) private var spaceMovesDown = PanelBehavior().spaceMovesDown
    @AppStorage(PanelBehavior.rightButtonKey) private var rightButtonMarks = PanelBehavior().rightButtonMarks
    @AppStorage(PanelBehavior.alwaysShowTabsKey) private var alwaysShowTabs = PanelBehavior().alwaysShowTabs
    @AppStorage(PanelBehavior.typingKey) private var typingToCommandLine = PanelBehavior().typingToCommandLine
    @AppStorage(PanelBehavior.arrowsKey) private var arrowsTargetPointedPanel = PanelBehavior().arrowsTargetPointedPanel
    @AppStorage(PanelBehavior.volumesKey) private var volumeButtonsFollow = PanelBehavior().volumeButtonsFollow
    @AppStorage(ThumbnailSize.key) private var thumbnailSize = ThumbnailSize.default.rawValue

    private func behavior(_ title: LocalizedStringKey, _ isOn: Binding<Bool>, _ caption: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: isOn)
            // Long captions wrap instead of ending in "…" (Czech texts are longer).
            Text(caption).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One F-key position on the bar; the last shown one cannot be turned off (spec 017).
    private func functionKeyToggle(_ number: Int) -> some View {
        let choice = FunctionKeyChoice(storage: hiddenFunctionKeys)
        let title = "F\(number)"
        return Toggle(title, isOn: Binding(
            get: { choice.isVisible(number) },
            set: { visible in
                var changed = FunctionKeyChoice(storage: hiddenFunctionKeys)
                changed.set(number, visible: visible)
                hiddenFunctionKeys = changed.storage
            }))
            .disabled(!choice.canHide(number))
    }

    /// A tab's form that scrolls when it is taller than the window, so it never pushes the tabs under the
    /// title bar.
    private func scrolling(_ form: some View) -> some View {
        ScrollView { form.padding() }
    }

    var body: some View {
        TabView(selection: $tab) {
            scrolling(Form {
                Picker("Terminal:", selection: $terminal) {
                    ForEach(Launcher.installedTerminals) { Text($0.name).tag($0.bundleID) }
                }
                Text("Used by Open Terminal Here (⌃/) and by commands typed in the command line.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                // What the window shows, from the top down; the View menu has the same switches.
                Section {
                    Toggle("Show volume bar", isOn: $showVolumeBar)
                    Toggle("Show drive row with free space", isOn: $showDriveRow)
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Show free space when the drive row is hidden", isOn: $freeSpaceElsewhere)
                            .disabled(showDriveRow)
                        Text("At the right end of the volume bar, or of the status line when the volume bar is hidden too.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 20)
                    Toggle("Show command line", isOn: $showCommandLine)
                    Toggle("Show function key bar", isOn: $showFunctionKeyBar)
                    Text("Also in the View menu. The bar shows what F1–F12 do; hold ⇧, ⌃, ⌥ or ⌘ to see the other commands.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Buttons on the bar:")
                        // Two rows of six, so the form keeps its width.
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                            ForEach([1, 7], id: \.self) { first in
                                GridRow { ForEach(first..<first + 6, id: \.self) { functionKeyToggle($0) } }
                            }
                        }
                        Text("A key whose button is off still works.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 20)
                }
                UpdateSettingsSection()
                Section {
                    HStack {
                        Button("Export Settings…") { SettingsTransfer.export(from: NSApp.keyWindow) }
                        Button("Import Settings…") { SettingsTransfer.importSettings(from: NSApp.keyWindow) }
                        Spacer()
                        // The release notes of every version (spec 026); also in Help and About.
                        Button("What's New…") { WhatsNew.show() }
                    }
                    Text("One file with the keys, preferences, appearance, hot paths, user menu, saved servers and toolbar. Passwords are never included.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            })
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsTab.general.rawValue)

            scrolling(Form {
                Section {
                    behavior("Space moves the cursor down", $spaceMovesDown,
                             "Off: Space marks the item and the cursor stays on it.")
                    behavior("Typing goes to the command line", $typingToCommandLine,
                             "Characters typed in a panel go to the command line; ⌥ + a character starts quick search.")
                    behavior("⌃← / ⌃→ change the panel the arrow points to", $arrowsTargetPointedPanel,
                             "Off: the item always goes to the other panel.")
                    behavior("Volume buttons open the other panel's folder or the last folder used there", $volumeButtonsFollow,
                             "Off: a volume button always opens the volume root.")
                    behavior("Right mouse button marks (Norton Commander style)", $rightButtonMarks,
                             "A right click marks, a right drag marks the items passed over, holding the right button opens the context menu. Off: a right click opens the context menu.")
                    behavior("Always show the tab bar", $alwaysShowTabs,
                             "Off: the tab bar appears when a panel has more than one tab.")
                    // In the content column: a form label this long would push the labels out of the window.
                    HStack {
                        Text("Thumbnail size:")
                        Picker("Thumbnail size:", selection: $thumbnailSize) {
                            Text("Small").tag(ThumbnailSize.small.rawValue)
                            Text("Medium").tag(ThumbnailSize.medium.rawValue)
                            Text("Large").tag(ThumbnailSize.large.rawValue)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            })
            .tabItem { Label("Panels", systemImage: "rectangle.split.2x1") }
            .tag(SettingsTab.panels.rawValue)

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

            ButtonBarSettings()
                .tabItem { Label("Button Bar", systemImage: "square.grid.3x1.below.line.grid.1x2") }
                .tag(SettingsTab.buttonBar.rawValue)

            KeyboardSettings()
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(SettingsTab.keyboard.rawValue)
        }
        .frame(width: 720, height: 600)
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
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
    @AppStorage(PathBar.styleKey) private var pathBarStyle = PathBar.Style.breadcrumbs.rawValue
    @AppStorage(PathBar.iconsKey) private var pathBarIcons = true
    @AppStorage(SizeSettings.displayKey) private var sizeDisplay = SizeDisplay.finder.rawValue
    @AppStorage(SizeSettings.unitsKey) private var sizeUnits = SizeUnits.decimal.rawValue
    @AppStorage(VolumeBarSettings.homeKey) private var volumeBarHome = VolumeBarSettings().showHome
    @AppStorage(VolumeBarSettings.iCloudKey) private var volumeBarICloud = VolumeBarSettings().showICloud
    @AppStorage(VolumeBarSettings.networkKey) private var volumeBarNetwork = VolumeBarSettings().showNetwork
    @AppStorage(VolumeBarSettings.serversKey) private var volumeBarServers = VolumeBarSettings().showServers
    @AppStorage(DriveRowSettings.showVolumeBarKey) private var showVolumeBar = DriveRowSettings().showVolumeBar

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                Picker("Selected items:", selection: $settings.appearance.markColor) {
                    ForEach(SystemColor.allCases, id: \.self) { ColorLabel(color: $0).tag($0) }
                }
                .frame(width: 260)
                Toggle("Bold", isOn: $settings.appearance.markBold)
            }
            HStack(spacing: 16) {
                Picker("Path bar:", selection: $pathBarStyle) {
                    Text("Breadcrumbs").tag(PathBar.Style.breadcrumbs.rawValue)
                    Text("Text field").tag(PathBar.Style.text.rawValue)
                }
                .frame(width: 260)
                Toggle("Show icons in path bar", isOn: $pathBarIcons)
                    .disabled(pathBarStyle != PathBar.Style.breadcrumbs.rawValue)
            }
            HStack(spacing: 16) {
                Picker("Size in panels:", selection: $sizeDisplay) {
                    Text("Like Finder (kB, MB, GB)").tag(SizeDisplay.finder.rawValue)
                    Text("In bytes").tag(SizeDisplay.bytes.rawValue)
                }
                .frame(width: 320)
                Picker("Units:", selection: $sizeUnits) {
                    Text("1000 (like Finder)").tag(SizeUnits.decimal.rawValue)
                    Text("1024 (like Windows)").tag(SizeUnits.binary.rawValue)
                }
                .frame(width: 240)
            }
            // Volumes are always shown; these items follow them.
            // Whether the bar is shown is in General, with the other bars.
            HStack(spacing: 16) {
                Text("Volume bar shows:")
                Toggle("Home", isOn: $volumeBarHome)
                Toggle("iCloud Drive", isOn: $volumeBarICloud)
                Toggle("Network", isOn: $volumeBarNetwork)
                Toggle("Server connections", isOn: $volumeBarServers)
            }
            .disabled(!showVolumeBar)
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
                Text("⇧F9 lists hot paths and saves the current folder.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

/// Settings → General: the automatic check, the last result and Check Now (spec 027, FR-002).
private struct UpdateSettingsSection: View {
    @AppStorage(UpdateState.automaticKey) private var automatic = true
    @State private var status = UpdateController.shared.statusText()

    var body: some View {
        Section {
            Toggle("Check for updates automatically", isOn: $automatic)
            HStack {
                Text(status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Check Now") { UpdateController.shared.checkNow() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UpdateController.stateChanged)) { _ in
            status = UpdateController.shared.statusText()
        }
    }
}
