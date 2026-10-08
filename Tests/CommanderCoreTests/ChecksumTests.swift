// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import Testing
import Foundation
import CryptoKit
@testable import CommanderCore

/// Every test works in its own UUID-named directory under
/// FileManager.default.temporaryDirectory, removed when the test ends.
private func withTempDir<T>(_ body: (URL) async throws -> T) async rethrows -> T {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ChecksumTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    return try await body(root)
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func scalars(_ s: String) -> [UInt32] { s.unicodeScalars.map(\.value) }

@Suite struct ChecksumDigestTests {
    @Test func crcVector() {
        var crc = CRC32()
        Data("123456789".utf8).withUnsafeBytes { crc.update($0) }
        #expect(crc.hex == "CBF43926")
    }

    @Test func knownVectorsOfABC() async throws {
        try await withTempDir { dir in
            let file = dir.appendingPathComponent("abc.txt")
            try write("abc", to: file)
            let d = try Checksums.digests(of: file, algorithms: Set(ChecksumAlgorithm.allCases))
            #expect(d[.crc32] == "352441C2")
            #expect(d[.md5] == "900150983cd24fb0d6963f7d28e17f72")
            #expect(d[.sha1] == "a9993e364706816aba3e25717850c26c9cd0d89d")
            #expect(d[.sha256] == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            #expect(d[.sha512] == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        }
    }

    @Test func multiChunkFileMatchesOneShot() async throws {
        try await withTempDir { dir in
            var bytes = [UInt8](repeating: 0, count: (5 << 20) / 2 + 13)
            var seed: UInt32 = 12345
            for i in bytes.indices {
                seed = seed &* 1_103_515_245 &+ 12345
                bytes[i] = UInt8(truncatingIfNeeded: seed >> 16)
            }
            let data = Data(bytes)
            let file = dir.appendingPathComponent("big.bin")
            try data.write(to: file)
            var last: Int64 = 0
            var calls = 0
            let d = try Checksums.digests(of: file, algorithms: [.crc32, .md5, .sha256, .sha512]) { n in
                last = n
                calls += 1
            }
            #expect(last == Int64(data.count))
            #expect(calls >= 3)
            #expect(d[.md5] == Hex.lower(Insecure.MD5.hash(data: data)))
            #expect(d[.sha256] == Hex.lower(SHA256.hash(data: data)))
            #expect(d[.sha512] == Hex.lower(SHA512.hash(data: data)))
            // Reference: bitwise CRC-32.
            var c: UInt32 = 0xFFFF_FFFF
            for b in bytes {
                c ^= UInt32(b)
                for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            }
            #expect(d[.crc32] == String(format: "%08X", c ^ 0xFFFF_FFFF))
        }
    }

    @Test func refusesNonRegularFile() async throws {
        await withTempDir { dir in
            #expect(throws: ChecksumError.notRegularFile) {
                try Checksums.digests(of: dir, algorithms: [.md5])
            }
            #expect(throws: ChecksumError.self) {
                try Checksums.digests(of: dir.appendingPathComponent("nope"), algorithms: [.md5])
            }
        }
    }

    @Test func algorithmMetadata() {
        #expect(ChecksumAlgorithm.forListFile(named: "x.SHA256") == .sha256)
        #expect(ChecksumAlgorithm.forListFile(named: "a.b.sfv") == .crc32)
        #expect(ChecksumAlgorithm.forListFile(named: "x.txt") == nil)
        #expect(ChecksumAlgorithm.allCases.map(\.hexLength) == [8, 32, 40, 64, 128])
    }

    @Test func collectsRegularFilesOnly() async throws {
        try await withTempDir { dir in
            try write("1", to: dir.appendingPathComponent("b/file10.txt"))
            try write("2", to: dir.appendingPathComponent("b/file2.txt"))
            try write("3", to: dir.appendingPathComponent("b/deep/c.txt"))
            try write("4", to: dir.appendingPathComponent("a.txt"))
            try write("5", to: dir.appendingPathComponent("elsewhere/x.txt"))
            let fm = FileManager.default
            try fm.createSymbolicLink(atPath: dir.appendingPathComponent("b/linkfile").path, withDestinationPath: "file2.txt")
            try fm.createSymbolicLink(atPath: dir.appendingPathComponent("b/linkdir").path,
                                      withDestinationPath: dir.appendingPathComponent("elsewhere").path)
            let found = try Checksums.files(
                in: [dir.appendingPathComponent("b"), dir.appendingPathComponent("a.txt"),
                     dir.appendingPathComponent("b/linkfile")],
                relativeTo: dir
            )
            #expect(found.map(\.path) == ["a.txt", "b/deep/c.txt", "b/file2.txt", "b/file10.txt"])
            let outside = try Checksums.files(in: [dir.appendingPathComponent("a.txt")],
                                              relativeTo: dir.appendingPathComponent("b"))
            #expect(outside.first?.path.hasPrefix("/") == true)
        }
    }
}

