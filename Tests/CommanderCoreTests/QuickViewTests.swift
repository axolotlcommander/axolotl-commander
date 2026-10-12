// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Quick view panel (spec 016): what is previewed, and the chord.
@Suite struct QuickViewTests {
    private let folder = URL(fileURLWithPath: "/tmp/qv", isDirectory: true)

    private func subject(_ item: FileItem?, archive: Bool = false, server: Bool = false, network: Bool = false)
        -> QuickViewSubject {
        QuickViewSubject.subject(cursor: item, location: folder, inArchive: archive, onServer: server, isNetwork: network)
    }

    @Test func previewsDiskItemsAndTheFolderForParent() {
        let file = FileItem(url: folder.appending(path: "a.txt"))
        let sub = FileItem(url: folder.appending(path: "docs"), isDirectory: true)
        #expect(subject(file) == .item(file.url))
        #expect(subject(sub) == .item(sub.url))
        #expect(subject(.parent(of: folder)) == .item(folder))
        #expect(subject(nil) == .nothing)
    }

    @Test func archivesServersAndNetworkHaveNoPreview() {
        let file = FileItem(url: folder.appending(path: "a.txt"))
        #expect(subject(file, archive: true) == .unavailable)
        #expect(subject(file, server: true) == .unavailable)
        #expect(subject(file, network: true) == .unavailable)
    }

    @Test func chord() {
        let q = KeyChord(.character("q"), .control)
        #expect(KeyMap.standard.command(for: q) == .quickView)
        #expect(KeyMap(context: .panel, bindings: KeyBindings(scheme: .classicCommander)).command(for: q) == .quickView)
    }
}
