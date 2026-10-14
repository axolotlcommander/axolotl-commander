// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

@Suite struct ThumbnailTests {
    func key(_ name: String, _ size: ThumbnailSize = .medium, date: Date? = Date(timeIntervalSince1970: 0)) -> ThumbnailKey {
        ThumbnailKey(path: "/f/\(name)", modified: date, size: size)
    }

    // MARK: Size

    @Test func sizes() {
        #expect(ThumbnailSize.allCases.map(\.points) == [64, 128, 256])
        #expect(ThumbnailSize.medium.larger == .large)
        #expect(ThumbnailSize.large.larger == nil)
        #expect(ThumbnailSize.medium.smaller == .small)
        #expect(ThumbnailSize.small.smaller == nil)
        #expect(ThumbnailSize(storage: nil) == .medium)
        #expect(ThumbnailSize(storage: "huge") == .medium)
        #expect(ThumbnailSize.key == "panel.thumbnailSize")
    }

    @Test func sizeSetting() {
        let suite = "ThumbnailTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ThumbnailSize.saved(defaults) == .medium)
        defaults.set("large", forKey: ThumbnailSize.key)
        #expect(ThumbnailSize.saved(defaults) == .large)
        #expect(SettingsCatalog.app.preferences.contains { $0.key == ThumbnailSize.key })
    }

    // MARK: Layout

    @Test func viewModeIsSavedAndUnknownModesReadAsDetailed() throws {
        let home = TabList(PanelState(location: URL(fileURLWithPath: "/tmp")))
        var layout = WindowLayout(left: home, right: home)
        layout.leftMode = .thumbnails
        layout.rightMode = .brief
        let data = try JSONEncoder().encode(layout)
        let back = try #require(WindowLayout.decode(data))
        #expect(back.leftMode == .thumbnails)
        #expect(back.rightMode == .brief)
        // A mode written by a newer build: the mode falls back, the rest of the layout is kept.
        var json = try #require(String(data: data, encoding: .utf8))
        json = json.replacingOccurrences(of: "\"thumbnails\"", with: "\"tiles\"")
        let newer = try #require(WindowLayout.decode(Data(json.utf8)))
        #expect(newer.leftMode == .detailed)
        #expect(newer.rightMode == .brief)
    }

    // MARK: Policy

    @Test func policy() {
        #expect(ThumbnailPolicy.allowsPreviews(inArchive: false, onServer: false, isNetwork: false))
        #expect(!ThumbnailPolicy.allowsPreviews(inArchive: true, onServer: false, isNetwork: false))
        #expect(!ThumbnailPolicy.allowsPreviews(inArchive: false, onServer: true, isNetwork: false))
        #expect(!ThumbnailPolicy.allowsPreviews(inArchive: false, onServer: false, isNetwork: true))
        let isArchive: (URL) -> Bool = { $0.path == "/data/a.zip" }
        #expect(ThumbnailPolicy.allowsPreview(of: URL(filePath: "/data/photo.jpg"), isRegularFile: isArchive))
        // The archive file itself is a file on disk; its members are not.
        #expect(ThumbnailPolicy.allowsPreview(of: URL(filePath: "/data/a.zip"), isRegularFile: isArchive))
        #expect(!ThumbnailPolicy.allowsPreview(of: URL(filePath: "/data/a.zip/inner/photo.jpg"), isRegularFile: isArchive))
        #expect(!ThumbnailPolicy.allowsPreview(of: URL(string: "sftp://host/photo.jpg")!, isRegularFile: isArchive))
    }

    // MARK: Cache

    @Test func cacheDropsTheLeastRecentlyUsed() {
        var cache = ThumbnailCache<String>(costLimit: 300)
        cache.insert("a", for: key("a"), cost: 100)
        cache.insert("b", for: key("b"), cost: 100)
        cache.insert("c", for: key("c"), cost: 100)
        #expect(cache.value(for: key("a")) == "a")          // a is now the most recent
        cache.insert("d", for: key("d"), cost: 100)          // over the limit: b goes
        #expect(cache.value(for: key("b")) == nil)
        #expect(cache.contains(key("a")) && cache.contains(key("c")) && cache.contains(key("d")))
        #expect(cache.totalCost == 300)
        cache.insert("e", for: key("e"), cost: 250)          // c, a and d go (a was read before d came)
        #expect(cache.count == 1)
        #expect(cache.totalCost == 250)
        cache.insert("huge", for: key("huge"), cost: 301)    // larger than the limit: not kept
        #expect(!cache.contains(key("huge")))
        #expect(cache.contains(key("e")))
    }

    @Test func cacheKeysDifferByDateAndSize() {
        var cache = ThumbnailCache<String>(costLimit: 1000)
        cache.insert("old", for: key("p"), cost: 1)
        #expect(cache.value(for: key("p", date: Date(timeIntervalSince1970: 60))) == nil)
        #expect(cache.value(for: key("p", .large)) == nil)
        cache.insert("new", for: key("p"), cost: 5)          // replacing keeps one entry
        #expect(cache.value(for: key("p")) == "new")
        #expect(cache.count == 1 && cache.totalCost == 5)
        cache.removeAll()
        #expect(cache.count == 0 && cache.totalCost == 0)
    }

    // MARK: Queue

    @Test func queueRunsTheMostWantedWithinTheLimit() {
        var queue = ThumbnailQueue(limit: 2)
        let first = queue.want([key("a"), key("b"), key("c"), key("a")])
        #expect(first.start == [key("a"), key("b")])
        #expect(first.cancel.isEmpty)
        #expect(queue.finished(key("a")) == [key("c")])
        #expect(queue.running == [key("b"), key("c")])
        // Scrolled on: b and c are not wanted any more, d and e are.
        let second = queue.want([key("d"), key("e"), key("f")])
        #expect(second.cancel == [key("b"), key("c")])
        #expect(second.start == [key("d"), key("e")])
        // A finished key is not started again even if it is still listed.
        #expect(queue.finished(key("d")) == [key("f")])
        #expect(queue.want([key("e"), key("f")]).start.isEmpty)
        #expect(queue.finished(key("e")).isEmpty)
        #expect(queue.finished(key("f")).isEmpty)
        #expect(queue.running.isEmpty)
    }
}
