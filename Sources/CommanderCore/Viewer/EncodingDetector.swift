public import Foundation

public enum EncodingSource: String, Sendable { case bom, validUTF8, utf16Heuristic, legacyHeuristic, fallback, manual }

public struct EncodingDetection: Sendable, Equatable {
    public var encoding: TextEncoding
    public var source: EncodingSource
    /// Bytes to skip when decoding (0 if no BOM).
    public var bomLength: Int

    public init(encoding: TextEncoding, source: EncodingSource, bomLength: Int) {
        self.encoding = encoding
        self.source = source
        self.bomLength = bomLength
    }
}

public enum EncodingDetector {
    private static let utf16SampleSize = 64 * 1024
    private static let legacySampleSize = 1024 * 1024

    public static func bom(in data: Data) -> (encoding: TextEncoding, length: Int)? {
        let s = data.startIndex
        if data.count >= 3, data[s] == 0xEF, data[s + 1] == 0xBB, data[s + 2] == 0xBF { return (.utf8, 3) }
        if data.count >= 2 {
            if data[s] == 0xFF, data[s + 1] == 0xFE { return (.utf16LE, 2) }
            if data[s] == 0xFE, data[s + 1] == 0xFF { return (.utf16BE, 2) }
        }
        return nil
    }

    /// Strict validation of the whole data.
    public static func isValidUTF8(_ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            let n = raw.count
            guard n > 0, let base = raw.baseAddress else { return true }
            let p = base.assumingMemoryBound(to: UInt8.self)
            var i = 0
            while i < n {
                // ASCII fast path, 8 bytes at a time.
                while i + 8 <= n {
                    let w = UnsafeRawPointer(p + i).loadUnaligned(as: UInt64.self)
                    if w & 0x8080_8080_8080_8080 != 0 { break }
                    i += 8
                }
                if i >= n { break }
                let b = p[i]
                if b < 0x80 { i += 1; continue }
                @inline(__always) func cont(_ k: Int, _ lo: UInt8 = 0x80, _ hi: UInt8 = 0xBF) -> Bool {
                    i + k < n && p[i + k] >= lo && p[i + k] <= hi
                }
                switch b {
                case 0xC2...0xDF:
                    guard cont(1) else { return false }
                    i += 2
                case 0xE0:
                    guard cont(1, 0xA0), cont(2) else { return false }
                    i += 3
                case 0xE1...0xEC, 0xEE...0xEF:
                    guard cont(1), cont(2) else { return false }
                    i += 3
                case 0xED:
                    guard cont(1, 0x80, 0x9F), cont(2) else { return false }
                    i += 3
                case 0xF0:
                    guard cont(1, 0x90), cont(2), cont(3) else { return false }
                    i += 4
                case 0xF1...0xF3:
                    guard cont(1), cont(2), cont(3) else { return false }
                    i += 4
                case 0xF4:
                    guard cont(1, 0x80, 0x8F), cont(2), cont(3) else { return false }
                    i += 4
                default:
                    return false
                }
            }
            return true
        }
    }

    /// UTF-16 without BOM by zero-byte pattern over the first 64 KiB.
    public static func utf16WithoutBOM(_ data: Data) -> TextEncoding? {
        let n = min(data.count, utf16SampleSize)
        guard n >= 4 else { return nil }
        var even = 0, odd = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<n where raw[i] == 0 {
                if i % 2 == 0 { even += 1 } else { odd += 1 }
            }
        }
        let evenTotal = Double((n + 1) / 2), oddTotal = Double(n / 2)
        let e = Double(even) / evenTotal, o = Double(odd) / oddTotal
        if e >= 0.4, o <= 0.05 { return .utf16BE }
        if o >= 0.4, e <= 0.05 { return .utf16LE }
        return nil
    }

    public static func looksBinary(_ data: Data) -> Bool {
        if data.isEmpty { return false }
        if bom(in: data) != nil { return false }
        if utf16WithoutBOM(data) != nil { return false }
        let n = min(data.count, utf16SampleSize)
        var control = 0
        let hasNul: Bool = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<n {
                let b = raw[i]
                if b == 0 { return true }
                if b <= 0x08 || b == 0x0B || (0x0E...0x1A).contains(b) || (0x1C...0x1F).contains(b) || b == 0x7F {
                    control += 1
                }
            }
            return false
        }
        if hasNul { return true }
        return Double(control) > Double(n) * 0.05
    }

    /// BOM → UTF-16 without BOM (zero pattern) → whole-data valid UTF-8 → legacy heuristic → fallback.
    public static func detect(_ data: Data, fallback: TextEncoding) -> EncodingDetection {
        if let (encoding, length) = bom(in: data) {
            return EncodingDetection(encoding: encoding, source: .bom, bomLength: length)
        }
        // Checked before UTF-8: ASCII-heavy UTF-16 is itself valid UTF-8 (NUL bytes), but
        // genuine UTF-8 text never has a regular zero pattern at every other byte.
        if let u16 = utf16WithoutBOM(data) {
            return EncodingDetection(encoding: u16, source: .utf16Heuristic, bomLength: 0)
        }
        if isValidUTF8(data) {
            return EncodingDetection(encoding: .utf8, source: .validUTF8, bomLength: 0)
        }
        if fallback == .windows1250 || fallback == .iso8859_2 {
            let n = min(data.count, legacySampleSize)
            var hasC1 = false, hasLatin2 = false
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                for i in 0..<n {
                    let b = raw[i]
                    if (0x80...0x9F).contains(b) { hasC1 = true; return }
                    if b == 0xA9 || b == 0xAB || b == 0xAE || b == 0xB9 || b == 0xBB || b == 0xBE { hasLatin2 = true }
                }
            }
            if hasC1 { return EncodingDetection(encoding: .windows1250, source: .legacyHeuristic, bomLength: 0) }
            if hasLatin2 { return EncodingDetection(encoding: .iso8859_2, source: .legacyHeuristic, bomLength: 0) }
        }
        return EncodingDetection(encoding: fallback, source: .fallback, bomLength: 0)
    }
}
