// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public enum HexFormat {
    public static let bytesPerLine = 16
    private static let digits = Array("0123456789ABCDEF".utf8)

    /// Uppercase hex, at least 8 digits; more when `fileSize - 1` needs them.
    public static func offsetText(_ offset: Int64, fileSize: Int64) -> String {
        let width = max(8, String(max(fileSize - 1, 0), radix: 16).count)
        let text = String(max(offset, 0), radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }

    /// Two digits per byte separated by a space, an extra space between byte 8 and 9, padded to a full line.
    public static func hexText(_ bytes: some Collection<UInt8>) -> String {
        var out = [UInt8]()
        out.reserveCapacity(48)
        for (i, b) in bytes.enumerated() {
            if i > 0 { out.append(0x20) }
            if i == 8 { out.append(0x20) }
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 15)])
        }
        let full = bytesPerLine * 3
        while out.count < full { out.append(0x20) }
        return String(decoding: out, as: UTF8.self)
    }

    /// One character per byte; unprintable bytes become ".".
    public static func charText(_ bytes: some Collection<UInt8>, encoding: TextEncoding) -> String {
        let table = encoding.byteTable
        var result = ""
        for b in bytes {
            if let table {
                if let ch = table[Int(b)], isPrintable(ch) { result.append(ch) } else { result.append(".") }
            } else if (0x20...0x7E).contains(b) {
                result.append(Character(Unicode.Scalar(b)))
            } else {
                result.append(".")
            }
        }
        return result
    }

    /// "4A 6F 68" — for the clipboard.
    public static func plainHex(_ bytes: some Collection<UInt8>) -> String {
        var out = [UInt8]()
        for (i, b) in bytes.enumerated() {
            if i > 0 { out.append(0x20) }
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 15)])
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func isPrintable(_ ch: Character) -> Bool {
        if ch == " " { return true }
        for s in ch.unicodeScalars {
            if s.properties.isWhitespace { return false }
            switch s.properties.generalCategory {
            case .control, .format, .unassigned, .surrogate, .lineSeparator, .paragraphSeparator, .privateUse:
                return false
            default: break
            }
        }
        return true
    }
}
