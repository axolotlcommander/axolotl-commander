// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Every UserDefaults key the app uses is either exported (`SettingsCatalog.app`) or deliberately
/// not (`SettingsCatalog.notExported`), so a new preference cannot be forgotten by Export Settings….
@Suite struct SettingsCatalogCoverageTests {
    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")
    static let catalogFile = "AppSettingsCatalog.swift"

    static let patterns = [
        #"forKey:\s*"([^"]+)""#,
        #"@AppStorage\("([^"]+)"\)"#,
        #"static let \w*[kK]ey\s*=\s*"([^"]+)""#,
        #"Self\.load\("([^"]+)"\)"#,
        // `AppSettings.save(_:_:)`, not the `Self.save` of other types (find history).
        #"(?<![.\w])save\([^,()]+,\s*"([^"]+)"\)"#,
    ]

    /// Keys written in the app's sources, outside the catalog file.
    static func keysInSources() throws -> Set<String> {
        let regexes = try patterns.map { try NSRegularExpression(pattern: $0) }
        var keys: Set<String> = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" && url.lastPathComponent != catalogFile {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            for regex in regexes {
                for match in regex.matches(in: text, range: range) {
                    keys.insert(String(text[Range(match.range(at: 1), in: text)!]))
                }
            }
        }
        return keys
    }

    static var exportedKeys: Set<String> {
        let catalog = SettingsCatalog.app
        return Set(catalog.preferences.map(\.key))
            .union(catalog.blobs.values.map(\.defaultsKey))
            .union([catalog.schemeKey, catalog.bindingsKey])
    }

    @Test func everyKeyIsExportedOrExcluded() throws {
        let found = try Self.keysInSources()
        #expect(found.count > 20, "the scan found too few keys; did the patterns break?")
        let unknown = found.subtracting(Self.exportedKeys).subtracting(SettingsCatalog.notExported)
        #expect(unknown.isEmpty, """
            UserDefaults keys missing from SettingsCatalog.app (export) or SettingsCatalog.notExported: \
            \(unknown.sorted())
            """)
    }

    /// A key renamed in the app but not in the catalog would silently stop being exported.
    @Test func everyCatalogKeyIsUsed() throws {
        let found = try Self.keysInSources()
        // AppKit writes the toolbar key itself, from the toolbar identifier.
        let unused = Self.exportedKeys.union(SettingsCatalog.notExported).subtracting(found)
            .subtracting([SettingsCatalog.toolbarKey])
        #expect(unused.isEmpty, "catalog keys no source uses: \(unused.sorted())")
        let toolbar = try String(contentsOf: Self.sources.appendingPathComponent("AxolotlCommander/MainToolbar.swift"), encoding: .utf8)
        #expect(SettingsCatalog.toolbarKey == "NSToolbar Configuration MainToolbar")
        #expect(toolbar.contains(#"NSToolbar(identifier: "MainToolbar")"#))
    }
}
