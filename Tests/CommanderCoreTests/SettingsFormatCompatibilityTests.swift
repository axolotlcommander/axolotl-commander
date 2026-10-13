// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// `Fixtures/settings-format-1.json` is a frozen export of format 1 with every catalog key, every
/// command of that time, both schemes' names and every section filled. Every later app version must
/// import it without skipping anything and keep every value. Never edit the fixture; when the format
/// changes incompatibly, raise `SettingsArchive.formatVersion`, convert older files in `read`, and add
/// a fixture for the new format next to this one.
@Suite struct SettingsFormatCompatibilityTests {
    /// Sections added after the fixture was frozen; a format-1 file may lack them.
    static let addedLater: Set<SettingsSection> = [.buttonBar]
    static let fixtureSections = SettingsSection.allCases.filter { !addedLater.contains($0) }

    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/settings-format-1.json")

    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "test.settings.compat.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func formatOneImportsWithoutLoss() throws {
        let data = try Data(contentsOf: Self.fixture)
        let contents = try SettingsArchive.read(data)
        #expect(contents.formatVersion == 1)
        #expect(contents.unknownSections.isEmpty)
        #expect(contents.availableSections == Self.fixtureSections)

        try withSuite { defaults in
            let report = SettingsArchive.apply(contents, sections: Set(SettingsSection.allCases), to: defaults, catalog: .app)
            #expect(report.skipped.isEmpty, "format 1 entries this version no longer understands: \(report.skipped)")
            #expect(report.applied == Self.fixtureSections)

            // Exporting again keeps every value of the old file (new fields may be added).
            let again = try JSONValue(data: SettingsArchive.export(from: defaults, catalog: .app, appVersion: "test"))
            let old = try JSONValue(data: data)
            for (key, value) in try #require(old.objectValue) where !["appVersion", "exported"].contains(key) {
                let now = try #require(again.objectValue?[key], "\(key) is no longer exported")
                #expect(Self.contains(now, value), "\(key) changed")
            }
        }
    }

    /// Every command name in the fixture still exists (a renamed command would lose the user's keys).
    @Test func commandNamesStay() throws {
        let old = try JSONValue(data: Data(contentsOf: Self.fixture))
        let bindings = try #require(old.objectValue?["keyboard"]?.objectValue?["bindings"]?.objectValue)
        #expect(bindings.count > 150)
        let missing = bindings.keys.filter { Command(rawValue: $0) == nil }
        #expect(missing.isEmpty, "renamed or removed commands: \(missing.sorted())")
        #expect(KeyScheme(rawValue: "classicCommander") != nil && KeyScheme(rawValue: "axolotl") != nil)
    }

    /// `new` holds everything `old` has: equal values, objects with at least the old keys.
    static func contains(_ new: JSONValue, _ old: JSONValue) -> Bool {
        switch (new, old) {
        case (.object(let n), .object(let o)):
            return o.allSatisfy { key, value in n[key].map { contains($0, value) } ?? false }
        case (.array(let n), .array(let o)):
            return n.count == o.count && zip(n, o).allSatisfy { contains($0, $1) }
        default:
            return new == old
        }
    }
}
