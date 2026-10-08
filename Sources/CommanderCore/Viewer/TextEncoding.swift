// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Text encodings offered by the viewer.
public enum TextEncoding: String, CaseIterable, Sendable, Codable {
    case utf8, utf16LE, utf16BE, windows1250, iso8859_2, windows1252, iso8859_1, macRoman, cp852, windows1251, koi8r

    public var title: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf16LE: "UTF-16 LE"
        case .utf16BE: "UTF-16 BE"
        case .windows1250: "Windows-1250"
        case .iso8859_2: "ISO 8859-2"
        case .windows1252: "Windows-1252"
        case .iso8859_1: "ISO 8859-1"
        case .macRoman: "Mac Roman"
        case .cp852: "DOS 852"
        case .windows1251: "Windows-1251"
        case .koi8r: "KOI8-R"
        }
    }

    public var isSingleByte: Bool {
        switch self {
        case .utf8, .utf16LE, .utf16BE: false
        default: true
        }
    }

    public var stringEncoding: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .utf16LE: .utf16LittleEndian
        case .utf16BE: .utf16BigEndian
        case .windows1250: .windowsCP1250
        case .iso8859_2: .isoLatin2
        case .windows1252: .windowsCP1252
        case .iso8859_1: .isoLatin1
        case .macRoman: .macOSRoman
        case .windows1251: .windowsCP1251
        case .cp852: Self.coreFoundation(CFStringEncodings.dosLatin2)
        case .koi8r: Self.coreFoundation(CFStringEncodings.KOI8_R)
        }
    }

    /// Encode text for searching; nil if not representable.
    public func encode(_ text: String) -> [UInt8]? {
        guard let data = text.data(using: stringEncoding, allowLossyConversion: false) else { return nil }
        return [UInt8](data)
    }

    /// 256 entries for single-byte encodings: the Unicode character of each byte (nil where undefined).
    public var byteTable: [Character?]? {
        isSingleByte ? Self.tables[self] : nil
    }

    private static func coreFoundation(_ e: CFStringEncodings) -> String.Encoding {
        let cf = CFStringEncoding(e.rawValue)
        return String.Encoding(rawValue: UInt(CFStringConvertEncodingToNSStringEncoding(cf)))
    }

    private static let tables: [TextEncoding: [Character?]] = {
        var result: [TextEncoding: [Character?]] = [:]
        for encoding in allCases where encoding.isSingleByte {
            let se = encoding.stringEncoding
            var table = [Character?](repeating: nil, count: 256)
            for b in 0..<256 {
                if b < 0x80 {
                    table[b] = Character(Unicode.Scalar(UInt8(b)))
                } else if let s = String(data: Data([UInt8(b)]), encoding: se),
                          s.unicodeScalars.count == 1, s != "\u{FFFD}" {
                    table[b] = s.first
                }
            }
            result[encoding] = table
        }
        return result
    }()
}
