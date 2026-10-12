// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Test Archives: reads every member's data, so libarchive checks the compressed streams and the
/// checksums the format keeps (zip CRC, gzip trailer, …). Nothing is written.
public enum ArchiveTester {
    /// Returns quietly for a sound archive and throws the first problem otherwise. Encrypted zip
    /// members need `passphrases` (`passwordRequired` / `wrongPassword` as in `ArchiveExtractor`).
    /// `progress` gets the cumulative bytes read, from any thread.
    @concurrent
    public static func test(archive: URL, passphrases: [String] = [],
                            progress: @escaping @Sendable (Int64) -> Void = { _ in }) async throws {
        try withUTF8Locale {
            let reader = try ArchiveReadHandle(path: archive.path, passphrases: passphrases)
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: 64 * 1024, alignment: 16)
            defer { buffer.deallocate() }
            var total: Int64 = 0
            while let e = try reader.next() {
                if Task.isCancelled { throw ArchiveError.cancelled }
                let info = RawEntryInfo(e)
                guard !info.isDirectory, !info.isSymlink else {
                    try reader.skip()
                    continue
                }
                let path = info.path
                if info.isEncrypted {
                    try ArchiveExtractor.checkEncrypted(path, reader: reader, passphrases: passphrases)
                }
                do throws(ArchiveError) {
                    while true {
                        if Task.isCancelled { throw .cancelled }
                        let n = try reader.read(into: buffer)
                        if n == 0 { break }
                        total += Int64(n)
                        progress(total)
                    }
                } catch {
                    if info.isEncrypted, error != .cancelled {
                        throw ArchiveReadHandle.passphraseError(for: path, after: error)
                    }
                    throw error
                }
            }
        }
    }
}
