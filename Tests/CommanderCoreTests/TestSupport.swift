// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Darwin

// Shared helpers for file system tests. Every test that touches the disk works inside a
// UUID-named directory under FileManager.default.temporaryDirectory that the helper creates
// and removes; nothing outside it is ever written.
//
// Older test files keep their own private variants; new tests use these.

enum TestSandbox {
    /// Runs `body` with a fresh sandbox directory (symlinks resolved, so `/private/var/...`).
    /// Restores write/search permission on everything inside before removing it.
    static func with<T>(_ prefix: String = "axo-test",
                        _ body: (URL) async throws -> T) async throws -> T {
        let root = try make(prefix)
        defer { remove(root) }
        return try await body(root)
    }

    static func with<T>(_ prefix: String = "axo-test", sync body: (URL) throws -> T) throws -> T {
        let root = try make(prefix)
        defer { remove(root) }
        return try body(root)
    }

    private static func make(_ prefix: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root.resolvingSymlinksInPath()
    }

    private static func remove(_ root: URL) {
        // A test may have locked down a subdirectory (chmod 000); open it up again first.
        if let walker = FileManager.default.enumerator(atPath: root.path) {
            chmod(root.path, 0o755)
            while let rel = walker.nextObject() as? String {
                let path = root.path + "/" + rel
                var st = Darwin.stat()
                if lstat(path, &st) == 0, st.st_mode & S_IFMT == S_IFDIR { chmod(path, 0o755) }
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes bytes under the exact name given (no path normalization).
    static func write(_ url: URL, _ text: String) throws {
        try write(url, Data(text.utf8))
    }

    static func write(_ url: URL, _ data: Data) throws {
        let fd = open(url.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        let n = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard n == data.count else { throw POSIXError(.EIO) }
    }

    static func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Directory entries exactly as stored (sorted by code units, not normalized).
    static func names(in url: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
            .sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) }
    }

    static func mkdirs(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

extension URL {
    /// Child URL built by plain string concatenation (keeps the exact code units).
    func child(_ name: String) -> URL { URL(fileURLWithPath: path + "/" + name) }
}
