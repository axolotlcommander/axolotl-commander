// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// FileManager.default.temporaryDirectory, removed when the test ends.
private func withTempDir<T>(_ body: (URL) async throws -> T) async rethrows -> T {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("SplitCombineTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    return try await body(root)
}

private func names(_ folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
}

private func bytes(_ count: Int, seed: UInt8 = 7) -> Data {
    var state = UInt32(seed)
    return Data((0..<count).map { _ in
        state = state &* 1_103_515_245 &+ 12345
        return UInt8(truncatingIfNeeded: state >> 16)
    })
}

/// Split File / Combine Files (spec 029); everything in a temporary folder.
@Suite struct SplitCombineTests {
    // MARK: Sizes

    @Test func presets() {
        #expect(PartSize.Preset.email.bytes == 26_214_400)
        #expect(PartSize.Preset.cd.bytes == 734_003_200)
        #expect(PartSize.Preset.dvd.bytes == 4_697_620_480)
        #expect(PartSize.Preset.dvd.bytes < 4_700_372_992)
        #expect(PartSize.Preset.fat32.bytes == 4_294_967_295)
        #expect(PartSize.Preset.matching(104_857_600) == .hundred)
        #expect(PartSize.defaultSize == PartSize.Preset.hundred.bytes)
    }

    @Test func parser() {
        #expect(PartSize.parse("123456") == 123_456)
        #expect(PartSize.parse("10M") == 10_485_760)
        #expect(PartSize.parse("10 MB") == 10_485_760)
        #expect(PartSize.parse("1,5 G") == 1_610_612_736)
        #expect(PartSize.parse("1.5g") == 1_610_612_736)
        #expect(PartSize.parse("700000k") == 716_800_000)
        #expect(PartSize.parse(" 2 kB ") == 2048)
        #expect(PartSize.parse("100B") == 100)
        #expect(PartSize.parse("0,5") == nil)            // below one byte
        #expect(PartSize.parse("0") == nil)
        #expect(PartSize.parse("") == nil)
        #expect(PartSize.parse("abc") == nil)
        #expect(PartSize.parse("1.2.3M") == nil)
        #expect(PartSize.parse("M") == nil)
        #expect(PartSize.parse("-5M") == nil)
        #expect(PartSize.parse("5T") == nil)
    }

    @Test func countsAndProblems() {
        #expect(PartSize.count(fileSize: 100, partSize: 25) == 4)
        #expect(PartSize.count(fileSize: 101, partSize: 25) == 5)
        #expect(PartSize.count(fileSize: 0, partSize: 25) == 0)
        // Above 4 GB.
        #expect(PartSize.count(fileSize: 6_000_000_000, partSize: PartSize.Preset.fat32.bytes) == 2)
        #expect(PartSize.problem(fileSize: 100, partSize: nil) == .invalid)
        #expect(PartSize.problem(fileSize: 100, partSize: 100) == .notLarger)
        #expect(PartSize.problem(fileSize: 0, partSize: 10) == .notLarger)
        #expect(PartSize.problem(fileSize: 101, partSize: 100) == nil)
        #expect(PartSize.problem(fileSize: 999, partSize: 1) == nil)
        #expect(PartSize.problem(fileSize: 1000, partSize: 1) == .tooManyParts)
    }

    // MARK: Names and checksum file

    @Test func partNames() {
        #expect(PartName.name(base: "a.zip", index: 1) == "a.zip.001")
        #expect(PartName.name(base: "a.zip", index: 999) == "a.zip.999")
        #expect(PartName.name(base: "a", index: 1000) == "a.1000")
        #expect(PartName.parse("a.zip.002")! == ("a.zip", 2, 3))
        #expect(PartName.parse("a.0010")! == ("a", 10, 4))
        #expect(PartName.parse("a.000") == nil)
        #expect(PartName.parse("a.01") == nil)
        #expect(PartName.parse(".001") == nil)
        #expect(PartName.parse("a.0x1") == nil)
        #expect(PartName.isChecksumFile("a.zip.CRC"))
        #expect(!PartName.isChecksumFile(".crc"))
    }

    @Test func checksumFileText() throws {
        let data = SplitChecksum.text(name: "report.zip", size: 1234, crc32: 0x0A1B_2C3D)
        #expect(String(decoding: data, as: UTF8.self) == "filename=report.zip\r\nsize=1234\r\ncrc32=0A1B2C3D\r\n")
        #expect(SplitChecksum(data: data) == SplitChecksum(name: "report.zip", size: 1234, crc32: 0x0A1B_2C3D))
        let lenient = Data("[x]\nFileName = report.zip \rSIZE= 99\nCrc32=0a1b2c3d\nother=1\n".utf8)
        #expect(SplitChecksum(data: lenient) == SplitChecksum(name: "report.zip", size: 99, crc32: 0x0A1B_2C3D))
        #expect(SplitChecksum(data: Data("nothing here".utf8)) == nil)
        for bad in ["", ".", "..", "a/b"] {
            #expect(SplitChecksum(data: Data("filename=\(bad)\nsize=1\n".utf8))?.name == nil)
        }
        // Latin-1 names from other programs.
        let latin = Data("filename=caf\u{E9}.txt\r\n".data(using: .isoLatin1)!)
        #expect(SplitChecksum(data: latin)?.name == "café.txt")
    }

    // MARK: Sets

    @Test func setFromAnyPartOrTheChecksumFile() throws {
        let folder = URL(filePath: "/x")
        let all = ["a.zip.001", "a.zip.002", "a.zip.003", "a.zip.crc", "b.001", "a.zip", "a.zip.0001"]
        for cursor in ["a.zip.001", "a.zip.003", "a.zip.crc"] {
            let set = try PartSet.find(around: cursor, among: all, in: folder)
            #expect(set.parts.map(\.lastPathComponent) == ["a.zip.001", "a.zip.002", "a.zip.003"])
            #expect(set.checksumFile?.lastPathComponent == "a.zip.crc")
            #expect(set.defaultName == "a.zip")
        }
        #expect(throws: SplitCombineError.missingParts(["a.zip.002"])) {
            try PartSet.find(around: "a.zip.001", among: ["a.zip.001", "a.zip.003"], in: folder)
        }
        #expect(throws: SplitCombineError.missingParts(["a.zip.001"])) {
            try PartSet.find(around: "a.zip.002", among: ["a.zip.002"], in: folder)
        }
        #expect(throws: SplitCombineError.missingParts(["a.zip.001"])) {
            try PartSet.find(around: "a.zip.crc", among: ["a.zip.crc"], in: folder)
        }
        #expect(throws: SplitCombineError.noParts) { try PartSet.find(around: "a.zip", among: all, in: folder) }
        // A single part is a set of one.
        #expect(try PartSet.find(around: "b.001", among: all, in: folder).parts.count == 1)
    }

    @Test func markedFilesInNaturalOrder() throws {
        let urls = ["part10", "part2", "part1", "notes.crc"].map { URL(filePath: "/x/\($0)") }
        let set = try PartSet.marked(urls)
        #expect(set.parts.map(\.lastPathComponent) == ["part1", "part2", "part10"])
        #expect(set.checksumFile?.lastPathComponent == "notes.crc")
        #expect(set.defaultName == "part1")
        #expect(try PartSet.marked([URL(filePath: "/x/movie.mkv.001"), URL(filePath: "/x/movie.mkv.002")]).defaultName
            == "movie.mkv")
        #expect(try PartSet.marked([URL(filePath: "/x/a.txt"), URL(filePath: "/x/b.txt")]).defaultName == "a")
        #expect(throws: SplitCombineError.noParts) { try PartSet.marked([URL(filePath: "/x/a.crc")]) }
    }

    // MARK: Split and combine

    @Test func splitAndCombineRoundTrip() async throws {
        try await withTempDir { root in
            let source = root.appending(path: "src")
            let out = root.appending(path: "out")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            for (size, part) in [(10_000, 2_500), (10_001, 2_500), (5_000, 4_999)] {
                let file = source.appending(path: "data \(size).bin")
                let content = bytes(size, seed: UInt8(size % 251))
                try content.write(to: file)
                let written = try await FileSplitter.split(source: file, name: file.lastPathComponent, partSize: Int64(part),
                                                           writeChecksum: true, into: out)
                let count = PartSize.count(fileSize: Int64(size), partSize: Int64(part))
                #expect(written.count == count + 1)
                #expect(written.dropLast().allSatisfy { (try? Data(contentsOf: $0).count) ?? 0 <= part })
                #expect(try Data(contentsOf: written[0]).count == part)

                let set = try PartSet.find(around: written[1].lastPathComponent, in: out)
                #expect(set.parts.count == count)
                #expect(try set.totalSize() == Int64(size))
                #expect(try set.partSizes().dropLast().allSatisfy { $0 == Int64(part) })
                let output = try await FileSplitter.combine(set, name: "joined", into: source)
                #expect(output.check == .passed)
                #expect(try Data(contentsOf: output.staged) == content)
                try FileManager.default.removeItem(at: output.staging)
                #expect(try Data(contentsOf: file) == content)  // the original is untouched
            }
            #expect(!names(source).contains { $0.hasPrefix(".~icmd-") })
            #expect(!names(out).contains { $0.hasPrefix(".~icmd-") })
        }
    }

    @Test func mismatchIsReported() async throws {
        try await withTempDir { root in
            let file = root.appending(path: "f")
            try bytes(3000).write(to: file)
            let out = root.appending(path: "out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let parts = try await FileSplitter.split(source: file, name: "f", partSize: 1000, writeChecksum: true, into: out)
            var second = try Data(contentsOf: parts[1])
            second[10] ^= 0xFF
            try second.write(to: parts[1])
            let output = try await FileSplitter.combine(try PartSet.find(around: "f.crc", in: out), name: "f", into: root.appending(path: "out"))
            guard case .mismatch(let expectedSize, let expectedCRC, let size, let crc) = output.check else {
                Issue.record("expected a mismatch")
                return
            }
            #expect(expectedSize == 3000 && size == 3000 && expectedCRC != crc)
            // Without the last part the size differs too.
            try FileManager.default.removeItem(at: output.staging)
            try FileManager.default.removeItem(at: parts[2])
            let short = try await FileSplitter.combine(try PartSet.find(around: "f.001", in: out), name: "f", into: out)
            if case .mismatch(_, _, let size, _) = short.check {
                #expect(size == 2000)
            } else {
                Issue.record("expected a size mismatch")
            }
            try FileManager.default.removeItem(at: short.staging)
            // No checksum file: not checked.
            let plain = try await FileSplitter.combine(try PartSet.marked([parts[0], parts[1]]), name: "g", into: out)
            #expect(plain.check == .notChecked)
        }
    }

    @Test func existingNamesAreKeptUnlessReplacing() async throws {
        try await withTempDir { root in
            let file = root.appending(path: "f")
            try bytes(3000).write(to: file)
            let out = root.appending(path: "out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let old = Data("old".utf8)
            try old.write(to: out.appending(path: "f.002"))
            #expect(try FileSplitter.existingNames(base: "f", count: 3, checksum: true, in: out) == ["f.002"])
            await #expect(throws: SplitCombineError.alreadyExists("f.002")) {
                try await FileSplitter.split(source: file, name: "f", partSize: 1000, writeChecksum: true, into: out)
            }
            // Nothing of the failed run stays; the old file is unchanged.
            #expect(names(out) == ["f.002"])
            #expect(try Data(contentsOf: out.appending(path: "f.002")) == old)
            _ = try await FileSplitter.split(source: file, name: "f", partSize: 1000, writeChecksum: false, into: out,
                                             replacing: ["f.002"])
            #expect(names(out) == ["f.001", "f.002", "f.003"])
            #expect(try Data(contentsOf: out.appending(path: "f.002")).count == 1000)
            // A folder with a part's name cannot be replaced.
            try FileManager.default.createDirectory(at: out.appending(path: "f.crc"), withIntermediateDirectories: false)
            #expect(throws: SplitCombineError.folderInTheWay("f.crc")) {
                try FileSplitter.existingNames(base: "f", count: 3, checksum: true, in: out)
            }
        }
    }

    @Test func cancelLeavesOnlyWhatWasThere() async throws {
        try await withTempDir { root in
            let file = root.appending(path: "big")
            try bytes(12 << 20).write(to: file)
            let out = root.appending(path: "out")
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: out.appending(path: "other.txt"))
            let task = Task {
                try await FileSplitter.split(source: file, name: "big", partSize: 1 << 20, writeChecksum: true, into: out,
                                             progress: { done in if done >= 3 << 20 { withUnsafeCurrentTask { $0?.cancel() } } })
            }
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(names(out) == ["other.txt"])

            let set = try PartSet.marked([file, file])
            let combine = Task {
                try await FileSplitter.combine(set, name: "joined", into: out,
                                               progress: { done in if done >= 3 << 20 { withUnsafeCurrentTask { $0?.cancel() } } })
            }
            await #expect(throws: CancellationError.self) { try await combine.value }
            #expect(names(out) == ["other.txt"])
        }
    }

    @Test func unreadablePartStopsCombine() async throws {
        try await withTempDir { root in
            let folder = root.appending(path: "parts")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: folder.appending(path: "x.002"), withIntermediateDirectories: false)
            try Data("a".utf8).write(to: folder.appending(path: "x.001"))
            let set = try PartSet.find(around: "x.001", in: folder)
            await #expect(throws: SplitCombineError.notRegularFile("x.002")) {
                try await FileSplitter.combine(set, name: "x", into: folder)
            }
            #expect(names(folder) == ["x.001", "x.002"])
        }
    }

    @Test func freeSpaceIsKnownForTheTempFolder() {
        #expect((FreeSpace.available(at: FileManager.default.temporaryDirectory.appending(path: "missing/deeper")) ?? 0) > 0)
    }
}
