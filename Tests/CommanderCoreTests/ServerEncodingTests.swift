import Testing
import Foundation
@testable import CommanderCore

@Suite struct ServerEncodingTests {
    private let czech = "Příliš žluťoučký kůň úpěl ďábelské ódy ŽLUŤOUČKÝ"

    @Test(arguments: [
        (ServerEncoding.windows1250, [UInt8]([0x9E, 0x9D, 0xF8])),
        (.iso8859_2, [0xBE, 0xBB, 0xF8]),
        (.cp852, [0xA7, 0x9C, 0xFD]),
    ])
    func czechRoundTrip(_ encoding: ServerEncoding, _ žťř: [UInt8]) throws {
        #expect(encoding.encode("žťř") == žťř)
        let bytes = try #require(encoding.encode(czech))
        #expect(bytes.count == czech.unicodeScalars.count)
        #expect(encoding.decode(bytes) == czech)
        // Decomposed (NFD) local names are precomposed first.
        #expect(encoding.encode("z\u{30C}lut\u{30C}") == encoding.encode("žluť"))
        #expect(encoding.encode("✓") == nil)
    }

    @Test(arguments: [ServerEncoding.windows1252, .iso8859_1])
    func western(_ encoding: ServerEncoding) throws {
        let bytes = try #require(encoding.encode("Café déjà vu"))
        #expect(bytes.contains(0xE9))
        #expect(encoding.decode(bytes) == "Café déjà vu")
        #expect(encoding.encode("žluť") == nil)
    }

    @Test(arguments: ServerEncoding.allCases.filter { $0.textEncoding != nil })
    func everyByteRoundTrips(_ encoding: ServerEncoding) {
        let all = (0...255).map(UInt8.init)
        let text = encoding.decode(all)
        #expect(text.unicodeScalars.count == 256)
        #expect(encoding.encode(text) == all)
    }

    @Test func autoAndUTF8() {
        #expect(ServerEncoding.auto.decode(Array("žluť".utf8)) == "žluť")
        #expect(ServerEncoding.auto.decode([0x63, 0x61, 0x66, 0xE9]) == "café")
        #expect(ServerEncoding.auto.encode("café") == Array("café".utf8))
        #expect(ServerEncoding.utf8.decode([0x61, 0xE9]) == "a\u{FFFD}")
        #expect(ServerEncoding.utf8.encode("✓") == Array("✓".utf8))
        #expect(ServerEncoding.auto.wantsUTF8 && !ServerEncoding.windows1250.wantsUTF8)
        #expect(ServerEncoding.windows1250.stringEncoding == .windowsCP1250)
    }

    @Test func autoCodecRemembersLatin1Names() {
        var codec = ServerNameCodec(.auto)
        codec.noteListing("/", latin1: ["café"])
        codec.noteListing("/café", latin1: ["é"])
        #expect(codec.encode(path: "/café") == Array("/caf".utf8) + [0xE9])
        #expect(codec.encode(path: "/café/é/x") == Array("/caf".utf8) + [0xE9, 0x2F, 0xE9] + Array("/x".utf8))
        // Same text elsewhere, or a new name: UTF-8.
        #expect(codec.encode(name: "café", in: "/other") == Array("café".utf8))
        #expect(codec.encode(path: "/new é") == Array("/new é".utf8))
        // NFD spelling of a remembered name.
        #expect(codec.encode(name: "cafe\u{301}", in: "/") == Array("caf".utf8) + [0xE9])
        // A new listing replaces the old one.
        codec.noteListing("/", latin1: [])
        #expect(codec.encode(path: "/café") == Array("/café".utf8))

        var home = ServerNameCodec(.auto)
        #expect(home.decodePath(Array("/home/jos".utf8) + [0xE9]) == "/home/josé")
        #expect(home.encode(path: "/home/josé/x") == Array("/home/jos".utf8) + [0xE9] + Array("/x".utf8))
        var utf8Home = ServerNameCodec(.auto)
        #expect(utf8Home.decodePath(Array("/home/josé".utf8)) == "/home/josé")
        #expect(utf8Home.encode(path: "/home/josé") == Array("/home/josé".utf8))
    }

    @Test func explicitCodec() {
        var codec = ServerNameCodec(.windows1250)
        codec.noteListing("/", latin1: ["žluť"])  // ignored outside .auto
        let expected: [UInt8] = [0x2F, 0x73, 0x6C, 0x6F, 0x9E, 0x6B, 0x61, 0x2F, 0x9E, 0x6C, 0x75, 0x9D]  // "/složka/žluť"
        #expect(codec.encode(path: "/složka/žluť") == expected)
        #expect(codec.encode(path: "/a/✓") == nil)
        #expect(codec.encode(components: "/") == [])
    }

    @Test func parserReportsLatin1Lines() {
        var data = Data("type=file;size=1; caf".utf8)
        data.append(0xE9)
        data.append(contentsOf: Array("\r\ntype=file;size=2; žluť\r\n".utf8))
        let auto = FTPListParser.parseMLSDReportingLatin1(data, .auto)
        #expect(auto.map(\.entry.name) == ["café", "žluť"])
        #expect(auto.map(\.latin1) == [true, false])

        var cp = Data("-rw-r--r-- 1 o g 1 Jan  1  2020 ".utf8)
        cp.append(contentsOf: ServerEncoding.windows1250.encode("žluťoučký.txt")!)
        let e = FTPListParser.parseLIST(cp, encoding: .windows1250)
        #expect(e.map(\.name) == ["žluťoučký.txt"])
    }

    @Test func profileEncodingIsSavedAndOldProfilesDecode() throws {
        let profile = ConnectionProfile(name: "Starý server", endpoint: RemoteEndpoint(proto: .ftp, host: "ftp.example.cz"),
                                        initialPath: "/pub", passiveMode: false, encoding: .cp852)
        let data = try JSONEncoder().encode(profile)
        #expect(try JSONDecoder().decode(ConnectionProfile.self, from: data) == profile)

        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["encoding"] as? String == "cp852")
        json["encoding"] = nil
        let old = try JSONDecoder().decode(ConnectionProfile.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.encoding == .auto)
        #expect(old.name == "Starý server" && old.initialPath == "/pub" && !old.passiveMode)
        #expect(old.connectOptions == ConnectOptions(passiveMode: false, encoding: .auto))
    }
}
