import Testing
import Foundation
@testable import CommanderCore

private let czech = "Příliš žluťoučký kůň úpěl ďábelské ódy."
private let unicodeText = czech + "\nZürich – Ελληνικά – 😀𝄞"

private func bytes(_ s: String, _ e: TextEncoding) -> Data { Data(e.encode(s)!) }

// MARK: Encoding detection

@Suite struct EncodingDetectionTests {
    @Test func utf8WithoutBOM() {
        let d = EncodingDetector.detect(Data(unicodeText.utf8), fallback: .windows1250)
        #expect(d == EncodingDetection(encoding: .utf8, source: .validUTF8, bomLength: 0))
    }

    @Test func utf8BOM() {
        let d = EncodingDetector.detect(Data([0xEF, 0xBB, 0xBF]) + Data(czech.utf8), fallback: .windows1250)
        #expect(d == EncodingDetection(encoding: .utf8, source: .bom, bomLength: 3))
    }

    @Test func utf16BOMs() {
        let le = Data([0xFF, 0xFE]) + bytes(unicodeText, .utf16LE)
        let be = Data([0xFE, 0xFF]) + bytes(unicodeText, .utf16BE)
        #expect(EncodingDetector.detect(le, fallback: .windows1250)
                == EncodingDetection(encoding: .utf16LE, source: .bom, bomLength: 2))
        #expect(EncodingDetector.detect(be, fallback: .windows1250)
                == EncodingDetection(encoding: .utf16BE, source: .bom, bomLength: 2))
    }

    @Test func utf16WithoutBOM() {
        let text = String(repeating: "Hello, world. This is plain text.\n", count: 5)
        let le = bytes(text, .utf16LE), be = bytes(text, .utf16BE)
        #expect(EncodingDetector.utf16WithoutBOM(le) == .utf16LE)
        #expect(EncodingDetector.utf16WithoutBOM(be) == .utf16BE)
        #expect(EncodingDetector.detect(le, fallback: .windows1250)
                == EncodingDetection(encoding: .utf16LE, source: .utf16Heuristic, bomLength: 0))
        #expect(EncodingDetector.detect(be, fallback: .windows1250)
                == EncodingDetection(encoding: .utf16BE, source: .utf16Heuristic, bomLength: 0))
        #expect(EncodingDetector.utf16WithoutBOM(Data([0, 1, 2])) == nil)
        #expect(EncodingDetector.utf16WithoutBOM(Data(czech.utf8)) == nil)
    }

    @Test func windows1250() {
        let data = bytes(czech, .windows1250)
        let a = EncodingDetector.detect(data, fallback: .windows1250)
        #expect(a == EncodingDetection(encoding: .windows1250, source: .legacyHeuristic, bomLength: 0))
        let b = EncodingDetector.detect(data, fallback: .iso8859_2)
        #expect(b == EncodingDetection(encoding: .windows1250, source: .legacyHeuristic, bomLength: 0))
    }

    @Test func iso8859_2() {
        let data = bytes(czech, .iso8859_2)
        let d = EncodingDetector.detect(data, fallback: .windows1250)
        #expect(d == EncodingDetection(encoding: .iso8859_2, source: .legacyHeuristic, bomLength: 0))
    }

    @Test func asciiIsUTF8() {
        let d = EncodingDetector.detect(Data("plain ascii\r\n".utf8), fallback: .windows1250)
        #expect(d == EncodingDetection(encoding: .utf8, source: .validUTF8, bomLength: 0))
        #expect(EncodingDetector.detect(Data(), fallback: .windows1250).encoding == .utf8)
    }

    @Test func fallbackForOtherGroups() {
        let data = Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x9A])
        let d = EncodingDetector.detect(data, fallback: .windows1252)
        #expect(d == EncodingDetection(encoding: .windows1252, source: .fallback, bomLength: 0))
        let e = EncodingDetector.detect(Data([0x61, 0xE9]), fallback: .windows1250)
        #expect(e == EncodingDetection(encoding: .windows1250, source: .fallback, bomLength: 0))
    }

    @Test func invalidUTF8() {
        #expect(!EncodingDetector.isValidUTF8(Data([0x61, 0xC5])))                 // truncated at end
        #expect(!EncodingDetector.isValidUTF8(Data([0xC0, 0x80])))                 // overlong
        #expect(!EncodingDetector.isValidUTF8(Data([0xE0, 0x80, 0x80])))           // overlong 3-byte
        #expect(!EncodingDetector.isValidUTF8(Data([0xED, 0xA0, 0x80])))           // surrogate
        #expect(!EncodingDetector.isValidUTF8(Data([0xF4, 0x90, 0x80, 0x80])))     // > U+10FFFF
        #expect(!EncodingDetector.isValidUTF8(Data([0x80])))                       // stray continuation
        #expect(!EncodingDetector.isValidUTF8(Data([0xF0, 0x9F, 0x98])))          // truncated 4-byte
        #expect(EncodingDetector.isValidUTF8(Data(unicodeText.utf8)))
        #expect(EncodingDetector.isValidUTF8(Data()))
    }

    @Test func validationCatchesLateErrors() {
        var data = Data(repeating: 0x41, count: 8 * 1024 * 1024)
        data.append(contentsOf: Array("č".utf8))
        #expect(EncodingDetector.isValidUTF8(data))
        data.append(0xFF)
        #expect(!EncodingDetector.isValidUTF8(data))
        #expect(EncodingDetector.detect(data, fallback: .windows1252).source == .fallback)
    }

    @Test func slicesWork() {
        let whole = Data([0x00, 0x00]) + Data(czech.utf8)
        let slice = whole.dropFirst(2)
        #expect(EncodingDetector.isValidUTF8(slice))
        #expect(EncodingDetector.bom(in: (Data([1]) + Data([0xEF, 0xBB, 0xBF, 0x41])).dropFirst()) != nil)
    }

    @Test func looksBinary() {
        var junk = Data()
        for i in 0..<1000 { junk.append(UInt8((i * 37 + 11) % 256)) }
        #expect(EncodingDetector.looksBinary(junk))
        #expect(EncodingDetector.looksBinary(Data([0x41, 0x00, 0x42, 0x43, 0x44, 0x45])))
        #expect(EncodingDetector.looksBinary(Data(repeating: 0x01, count: 100)))
        #expect(!EncodingDetector.looksBinary(Data("a\tb\r\nc\u{1B}[0m\u{0C}\n".utf8)))
        #expect(!EncodingDetector.looksBinary(bytes(String(repeating: "Hello world\n", count: 10), .utf16LE)))
        #expect(!EncodingDetector.looksBinary(bytes(String(repeating: "Hello world\n", count: 10), .utf16BE)))
        #expect(!EncodingDetector.looksBinary(Data([0xFF, 0xFE, 0x00, 0x00])))
        #expect(!EncodingDetector.looksBinary(Data()))
        #expect(!EncodingDetector.looksBinary(Data(czech.utf8)))
    }
}

