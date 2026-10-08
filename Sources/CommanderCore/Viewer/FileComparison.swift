// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Compares two files: byte-wise for binary data, line-wise for text.
public enum FileComparison {
    public enum Result: Sendable, Equatable {
        case identical
        /// `firstDifference` is the offset of the first differing byte (the smaller size when one file is a prefix of the other).
        case binaryDifferent(firstDifference: Int64, leftSize: Int64, rightSize: Int64)
        case text(LineDiff, left: [String], right: [String], leftEncoding: TextEncoding, rightEncoding: TextEncoding)
    }

    private static let chunkSize = 1 << 20
    private static let headSize = 64 * 1024

    /// Reads both files (call off the main actor). Identical bytes give `.identical`. If either file looks binary
    /// or is larger than `textLimit` bytes, the result is a byte comparison (streamed, never fully loaded).
    /// Otherwise both are decoded with `EncodingDetector.detect` (BOM stripped) and diffed by lines; a text
    /// diff without differences is still returned as `.text` (with `isIdentical == true`) so contents can be shown.
    public static func compare(
        _ left: URL, _ right: URL, options: DiffOptions = .init(), fallback: TextEncoding, textLimit: Int = 64 << 20
    ) throws -> Result {
        let leftSize = try size(of: left), rightSize = try size(of: right)
        var difference: Int64?
        if leftSize == rightSize {
            difference = try firstDifference(left, right)
            if difference == nil { return .identical }
        }

        func binary() throws -> Result {
            let at = try difference ?? firstDifference(left, right)
            guard let at else { return .identical }
            return .binaryDifferent(firstDifference: at, leftSize: leftSize, rightSize: rightSize)
        }

        if max(leftSize, rightSize) > Int64(textLimit) { return try binary() }
        if try looksBinary(left) || looksBinary(right) { return try binary() }

        let leftData = try Data(contentsOf: left), rightData = try Data(contentsOf: right)
        try Task.checkCancellation()
        let le = EncodingDetector.detect(leftData, fallback: fallback)
        let re = EncodingDetector.detect(rightData, fallback: fallback)
        let leftLines = LineDiff.lines(of: TextDecoding.decode(leftData, as: le.encoding, skip: le.bomLength))
        let rightLines = LineDiff.lines(of: TextDecoding.decode(rightData, as: re.encoding, skip: re.bomLength))
        let diff = try LineDiff.compute(left: leftLines, right: rightLines, options: options)
        return .text(diff, left: leftLines, right: rightLines, leftEncoding: le.encoding, rightEncoding: re.encoding)
    }

    /// Offset of the first differing byte, or nil when the files are identical. Streams in 1 MB chunks.
    public static func firstDifference(_ left: URL, _ right: URL) throws -> Int64? {
        let l = try FileHandle(forReadingFrom: left)
        defer { try? l.close() }
        let r = try FileHandle(forReadingFrom: right)
        defer { try? r.close() }
        var position: Int64 = 0
        while true {
            try Task.checkCancellation()
            let a = try l.read(upToCount: chunkSize) ?? Data()
            let b = try r.read(upToCount: chunkSize) ?? Data()
            if a.isEmpty && b.isEmpty { return nil }
            let common = min(a.count, b.count)
            if a.count != b.count || a != b {
                let at: Int = a.withUnsafeBytes { (pa: UnsafeRawBufferPointer) -> Int in
                    b.withUnsafeBytes { (pb: UnsafeRawBufferPointer) -> Int in
                        var i = 0
                        while i < common && pa[i] == pb[i] { i += 1 }
                        return i
                    }
                }
                return position + Int64(at)
            }
            position += Int64(common)
        }
    }

    private static func size(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func looksBinary(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let head = try handle.read(upToCount: headSize) ?? Data()
        return EncodingDetector.looksBinary(head)
    }
}
