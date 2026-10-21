// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct ClickRenameTests {
    func press(_ change: (inout ClickRename.Press) -> Void = { _ in }) -> ClickRename.Press {
        var press = ClickRename.Press()
        change(&press)
        return press
    }

    @Test func armsForASingleClickOnTheCursorItemsName() {
        #expect(ClickRename.arms(press()))
    }

    @Test func doesNotArmOtherwise() {
        #expect(!ClickRename.arms(press { $0.enabled = false }))
        #expect(!ClickRename.arms(press { $0.clickCount = 2 }))
        #expect(!ClickRename.arms(press { $0.hasModifiers = true }))
        #expect(!ClickRename.arms(press { $0.panelWasActive = false }))
        #expect(!ClickRename.arms(press { $0.wasCursor = false }))
        #expect(!ClickRename.arms(press { $0.onText = false }))
        #expect(!ClickRename.arms(press { $0.isParent = true }))
        #expect(!ClickRename.arms(press { $0.renameAvailable = false }))
    }

    @Test func firesOnlyWhenNothingChanged() {
        let url = URL(fileURLWithPath: "/tmp/a.txt")
        let pending = ClickRename.Pending(index: 3, item: url, scrollOrigin: CGPoint(x: 0, y: 40))
        #expect(pending.fires(cursor: 3, item: url, scrollOrigin: CGPoint(x: 0, y: 40), panelActive: true, editing: false))
        #expect(!pending.fires(cursor: 4, item: url, scrollOrigin: CGPoint(x: 0, y: 40), panelActive: true, editing: false))
        #expect(!pending.fires(cursor: 3, item: URL(fileURLWithPath: "/tmp/b.txt"), scrollOrigin: CGPoint(x: 0, y: 40),
                               panelActive: true, editing: false))
        #expect(!pending.fires(cursor: 3, item: nil, scrollOrigin: CGPoint(x: 0, y: 40), panelActive: true, editing: false))
        #expect(!pending.fires(cursor: 3, item: url, scrollOrigin: CGPoint(x: 0, y: 60), panelActive: true, editing: false))
        #expect(!pending.fires(cursor: 3, item: url, scrollOrigin: CGPoint(x: 0, y: 40), panelActive: false, editing: false))
        #expect(!pending.fires(cursor: 3, item: url, scrollOrigin: CGPoint(x: 0, y: 40), panelActive: true, editing: true))
    }

    @Test func selectsTheBaseName() {
        #expect(ClickRename.selection(of: "a.txt", isFolder: false) == NSRange(location: 0, length: 1))
        #expect(ClickRename.selection(of: "archive.tar.gz", isFolder: false) == NSRange(location: 0, length: 11))
        #expect(ClickRename.selection(of: "README", isFolder: false) == NSRange(location: 0, length: 6))
        #expect(ClickRename.selection(of: ".bashrc", isFolder: false) == NSRange(location: 0, length: 7))
        #expect(ClickRename.selection(of: "Mail.app", isFolder: false) == NSRange(location: 0, length: 4))
        #expect(ClickRename.selection(of: "v1.2", isFolder: true) == NSRange(location: 0, length: 4))
        // UTF-16 length, as the field editor counts.
        #expect(ClickRename.selection(of: "😀é.txt", isFolder: false) == NSRange(location: 0, length: 3))
    }

    @Test func settingIsOnByDefault() {
        #expect(PanelBehavior().clickToRename)
        let suite = "ClickRenameTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(PanelBehavior(defaults: defaults).clickToRename)
        defaults.set(false, forKey: PanelBehavior.clickToRenameKey)
        #expect(!PanelBehavior(defaults: defaults).clickToRename)
    }
}