// MARK: Decoding

@Suite struct TextDecodingTests {
    @Test func roundTrips() {
        for e in TextEncoding.allCases {
            let text: String
            switch e {
            case .utf8, .utf16LE, .utf16BE: text = unicodeText
            case .windows1250, .iso8859_2, .cp852: text = czech
            default: continue            // the Czech text is not representable
            }
            #expect(TextDecoding.decode(bytes(text, e), as: e) == text, "\(e.title)")
        }
    }

    @Test func roundTripWithBOM() {
        let data = Data([0xFF, 0xFE]) + bytes(unicodeText, .utf16LE)
        #expect(TextDecoding.decode(data, as: .utf16LE, skip: 2) == unicodeText)
        let u8 = Data([0xEF, 0xBB, 0xBF]) + Data(unicodeText.utf8)
        #expect(TextDecoding.decode(u8, as: .utf8, skip: 3) == unicodeText)
        #expect(TextDecoding.decode(u8.dropFirst(0), as: .utf8, skip: 100) == "")
    }

    @Test func limitCutsInsideCharacter() {
        let data = Data("aé".utf8)                    // 61 C3 A9
        #expect(TextDecoding.decode(data, as: .utf8, limit: 2) == "a")
        #expect(TextDecoding.decode(data, as: .utf8, limit: 3) == "aé")
        let emoji = Data("x😀".utf8)
        #expect(TextDecoding.decode(emoji, as: .utf8, limit: 3) == "x")
        #expect(TextDecoding.decode(emoji, as: .utf8, limit: 4) == "x")
        #expect(TextDecoding.decode(emoji, as: .utf8, limit: 0) == "")
        let u16 = bytes("a😀", .utf16LE)
        #expect(TextDecoding.decode(u16, as: .utf16LE, limit: 3) == "a")
        #expect(TextDecoding.decode(u16, as: .utf16LE, limit: 4) == "a")
        #expect(TextDecoding.decode(u16, as: .utf16LE, limit: 6) == "a😀")
    }

