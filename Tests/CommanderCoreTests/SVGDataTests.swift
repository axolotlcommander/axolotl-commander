// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct SVGDataTests {
    static let svg = Data(String(repeating: "<svg xmlns=\"http://www.w3.org/2000/svg\"/>\n", count: 200).utf8)

    static func gzip(_ data: Data) throws -> Data {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.svg")
        try data.write(to: file)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        p.arguments = ["-c", file.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return out
    }

    @Test func plainPassesThrough() throws {
        #expect(try SVGData.unpack(Self.svg) == Self.svg)
    }

    @Test func gzipUnpacks() throws {
        let z = try Self.gzip(Self.svg)
        #expect(z.count < Self.svg.count)
        #expect(try SVGData.unpack(z) == Self.svg)
    }

    @Test func tooLarge() throws {
        let z = try Self.gzip(Self.svg)
        #expect(throws: SVGData.Failure.tooLarge) { try SVGData.unpack(z, maxSize: 100) }
    }

    @Test func truncatedIsCorrupt() throws {
        let z = try Self.gzip(Self.svg)
        let cut = Data(z.prefix(z.count / 2))
        #expect(throws: SVGData.Failure.corrupt) { try SVGData.unpack(cut) }
    }
}
