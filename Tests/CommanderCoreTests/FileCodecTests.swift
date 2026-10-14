// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Encode and decode files (spec 030). Everything happens in a temporary folder.
@Suite struct FileCodecTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "FileCodecTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, _ name: String, in dir: URL) throws -> URL {
        let url = dir.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }

    /// Decodes `inputs` into a new staging folder inside `dir`.
    private func decode(_ inputs: [URL], in dir: URL) async throws -> [DecodedFile] {
        let staging = dir.appending(path: "staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        return try await FileCodec.decode(inputs, into: staging)
    }

    private func bytes(_ count: Int, seed: Int = 7) -> Data {
        Data((0..<count).map { UInt8(truncatingIfNeeded: ($0 &* 31 &+ seed) ^ ($0 >> 3)) })
    }

    // MARK: Building blocks

    @Test func crc16CheckValue() {
        #expect(CRC16.xmodem(Array("123456789".utf8)) == 0x31C3)
    }

    @Test func safeNames() {
        #expect(NameAllocator.safe("../../evil") == "evil")
        #expect(NameAllocator.safe("a/b/c.txt") == "c.txt")
        #expect(NameAllocator.safe("..\\x") == "x")
        #expect(NameAllocator.safe("..") == "decoded")
        #expect(NameAllocator.safe("  ") == "decoded")
        #expect(NameAllocator.safe("", fallbackExtension: "pdf") == "decoded.pdf")
        #expect(NameAllocator.safe("x:y\u{1}z") == "x_y_z")
        let long = String(repeating: "é", count: 200) + ".txt"
        let short = NameAllocator.safe(long)
        #expect(short.utf8.count <= 255 && short.hasSuffix(".txt"))
        var names = NameAllocator()
        #expect(names.unique("same.txt") == "same.txt")
        #expect(names.unique("SAME.txt") == "SAME 2.txt")
        #expect(names.unique("same.txt") == "same 3.txt")
    }

    @Test func encodedWordsAndParameters() {
        #expect(EncodedWords.decode("=?UTF-8?B?xb5sdcWlb3XEjWvDvS50eHQ=?=") == "žluťoučký.txt")
        #expect(EncodedWords.decode("=?ISO-8859-2?Q?P=F8=EDli=B9?= =?UTF-8?Q?_k=C5=AF=C5=88?=") == "Příliš kůň")
        let value = HeaderValue.parse("attachment; filename*0*=UTF-8''%C5%BElu; filename*1=\".txt\"; size=3")
        #expect(value.value == "attachment")
        #expect(value.parameters["filename"] == "žlu.txt")
        #expect(value.parameters["size"] == "3")
        #expect(HeaderValue.parse("text/plain; name=\"a \\\"b\\\";c.txt\"").parameters["name"] == "a \"b\";c.txt")
    }

    // MARK: Round trips

    @Test(arguments: [EncodeFormat.base64, .uue])
    func roundTrip(format: EncodeFormat) async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (index, size) in [0, 1, 2, 3, 44, 45, 46, 57, 1000, 2_000_000].enumerated() {
            let name = index % 2 == 0 ? "file \(size).bin" : "Příliš žluťoučký \(size).bin"
            let source = dir.appending(path: "src-\(size)")
            let content = bytes(size, seed: size)
            try content.write(to: source)
            let out = dir.appending(path: "enc-\(size)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)
            let encoded = try await FileCodec.encode(source: source, name: name, format: format, into: out)
            #expect(encoded.lastPathComponent == name + "." + format.fileExtension)
            let size64 = Int64(try Data(contentsOf: encoded).count)
            #expect(size64 <= FileCodec.encodedSize(Int64(size), name: name, format: format))
            let decoded = try await decode([encoded], in: dir)
            #expect(decoded.count == 1)
            #expect(decoded.first?.name == name)
            #expect(decoded.first?.state == .complete)
            #expect(try decoded.first.map { try Data(contentsOf: $0.url) } == content)
        }
    }

    // MARK: Other tools

    private func run(_ tool: String, _ arguments: [String], in dir: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func otherToolsReadOurOutputAndWeReadTheirs() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/uuencode") else { return }
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = bytes(10_000)
        let source = dir.appending(path: "data.bin")
        try content.write(to: source)
        let out = dir.appending(path: "out", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: false)

        let uue = try await FileCodec.encode(source: source, name: "data.bin", format: .uue, into: out)
        #expect(try run("/usr/bin/uudecode", ["-o", dir.appending(path: "u.bin").path, uue.path], in: dir) == 0)
        #expect(try Data(contentsOf: dir.appending(path: "u.bin")) == content)

        let b64 = try await FileCodec.encode(source: source, name: "data.bin", format: .base64, into: out)
        let text = try String(contentsOf: b64, encoding: .utf8)
        let body = text.components(separatedBy: "\n\n").dropFirst().joined(separator: "\n\n")
        let bodyFile = try write(body, "body.txt", in: dir)
        #expect(try run("/usr/bin/base64", ["-D", "-i", bodyFile.path, "-o", dir.appending(path: "b.bin").path], in: dir) == 0)
        #expect(try Data(contentsOf: dir.appending(path: "b.bin")) == content)

        for (flag, name) in [([String](), "theirs.uue"), (["-m"], "theirs-m.uue")] {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/uuencode")
            process.arguments = flag + [source.path, "their name.bin"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let url = dir.appending(path: name)
            try data.write(to: url)
            let decoded = try await decode([url], in: dir)
            #expect(decoded.map(\.name) == ["their name.bin"])
            #expect(decoded.first?.kind == (flag.isEmpty ? .uue : .base64))
            #expect(decoded.first?.state == .complete)
            #expect(try decoded.first.map { try Data(contentsOf: $0.url) } == content)
        }
    }

    // MARK: MIME

    @Test func mailWithTwoAttachments() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = bytes(3000)
        let lines = pdf.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        let mail = """
            From: a@example.com\r
            Subject: test\r
            MIME-Version: 1.0\r
            Content-Type: multipart/mixed;\r
             boundary="XYZ"\r
            \r
            This is a multi-part message.\r
            --XYZ\r
            Content-Type: text/plain; charset=utf-8\r
            \r
            Hello.\r
            --XYZ\r
            Content-Type: application/pdf; name="invoice.pdf"\r
            Content-Transfer-Encoding: base64\r
            Content-Disposition: attachment; filename="invoice.pdf"\r
            \r
            \(lines)\r
            --XYZ\r
            Content-Type: text/plain; name="=?UTF-8?B?xb5sdcWlb3XEjWvDvS50eHQ=?="\r
            Content-Transfer-Encoding: quoted-printable\r
            Content-Disposition: attachment\r
            \r
            P=C5=99=C3=ADli=C5=A1 =\r
            k=C5=AF=C5=88\r
            second line\r
            --XYZ--\r
            epilogue\r

            """
        let decoded = try await decode([write(mail, "mail.eml", in: dir)], in: dir)
        #expect(decoded.map(\.name) == ["invoice.pdf", "žluťoučký.txt"])
        #expect(decoded.allSatisfy { $0.state == .complete && $0.kind == .mime })
        #expect(try Data(contentsOf: decoded[0].url) == pdf)
        #expect(try String(contentsOf: decoded[1].url, encoding: .utf8) == "Příliš kůň\r\nsecond line")
    }

    @Test func nestedPartsAndForwardedMessage() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mail = """
            MIME-Version: 1.0
            Content-Type: multipart/mixed; boundary=outer

            --outer
            Content-Type: multipart/alternative; boundary="alt"

            --alt
            Content-Type: text/plain

            plain
            --alt
            Content-Type: text/html

            <p>html</p>
            --alt--
            --outer
            Content-Type: message/rfc822

            Subject: forwarded
            Content-Type: multipart/mixed; boundary=inner

            --inner
            Content-Type: text/plain
            Content-Disposition: attachment; filename*0*=UTF-8''%C5%BElu; filename*1=".txt"
            Content-Transfer-Encoding: 7bit

            line one
            line two
            --inner--
            --outer
            Content-Type: application/pdf
            Content-Transfer-Encoding: base64

            JVBERg==
            --outer--

            """
        let decoded = try await decode([write(mail, "fwd.eml", in: dir)], in: dir)
        #expect(decoded.map(\.name) == ["žlu.txt", "decoded.pdf"])
        #expect(try String(contentsOf: decoded[0].url, encoding: .utf8) == "line one\nline two")
        #expect(try String(contentsOf: decoded[1].url, encoding: .utf8) == "%PDF")
        #expect(decoded.allSatisfy { $0.state == .complete })
    }

    @Test func mailWithoutAttachmentsHasNothing() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mail = "MIME-Version: 1.0\nContent-Type: text/plain\n\nJust text.\nNothing else.\n"
        #expect(try await decode([write(mail, "plain.eml", in: dir)], in: dir).isEmpty)
        #expect(try await decode([write("Hello\nworld\n", "small.txt", in: dir)], in: dir).isEmpty)
    }

    @Test func missingClosingBoundaryIsIncomplete() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mail = "MIME-Version: 1.0\nContent-Type: multipart/mixed; boundary=b\n\n--b\nContent-Type: application/octet-stream; name=x.bin\nContent-Transfer-Encoding: base64\n\nAAEC\n"
        let decoded = try await decode([write(mail, "cut.eml", in: dir)], in: dir)
        #expect(decoded.map(\.name) == ["x.bin"])
        #expect(decoded.first?.state == .incomplete)
        #expect(try Data(contentsOf: decoded[0].url) == Data([0, 1, 2]))
    }

    // MARK: UUE, XXE, BinHex, Base64

    private func uue(_ data: Data, name: String) -> String {
        var out: [UInt8] = []
        var i = 0
        let bytes = Array(data)
        while i < bytes.count {
            FileCodec.uueLine(bytes[i..<min(i + 45, bytes.count)], into: &out)
            i += 45
        }
        return "begin 644 \(name)\n" + String(decoding: out, as: UTF8.self) + "`\nend\n"
    }

    @Test func uueInsideAPlainMailBody() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = bytes(500)
        let text = "Subject: files\nFrom: someone\n\nHere it is:\n\n" + uue(content, name: "x.bin") + "\nBye.\n"
        let decoded = try await decode([write(text, "mail.txt", in: dir)], in: dir)
        #expect(decoded.map(\.name) == ["x.bin"])
        #expect(try Data(contentsOf: decoded[0].url) == content)
    }

    @Test func uueInsideAMimeTextBody() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = bytes(100)
        let text = "MIME-Version: 1.0\nContent-Type: text/plain\n\n" + uue(content, name: "y.bin")
        let decoded = try await decode([write(text, "mail.eml", in: dir)], in: dir)
        #expect(decoded.map(\.name) == ["y.bin"])
        #expect(try Data(contentsOf: decoded[0].url) == content)
    }

    @Test func xxeIsRecognized() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let alphabet = Array("+-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
        let content = Array(bytes(200))
        var text = "begin 644 x.xx\n"
        var i = 0
        while i < content.count {
            let line = content[i..<min(i + 45, content.count)]
            var out = [alphabet[line.count]]
            var j = line.startIndex
            while j < line.endIndex {
                let a = Int(line[j])
                let b: Int = j + 1 < line.endIndex ? Int(line[j + 1]) : 0
                let c: Int = j + 2 < line.endIndex ? Int(line[j + 2]) : 0
                let values: [Int] = [a >> 2, (a & 3) << 4 | b >> 4, (b & 15) << 2 | c >> 6, c & 63]
                out += values.map { alphabet[$0] }
                j += 3
            }
            text += String(decoding: out, as: UTF8.self) + "\n"
            i += 45
        }
        text += "+\nend\n"
        let decoded = try await decode([write(text, "x.xxe", in: dir)], in: dir)
        #expect(decoded.map(\.name) == ["x.xx"])
        #expect(decoded.first?.kind == .xxe)
        #expect(try Data(contentsOf: decoded[0].url) == Data(content))
    }

    /// A BinHex 4.0 text for `data` (with run-length coding), optionally with a wrong data CRC.
    private func binhex(_ data: [UInt8], name: String, damage: Bool = false) -> String {
        func be32(_ v: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: v >> $0) } }
        func crc(_ b: [UInt8]) -> [UInt8] { let c = CRC16.xmodem(b); return [UInt8(c >> 8), UInt8(c & 0xFF)] }
        var header: [UInt8] = [UInt8(name.utf8.count)]
        header += Array(name.utf8)
        header += [0]
        header += Array("TEXTttxt".utf8)
        header += [0, 0]
        header += be32(data.count)
        header += be32(0)
        header += crc(header)
        var dataCRC = crc(data)
        if damage { dataCRC[0] ^= 0xFF }
        let stream: [UInt8] = header + data + dataCRC + [0, 0]
        // Run-length coding: runs of 4+ become "byte 0x90 count"; 0x90 itself becomes "0x90 0x00".
        var rle: [UInt8] = []
        var i = 0
        while i < stream.count {
            let b = stream[i]
            var run = 1
            while i + run < stream.count, stream[i + run] == b, run < 255 { run += 1 }
            if b == 0x90 {
                rle += [0x90, 0x00]
                run = 1
            } else if run >= 4 {
                rle += [b, 0x90, UInt8(run)]
            } else {
                rle += Array(repeating: b, count: run)
            }
            i += run
        }
        let alphabet = Array("!\"#$%&'()*+,-012345689@ABCDEFGHIJKLMNPQRSTUVXYZ[`abcdefhijklmpqr".utf8)
        var chars: [UInt8] = []
        var acc: UInt32 = 0, bits = 0
        for b in rle {
            acc = acc << 8 | UInt32(b)
            bits += 8
            while bits >= 6 {
                bits -= 6
                chars.append(alphabet[Int(acc >> UInt32(bits) & 63)])
            }
        }
        if bits > 0 { chars.append(alphabet[Int(acc << UInt32(6 - bits) & 63)]) }
        var lines: [String] = []
        var j = 0
        while j < chars.count {
            lines.append(String(decoding: chars[j..<min(j + 64, chars.count)], as: UTF8.self))
            j += 64
        }
        return "(This file must be converted with BinHex 4.0)\n:" + lines.joined(separator: "\n") + ":\n"
    }

    @Test func binhexDataFork() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        var data: [UInt8] = Array("hello ".utf8)
        data += Array(repeating: 0x41, count: 20)
        data += [0x90, 0x90, 1, 2]
        data += Array(bytes(300))
        let good = try await decode([write("Some text first\n" + binhex(data, name: "Read Me"), "a.hqx", in: dir)], in: dir)
        #expect(good.map(\.name) == ["Read Me"])
        #expect(good.first?.kind == .binhex)
        #expect(good.first?.state == .complete)
        #expect(try Data(contentsOf: good[0].url) == Data(data))

        let bad = try await decode([write(binhex(data, name: "Bad", damage: true), "b.hqx", in: dir)], in: dir)
        #expect(bad.first?.state == .damaged)
        #expect(try Data(contentsOf: bad[0].url) == Data(data))
    }

    @Test func uueWithoutEndIsIncomplete() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = bytes(450)
        let text = uue(content, name: "cut.bin").components(separatedBy: "\n").prefix(6).joined(separator: "\n")
        let decoded = try await decode([write(text, "cut.uue", in: dir)], in: dir)
        #expect(decoded.map(\.name) == ["cut.bin"])
        #expect(decoded.first?.state == .incomplete)
        #expect(try Data(contentsOf: decoded[0].url) == content.prefix(225))
    }

    @Test func piecesInSeveralFilesAreJoined() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = bytes(4500)
        let lines = uue(content, name: "big.bin").components(separatedBy: "\n")
        let first = lines.prefix(50).joined(separator: "\n") + "\n--- cut here ---\n"
        let second = "From: someone\nSubject: big.bin (2/2)\n\nsection 2 of 2\n--- cut here ---\n" + lines.dropFirst(50).joined(separator: "\n")
        let decoded = try await decode([write(first, "part1.uue", in: dir), write(second, "part2.uue", in: dir)], in: dir)
        #expect(decoded.map(\.name) == ["big.bin"])
        #expect(decoded.first?.state == .complete)
        #expect(try Data(contentsOf: decoded[0].url) == content)
    }

    @Test func plainBase64TakesTheFileName() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = bytes(1000)
        let text = content.base64EncodedString(options: [.lineLength64Characters]) + "\n"
        let a = try await decode([write(text, "photo.jpg.b64", in: dir)], in: dir)
        #expect(a.map(\.name) == ["photo.jpg"])
        #expect(try Data(contentsOf: a[0].url) == content)
        let b = try await decode([write(text, "data.txt", in: dir)], in: dir)
        #expect(b.map(\.name) == ["data.txt.bin"])
        #expect(b.first?.kind == .base64)
    }

    // MARK: Safety

    @Test func hostileAndDuplicateNamesStayInside() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let content = bytes(10)
        let text = ["../../evil", "a/b/c.txt", "..", "", "same.txt", "same.txt"].map { uue(content, name: $0) }.joined()
        let staging = dir.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let decoded = try await FileCodec.decode([write(text, "evil.uue", in: dir)], into: staging)
        #expect(decoded.map(\.name) == ["evil", "c.txt", "decoded", "decoded 2", "same.txt", "same 2.txt"])
        #expect(decoded.allSatisfy { $0.url.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL })
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["evil.uue", "staging"])
    }

    @Test func cancellingStops() async throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = try write(uue(bytes(100), name: "x"), "x.uue", in: dir)
        let staging = dir.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileCodec.decode([input], into: staging)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        let encodeTask = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FileCodec.encode(source: input, name: "x.uue", format: .base64, into: staging)
        }
        await #expect(throws: CancellationError.self) { try await encodeTask.value }
    }
}