    @Test func invalidSequences() {
        #expect(TextDecoding.decode(Data([0x61, 0xFF, 0x62]), as: .utf8) == "a\u{FFFD}b")
        #expect(TextDecoding.decode(Data([0x61, 0xC5]), as: .utf8) == "a\u{FFFD}")
        #expect(TextDecoding.decode(Data([0x61, 0x00, 0x62]), as: .utf16LE) == "a\u{FFFD}")
        #expect(TextDecoding.decode(Data([0x00, 0x61, 0x00]), as: .utf16BE) == "a\u{FFFD}")
        #expect(TextDecoding.decode(Data([0x00, 0xD8, 0x61, 0x00]), as: .utf16LE) == "\u{FFFD}a")
        #expect(TextDecoding.decode(Data([0x61, 0x81, 0x62]), as: .windows1250) == "a\u{FFFD}b")
    }

    @Test func singleByteSamples() {
        #expect(TextDecoding.decode(Data([0x9A, 0x9E, 0x9D]), as: .windows1250) == "šžť")
        #expect(TextDecoding.decode(Data([0xB9, 0xBE, 0xBB]), as: .iso8859_2) == "šžť")
        #expect(TextDecoding.decode(Data([0xCF, 0xF0]), as: .windows1251) == "Пр")
        #expect(TextDecoding.decode(Data([0xF0, 0xF2]), as: .koi8r) == "ПР")
        #expect(TextDecoding.decode(Data([0xE9]), as: .iso8859_1) == "é")
        #expect(TextDecoding.decode(Data([0x8E]), as: .macRoman) == "é")
        #expect(TextDecoding.decode(Data([0x9F]), as: .cp852) == "č")
    }

    @Test func largeSingleByteIsFast() {
        let data = Data(repeating: 0x9A, count: 4 * 1024 * 1024)
        let s = TextDecoding.decode(data, as: .windows1250)
        #expect(s.unicodeScalars.count == data.count)
        #expect(TextDecoding.decode(data, as: .windows1250, skip: 1, limit: 10) == String(repeating: "š", count: 10))
    }
}

// MARK: TextEncoding

@Suite struct TextEncodingTests {
    @Test func encodeForSearch() {
        #expect(TextEncoding.windows1250.encode("š") == [0x9A])
        #expect(TextEncoding.windows1250.encode("😀") == nil)
        #expect(TextEncoding.utf8.encode("č") == [0xC4, 0x8D])
        #expect(TextEncoding.utf16LE.encode("a") == [0x61, 0x00])
        #expect(TextEncoding.utf16BE.encode("a") == [0x00, 0x61])
        #expect(TextEncoding.iso8859_2.encode("š") == [0xB9])
        #expect(TextEncoding.cp852.encode("č") == [0x9F])
    }

    @Test func tables() {
        for e in TextEncoding.allCases {
            if e.isSingleByte {
                let t = e.byteTable
                #expect(t?.count == 256, "\(e.title)")
                #expect(t?[0x41] == "A")
            } else {
                #expect(e.byteTable == nil)
            }
        }
        #expect(TextEncoding.windows1250.byteTable?[0x81] == .some(nil))
        #expect(TextEncoding.windows1250.byteTable?[0x9A] == "š")
    }

    @Test func titlesAndCodable() throws {
        #expect(TextEncoding.cp852.title == "DOS 852")
        #expect(Set(TextEncoding.allCases.map(\.title)).count == TextEncoding.allCases.count)
        let data = try JSONEncoder().encode(TextEncoding.koi8r)
        #expect(try JSONDecoder().decode(TextEncoding.self, from: data) == .koi8r)
    }
}

// MARK: Hex

@Suite struct HexFormatTests {
    @Test func offsetWidths() {
        #expect(HexFormat.offsetText(0, fileSize: 0) == "00000000")
        #expect(HexFormat.offsetText(0x1A2B, fileSize: 100_000) == "00001A2B")
        #expect(HexFormat.offsetText(0xFFFF_FFFF, fileSize: 0x1_0000_0000) == "FFFFFFFF")
        #expect(HexFormat.offsetText(0xFFFF_FFFF, fileSize: 0x1_0000_0001) == "0FFFFFFFF")
        #expect(HexFormat.offsetText(0x1_0000_0000, fileSize: 0x1_0000_0001) == "100000000")
    }

