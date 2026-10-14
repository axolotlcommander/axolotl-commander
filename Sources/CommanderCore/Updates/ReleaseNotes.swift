// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// A version of the app (`X.Y.Z`, Semantic Versioning without pre-release tags), compared by numbers.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// `0.6.0`, `v0.6.0` or `[0.6.0]`; anything else is not a version.
    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("["), text.hasSuffix("]") { text = String(text.dropFirst().dropLast()) }
        if text.hasPrefix("v") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// The notes of one released version from the changelog.
public struct ReleaseNote: Equatable, Sendable {
    public let version: AppVersion
    /// The date as written in the heading (`YYYY-MM-DD`), if any.
    public let date: String?
    /// The Markdown below the heading.
    public let body: String

    public init(version: AppVersion, date: String?, body: String) {
        self.version = version
        self.date = date
        self.body = body
    }
}

/// The project's changelog (Keep a Changelog: `## [X.Y.Z] - YYYY-MM-DD` sections) as release notes.
public enum ReleaseNotes {
    /// The released versions, newest first; the "Unreleased" section and the text before the first version
    /// are left out, and a repeated version keeps its first section.
    public static func parse(_ changelog: String) -> [ReleaseNote] {
        var notes: [ReleaseNote] = []
        var current: (version: AppVersion, date: String?)?
        var body: [Substring] = []
        func finish() {
            guard let current, !notes.contains(where: { $0.version == current.version }) else { return }
            let text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            notes.append(ReleaseNote(version: current.version, date: current.date, body: text))
        }
        for line in changelog.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = line.hasSuffix("\r") ? line.dropLast() : line
            if line.hasPrefix("## ") {
                finish()
                current = heading(line.dropFirst(3))
                body = []
            } else if current != nil {
                body.append(line)
            }
        }
        finish()
        return notes.sorted { $0.version > $1.version }
    }

    /// `[0.6.0] - 2026-10-14`, `0.6.0 - 2026-10-14`, `[0.6.0]` or `0.6.0`.
    private static func heading(_ text: Substring) -> (AppVersion, String?)? {
        let parts = text.split(separator: " ", maxSplits: 1)
        guard let first = parts.first, let version = AppVersion(String(first)) else { return nil }
        let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        let date = rest.hasPrefix("-") ? rest.dropFirst().trimmingCharacters(in: .whitespaces) : rest
        return (version, date.isEmpty ? nil : date)
    }

    /// The notes in the user's language: each version of `base` (the English changelog) with the body of the
    /// same version in `translated` when it has one; a version without a translation stays in English, and a
    /// version that is only in the translation is left out.
    public static func localized(_ base: [ReleaseNote], translated: [ReleaseNote]) -> [ReleaseNote] {
        var bodies: [AppVersion: String] = [:]
        for note in translated where !note.body.isEmpty && bodies[note.version] == nil { bodies[note.version] = note.body }
        return base.map { note in
            bodies[note.version].map { ReleaseNote(version: note.version, date: note.date, body: $0) } ?? note
        }
    }

    /// One Markdown page: a heading with the version and date above each version's notes.
    public static func markdown(_ notes: [ReleaseNote]) -> String {
        notes.map { note in
            let title = note.date.map { "## \(note.version) — \($0)" } ?? "## \(note.version)"
            return note.body.isEmpty ? title : title + "\n\n" + note.body
        }.joined(separator: "\n\n")
    }
}

/// What the app shows at a start: the notes of the versions newer than the one that ran before on this Mac,
/// up to the running one. Nothing at the very first start, for the same version or after a downgrade.
public enum WhatsNewStart {
    /// The setting with the version that last ran on this Mac (not exported with the settings).
    public static let lastRunKey = "app.lastRunVersion"

    public static func decide(lastRun: String?, running: AppVersion,
                              notes: [ReleaseNote]) -> (show: [ReleaseNote], remember: String) {
        guard let previous = lastRun.flatMap(AppVersion.init), previous < running else {
            return ([], running.description)
        }
        return (notes.filter { $0.version > previous && $0.version <= running }, running.description)
    }
}
