// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

// SFTP protocol version 3 (draft-ietf-secsh-filexfer-02) wire format.

enum SFTPType: UInt8, Sendable {
    case initialize = 1, version = 2, open = 3, close = 4, read = 5, write = 6
    case lstat = 7, fstat = 8, setstat = 9, fsetstat = 10, opendir = 11, readdir = 12
    case remove = 13, mkdir = 14, rmdir = 15, realpath = 16, stat = 17, rename = 18
    case readlink = 19, symlink = 20
    case status = 101, handle = 102, data = 103, name = 104, attrs = 105
    case extended = 200, extendedReply = 201
}

enum SFTPStatus {
    static let ok: UInt32 = 0
    static let eof: UInt32 = 1
    static let noSuchFile: UInt32 = 2
    static let permissionDenied: UInt32 = 3
    static let failure: UInt32 = 4
}

/// SSH_FXF_* flags of OPEN.
enum SFTPOpenFlags {
    static let read: UInt32 = 0x01
    static let write: UInt32 = 0x02
    static let append: UInt32 = 0x04
    static let create: UInt32 = 0x08
    static let truncate: UInt32 = 0x10
    static let exclusive: UInt32 = 0x20
}

struct SFTPPacketError: Error, Equatable {
    var reason: String
}

/// File attributes; nil fields are absent on the wire.
struct SFTPAttributes: Equatable, Sendable {
    var size: UInt64?
    var uid: UInt32?
    var gid: UInt32?
    var permissions: UInt32?
    var atime: UInt32?
    var mtime: UInt32?

    static let none = SFTPAttributes()

    static let sizeFlag: UInt32 = 0x01
    static let uidGidFlag: UInt32 = 0x02
    static let permissionsFlag: UInt32 = 0x04
    static let timesFlag: UInt32 = 0x08
    static let extendedFlag: UInt32 = 0x8000_0000

    /// POSIX file type bits of `permissions`.
    var fileType: UInt32? { permissions.map { $0 & 0o170000 } }
}

struct SFTPName: Equatable, Sendable {
    var filename: Data
    var longname: Data
    var attributes: SFTPAttributes
}

/// A decoded server → client packet (and, for tests, encodable back).
enum SFTPResponse: Equatable, Sendable {
    case version(UInt32, extensions: [String: Data])
    case status(id: UInt32, code: UInt32, message: String)
    case handle(id: UInt32, Data)
    case data(id: UInt32, Data)
    case name(id: UInt32, [SFTPName])
    case attrs(id: UInt32, SFTPAttributes)
    case extendedReply(id: UInt32, Data)

    var requestID: UInt32? {
        switch self {
        case .version: nil
        case .status(let id, _, _), .handle(let id, _), .data(let id, _), .name(let id, _),
             .attrs(let id, _), .extendedReply(let id, _): id
        }
    }

    /// `packet` is one frame without the length prefix.
    static func decode(_ packet: Data) throws -> SFTPResponse {
        var r = SFTPDecoder(packet)
        let type = try r.u8()
        switch SFTPType(rawValue: type) {
        case .version:
            let version = try r.u32()
            var extensions: [String: Data] = [:]
            while !r.atEnd {
                let name = String(decoding: try r.string(), as: UTF8.self)
                extensions[name] = try r.string()
            }
            return .version(version, extensions: extensions)
        case .status:
            let id = try r.u32()
            let code = try r.u32()
            // Message and language tag are optional in some old servers.
            let message = r.atEnd ? "" : String(decoding: try r.string(), as: UTF8.self)
            return .status(id: id, code: code, message: message)
        case .handle:
            return .handle(id: try r.u32(), try r.string())
        case .data:
            return .data(id: try r.u32(), try r.string())
        case .name:
            let id = try r.u32()
            let count = try r.u32()
            var names: [SFTPName] = []
            names.reserveCapacity(Int(min(count, 4096)))
            for _ in 0..<count {
                names.append(SFTPName(filename: try r.string(), longname: try r.string(), attributes: try r.attributes()))
            }
            return .name(id: id, names)
        case .attrs:
            return .attrs(id: try r.u32(), try r.attributes())
        case .extendedReply:
            let id = try r.u32()
            return .extendedReply(id: id, r.rest())
        default:
            throw SFTPPacketError(reason: "unexpected packet type \(type)")
        }
    }

    /// Full frame including the length prefix.
    func encoded() -> Data {
        var w = SFTPEncoder()
        switch self {
        case .version(let version, let extensions):
            w.u8(SFTPType.version.rawValue)
            w.u32(version)
            for (name, data) in extensions.sorted(by: { $0.key < $1.key }) {
                w.string(name)
                w.string(data)
            }
        case .status(let id, let code, let message):
            w.u8(SFTPType.status.rawValue); w.u32(id); w.u32(code); w.string(message); w.string("")
        case .handle(let id, let handle):
            w.u8(SFTPType.handle.rawValue); w.u32(id); w.string(handle)
        case .data(let id, let data):
            w.u8(SFTPType.data.rawValue); w.u32(id); w.string(data)
        case .name(let id, let names):
            w.u8(SFTPType.name.rawValue); w.u32(id); w.u32(UInt32(names.count))
            for n in names {
                w.string(n.filename); w.string(n.longname); w.attributes(n.attributes)
            }
        case .attrs(let id, let attributes):
            w.u8(SFTPType.attrs.rawValue); w.u32(id); w.attributes(attributes)
        case .extendedReply(let id, let data):
            w.u8(SFTPType.extendedReply.rawValue); w.u32(id); w.bytes.append(contentsOf: data)
        }
        return w.framed()
    }
}