    @Test func hexText() {
        let full = Array("John Smith, 1234!".utf8.prefix(16))
        let text = HexFormat.hexText(full)
        #expect(text.count == 48)
        #expect(text == "4A 6F 68 6E 20 53 6D 69  74 68 2C 20 31 32 33 34")
        let partial = HexFormat.hexText([0x4A, 0x6F, 0x68])
        #expect(partial.count == 48)
        #expect(partial.hasPrefix("4A 6F 68   "))
        #expect(HexFormat.hexText([UInt8]()).count == 48)
        #expect(HexFormat.hexText(Array(0..<9)).count == 48)
        #expect(HexFormat.hexText(Array(0..<9)).hasPrefix("00 01 02 03 04 05 06 07  08"))
    }

    @Test func charText() {
        #expect(HexFormat.charText([0x4A, 0x00, 0x9A, 0x81, 0x0A, 0xA0], encoding: .windows1250) == "J.š...")
        #expect(HexFormat.charText([0x4A, 0x20, 0x9A, 0xFF], encoding: .utf8) == "J ..")
        #expect(HexFormat.charText([0x7F, 0x7E], encoding: .utf16LE) == ".~")
        #expect(HexFormat.charText([0xB9], encoding: .iso8859_2) == "š")
    }

    @Test func plainHex() {
        #expect(HexFormat.plainHex([0x4A, 0x6F, 0x68]) == "4A 6F 68")
        #expect(HexFormat.plainHex([UInt8]()) == "")
    }
}

// MARK: Search

@Suite struct ByteSearchTests {
    let data = Data("abc ABC abc xyz".utf8)

    @Test func forward() {
        let p = Array("abc".utf8)
        #expect(ByteSearch.find(p, in: data, from: 0) == 0)
        #expect(ByteSearch.find(p, in: data, from: 1) == 8)
        #expect(ByteSearch.find(p, in: data, from: 9) == nil)
        #expect(ByteSearch.find(Array("xyz".utf8), in: data, from: 12) == 12)
        #expect(ByteSearch.find(Array("xyz".utf8), in: data, from: 13) == nil)
        #expect(ByteSearch.find(p, in: data, from: 1000) == nil)
        #expect(ByteSearch.find(p, in: data, from: -5) == 0)
        #expect(ByteSearch.find([], in: data, from: 0) == nil)
        #expect(ByteSearch.find(Array("nope".utf8), in: data, from: 0) == nil)
        #expect(ByteSearch.find(Array("a-very-long-pattern-beyond-data".utf8), in: data, from: 0) == nil)
    }

    @Test func backward() {
        let p = Array("abc".utf8)
        #expect(ByteSearch.find(p, in: data, from: data.count, backward: true) == 8)
        #expect(ByteSearch.find(p, in: data, from: 8, backward: true) == 0)
        #expect(ByteSearch.find(p, in: data, from: 0, backward: true) == nil)
        #expect(ByteSearch.find(p, in: data, from: 1, backward: true) == 0)
        #expect(ByteSearch.find(p, in: data, from: 9999, backward: true) == 8)
        #expect(ByteSearch.find(Array("xyz".utf8), in: data, from: 12, backward: true) == nil)
        #expect(ByteSearch.find(Array("xyz".utf8), in: data, from: 13, backward: true) == 12)
    }

    @Test func slices() {
        let slice = data.dropFirst(4)                 // "ABC abc xyz"
        #expect(slice.startIndex == 4)
        #expect(ByteSearch.find(Array("abc".utf8), in: slice, from: 0) == 4)
        #expect(ByteSearch.find(Array("xyz".utf8), in: slice, from: 0) == 8)
        #expect(ByteSearch.find(Array("abc".utf8), in: slice, from: 100, backward: true) == 4)
        #expect(ByteSearch.find(Array("ABC".utf8), in: slice, from: 0, ignoringASCIICase: true) == 0)
    }

    @Test func caseFolding() {
        let p = Array("aBc".utf8)
        #expect(ByteSearch.find(p, in: data, from: 0) == nil)
        #expect(ByteSearch.find(p, in: data, from: 0, ignoringASCIICase: true) == 0)
        #expect(ByteSearch.find(p, in: data, from: 1, ignoringASCIICase: true) == 4)
        #expect(ByteSearch.find(p, in: data, from: data.count, backward: true, ignoringASCIICase: true) == 8)
        #expect(ByteSearch.find(p, in: data, from: 8, backward: true, ignoringASCIICase: true) == 4)
        // Only ASCII is folded.
        let latin = Data([0x9A, 0x8A])
        #expect(ByteSearch.find([0x8A], in: latin, from: 0, ignoringASCIICase: true) == 1)
        // '@' (0x40) and '`' (0x60) must not fold onto each other.
        #expect(ByteSearch.find([0x40], in: Data([0x60]), from: 0, ignoringASCIICase: true) == nil)
    }

