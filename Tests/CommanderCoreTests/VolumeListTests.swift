// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
import Synchronization
@testable import CommanderCore

/// The volume list with a fake reader: no disk is touched.
@Suite struct VolumeListTests {
    /// A reader that counts its calls, can be held back, and returns the volumes set last.
    final class Reader: Sendable {
        let calls = Mutex(0)
        let volumes = Mutex<[VolumeInfo]>([])
        let gate = DispatchSemaphore(value: 0)
        let held = Mutex(false)

        func read() -> [VolumeInfo] {
            calls.withLock { $0 += 1 }
            if held.withLock({ $0 }) { gate.wait() }
            return volumes.withLock { $0 }
        }
    }

    private func volume(_ name: String, free: Int64 = 1) -> VolumeInfo {
        VolumeInfo(url: URL(fileURLWithPath: "/Volumes/\(name)"), name: name, availableCapacity: free)
    }

    @Test func emptyUntilTheFirstReadThenNotifiesOnlyOnChange() async {
        let reader = Reader()
        reader.volumes.withLock { $0 = [volume("A")] }
        let notified = Mutex(0)
        let list = VolumeList(load: { reader.read() }, notify: { notified.withLock { $0 += 1 } })
        #expect(list.current.isEmpty)
        #expect(await list.fresh() == [volume("A")])
        #expect(list.current == [volume("A")])
        #expect(notified.withLock { $0 } == 1)
        // Same volumes: no notification.
        _ = await list.fresh()
        #expect(notified.withLock { $0 } == 1)
        // Free space changed: notified.
        reader.volumes.withLock { $0 = [volume("A", free: 2)] }
        _ = await list.fresh()
        #expect(notified.withLock { $0 } == 2)
        #expect(list.current == [volume("A", free: 2)])
    }

    @Test func requestsDuringASlowReadFoldIntoOneMoreRead() async throws {
        let reader = Reader()
        reader.held.withLock { $0 = true }
        let list = VolumeList(load: { reader.read() }, notify: {})
        list.refresh()
        // The first read is waiting on the disk; the caller is never blocked.
        while reader.calls.withLock({ $0 }) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(list.current.isEmpty)
        reader.volumes.withLock { $0 = [volume("B")] }
        for _ in 0..<5 { list.refresh() }
        async let after = list.fresh()
        reader.held.withLock { $0 = false }
        reader.gate.signal()
        // The waiter gets the read that started after it asked.
        #expect(await after == [volume("B")])
        // The five refreshes became one more read; the waiter may have asked only after that one
        // started, which takes a third.
        #expect((2...3).contains(reader.calls.withLock { $0 }))
    }
}

@Suite struct VolumeRootByPathTests {
    private let volumes = [
        VolumeInfo(url: URL(fileURLWithPath: "/", isDirectory: true), name: "Macintosh HD"),
        VolumeInfo(url: URL(fileURLWithPath: "/Volumes/Media", isDirectory: true), name: "Media"),
        VolumeInfo(url: URL(fileURLWithPath: "/Volumes/Media 2", isDirectory: true), name: "Media 2"),
        VolumeInfo(url: URL(fileURLWithPath: "/Volumes/Media/Inner", isDirectory: true), name: "Inner"),
    ]

    private func root(_ path: String) -> String {
        VolumeList.root(of: URL(fileURLWithPath: path), in: volumes).path(percentEncoded: false)
    }

    @Test func longestMountPointThatThePathLiesUnder() {
        #expect(root("/Users/me/Documents") == "/")
        #expect(root("/Volumes/Media") == "/Volumes/Media/")
        #expect(root("/Volumes/Media/Films/a.mkv") == "/Volumes/Media/")
        #expect(root("/Volumes/Media 2/x") == "/Volumes/Media 2/")
        #expect(root("/Volumes/MediaX/x") == "/")
        #expect(root("/Volumes/Media/Inner/deep") == "/Volumes/Media/Inner/")
        #expect(root("/Volumes/Media/./Films/../Films") == "/Volumes/Media/")
        #expect(VolumeList.root(of: URL(fileURLWithPath: "/Volumes/Media/x"), in: []).path == "/")
    }
}
