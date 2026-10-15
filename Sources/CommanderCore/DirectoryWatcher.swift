// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Synchronization

/// Watches one directory for entries being added, removed or renamed and
/// reports a debounced change notification (~150 ms) on a background queue.
/// The directory is opened on that queue too: opening a folder on a disk that is asleep or a
/// server that stopped answering waits for it, and the caller's thread must not.
public final class DirectoryWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "axolotl.DirectoryWatcher", qos: .utility)
    private var source: (any DispatchSourceFileSystemObject)?  // confined to `queue`
    private let onChange: @Sendable () -> Void
    private let cancelled = Mutex(false)
    private var pending: DispatchWorkItem?  // confined to `queue`

    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        let path = url.path
        queue.async { [weak self] in self?.start(path) }
    }

    private func start(_ path: String) {
        guard !cancelled.withLock({ $0 }) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link], queue: queue)
        source.setCancelHandler { close(fd) }
        source.setEventHandler { [weak self] in self?.schedule() }
        self.source = source
        source.resume()
        // Cancelled while the folder was being opened.
        if cancelled.withLock({ $0 }) { source.cancel() }
    }

    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.cancelled.withLock({ $0 }) else { return }
            self.onChange()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
    }

    public func cancel() {
        cancelled.withLock { $0 = true }
        // On the queue: after the folder was opened.
        queue.async { [weak self] in self?.source?.cancel() }
    }

    /// True once the folder is open and watched (waits for the opening; for tests).
    func isWatching() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.source.map { !$0.isCancelled } ?? false) }
        }
    }

    deinit {
        cancelled.withLock { $0 = true }
        source?.cancel()
    }
}
