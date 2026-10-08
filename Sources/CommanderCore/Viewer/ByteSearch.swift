// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

public import Foundation

public enum ByteSearch {
    /// Forward: first match starting at index >= `start`. Backward: last match starting at index < `start`.
    public static func find(_ pattern: [UInt8], in data: Data, from start: Int,
                            backward: Bool = false, ignoringASCIICase: Bool = false) -> Int? {
        let m = pattern.count
        guard m > 0, data.count >= m else { return nil }
        return data.withUnsafeBytes { raw -> Int? in
            guard let base = raw.baseAddress else { return nil }
            let n = raw.count
            let p = base.assumingMemoryBound(to: UInt8.self)
            return pattern.withUnsafeBufferPointer { pat -> Int? in
                if ignoringASCIICase {
                    let lower = pat.map(fold)
                    return lower.withUnsafeBufferPointer { l in
                        scan(p, n, l, start, backward, fold: true)
                    }
                }
                if !backward {
                    let from = max(start, 0)
                    guard from + m <= n else { return nil }
                    guard let hit = memmem(p + from, n - from, pat.baseAddress!, m) else { return nil }
                    return UnsafeRawPointer(hit) - UnsafeRawPointer(p)
                }
                return scan(p, n, pat, start, true, fold: false)
            }
        }
    }

    @inline(__always) private static func fold(_ b: UInt8) -> UInt8 {
        (0x41...0x5A).contains(b) ? b | 0x20 : b
    }

    private static func scan(_ p: UnsafePointer<UInt8>, _ n: Int, _ pat: UnsafeBufferPointer<UInt8>,
                             _ start: Int, _ backward: Bool, fold doFold: Bool) -> Int? {
        let m = pat.count
        let last = n - m
        @inline(__always) func matches(_ i: Int) -> Bool {
            if doFold {
                for k in 0..<m where fold(p[i + k]) != pat[k] { return false }
                return true
            }
            return memcmp(p + i, pat.baseAddress!, m) == 0
        }
        if backward {
            var i = min(start - 1, last)
            while i >= 0 {
                if matches(i) { return i }
                i -= 1
            }
            return nil
        }
        var i = max(start, 0)
        let first = pat[0]
        while i <= last {
            if doFold {
                if fold(p[i]) == first, matches(i) { return i }
                i += 1
            } else {
                guard let hit = memchr(p + i, Int32(first), last - i + 1) else { return nil }
                i = UnsafeRawPointer(hit) - UnsafeRawPointer(p)
                if matches(i) { return i }
                i += 1
            }
        }
        return nil
    }

    /// "4A 6f", "4a6f", "0x4A 0x6F", "4A,6F" → bytes; nil on empty, invalid characters or an odd digit count.
    /// In a multi-token input a single-digit token is one byte ("4 A" → 04 0A).
    public static func parseHex(_ text: String) -> [UInt8]? {
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\t" || $0 == "\n" || $0 == "\r" })
        guard !tokens.isEmpty else { return nil }
        var out = [UInt8]()
        for token in tokens {
            var digits = Substring(token)
            if digits.hasPrefix("0x") || digits.hasPrefix("0X") { digits = digits.dropFirst(2) }
            let values = digits.utf8.map(hexValue)
            guard !values.isEmpty, !values.contains(nil) else { return nil }
            let v = values.compactMap { $0 }
            if v.count == 1, tokens.count > 1 {
                out.append(v[0])
                continue
            }
            guard v.count % 2 == 0 else { return nil }
            var i = 0
            while i < v.count { out.append(v[i] << 4 | v[i + 1]); i += 2 }
        }
        return out
    }

    fileprivate static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: c - 0x30
        case 0x41...0x46: c - 0x41 + 10
        case 0x61...0x66: c - 0x61 + 10
        default: nil
        }
    }
}

public enum OffsetInput {
    /// "1234" decimal; "0x4D2", "$4D2", "4D2h" hex; nil for empty, negative, invalid or overflowing input.
    public static func parse(_ text: String) -> Int64? {
        var s = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var radix = 10
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s = s.dropFirst(2); radix = 16 }
        else if s.hasPrefix("$") { s = s.dropFirst(); radix = 16 }
        else if s.hasSuffix("h") || s.hasSuffix("H") { s = s.dropLast(); radix = 16 }
        guard !s.isEmpty, s.utf8.allSatisfy({ radix == 16 ? ByteSearch.hexValue($0) != nil : ($0 >= 0x30 && $0 <= 0x39) })
        else { return nil }
        return Int64(s, radix: radix)
    }
}
