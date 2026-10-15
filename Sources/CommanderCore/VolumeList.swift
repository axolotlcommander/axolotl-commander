// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Synchronization

/// The mounted volumes, read in the background. Reading a volume's name and free space waits for
/// its disk: an external disk that is asleep or busy with a backup, or a server that stopped
/// answering, can take seconds or minutes. The UI reads `current`, which never touches a disk, and
/// asks for a `refresh()` when volumes are mounted, unmounted or renamed.
public final class VolumeList: Sendable {
    public static let shared = VolumeList(load: Volumes.mounted)

    /// Posted on the main queue after `current` changed.
    public static let didChangeNotification = Notification.Name("VolumeList.didChange")

    private struct State {
        var volumes: [VolumeInfo] = []
        var loaded = false
        var loading = false
        var again = false
        /// Waiting for a read that starts after they asked.
        var waiting: [CheckedContinuation<[VolumeInfo], Never>] = []
    }

    private let state = Mutex(State())
    private let load: @Sendable () -> [VolumeInfo]
    private let notify: @Sendable () -> Void
    private let queue = DispatchQueue(label: "VolumeList", qos: .utility)

    init(load: @escaping @Sendable () -> [VolumeInfo],
         notify: @escaping @Sendable () -> Void = {
             DispatchQueue.main.async { NotificationCenter.default.post(name: VolumeList.didChangeNotification, object: nil) }
         }) {
        self.load = load
        self.notify = notify
    }

    /// The volumes of the last read; empty until the first read finished.
    public var current: [VolumeInfo] { state.withLock { $0.volumes } }

    /// The mount point of the volume holding `url`, from the paths alone (no disk is touched): the
    /// longest mount point that `url` lies under, "/" otherwise. A path through a symbolic link into
    /// another volume counts as the volume of the link; `Volumes.root(of:)` reads the real one.
    public static func root(of url: URL, in volumes: [VolumeInfo]) -> URL {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        var best = URL(filePath: "/", directoryHint: .isDirectory)
        var bestLength = 1
        for volume in volumes {
            var mount = volume.url.standardizedFileURL.path(percentEncoded: false)
            if mount.hasSuffix("/") { mount.removeLast() }
            guard !mount.isEmpty, mount.count > bestLength - 1 else { continue }
            if path == mount || path.hasPrefix(mount + "/") {
                best = volume.url
                bestLength = mount.count + 1
            }
        }
        return best
    }

    /// Reads the volumes again in the background. Requests made during a read are folded into one
    /// more read after it.
    public func refresh() {
        if state.withLock({ Self.start(&$0) }) { queue.async { self.run() } }
    }

    /// The volumes read after this call; waits for the background read, never blocks the caller's thread.
    public func fresh() async -> [VolumeInfo] {
        await withCheckedContinuation { continuation in
            let start = state.withLock { state in
                state.waiting.append(continuation)
                return Self.start(&state)
            }
            if start { queue.async { self.run() } }
        }
    }

    /// True when the caller has to start a read; otherwise the running one reads once more.
    private static func start(_ state: inout State) -> Bool {
        if state.loading {
            state.again = true
            return false
        }
        state.loading = true
        return true
    }

    private func run() {
        while true {
            let waiters = state.withLock { state in
                state.again = false
                defer { state.waiting = [] }
                return state.waiting
            }
            let volumes = load()
            let (changed, more) = state.withLock { state in
                let changed = !state.loaded || state.volumes != volumes
                state.volumes = volumes
                state.loaded = true
                if !state.again { state.loading = false }
                return (changed, state.again)
            }
            for waiter in waiters { waiter.resume(returning: volumes) }
            if changed { notify() }
            if !more { return }
        }
    }
}