@Suite struct ChecksumListTests {
    @Test func gnuRoundTrip() throws {
        let nfc = "příliš žluťoučký.txt".precomposedStringWithCanonicalMapping
        let nfd = "dir/kůň.txt".decomposedStringWithCanonicalMapping
        let names = ["a b.txt", nfc, nfd, "back\\slash.txt", "new\nline.txt", "cr\rname", " lead", "*star"]
        let digest = String(repeating: "ab", count: 16)
        let (data, skipped) = Checksums.listData(names.map { ($0, digest) }, algorithm: .md5)
        #expect(skipped.isEmpty)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("\(digest)  a b.txt\n"))
        #expect(text.contains("\\\(digest)  back\\\\slash.txt\n"))
        #expect(text.contains("\\\(digest)  new\\nline.txt\n"))
        #expect(!text.contains("\r"))
        let list = try Checksums.parse(data, fileName: "list.md5")
        #expect(list.algorithm == .md5)
        #expect(list.invalidLines.isEmpty)
        #expect(list.entries.map { scalars($0.path) } == names.map(scalars))
        #expect(list.entries.map(\.line) == Array(1...names.count))
    }

    @Test func sfvSkipsUnrepresentableNames() throws {
        let entries = [("my file.txt", "cbf43926"), ("bad\nname", "00000000"), ("x\\y", "00000001")]
        let (data, skipped) = Checksums.listData(entries, algorithm: .crc32)
        #expect(skipped == ["bad\nname", "x\\y"])
        #expect(String(decoding: data, as: UTF8.self) == "my file.txt CBF43926\n")
        let list = try Checksums.parse(data, fileName: "x.sfv")
        #expect(list.entries == [ChecksumList.Entry(path: "my file.txt", digest: "cbf43926", line: 1)])
    }

    @Test func parsesFormsCommentsAndInvalidLines() throws {
        let md5 = "900150983cd24fb0d6963f7d28e17f72"
        let text = "# comment\r\n\(md5)  a.txt\r\n\(md5) *bin.dat\r\n\(md5) single.txt\r\n\r\n"
            + "garbage line\r\nMD5 (tag (x).txt) = \(md5.uppercased())\r\n\(md5.dropLast())  short.txt\r\n"
            + "win\\dir\\f.txt\r\n\(md5)  win\\dir\\f.txt\r\nSHA1 (wrong) = \(md5)\r\n"
        let list = try Checksums.parse(Data(text.utf8), fileName: "list.md5")
        #expect(list.entries.map(\.path) == ["a.txt", "bin.dat", "single.txt", "tag (x).txt", "win/dir/f.txt"])
        #expect(list.entries.allSatisfy { $0.digest == md5 })
        #expect(list.invalidLines == [6, 8, 9, 11])
        #expect(list.encoding == .utf8)
    }

