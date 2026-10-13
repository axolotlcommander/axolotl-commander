// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

internal import Compression
public import Foundation

/// Helpers for loading SVG documents, including gzip-compressed `.svgz`.
public enum SVGData {
    public enum Failure: Error, Equatable { case tooLarge, corrupt }

    /// Gzip data (starts with 1F 8B) unpacked; any other data returned unchanged.
    public static func unpack(_ data: Data, maxSize: Int = 64 << 20) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, bytes[0] == 0x1F, bytes[1] == 0x8B else { return data }
        let start = try deflateStart(bytes)
        // 8-byte trailer (CRC32 + ISIZE) must be present.
        guard bytes.count >= start + 8 else { throw Failure.corrupt }
        return try inflate(bytes[start..<(bytes.count - 8)], maxSize: maxSize)
    }

    /// Offset of the raw deflate stream after the RFC 1952 header.
    private static func deflateStart(_ b: [UInt8]) throws -> Int {
        guard b.count >= 10, b[2] == 8 else { throw Failure.corrupt }
        let flags = b[3]
        var i = 10
        if flags & 0x04 != 0 {  // FEXTRA
            guard b.count >= i + 2 else { throw Failure.corrupt }
            i += 2 + Int(b[i]) + Int(b[i + 1]) << 8
        }
        for bit: UInt8 in [0x08, 0x10] where flags & bit != 0 {  // FNAME, FCOMMENT
            guard let nul = b[min(i, b.count)...].firstIndex(of: 0) else { throw Failure.corrupt }
            i = nul + 1
        }
        if flags & 0x02 != 0 { i += 2 }  // FHCRC
        guard i <= b.count else { throw Failure.corrupt }
        return i
    }

    private static func inflate(_ input: ArraySlice<UInt8>, maxSize: Int) throws -> Data {
        let dummy = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { dummy.deallocate() }
        var stream = compression_stream(dst_ptr: dummy, dst_size: 0, src_ptr: dummy, src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
        else { throw Failure.corrupt }
        defer { compression_stream_destroy(&stream) }

        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let src = Array(input)
        return try src.withUnsafeBufferPointer { sp -> Data in
            // An empty slice still needs a valid pointer.
            stream.src_ptr = sp.baseAddress ?? UnsafePointer(dummy)
            stream.src_size = sp.count
            while true {
                let status = buffer.withUnsafeMutableBufferPointer { bp -> compression_status in
                    stream.dst_ptr = bp.baseAddress!
                    stream.dst_size = bp.count
                    return compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                }
                let produced = buffer.count - stream.dst_size
                out.append(contentsOf: buffer[0..<produced])
                if out.count > maxSize { throw Failure.tooLarge }
                switch status {
                case COMPRESSION_STATUS_END: return out
                case COMPRESSION_STATUS_OK:
                    // No progress with input exhausted means a truncated stream.
                    if produced == 0 && stream.src_size == 0 { throw Failure.corrupt }
                default: throw Failure.corrupt
                }
            }
        }
    }
}
