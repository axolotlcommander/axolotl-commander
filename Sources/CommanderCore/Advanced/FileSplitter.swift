// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import Darwin

/// Writes the parts of Split File and the joined file of Combine Files (spec 029). Everything is written
/// into a hidden staging folder inside the target folder first; names in the target are given only to
/// complete data, and a cancelled or failed run removes what it wrote and nothing else (R7, R8).
public enum FileSplitter {
    static let chunkSize = 4 << 20

    /// Of the names a split would write, those that exist in `folder`. A folder with such a name throws
    /// `folderInTheWay`: it cannot be replaced by a part.
    public static func existingNames(base: String, count: Int, checksum: Bool, in folder: URL) throws -> [String] {
        var names = (1...max(1, count)).map { PartName.name(base: base, index: $0) }
        if checksum { names.append(PartName.checksumName(base: base)) }
        return try names.filter { name in
            var st = stat()
            guard lstat(path(folder.appending(path: name)), &st) == 0 else { return false }
            if st.st_mode & S_IFMT == S_IFDIR { throw SplitCombineError.folderInTheWay(name) }
            return true
        }
    }

    // MARK: Split

    /// Splits `source` (links followed) into `<name>.001`, `<name>.002`, … of `partSize` bytes in `folder`,
    /// with `<name>.crc` when `writeChecksum`. Names in `replacing` may replace existing files (the user
    /// agreed); any other existing name stops the run. Returns the written files. Throws
    /// `CancellationError` when the task is cancelled.
    public static func split(
        source: URL, name: String, partSize: Int64, writeChecksum: Bool, into folder: URL,
        replacing: Set<String> = [], progress: @Sendable (Int64) -> Void = { _ in }
    ) async throws -> [URL] {
        let sourcePath = path(source)
        let input = try openForReading(sourcePath)
        defer { close(input) }
        let size = try regularFileSize(input, name: source.lastPathComponent, path: sourcePath)
        guard partSize > 0, size > 0 else { throw SplitCombineError.noParts }
        let count = PartSize.count(fileSize: size, partSize: partSize)

        let staging = try makeStaging(in: folder)
        defer { try? FileManager.default.removeItem(at: staging) }
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 16)
        defer { buffer.deallocate() }
        var crc = CRC32()
        var done: Int64 = 0
        var staged: [String] = []
        for index in 1...count {
            let partName = PartName.name(base: name, index: index)
            let partPath = path(staging.appending(path: partName))
            let output = try createExclusive(partPath)
            staged.append(partName)
            do {
                var remaining = min(partSize, size - done)
                while remaining > 0 {
                    try Task.checkCancellation()
                    let n = try readSome(input, buffer, Int(min(Int64(chunkSize), remaining)), path: sourcePath)
                    if n == 0 { throw SplitCombineError.sourceChanged(source.lastPathComponent) }
                    let bytes = UnsafeRawBufferPointer(rebasing: buffer[0..<n])
                    crc.update(bytes)
                    try writeAll(output, bytes, path: partPath)
                    remaining -= Int64(n)
                    done += Int64(n)
                    progress(done)
                }
            } catch {
                close(output)
                throw error
            }
            guard close(output) == 0 else { throw SplitCombineError.cannotWrite(describe(partPath)) }
        }
        // The file must end where it ended when the split started.
        if try readSome(input, buffer, 1, path: sourcePath) > 0 {
            throw SplitCombineError.sourceChanged(source.lastPathComponent)
        }
        if writeChecksum {
            let checksumName = PartName.checksumName(base: name)
            let checksumPath = path(staging.appending(path: checksumName))
            let output = try createExclusive(checksumPath)
            staged.append(checksumName)
            let text = SplitChecksum.text(name: name, size: size, crc32: crc.value)
            do {
                try text.withUnsafeBytes { try writeAll(output, $0, path: checksumPath) }
            } catch {
                close(output)
                throw error
            }
            guard close(output) == 0 else { throw SplitCombineError.cannotWrite(describe(checksumPath)) }
        }
        try Task.checkCancellation()
        return try commit(staged, from: staging, to: folder, replacing: replacing)
    }

    /// Gives the staged files their names in `folder`. A failure removes the files this commit placed under
    /// names that were free (the replaced ones cannot be brought back, the user agreed to replace them).
    static func commit(_ names: [String], from staging: URL, to folder: URL, replacing: Set<String>) throws -> [URL] {
        var placed: [URL] = []
        do {
            for name in names {
                let from = path(staging.appending(path: name))
                let target = folder.appending(path: name)
                if replacing.contains(name) {
                    guard rename(from, path(target)) == 0 else { throw SplitCombineError.cannotWrite(describe(path(target))) }
                } else {
                    guard ExclusiveRename.rename(from, path(target)) == 0 else {
                        if errno == EEXIST { throw SplitCombineError.alreadyExists(name) }
                        throw SplitCombineError.cannotWrite(describe(path(target)))
                    }
                    placed.append(target)
                }
            }
        } catch {
            for url in placed { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return names.map { folder.appending(path: $0) }
    }

    // MARK: Combine

    public enum Check: Equatable, Sendable {
        case passed
        case notChecked
        case mismatch(expectedSize: Int64?, expectedCRC: UInt32?, size: Int64, crc32: UInt32)
    }

    public struct CombineOutput: Sendable {
        /// The joined file, under its final name inside `staging`.
        public let staged: URL
        /// The hidden staging folder in the target folder; the caller removes it after moving `staged` out.
        public let staging: URL
        public let size: Int64
        public let crc32: UInt32
        public let check: Check
    }

    /// Joins the parts of `set` into `<folder>/<staging>/<name>` and checks the result against the set's
    /// checksum file. On an error or cancellation the staging folder is removed.
    public static func combine(
        _ set: PartSet, name: String, into folder: URL, progress: @Sendable (Int64) -> Void = { _ in }
    ) async throws -> CombineOutput {
        guard !set.parts.isEmpty else { throw SplitCombineError.noParts }
        let staging = try makeStaging(in: folder)
        do {
            let staged = staging.appending(path: name)
            let stagedPath = path(staged)
            let output = try createExclusive(stagedPath)
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 16)
            defer { buffer.deallocate() }
            var crc = CRC32()
            var done: Int64 = 0
            do {
                for part in set.parts {
                    let partPath = path(part)
                    let input = try openForReading(partPath)
                    defer { close(input) }
                    _ = try regularFileSize(input, name: part.lastPathComponent, path: partPath)
                    while true {
                        try Task.checkCancellation()
                        let n = try readSome(input, buffer, chunkSize, path: partPath)
                        if n == 0 { break }
                        let bytes = UnsafeRawBufferPointer(rebasing: buffer[0..<n])
                        crc.update(bytes)
                        try writeAll(output, bytes, path: stagedPath)
                        done += Int64(n)
                        progress(done)
                    }
                }
            } catch {
                close(output)
                throw error
            }
            guard close(output) == 0 else { throw SplitCombineError.cannotWrite(describe(stagedPath)) }
            try Task.checkCancellation()
            return CombineOutput(staged: staged, staging: staging, size: done, crc32: crc.value,
                                 check: check(size: done, crc32: crc.value, against: set.checksum))
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    static func check(size: Int64, crc32: UInt32, against checksum: SplitChecksum?) -> Check {
        guard let checksum, checksum.size != nil || checksum.crc32 != nil else { return .notChecked }
        if (checksum.size ?? size) == size, (checksum.crc32 ?? crc32) == crc32 { return .passed }
        return .mismatch(expectedSize: checksum.size, expectedCRC: checksum.crc32, size: size, crc32: crc32)
    }

    // MARK: Low level

    static func path(_ url: URL) -> String { url.path(percentEncoded: false) }

    static func describe(_ path: String) -> String { "\(path): \(String(cString: strerror(errno)))" }

    static func makeStaging(in folder: URL) throws -> URL {
        let staging = folder.appending(path: FileCopy.tempPrefix + UUID().uuidString, directoryHint: .isDirectory)
        guard mkdir(path(staging), 0o700) == 0 else { throw SplitCombineError.cannotWrite(describe(path(staging))) }
        return staging
    }

    static func openForReading(_ path: String) throws -> Int32 {
        // O_NONBLOCK: a FIFO in place of the file must not block the open; it is refused by the size check.
        var fd: Int32
        repeat { fd = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK) } while fd < 0 && errno == EINTR
        guard fd >= 0 else { throw SplitCombineError.cannotRead(describe(path)) }
        return fd
    }

    static func regularFileSize(_ fd: Int32, name: String, path: String) throws -> Int64 {
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw SplitCombineError.cannotRead(describe(path)) }
        guard st.st_mode & S_IFMT == S_IFREG else { throw SplitCombineError.notRegularFile(name) }
        // Regular files never block; clear O_NONBLOCK for plain reads.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        return Int64(st.st_size)
    }

    static func createExclusive(_ path: String) throws -> Int32 {
        var fd: Int32
        repeat { fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644) } while fd < 0 && errno == EINTR
        guard fd >= 0 else { throw SplitCombineError.cannotWrite(describe(path)) }
        return fd
    }

    static func readSome(_ fd: Int32, _ buffer: UnsafeMutableRawBufferPointer, _ count: Int, path: String) throws -> Int {
        while true {
            let n = read(fd, buffer.baseAddress, count)
            if n >= 0 { return n }
            if errno == EINTR || errno == EAGAIN { continue }
            throw SplitCombineError.cannotRead(describe(path))
        }
    }

    static func writeAll(_ fd: Int32, _ bytes: UnsafeRawBufferPointer, path: String) throws {
        var offset = 0
        while offset < bytes.count {
            let n = write(fd, bytes.baseAddress! + offset, bytes.count - offset)
            if n < 0 {
                if errno == EINTR { continue }
                throw SplitCombineError.cannotWrite(describe(path))
            }
            offset += n
        }
    }
}
