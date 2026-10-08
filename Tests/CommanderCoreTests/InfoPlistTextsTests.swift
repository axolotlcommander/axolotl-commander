// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing

/// The folder access prompts in the app's Info.plist (written by scripts/bundle.sh) match the
/// English texts of Resources/InfoPlist.xcstrings, and each has a Czech translation.
@Suite struct InfoPlistTextsTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func usageDescriptionsMatchTheCatalog() throws {
        let script = try String(contentsOf: root.appending(path: "scripts/bundle.sh"), encoding: .utf8)
        let pattern = /<key>(NS\w+UsageDescription)<\/key><string>([^<]*)<\/string>/
        let plist = Dictionary(script.matches(of: pattern).map { (String($0.1), String($0.2)) },
                               uniquingKeysWith: { first, _ in first })
        #expect(plist.count >= 5)

        let data = try Data(contentsOf: root.appending(path: "Resources/InfoPlist.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])
        func value(_ key: String, _ language: String) -> String? {
            let entry = strings[key] as? [String: Any]
            let localized = (entry?["localizations"] as? [String: Any])?[language] as? [String: Any]
            return (localized?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        #expect(Set(plist.keys) == Set(strings.keys))
        for (key, english) in plist {
            #expect(value(key, "en") == english, "\(key): English text differs from the catalog")
            #expect(value(key, "cs")?.isEmpty == false, "\(key): missing Czech translation")
        }
    }
}