    @Test func hexInput() {
        #expect(ByteSearch.parseHex("4A 6f") == [0x4A, 0x6F])
        #expect(ByteSearch.parseHex("4a6f") == [0x4A, 0x6F])
        #expect(ByteSearch.parseHex("0x4A 0x6F") == [0x4A, 0x6F])
        #expect(ByteSearch.parseHex("4A,6F") == [0x4A, 0x6F])
        #expect(ByteSearch.parseHex("  4A , 6F  ") == [0x4A, 0x6F])
        #expect(ByteSearch.parseHex("") == nil)
        #expect(ByteSearch.parseHex("   ") == nil)
        #expect(ByteSearch.parseHex("4A6") == nil)
        #expect(ByteSearch.parseHex("4G") == nil)
        #expect(ByteSearch.parseHex("0x") == nil)
        #expect(ByteSearch.parseHex("4A 6F 7") == [0x4A, 0x6F, 0x07])
    }

    @Test func offsets() {
        #expect(OffsetInput.parse("1234") == 1234)
        #expect(OffsetInput.parse("0x4D2") == 1234)
        #expect(OffsetInput.parse("0X4d2") == 1234)
        #expect(OffsetInput.parse("$4D2") == 1234)
        #expect(OffsetInput.parse("4D2h") == 1234)
        #expect(OffsetInput.parse("4d2H") == 1234)
        #expect(OffsetInput.parse("  42 \n") == 42)
        #expect(OffsetInput.parse("0") == 0)
        #expect(OffsetInput.parse("") == nil)
        #expect(OffsetInput.parse("  ") == nil)
        #expect(OffsetInput.parse("-5") == nil)
        #expect(OffsetInput.parse("+5") == nil)
        #expect(OffsetInput.parse("12ab") == nil)
        #expect(OffsetInput.parse("0x") == nil)
        #expect(OffsetInput.parse("h") == nil)
        #expect(OffsetInput.parse("99999999999999999999") == nil)
        #expect(OffsetInput.parse("0xFFFFFFFFFFFFFFFFF") == nil)
        #expect(OffsetInput.parse("0x7FFFFFFFFFFFFFFF") == Int64.max)
    }
}

// MARK: FileSequence

@Suite struct FileSequenceTests {
    private func url(_ n: String) -> URL { URL(fileURLWithPath: "/tmp/seq/\(n)") }

    private func make(current: String, selected: Set<String> = []) -> FileSequence? {
        let names = ["a", "b", "c", "d", "e"]
        return FileSequence(entries: names.map { .init(url: url($0), isSelected: selected.contains($0)) },
                            current: url(current))
    }

    @Test func nextPrevious() throws {
        var s = try #require(make(current: "b"))
        #expect(s.current == url("b"))
        #expect(s.move(.next) == url("c"))
        #expect(s.index == 2)
        #expect(s.move(.previous) == url("b"))
        #expect(s.move(.previous) == url("a"))
        #expect(s.move(.previous) == nil)
        #expect(s.current == url("a"))
        var e = try #require(make(current: "e"))
        #expect(e.move(.next) == nil)
        #expect(e.index == 4)
    }

    @Test func firstLast() throws {
        var s = try #require(make(current: "c"))
        #expect(s.move(.last) == url("e"))
        #expect(s.move(.last) == nil)
        #expect(s.move(.first) == url("a"))
        #expect(s.move(.first) == nil)
        #expect(s.current == url("a"))
    }

    @Test func selected() throws {
        var s = try #require(make(current: "a", selected: ["b", "d"]))
        #expect(s.move(.previousSelected) == nil)
        #expect(s.move(.nextSelected) == url("b"))
        #expect(s.move(.nextSelected) == url("d"))
        #expect(s.move(.nextSelected) == nil)
        #expect(s.current == url("d"))
        #expect(s.move(.previousSelected) == url("b"))
        #expect(s.move(.previousSelected) == nil)
        var none = try #require(make(current: "c"))
        #expect(none.move(.nextSelected) == nil)
        #expect(none.move(.previousSelected) == nil)
    }

    @Test func unknownAndStandardizedURL() throws {
        #expect(make(current: "zzz") == nil)
        let s = try #require(FileSequence(
            entries: [.init(url: url("a"), isSelected: false), .init(url: url("b"), isSelected: false)],
            current: URL(fileURLWithPath: "/tmp/seq/x/../b")))
        #expect(s.index == 1)
        #expect(FileSequence(entries: [], current: url("a")) == nil)
    }
}