    @Test func algorithmFromTagsAndLength() throws {
        let sha256 = String(repeating: "0a", count: 32)
        let tagged = try Checksums.parse(Data("SHA-256 (a) = \(sha256)\nSHA256 (b) = \(sha256)\n".utf8), fileName: "sums.txt")
        #expect(tagged.algorithm == .sha256)
        #expect(tagged.entries.map(\.path) == ["a", "b"])

        let sha1 = String(repeating: "f", count: 40)
        let byLength = try Checksums.parse(Data("\n\(sha1)  x\n".utf8), fileName: "CHECKSUMS")
        #expect(byLength.algorithm == .sha1)
        let sha512 = try Checksums.parse(Data("\(String(repeating: "1", count: 128))  y\n".utf8), fileName: "s")
        #expect(sha512.algorithm == .sha512)

        let sfv = try Checksums.parse(Data("; made by tool\nsome file.bin   DEADBEEF\n".utf8), fileName: "list.txt")
        #expect(sfv.algorithm == .crc32)
        #expect(sfv.entries == [ChecksumList.Entry(path: "some file.bin", digest: "deadbeef", line: 2)])

        #expect(throws: ChecksumError.unknownAlgorithm) {
            try Checksums.parse(Data("hello world\n".utf8), fileName: "readme")
        }
        #expect(throws: ChecksumError.noEntries) {
            try Checksums.parse(Data("hello world\n".utf8), fileName: "x.md5")
        }
    }

    @Test func utf16WithBOM() throws {
        let md5 = "900150983cd24fb0d6963f7d28e17f72"
        var data = Data([0xFF, 0xFE])
        data.append("\(md5)  žluť.txt\r\n".data(using: .utf16LittleEndian) ?? Data())
        let list = try Checksums.parse(data, fileName: "x.md5")
        #expect(list.encoding == .utf16LE)
        #expect(list.entries.map(\.path) == ["žluť.txt"])
    }

    @Test func legacyEncodings() throws {
        let md5 = "900150983cd24fb0d6963f7d28e17f72"
        // "café.txt" in Windows-1252 (é = 0xE9), default fallback.
        var w1252 = Data("\(md5)  caf".utf8)
        w1252.append(contentsOf: [0xE9])
        w1252.append(Data(".txt\n".utf8))
        let l1 = try Checksums.parse(w1252, fileName: "x.md5")
        #expect(l1.encoding == .windows1252)
        #expect(l1.entries.first?.path == "café.txt")

        // "šňůra.txt" in Windows-1250 (š = 0x9A, ň = 0xF2, ů = 0xF9).
        var w1250 = Data("\(md5)  ".utf8)
        w1250.append(contentsOf: [0x9A, 0xF2, 0xF9])
        w1250.append(Data("ra.txt\n".utf8))
        let l2 = try Checksums.parse(w1250, fileName: "x.md5", fallback: .windows1250)
        #expect(l2.encoding == .windows1250)
        #expect(l2.entries.first?.path == "šňůra.txt")
    }

    @Test func nulBecomesReplacementCharacter() async throws {
        try await withTempDir { dir in
            let md5 = "900150983cd24fb0d6963f7d28e17f72"
            var data = Data("\(md5)  a".utf8)
            data.append(0)
            data.append(Data("b.txt\n\(md5)  c.txt\n".utf8))
            let list = try Checksums.parse(data, fileName: "x.md5")
            #expect(list.entries.map(\.path) == ["a\u{FFFD}b.txt", "c.txt"])
            try write("abc", to: dir.appendingPathComponent("a"))
            let results = try await Checksums.verify(list, listDirectory: dir, mounts: MountTable(mountPoints: ["/"]))
            #expect(results.map(\.status) == [.missing, .missing])
        }
    }
}

@Suite struct ChecksumVerifyTests {
    static let abcMD5 = "900150983cd24fb0d6963f7d28e17f72"

    /// tmp/vol is the list's (fake) volume, tmp/vol/other another volume, tmp/outside on "/".
    private func setUp(_ dir: URL) throws -> (vol: URL, mounts: MountTable) {
        let vol = dir.appendingPathComponent("vol")
        try write("abc", to: vol.appendingPathComponent("a.txt"))
        try write("abc", to: vol.appendingPathComponent("sub/b.txt"))
        try write("xyz", to: vol.appendingPathComponent("bad.txt"))
        try write("abc", to: vol.appendingPathComponent("other/secret.txt"))
        try write("abc", to: dir.appendingPathComponent("outside/secret.txt"))
        let mounts = MountTable(mountPoints: ["/", vol.path, vol.appendingPathComponent("other").path])
        return (vol, mounts)
    }

    private func list(_ paths: [String]) -> ChecksumList {
        ChecksumList(
            algorithm: .md5,
            entries: paths.enumerated().map { ChecksumList.Entry(path: $1, digest: Self.abcMD5, line: $0 + 1) },
            invalidLines: [], encoding: .utf8
        )
    }

    @Test func okMismatchMissing() async throws {
        try await withTempDir { dir in
            let (vol, mounts) = try setUp(dir)
            let progress = ProgressLog()
            let results = try await Checksums.verify(
                list(["a.txt", "bad.txt", "nope.txt", "sub/../sub/b.txt", "../vol/a.txt", "sub"]),
                listDirectory: vol, mounts: mounts, progress: { progress.add($0, $1) }
            )
            let xyz = Hex.lower(Insecure.MD5.hash(data: Data("xyz".utf8)))
            #expect(results.map(\.status) == [.ok, .mismatch(actual: xyz), .missing, .ok, .ok, .missing])
            #expect(progress.last == [6, 6])
        }
    }

