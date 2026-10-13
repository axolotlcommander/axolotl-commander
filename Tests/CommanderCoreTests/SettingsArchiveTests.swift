// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Export and import on a temporary UserDefaults suite (never the app's own defaults).
@Suite struct SettingsArchiveTests {
    static let catalog = SettingsCatalog.standard(preferences: [
        PreferenceSpec("showCommandLine", .bool, default: .bool(true)),
        PreferenceSpec("pathBar.style", .string(allowed: ["breadcrumbs", "text"]), default: .string("breadcrumbs")),
        PreferenceSpec("terminal.bundleID", .string(allowed: nil)),
        PreferenceSpec("viewer.fontSize", .number(6...72)),
        PreferenceSpec("ssh.extraArguments", .stringArray),
        PreferenceSpec("comparison", .json(validate: SettingsCatalog.decodes(ComparisonOptions.self))),
    ], toolbarKey: "NSToolbar Configuration MainToolbar")

    /// A fresh suite; `body` runs with it and the suite is removed afterwards.
    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "test.settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    private func fill(_ defaults: UserDefaults) throws {
        defaults.set("classicCommander", forKey: "keys.scheme")
        defaults.set(try JSONEncoder().encode(["rename": ["shift+F11"], "copy": [String]()]), forKey: "keys.bindings")
        defaults.set(false, forKey: "showCommandLine")
        defaults.set("text", forKey: "pathBar.style")
        defaults.set("com.example.term", forKey: "terminal.bundleID")
        defaults.set(15.0, forKey: "viewer.fontSize")
        defaults.set(["-o", "ConnectTimeout=5"], forKey: "ssh.extraArguments")
        var comparison = ComparisonOptions()
        comparison.compareSize = false
        defaults.set(try JSONEncoder().encode(comparison), forKey: "comparison")
        defaults.set(try JSONEncoder().encode(PanelAppearance(markColor: .blue)), forKey: "appearance")
        defaults.set(try JSONEncoder().encode(HotPaths(slots: [HotPath(name: "Tmp", path: "/tmp")])), forKey: "hotPaths")
        defaults.set(try UserMenuStore.encode([UserMenuItem(title: "List", program: "/bin/ls")]), forKey: "userMenu.items")
        let profile = ConnectionProfile(name: "Example", endpoint: RemoteEndpoint(proto: .sftp, host: "example.org", user: "me"))
        defaults.set(try JSONEncoder().encode([profile]), forKey: "connections")
        defaults.set(["TB Display Mode": 2, "TB Item Identifiers": ["a", "b"]] as [String: Any],
                     forKey: "NSToolbar Configuration MainToolbar")
        // Not in the catalog: must never be exported.
        defaults.set("/Users/me/secret", forKey: "panel.left.path")
        defaults.set(["rm -rf x"], forKey: "commandLine.history")
        defaults.set("hunter2", forKey: "secret.password")
    }

    private func json(_ data: Data) throws -> [String: JSONValue] {
        try #require(try JSONValue(data: data).objectValue)
    }

    private func file(_ sections: [String: JSONValue], version: Int = 1) throws -> Data {
        var root = sections
        root["format"] = .string(SettingsArchive.format)
        root["formatVersion"] = .number(Double(version))
        return try JSONValue.object(root).data()
    }

    @Test func roundTripRestoresEverything() throws {
        try withSuite { source in
            try fill(source)
            let date = Date(timeIntervalSince1970: 1_800_000_000)
            let exported = try SettingsArchive.export(from: source, catalog: Self.catalog, appVersion: "0.4.0", date: date)

            try withSuite { target in
                let contents = try SettingsArchive.read(exported)
                #expect(contents.availableSections == SettingsSection.allCases)
                let report = SettingsArchive.apply(contents, sections: Set(SettingsSection.allCases), to: target,
                                                   catalog: Self.catalog)
                #expect(report.skipped.isEmpty)
                #expect(report.applied == SettingsSection.allCases)
                // SC-004: exporting again gives the same file.
                let again = try SettingsArchive.export(from: target, catalog: Self.catalog, appVersion: "0.4.0", date: date)
                #expect(again == exported)
                #expect(target.string(forKey: "keys.scheme") == "classicCommander")
                #expect(target.bool(forKey: "showCommandLine") == false)
                #expect(target.double(forKey: "viewer.fontSize") == 15)
                #expect(target.stringArray(forKey: "ssh.extraArguments") == ["-o", "ConnectTimeout=5"])
                let profiles = try JSONDecoder().decode([ConnectionProfile].self, from: #require(target.data(forKey: "connections")))
                #expect(profiles.map(\.name) == ["Example"])
                let bindings = try JSONDecoder().decode(KeyBindings.self, from: #require(target.data(forKey: "keys.bindings")))
                #expect(bindings.chords(for: .rename) == [KeyChord(.function(11), .shift)])
                #expect(bindings.chords(for: .copy).isEmpty)
                #expect(target.object(forKey: "panel.left.path") == nil)
            }
        }
    }

    /// SC-005 and FR-019: only catalog keys are written, so no session state and no secret.
    @Test func exportWritesOnlyCatalogKeys() throws {
        try withSuite { defaults in
            try fill(defaults)
            let data = try SettingsArchive.export(from: defaults, catalog: Self.catalog, appVersion: "0.4.0")
            let text = String(decoding: data, as: UTF8.self)
            for leaked in ["panel.left.path", "/Users/me/secret", "commandLine.history", "rm -rf", "hunter2", "secret.password"] {
                #expect(!text.contains(leaked), "\(leaked)")
            }
            #expect(!text.lowercased().contains("password"))
            let root = try json(data)
            #expect(Set(root.keys) == Set(["format", "formatVersion", "appVersion", "exported"] + SettingsSection.allCases.map(\.rawValue)))
        }
    }

    /// An untouched setup still exports a complete file of the current (default) values.
    @Test func exportOfDefaultsIsComplete() throws {
        try withSuite { defaults in
            let root = try json(SettingsArchive.export(from: defaults, catalog: Self.catalog, appVersion: "0.4.0"))
            #expect(root["keyboard"] == .object(["scheme": .string("axolotl"), "bindings": .object([:])]))
            #expect(root["preferences"]?.objectValue?["showCommandLine"] == .bool(true))
            #expect(root["preferences"]?.objectValue?["pathBar.style"] == .string("breadcrumbs"))
            #expect(root["appearance"] != nil && root["hotPaths"] != nil)
            #expect(root["connections"] == .array([]))
            #expect(root["toolbar"] == nil)
        }
    }

    @Test func uncheckedSectionsStayUnchanged() throws {
        try withSuite { source in
            try fill(source)
            let exported = try SettingsArchive.export(from: source, catalog: Self.catalog, appVersion: "0.4.0")
            try withSuite { target in
                target.set(try JSONEncoder().encode([ConnectionProfile]()), forKey: "connections")
                let report = SettingsArchive.apply(try SettingsArchive.read(exported), sections: [.keyboard],
                                                   to: target, catalog: Self.catalog)
                #expect(report.applied == [.keyboard])
                #expect(try JSONDecoder().decode([ConnectionProfile].self, from: #require(target.data(forKey: "connections"))).isEmpty)
                #expect(target.object(forKey: "showCommandLine") == nil)
                #expect(target.string(forKey: "keys.scheme") == "classicCommander")
            }
        }
    }

    @Test func badEntriesAreSkippedAndReported() throws {
        let good = try JSONValue(data: JSONEncoder().encode(
            ConnectionProfile(name: "Good", endpoint: RemoteEndpoint(proto: .ftp, host: "ftp.example.org"))))
        let data = try file([
            "keyboard": .object([
                "scheme": .string("emacs"),
                "bindings": .object([
                    "rename": .array([.string("shift+F6")]),
                    "noSuchCommand": .array([.string("F5")]),
                    "copy": .array([.string("ctrl+bogus")]),
                ]),
            ]),
            "preferences": .object([
                "showCommandLine": .bool(false),
                "viewer.fontSize": .number(999),
                "pathBar.style": .string("sideways"),
                "terminal.bundleID": .number(3),
                "unknown.key": .bool(true),
                "comparison": .object(["compareDate": .string("yes")]),
            ]),
            "connections": .array([good, .object(["name": .string("Broken")])]),
            "plugins": .array([]),
        ])
        try withSuite { defaults in
            defaults.set("classicCommander", forKey: "keys.scheme")
            let contents = try SettingsArchive.read(data)
            #expect(contents.unknownSections == ["plugins"])
            let report = SettingsArchive.apply(contents, sections: Set(SettingsSection.allCases), to: defaults,
                                               catalog: Self.catalog)
            let skipped = Set(report.skipped.map { "\($0.item):\($0.reason)" })
            #expect(skipped == [
                "scheme:unknownScheme", "noSuchCommand:unknownCommand", "copy:malformedChord",
                "viewer.fontSize:outOfRange", "pathBar.style:outOfRange", "terminal.bundleID:wrongType",
                "unknown.key:unknownKey", "comparison:invalidEntry", "connections[1]:invalidEntry",
                "plugins:unknownSection",
            ])
            // The rest is applied; the unknown scheme keeps the current one.
            #expect(defaults.string(forKey: "keys.scheme") == "classicCommander")
            #expect(defaults.bool(forKey: "showCommandLine") == false)
            #expect(defaults.object(forKey: "viewer.fontSize") == nil)
            let bindings = try JSONDecoder().decode(KeyBindings.self, from: #require(defaults.data(forKey: "keys.bindings")))
            #expect(bindings.overrides == [.rename: [KeyChord(.function(6), .shift)]])
            let profiles = try JSONDecoder().decode([ConnectionProfile].self, from: #require(defaults.data(forKey: "connections")))
            #expect(profiles.map(\.name) == ["Good"])
        }
    }

    @Test func newerFormatImportsWhatItKnows() throws {
        let data = try file(["preferences": .object(["showCommandLine": .bool(false)]), "future": .bool(true)], version: 7)
        try withSuite { defaults in
            let contents = try SettingsArchive.read(data)
            #expect(contents.isNewer)
            let report = SettingsArchive.apply(contents, sections: [.preferences], to: defaults, catalog: Self.catalog)
            #expect(report.newerFormat)
            #expect(report.applied == [.preferences])
            #expect(defaults.bool(forKey: "showCommandLine") == false)
        }
    }

    /// An older file without a key leaves that key as it is.
    @Test func missingPreferenceStaysUnchanged() throws {
        let data = try file(["preferences": .object(["showCommandLine": .bool(false)])])
        try withSuite { defaults in
            defaults.set("text", forKey: "pathBar.style")
            _ = SettingsArchive.apply(try SettingsArchive.read(data), sections: [.preferences], to: defaults, catalog: Self.catalog)
            #expect(defaults.string(forKey: "pathBar.style") == "text")
        }
    }

    /// SC-007: damaged or foreign files are rejected before anything is applied.
    @Test func foreignFilesAreRejected() {
        #expect(throws: SettingsArchiveError.notJSON) { try SettingsArchive.read(Data("not json {".utf8)) }
        #expect(throws: SettingsArchiveError.notSettingsFile) { try SettingsArchive.read(Data(#"{"name":"x"}"#.utf8)) }
        #expect(throws: SettingsArchiveError.notSettingsFile) { try SettingsArchive.read(Data("[1,2]".utf8)) }
        #expect(throws: SettingsArchiveError.notSettingsFile) {
            try SettingsArchive.read(Data(#"{"format":"axolotl-commander-settings","formatVersion":"one"}"#.utf8))
        }
    }

    @Test func jsonValuePropertyListRoundTrip() throws {
        let plist: [String: Any] = ["flag": true, "count": 2, "ratio": 0.5, "names": ["a", "b"]]
        let value = try #require(JSONValue(propertyList: plist))
        #expect(value == .object(["flag": .bool(true), "count": .number(2), "ratio": .number(0.5),
                                  "names": .array([.string("a"), .string("b")])]))
        let back = try #require(value.propertyList as? [String: Any])
        #expect(back["flag"] as? Bool == true)
        #expect(back["count"] as? Int == 2)
        #expect(String(decoding: try value.data(), as: UTF8.self).contains("\"count\" : 2,"))
    }
}
