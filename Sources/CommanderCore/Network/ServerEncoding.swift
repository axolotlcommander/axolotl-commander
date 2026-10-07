public import Foundation

/// How a server encodes file names (Salamander's FTP "Encoding" option). Legacy servers send
/// their local 8-bit code page; the bytes must be decoded for display and encoded back exactly
/// for every command that names the file.
public enum ServerEncoding: String, Codable, CaseIterable, Sendable {
    /// UTF-8 when the bytes are valid UTF-8, else ISO Latin-1; see `ServerNameCodec` for how
    /// such names still round-trip.
    case auto
    case utf8, windows1250, iso8859_2, cp852, windows1252, iso8859_1

    public var title: String {
        switch self {
        case .auto: "Automatic (UTF-8, else Latin-1)"
        case .utf8: "UTF-8"
        case .windows1250: "Central European (Windows-1250)"
        case .iso8859_2: "Central European (ISO 8859-2)"
        case .cp852: "Central European (DOS 852)"
        case .windows1252: "Western (Windows-1252)"
        case .iso8859_1: "Western (ISO 8859-1)"
        }
    }

    /// The single-byte text encoding; nil for `.auto` and `.utf8`.
    public var textEncoding: TextEncoding? {
        switch self {
        case .auto, .utf8: nil
        case .windows1250: .windows1250
        case .iso8859_2: .iso8859_2
        case .cp852: .cp852
        case .windows1252: .windows1252
        case .iso8859_1: .iso8859_1
        }
    }

    public var stringEncoding: String.Encoding? {
        switch self {
        case .auto: nil
        case .utf8: .utf8
        default: textEncoding?.stringEncoding
        }
    }

    /// Sends "OPTS UTF8 ON" at login (an 8-bit setting must not switch the server to UTF-8).
    var wantsUTF8: Bool { self == .auto || self == .utf8 }

    /// Never fails: invalid UTF-8 is repaired (`.utf8`) or read as Latin-1 (`.auto`); bytes a
    /// code page leaves undefined become U+0080…U+009F, so they still encode back.
    public func decode(_ bytes: some Collection<UInt8>) -> String {
        decodeReportingFallback(bytes).text
    }

    /// `fallback`: `.auto` read the bytes as Latin-1 because they were not valid UTF-8.
    func decodeReportingFallback(_ bytes: some Collection<UInt8>) -> (text: String, fallback: Bool) {
        switch self {
        case .auto:
            if let s = String(validating: bytes, as: UTF8.self) { return (s, false) }
            return (Self.latin1(bytes), true)
        case .utf8:
            return (String(decoding: bytes, as: UTF8.self), false)
        default:
            let table = Self.tables[self]!.decode
            var scalars = String.UnicodeScalarView()
            scalars.append(contentsOf: bytes.map { table[Int($0)] })
            return (String(scalars), false)
        }
    }

    /// The name as the server stores it; nil when a character has no byte in the code page.
    /// `.auto` encodes UTF-8 (a name read as Latin-1 needs `ServerNameCodec`).
    public func encode(_ text: String) -> [UInt8]? {
        switch self {
        case .auto, .utf8:
            return Array(text.utf8)
        default:
            let table = Self.tables[self]!.encode
            var bytes: [UInt8] = []
            // Local names may be decomposed (NFD); code pages only have precomposed letters.
            for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
                guard let b = table[scalar] else { return nil }
                bytes.append(b)
            }
            return bytes
        }
    }

    static func latin1(_ bytes: some Collection<UInt8>) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: bytes.map { Unicode.Scalar($0) })
        return String(scalars)
    }

    static func latin1Bytes(_ text: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        for scalar in text.precomposedStringWithCanonicalMapping.unicodeScalars {
            guard scalar.value <= 0xFF else { return nil }
            bytes.append(UInt8(scalar.value))
        }
        return bytes
    }

    private struct Table {
        var decode: [Unicode.Scalar]
        var encode: [Unicode.Scalar: UInt8]
    }

    private static let tables: [ServerEncoding: Table] = {
        var result: [ServerEncoding: Table] = [:]
        for encoding in allCases {
            guard let byteTable = encoding.textEncoding?.byteTable else { continue }
            let defined = byteTable.map { $0?.unicodeScalars.first }
            var encode: [Unicode.Scalar: UInt8] = [:]
            for (b, s) in defined.enumerated() {
                if let s, encode[s] == nil { encode[s] = UInt8(b) }
            }
            var decode: [Unicode.Scalar] = []
            for (b, s) in defined.enumerated() {
                var scalar = s ?? Unicode.Scalar(UInt8(b))
                if s == nil {
                    // Undefined byte: the C1 control of the same value, unless the page uses it.
                    if encode[scalar] == nil { encode[scalar] = UInt8(b) } else { scalar = "\u{FFFD}" }
                }
                decode.append(scalar)
            }
            result[encoding] = Table(decode: decode, encode: encode)
        }
        return result
    }()
}

