// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Synchronization

/// Watches one directory for entries being added, removed or renamed and
/// reports a debounced change notification (~150 ms) on a background queue.
public final class DirectoryWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "axolotl.DirectoryWatcher", qos: .utility)
    private let source: any DispatchSourceFileSystemObject
    private let onChange: @Sendable () -> Void
    private let cancelled = Mutex(false)
    private var pending: DispatchWorkItem?  // confined to `queue`

    public init?(url: URL, onChange: @escaping @Sendable () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.onChange = onChange
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .link], queue: queue)
        source.setCancelHandler { close(fd) }
        source.setEventHandler { [weak self] in self?.schedule() }
        source.resume()
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
        source.cancel()
    }

    deinit { cancel() }
}
