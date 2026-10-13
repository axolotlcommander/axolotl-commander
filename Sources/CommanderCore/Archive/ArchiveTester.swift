// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Test Archives: reads every member's data, so libarchive checks the compressed streams and the
/// checksums the format keeps (zip CRC, gzip trailer, …). Nothing is written. A zip also needs its
/// end of central directory record: libarchive reads a zip cut short after the last member from
/// the local headers without a complaint, while other tools refuse it.
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
            var checkedFormat = false
            while let e = try reader.next() {
                if !checkedFormat {
                    checkedFormat = true
                    if reader.detectedFormat() == .zip, !hasZipEndRecord(archive) { throw ArchiveError.incomplete }
                }
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

    /// Whether the last 64 kB (the most a zip comment can push the record back) hold the end of
    /// central directory signature.
    static func hasZipEndRecord(_ archive: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return false }
        let tail = min(size, 22 + 65_535)
        guard (try? handle.seek(toOffset: size - tail)) != nil,
              let data = try? handle.read(upToCount: Int(tail)) else { return false }
        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { return false }
        return (0...(bytes.count - 22)).reversed().contains { bytes[$0..<$0 + 4].elementsEqual(signature) }
    }
}
