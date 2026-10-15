// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct FindResultActionsTests {
    @Test func behaviorDefaultsToHide() throws {
        let suite = "FindResultActionsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(FindWindowBehavior(defaults: defaults) == .hide)
        defaults.set(FindWindowBehavior.keepOpen.rawValue, forKey: FindWindowBehavior.key)
        #expect(FindWindowBehavior(defaults: defaults) == .keepOpen)
        defaults.set("nonsense", forKey: FindWindowBehavior.key)
        #expect(FindWindowBehavior(defaults: defaults) == .hide)
    }

    @Test func fileGoesToItsFolder() {
        let url = URL(filePath: "/tmp/a/b/c.txt")
        #expect(FindGoToTarget.resolve(url) { _ in true } == .focus(folder: URL(filePath: "/tmp/a/b/"), name: "c.txt"))
    }

    @Test func folderGoesToItsParent() {
        let url = URL(filePath: "/tmp/a/b/", directoryHint: .isDirectory)
        #expect(FindGoToTarget.resolve(url) { _ in true } == .focus(folder: URL(filePath: "/tmp/a/"), name: "b"))
    }

    @Test func missingItemShowsTheFolder() {
        let url = URL(filePath: "/tmp/a/b/c.txt")
        let target = FindGoToTarget.resolve(url) { $0.lastPathComponent != "c.txt" }
        #expect(target == .folderOnly(URL(filePath: "/tmp/a/b/")))
    }

    @Test func missingFolderIsReported() {
        let url = URL(filePath: "/tmp/a/b/c.txt")
        #expect(FindGoToTarget.resolve(url) { _ in false } == .gone(URL(filePath: "/tmp/a/b/")))
    }

    @Test func behaviorIsExported() {
        #expect(SettingsCatalog.app.preferences.contains { $0.key == FindWindowBehavior.key })
    }
}
