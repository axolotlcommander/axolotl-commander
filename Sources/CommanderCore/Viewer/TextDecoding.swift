// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

public enum TextDecoding {
    /// Never fails. Skips `skip` leading bytes (BOM), decodes at most `limit` bytes after that (nil = all).
    /// A limit that cuts a multi-byte sequence is moved back to a character boundary.
    /// Invalid sequences become U+FFFD.
    public static func decode(_ data: Data, as encoding: TextEncoding, skip: Int = 0, limit: Int? = nil) -> String {
        data.withUnsafeBytes { raw -> String in
            let total = raw.count
            let start = min(max(skip, 0), total)
            var end = total
            var cut = false
            if let limit {
                let e = start + max(limit, 0)
                if e < total { end = e; cut = true }
            }
            let bytes = UnsafeBufferPointer(rebasing: raw.bindMemory(to: UInt8.self)[start..<end])
            switch encoding {
            case .utf8: return decodeUTF8(bytes, cut: cut)
            case .utf16LE: return decodeUTF16(bytes, bigEndian: false, cut: cut)
            case .utf16BE: return decodeUTF16(bytes, bigEndian: true, cut: cut)
            default: return decodeSingleByte(bytes, encoding)
            }
        }
    }

    private static func decodeUTF8(_ bytes: UnsafeBufferPointer<UInt8>, cut: Bool) -> String {
        var n = bytes.count
        if cut {
            // Drop a trailing incomplete (but so far valid-looking) sequence.
            var back = 1
            while back <= min(3, n) {
                let b = bytes[n - back]
                if b & 0xC0 == 0x80 { back += 1; continue }
                let need = b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 1
                if need > back { n -= back }
                break
            }
        }
        return String(decoding: UnsafeBufferPointer(rebasing: bytes[0..<n]), as: UTF8.self)
    }

    private static func decodeUTF16(_ bytes: UnsafeBufferPointer<UInt8>, bigEndian: Bool, cut: Bool) -> String {
        var n = bytes.count
        var oddTail = false
        if n % 2 == 1 {
            n -= 1
            oddTail = !cut
        }
        var units = [UInt16]()
        units.reserveCapacity(n / 2 + 1)
        var i = 0
        while i < n {
            let a = UInt16(bytes[i]), b = UInt16(bytes[i + 1])
            units.append(bigEndian ? (a << 8 | b) : (b << 8 | a))
            i += 2
        }
        if cut, let last = units.last, UTF16.isLeadSurrogate(last) { units.removeLast() }
        var s = String(decoding: units, as: UTF16.self)
        if oddTail { s.append("\u{FFFD}") }
        return s
    }

    /// Per-byte UTF-8 sequences: 4 bytes per entry, first is the length.
    private static let utf8Tables: [TextEncoding: [UInt8]] = {
        var result: [TextEncoding: [UInt8]] = [:]
        for e in TextEncoding.allCases {
            guard let table = e.byteTable else { continue }
            var flat = [UInt8](repeating: 0, count: 256 * 4)
            for b in 0..<256 {
                let utf8 = Array(String(table[b] ?? "\u{FFFD}").utf8)
                flat[b * 4] = UInt8(utf8.count)
                for (k, u) in utf8.prefix(3).enumerated() { flat[b * 4 + 1 + k] = u }
            }
            result[e] = flat
        }
        return result
    }()

    private static func decodeSingleByte(_ bytes: UnsafeBufferPointer<UInt8>, _ encoding: TextEncoding) -> String {
        guard let table = utf8Tables[encoding] else { return "" }
        return table.withUnsafeBufferPointer { t in
            String(unsafeUninitializedCapacity: bytes.count * 3) { out in
                var o = 0
                for b in bytes {
                    let base = Int(b) * 4
                    let len = Int(t[base])
                    out[o] = t[base + 1]
                    if len > 1 { out[o + 1] = t[base + 2] }
                    if len > 2 { out[o + 2] = t[base + 3] }
                    o += len
                }
                return o
            }
        }
    }
}
