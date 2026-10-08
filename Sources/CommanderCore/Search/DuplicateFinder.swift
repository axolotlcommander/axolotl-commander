// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import Foundation
import CryptoKit
import Darwin

public struct DuplicateCriteria: Codable, Sendable, Hashable {
    public var sameName: Bool
    public var sameSize: Bool
    public var sameContent: Bool

    public init(sameName: Bool = true, sameSize: Bool = true, sameContent: Bool = false) {
        self.sameName = sameName
        self.sameSize = sameSize
        self.sameContent = sameContent
    }
}

public enum DuplicateFinder {
    private static let partialSize = 64 * 1024

    /// Groups of at least two files that agree in the selected criteria. Directories and items
    /// without a size are ignored. `sameContent` implies `sameSize`. `progress(done, total)`
    /// counts files whose content check is finished (only called with `sameContent`).
    public static func groups(
        _ files: [FileItem],
        by criteria: DuplicateCriteria,
        rules: NameRules = .apfsDefault,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> [[FileItem]] {
        guard criteria.sameName || criteria.sameSize || criteria.sameContent else { return [] }
        let useSize = criteria.sameSize || criteria.sameContent

        struct Key: Hashable { let name: String; let size: Int64 }
        var buckets: [Key: [FileItem]] = [:]
        for file in files where !file.isDirectory && !file.isParent {
            guard let size = file.size else { continue }
            let key = Key(name: criteria.sameName ? rules.key(file.name) : "", size: useSize ? size : 0)
            buckets[key, default: []].append(file)
        }

        var result: [(key: Key, items: [FileItem])] = []
        let candidates = buckets.filter { $0.value.count >= 2 }

        if !criteria.sameContent {
            for (key, items) in candidates { result.append((key, items)) }
        } else {
            let total = candidates.values.reduce(0) { $0 + $1.count }
            var done = 0
            progress(0, total)
            for (key, items) in candidates {
                try Task.checkCancellation()
                if key.size == 0 {
                    result.append((key, items))
                    done += items.count
                    progress(done, total)
                    continue
                }
                var byPartial: [[UInt8]: [FileItem]] = [:]
                for item in items {
                    try Task.checkCancellation()
                    guard let digest = try? hash(item.url.path, limit: partialSize) else {
                        done += 1
                        progress(done, total)
                        continue
                    }
                    byPartial[digest, default: []].append(item)
                }
                for (_, partialGroup) in byPartial {
                    if partialGroup.count < 2 {
                        done += partialGroup.count
                        progress(done, total)
                        continue
                    }
                    if key.size <= Int64(partialSize) {
                        result.append((key, partialGroup))
                        done += partialGroup.count
                        progress(done, total)
                        continue
                    }
                    var byFull: [[UInt8]: [FileItem]] = [:]
                    for item in partialGroup {
                        try Task.checkCancellation()
                        if let digest = try? hash(item.url.path, limit: nil) {
                            byFull[digest, default: []].append(item)
                        }
                        done += 1
                        progress(done, total)
                    }
                    for (_, group) in byFull where group.count >= 2 { result.append((key, group)) }
                }
            }
        }

        let sorted = result.map { (key: $0.key, items: $0.items.sorted { $0.url.path < $1.url.path }) }
            .sorted { a, b in
                if a.key.name != b.key.name { return a.key.name < b.key.name }
                if a.key.size != b.key.size { return a.key.size < b.key.size }
                return a.items[0].url.path < b.items[0].url.path
            }
        return sorted.map(\.items)
    }

    /// SHA-256 of the file, or of its first `limit` bytes; streamed in 1 MiB chunks.
    private static func hash(_ path: String, limit: Int?) throws -> [UInt8] {
        let fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw SearchError.cannotRead(String(cString: strerror(errno))) }
        defer { close(fd) }
        var hasher = SHA256()
        let chunk = 1 << 20
        var buffer = [UInt8](repeating: 0, count: chunk)
        var remaining = limit ?? Int.max
        while remaining > 0 {
            if Task.isCancelled { throw CancellationError() }
            let want = min(chunk, remaining)
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress!, want) }
            if n < 0 {
                if errno == EINTR { continue }
                throw SearchError.cannotRead(String(cString: strerror(errno)))
            }
            if n == 0 { break }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0.prefix(n))) }
            remaining -= n
        }
        return Array(hasher.finalize())
    }
}
