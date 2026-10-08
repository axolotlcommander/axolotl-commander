// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Drains a pipe while the program writing into it runs (a full pipe buffer would block the
/// program forever) and keeps only the end of what came through, e.g. for an error message.
public enum PipeTail {
    /// Reads `handle` to its end on a background thread; the result is the last `limit` bytes.
    public static func read(_ handle: FileHandle, limit: Int) -> Task<Data, Never> {
        Task.detached {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    var tail = Data()
                    while let chunk = try? handle.read(upToCount: 65536), !chunk.isEmpty {
                        tail.append(chunk)
                        if tail.count > limit { tail = Data(tail.suffix(limit)) }
                    }
                    continuation.resume(returning: tail)
                }
            }
        }
    }
}