    @Test func refusesOtherVolumes() async throws {
        try await withTempDir { dir in
            let (vol, mounts) = try setUp(dir)
            let fm = FileManager.default
            try fm.createSymbolicLink(atPath: vol.appendingPathComponent("linkOut").path,
                                      withDestinationPath: dir.appendingPathComponent("outside").path)
            try fm.createSymbolicLink(atPath: vol.appendingPathComponent("linkOther").path, withDestinationPath: "other")
            try fm.createSymbolicLink(atPath: vol.appendingPathComponent("linkUp").path, withDestinationPath: "../outside")
            try fm.createSymbolicLink(atPath: vol.appendingPathComponent("linkIn").path, withDestinationPath: "sub")
            try fm.createSymbolicLink(atPath: vol.appendingPathComponent("loop").path, withDestinationPath: "loop")
            let outsideAbsolute = dir.appendingPathComponent("outside/secret.txt").path
            let paths = [
                outsideAbsolute, "../outside/secret.txt", "other/secret.txt", "linkOut/secret.txt",
                "linkOther/secret.txt", "linkUp/secret.txt", "loop", "linkIn/b.txt",
                vol.appendingPathComponent("a.txt").path,
            ]
            let results = try await Checksums.verify(list(paths), listDirectory: vol, mounts: mounts)
            #expect(results.map(\.status) == Array(repeating: .missing, count: 7) + [.ok, .ok])

            // The same files are real, readable and on the same device: only the lexical
            // volume rule rejected them above.
            let plain = MountTable(mountPoints: ["/"])
            for path in paths.prefix(6) {
                #expect(Checksums.resolve(path, listDirectory: vol, mounts: plain) != nil)
                #expect(Checksums.resolve(path, listDirectory: vol, mounts: mounts) == nil)
            }
        }
    }

    @Test func refusesBadNamesAndWindowsForms() async throws {
        try await withTempDir { dir in
            let (vol, mounts) = try setUp(dir)
            try write("abc", to: vol.appendingPathComponent("ctl\u{1}name"))
            let paths = ["ctl\u{1}name", "del\u{7F}", "x\u{FFFD}", "C:\\x", "C:/x", "c:", "//server/x",
                         "\\\\server\\x", ""]
            let results = try await Checksums.verify(list(paths), listDirectory: vol, mounts: mounts)
            #expect(results.allSatisfy { $0.status == .missing })
        }
    }

    @Test func emptyMountTableRefusesEverything() async throws {
        try await withTempDir { dir in
            let (vol, _) = try setUp(dir)
            #expect(Checksums.resolve("a.txt", listDirectory: vol, mounts: MountTable(mountPoints: [])) == nil)
        }
    }

    @Test func realMountTable() async throws {
        try await withTempDir { dir in
            let (vol, _) = try setUp(dir)
            let mounts = MountTable.current()
            #expect(mounts.mountPoints.contains("/"))
            let results = try await Checksums.verify(list(["a.txt", "sub/b.txt"]), listDirectory: vol)
            #expect(results.map(\.status) == [.ok, .ok])
        }
    }

    @Test func mountPointMatching() {
        let mounts = MountTable(mountPoints: ["/", "/Volumes/Share", "/Volumes/Share/inner", "/vol"])
        #expect(mounts.mountPoint(for: "/Users/x") == "/")
        #expect(mounts.mountPoint(for: "/volume/x") == "/")
        #expect(mounts.mountPoint(for: "/vol") == "/vol")
        #expect(mounts.mountPoint(for: "/Volumes/Share/a/b") == "/Volumes/Share")
        #expect(mounts.mountPoint(for: "/Volumes/Share/inner/a") == "/Volumes/Share/inner")
        #expect(mounts.mountPoint(for: "/Volumes/Share/x/../inner//a") == "/Volumes/Share/inner")
        #expect(mounts.mountPoint(for: "/VOLUMES/share/a") == "/Volumes/Share")
        #expect(mounts.mountPoint(for: "/Volumes/Share/../Other") == "/")
    }

    @Test func cancellation() async throws {
        try await withTempDir { dir in
            let (vol, mounts) = try setUp(dir)
            let entries = list(["a.txt", "sub/b.txt"])
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await Checksums.verify(entries, listDirectory: vol, mounts: mounts)
            }
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [Int] = []

    func add(_ done: Int, _ total: Int) {
        lock.lock()
        value = [done, total]
        lock.unlock()
    }

    var last: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
