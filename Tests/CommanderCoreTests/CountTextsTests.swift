// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing

/// The counts in the status line and Properties use plural forms ("1 file", "3 soubory").
struct CountTextsTests {
    private func plural(_ key: String, _ language: String) throws -> [String: String] {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let entry = (json?["strings"] as? [String: Any])?[key] as? [String: Any]
        let localization = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
        let forms = (localization?["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
        return forms.compactMapValues { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
    }

    @Test func fileAndFolderCountsHavePluralForms() throws {
        #expect(try plural("%lld files", "en") == ["one": "%lld file", "other": "%lld files"])
        #expect(try plural("%lld folders", "en") == ["one": "%lld folder", "other": "%lld folders"])
        let files = try plural("%lld files", "cs")
        #expect(files["one"] == "%lld soubor" && files["few"] == "%lld soubory" && files["other"] == "%lld souborů")
        let folders = try plural("%lld folders", "cs")
        #expect(folders["one"] == "%lld složka" && folders["few"] == "%lld složky" && folders["other"] == "%lld složek")
    }
}
