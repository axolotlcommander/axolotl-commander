// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

extension SettingsCatalog {
    /// The app's catalog: every setting that Export Settings… writes and Import Settings… may change.
    ///
    /// Compatibility rules (`specs/010-keyboard-schemes/contracts/settings-file.md`):
    /// - A new preference is added here; `SettingsCatalogCoverageTests` fails for a UserDefaults key
    ///   that is neither here nor in `notExported`.
    /// - Keys, command names, scheme names and the Codable shapes of the sections are never renamed;
    ///   `SettingsFormatCompatibilityTests` imports a frozen format-1 file with every one of them.
    /// - An incompatible change raises `SettingsArchive.formatVersion` and converts older files in
    ///   `SettingsArchive.read`.
    public static let app = SettingsCatalog.standard(preferences: [
        PreferenceSpec("showCommandLine", .bool, default: .bool(true)),
        PreferenceSpec("showFunctionKeyBar", .bool, default: .bool(true)),
        PreferenceSpec("terminal.bundleID", .string(allowed: nil), default: .string("com.apple.Terminal")),
        PreferenceSpec("editor.bundleID", .string(allowed: nil), default: .string("com.apple.TextEdit")),
        PreferenceSpec("viewer.encoding", .string(allowed: values(TextEncoding.self))),
        PreferenceSpec("viewer.wrap", .bool, default: .bool(true)),
        PreferenceSpec("viewer.highlight", .bool, default: .bool(true)),
        PreferenceSpec("viewer.fontSize", .number(fontSizes), default: .number(12)),
        PreferenceSpec("pathBar.style", .string(allowed: ["breadcrumbs", "text"]), default: .string("breadcrumbs")),
        PreferenceSpec("pathBar.showIcons", .bool, default: .bool(true)),
        PreferenceSpec("size.display", .string(allowed: values(SizeDisplay.self)), default: .string(SizeDisplay.finder.rawValue)),
        PreferenceSpec("size.units", .string(allowed: values(SizeUnits.self)), default: .string(SizeUnits.decimal.rawValue)),
        PreferenceSpec(VolumeBarSettings.homeKey, .bool, default: .bool(VolumeBarSettings().showHome)),
        PreferenceSpec(VolumeBarSettings.iCloudKey, .bool, default: .bool(VolumeBarSettings().showICloud)),
        PreferenceSpec(VolumeBarSettings.networkKey, .bool, default: .bool(VolumeBarSettings().showNetwork)),
        PreferenceSpec(VolumeBarSettings.serversKey, .bool, default: .bool(VolumeBarSettings().showServers)),
        PreferenceSpec("compare.whitespace", .string(allowed: values(DiffOptions.Whitespace.self)),
                       default: .string(DiffOptions.Whitespace.compare.rawValue)),
        PreferenceSpec("compare.ignoreCase", .bool, default: .bool(false)),
        PreferenceSpec("compare.differencesOnly", .bool, default: .bool(false)),
        PreferenceSpec("compare.fontSize", .number(fontSizes)),
        PreferenceSpec("checksum.algorithm", .string(allowed: values(ChecksumAlgorithm.self)),
                       default: .string(ChecksumAlgorithm.sha256.rawValue)),
        PreferenceSpec("links.relativePath", .bool, default: .bool(false)),
        PreferenceSpec("ssh.extraArguments", .stringArray),
        PreferenceSpec("comparison", .json(validate: decodes(ComparisonOptions.self))),
    ], toolbarKey: toolbarKey)

    /// AppKit's autosave key of the main window toolbar ("MainToolbar").
    public static let toolbarKey = "NSToolbar Configuration MainToolbar"

    /// Viewer and compare font sizes (points).
    public static let fontSizes: ClosedRange<Double> = 8...36

    /// UserDefaults keys that are deliberately not exported: session state, history, dialog memory and
    /// notices. Written as they appear in the source (interpolated keys included).
    public static let notExported: Set<String> = [
        "settings.tab", "window.layout", "panel.\\(side).path", "panel.\\(side).sort",
        "recentPaths", "commandLine.history", "find.history.\\(key)", "find.options",
        "batchRename.last", "changeCase.last", "functionKeyNotice",
    ]

    private static func values<T: RawRepresentable & CaseIterable>(_ type: T.Type) -> Set<String>
        where T.RawValue == String {
        Set(T.allCases.map(\.rawValue))
    }
}
