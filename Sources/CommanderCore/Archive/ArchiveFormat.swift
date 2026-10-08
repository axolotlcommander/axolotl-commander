// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Archive kinds the panels can open.
public enum ArchiveFormat: Hashable, Sendable {
    case zip, sevenZip, tar, tarGzip, tarBzip2, tarXz, rar

    /// From the file name, case-insensitive; nil for anything else.
    public static func detect(fileName: String) -> ArchiveFormat? {
        let name = fileName.lowercased()
        let suffixes: [(String, ArchiveFormat)] = [
            (".tar.gz", .tarGzip), (".tgz", .tarGzip),
            (".tar.bz2", .tarBzip2), (".tbz", .tarBzip2), (".tbz2", .tarBzip2),
            (".tar.xz", .tarXz), (".txz", .tarXz),
            (".tar", .tar), (".zip", .zip), (".jar", .zip), (".7z", .sevenZip), (".rar", .rar),
        ]
        for (suffix, format) in suffixes where name.hasSuffix(suffix) && name.count > suffix.count {
            return format
        }
        return nil
    }

    /// False only for rar (no writer in libarchive).
    public var isWritable: Bool { self != .rar }

    public var preferredExtension: String {
        switch self {
        case .zip: "zip"
        case .sevenZip: "7z"
        case .tar: "tar"
        case .tarGzip: "tar.gz"
        case .tarBzip2: "tar.bz2"
        case .tarXz: "tar.xz"
        case .rar: "rar"
        }
    }
}

public enum ArchiveError: Error, Equatable, Sendable {
    case unsupportedFormat
    /// Rar, or the archive has encrypted entries and would need rewriting.
    case readOnly
    /// Member encrypted with a method libarchive cannot decrypt (7z, rar, zip strong encryption).
    case encrypted(String)
    /// Encrypted zip member and no passphrase was given.
    case passwordRequired(String)
    /// None of the given passphrases decrypts the member.
    case wrongPassword(String)
    /// Inner folder or member not in the archive, or a source file that is missing.
    case notFound(String)
    case alreadyExists(String)
    /// libarchive error string.
    case library(String)
    case cancelled
}

extension ArchiveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            String(localized: "The archive format is not supported.")
        case .readOnly:
            String(localized: "This archive cannot be modified.")
        case .encrypted(let path):
            String(localized: "“\(path)” is encrypted with a method that is not supported.")
        case .passwordRequired(let path):
            String(localized: "“\(path)” is encrypted and needs a password.")
        case .wrongPassword(let path):
            String(localized: "The password for “\(path)” is wrong.")
        case .notFound(let path):
            String(localized: "“\(path)” was not found in the archive.")
        case .alreadyExists(let path):
            String(localized: "“\(path)” already exists.")
        case .library(let message):
            String(localized: "Archive error: \(message)")
        case .cancelled:
            String(localized: "The operation was cancelled.")
        }
    }
}
