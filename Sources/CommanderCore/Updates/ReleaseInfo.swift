// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// A release from the releases API (spec 027, `contracts/release.md`): its version, date, page and the files
/// the app uses.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: AppVersion
    public let published: Date?
    public let page: URL
    public let isDraft: Bool
    public let isPrerelease: Bool
    /// `Axolotl-Commander-X.Y.Z.zip`
    public let archive: URL?
    /// `SHA256SUMS.txt`
    public let checksums: URL?
    public let changelog: URL?
    public let czechChangelog: URL?

    public static func archiveName(_ version: AppVersion) -> String { "Axolotl-Commander-\(version).zip" }
    public static let checksumsName = "SHA256SUMS.txt"

    public var archiveName: String { Self.archiveName(version) }

    /// The app archive and its checksum are there; a release without them is never offered.
    public var isComplete: Bool { archive != nil && checksums != nil }

    public init(version: AppVersion, published: Date?, page: URL, isDraft: Bool = false, isPrerelease: Bool = false,
                archive: URL?, checksums: URL?, changelog: URL? = nil, czechChangelog: URL? = nil) {
        self.version = version
        self.published = published
        self.page = page
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.archive = archive
        self.checksums = checksums
        self.changelog = changelog
        self.czechChangelog = czechChangelog
    }

    public enum ParseError: Error, Equatable {
        case malformed
        case notAVersion(String)
    }

    /// The `releases/latest` answer. Only HTTPS files count; unknown fields are ignored.
    /// HTTPS only; plain HTTP just to this Mac itself (the local test server of the GUI check, R9).
    static func isSafe(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https": true
        case "http": ["127.0.0.1", "localhost", "::1"].contains(url.host?.lowercased() ?? "")
        default: false
        }
    }

    public static func parse(_ data: Data) throws -> ReleaseInfo {
        struct Answer: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
            }
            let tag_name: String
            let html_url: String
            let draft: Bool?
            let prerelease: Bool?
            let published_at: String?
            let assets: [Asset]?
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data),
              let page = URL(string: answer.html_url), isSafe(page) else { throw ParseError.malformed }
        guard let version = AppVersion(answer.tag_name) else { throw ParseError.notAVersion(answer.tag_name) }
        var files: [String: URL] = [:]
        for asset in answer.assets ?? [] {
            if let url = URL(string: asset.browser_download_url), isSafe(url), files[asset.name] == nil {
                files[asset.name] = url
            }
        }
        return ReleaseInfo(version: version, published: answer.published_at.flatMap(date), page: page,
                           isDraft: answer.draft ?? false, isPrerelease: answer.prerelease ?? false,
                           archive: files[archiveName(version)], checksums: files[checksumsName],
                           changelog: files["CHANGELOG.md"], czechChangelog: files["CHANGELOG.cs.md"])
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}

/// `SHA256SUMS.txt` as written by `shasum -a 256`: `<64 hex>  <name>` (or `<hex> *<name>`) per line.
public enum ChecksumFile {
    /// File name → lowercase hex digest; lines that do not fit are skipped.
    public static func parse(_ text: String) -> [String: String] {
        var sums: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2 else { continue }
            let hash = parts[0].lowercased()
            var name = parts[1].drop(while: { $0 == " " || $0 == "\t" })
            if name.hasPrefix("*") { name = name.dropFirst() }
            guard hash.count == 64, hash.allSatisfy(\.isHexDigit), !name.isEmpty else { continue }
            sums[String(name)] = hash
        }
        return sums
    }
}