struct SFTPEncoder {
    var bytes: [UInt8] = []

    mutating func u8(_ v: UInt8) { bytes.append(v) }

    mutating func u32(_ v: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: v >> 24))
        bytes.append(UInt8(truncatingIfNeeded: v >> 16))
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v))
    }

    mutating func u64(_ v: UInt64) {
        u32(UInt32(truncatingIfNeeded: v >> 32))
        u32(UInt32(truncatingIfNeeded: v))
    }

    mutating func string(_ data: Data) {
        u32(UInt32(data.count))
        bytes.append(contentsOf: data)
    }

    mutating func string(_ text: String) { string(Data(text.utf8)) }

    mutating func attributes(_ a: SFTPAttributes) {
        var flags: UInt32 = 0
        if a.size != nil { flags |= SFTPAttributes.sizeFlag }
        if a.uid != nil, a.gid != nil { flags |= SFTPAttributes.uidGidFlag }
        if a.permissions != nil { flags |= SFTPAttributes.permissionsFlag }
        if a.atime != nil || a.mtime != nil { flags |= SFTPAttributes.timesFlag }
        u32(flags)
        if let size = a.size { u64(size) }
        if let uid = a.uid, let gid = a.gid { u32(uid); u32(gid) }
        if let p = a.permissions { u32(p) }
        if a.atime != nil || a.mtime != nil {
            u32(a.atime ?? a.mtime ?? 0)
            u32(a.mtime ?? a.atime ?? 0)
        }
    }

    /// A request frame: length, type, id, then the body written by `body`.
    static func request(_ type: SFTPType, id: UInt32?, _ body: (inout SFTPEncoder) -> Void) -> Data {
        var w = SFTPEncoder()
        w.u8(type.rawValue)
        if let id { w.u32(id) }
        body(&w)
        return w.framed()
    }

    func framed() -> Data {
        var out = Data(capacity: bytes.count + 4)
        let n = UInt32(bytes.count)
        out.append(contentsOf: [UInt8(n >> 24), UInt8(truncatingIfNeeded: n >> 16),
                                UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n)])
        out.append(contentsOf: bytes)
        return out
    }
}

struct SFTPDecoder {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    var atEnd: Bool { offset >= data.endIndex }

    private mutating func take(_ n: Int) throws -> Data {
        guard n >= 0, data.endIndex - offset >= n else { throw SFTPPacketError(reason: "truncated packet") }
        defer { offset += n }
        return data[offset..<offset + n]
    }

    mutating func u8() throws -> UInt8 { try take(1).first! }

    mutating func u32() throws -> UInt32 {
        try take(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func u64() throws -> UInt64 {
        try take(8).reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func string() throws -> Data {
        Data(try take(Int(try u32())))
    }

    mutating func rest() -> Data {
        defer { offset = data.endIndex }
        return Data(data[offset...])
    }

    mutating func attributes() throws -> SFTPAttributes {
        let flags = try u32()
        var a = SFTPAttributes()
        if flags & SFTPAttributes.sizeFlag != 0 { a.size = try u64() }
        if flags & SFTPAttributes.uidGidFlag != 0 { a.uid = try u32(); a.gid = try u32() }
        if flags & SFTPAttributes.permissionsFlag != 0 { a.permissions = try u32() }
        if flags & SFTPAttributes.timesFlag != 0 { a.atime = try u32(); a.mtime = try u32() }
        if flags & SFTPAttributes.extendedFlag != 0 {
            for _ in 0..<(try u32()) { _ = try string(); _ = try string() }
        }
        return a
    }
}

/// Splits a byte stream into length-prefixed frames.
struct SFTPFramer {
    /// Larger frames mean the peer is not speaking SFTP (e.g. shell startup output).
    static let maxFrame = 1 << 24

    private var buffer: [UInt8] = []
    private var start = 0

    /// Appends bytes and returns complete frames (without length); throws on an absurd length.
    mutating func feed(_ chunk: UnsafeRawBufferPointer) throws -> [Data] {
        buffer.append(contentsOf: chunk)
        var frames: [Data] = []
        while buffer.count - start >= 4 {
            let len = Int(buffer[start]) << 24 | Int(buffer[start + 1]) << 16
                | Int(buffer[start + 2]) << 8 | Int(buffer[start + 3])
            guard len > 0, len <= Self.maxFrame else { throw SFTPPacketError(reason: "invalid frame length \(len)") }
            guard buffer.count - start - 4 >= len else { break }
            frames.append(Data(buffer[(start + 4)..<(start + 4 + len)]))
            start += 4 + len
        }
        if start == buffer.count {
            buffer.removeAll(keepingCapacity: true)
            start = 0
        } else if start > 1 << 20 {
            buffer.removeFirst(start)
            start = 0
        }
        return frames
    }
}