/// Server names ↔ bytes for one session. With an explicit encoding this is just
/// `ServerEncoding.encode`/`decode`. With `.auto` a decoded "é" is ambiguous (UTF-8 C3 A9 or
/// Latin-1 E9), so the codec remembers, per listed folder, which names were read as Latin-1
/// (their listing line was not valid UTF-8) and encodes exactly those as Latin-1 again; every
/// other name, including new ones typed or uploaded by the user, goes as UTF-8. A path is
/// encoded component by component against its parent folder, so `/a/é/x` works once `/a` and
/// `/a/é` were listed (which is how a panel reaches it). A home directory that was not valid
/// UTF-8 counts as Latin-1 in every component.
public struct ServerNameCodec: Sendable {
    public let encoding: ServerEncoding
    /// `.auto` only: folder path → names in it that were read as Latin-1.
    private var latin1Names: [String: Set<String>] = [:]

    public init(_ encoding: ServerEncoding) { self.encoding = encoding }

    /// Records a fresh listing of `folder` (normalized absolute path): `latin1` are the names
    /// that were read as Latin-1. Replaces what an earlier listing of the folder recorded.
    public mutating func noteListing(_ folder: String, latin1: some Sequence<String>) {
        guard encoding == .auto else { return }
        let names = Set(latin1)
        latin1Names[folder] = names.isEmpty ? nil : names
    }

    /// Decodes an absolute path the server reported (PWD); a `.auto` fallback marks every
    /// component as Latin-1.
    public mutating func decodePath(_ bytes: some Collection<UInt8>) -> String {
        let (path, fallback) = encoding.decodeReportingFallback(bytes)
        if fallback {
            var folder = "/"
            for part in path.split(separator: "/") {
                latin1Names[folder, default: []].insert(String(part))
                folder = RemotePath.join(folder, String(part))
            }
        }
        return path
    }

    /// One name inside `folder`; nil when the encoding cannot represent it.
    public func encode(name: String, in folder: String) -> [UInt8]? {
        if encoding == .auto, latin1Names[folder]?.contains(name) == true {
            return ServerEncoding.latin1Bytes(name)
        }
        return encoding.encode(name)
    }

    /// The components of a normalized absolute path, each encoded; nil when one cannot be.
    public func encode(components path: String) -> [[UInt8]]? {
        var folder = "/"
        var result: [[UInt8]] = []
        for part in path.split(separator: "/") {
            let name = String(part)
            guard let bytes = encode(name: name, in: folder) else { return nil }
            result.append(bytes)
            folder = RemotePath.join(folder, name)
        }
        return result
    }

    /// A normalized absolute path as bytes ("/" + components joined by "/").
    public func encode(path: String) -> [UInt8]? {
        guard let parts = encode(components: path) else { return nil }
        return [UInt8(ascii: "/")] + Array(parts.joined(separator: [UInt8(ascii: "/")]))
    }
}
