// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// What the app remembers about checking for updates (spec 027, `data-model.md`), in the user defaults.
public struct UpdateState: Equatable, Sendable {
    public static let automaticKey = "updates.automatic"
    public static let lastCheckKey = "updates.lastCheck"
    public static let lastSuccessKey = "updates.lastSuccess"
    public static let lastResultKey = "updates.lastResult"
    public static let availableVersionKey = "updates.availableVersion"
    public static let skippedVersionKey = "updates.skippedVersion"
    public static let remindAfterKey = "updates.remindAfter"
    /// Hidden: a test server instead of the project's releases (never shown in Settings, not exported).
    public static let feedURLKey = "updates.feedURL"

    public static let checkInterval: TimeInterval = 24 * 3600
    public static let retryInterval: TimeInterval = 3600

    public enum Result: String, Sendable { case upToDate, available, failed }

    public var automatic = true
    /// The last attempt (written before the request, so a second running copy finds the check not due).
    public var lastCheck: Date?
    public var lastSuccess: Date?
    public var lastResult: Result?
    public var availableVersion: AppVersion?
    public var skippedVersion: AppVersion?
    public var remindAfter: Date?

    public init() {}

    public init(_ defaults: UserDefaults) {
        automatic = defaults.object(forKey: Self.automaticKey) as? Bool ?? true
        lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        lastSuccess = defaults.object(forKey: Self.lastSuccessKey) as? Date
        lastResult = defaults.string(forKey: Self.lastResultKey).flatMap(Result.init)
        availableVersion = defaults.string(forKey: Self.availableVersionKey).flatMap(AppVersion.init)
        skippedVersion = defaults.string(forKey: Self.skippedVersionKey).flatMap(AppVersion.init)
        remindAfter = defaults.object(forKey: Self.remindAfterKey) as? Date
    }

    /// Writes the remembered state (`automatic` is the user's setting and is written where it changes).
    public func save(to defaults: UserDefaults) {
        func put(_ value: Any?, _ key: String) {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        put(lastCheck, Self.lastCheckKey)
        put(lastSuccess, Self.lastSuccessKey)
        put(lastResult?.rawValue, Self.lastResultKey)
        put(availableVersion?.description, Self.availableVersionKey)
        put(skippedVersion?.description, Self.skippedVersionKey)
        put(remindAfter, Self.remindAfterKey)
    }

    /// Whether the automatic check should run now: once a day after a success, once an hour after a
    /// failure; a time in the future (the clock moved back) counts as due.
    public func isDue(now: Date) -> Bool {
        guard automatic else { return false }
        guard let lastCheck, lastCheck <= now else { return true }
        // An attempt in the last hour (also one another copy has just started) waits.
        guard now.timeIntervalSince(lastCheck) >= Self.retryInterval else { return false }
        if lastResult == .failed { return true }
        guard let lastSuccess, lastSuccess <= now else { return true }
        return now.timeIntervalSince(lastSuccess) >= Self.checkInterval
    }

    /// Whether to show the release: newer than the running version, published and complete; the automatic
    /// check also leaves out a skipped version and waits after Remind Me Later.
    public func offers(_ release: ReleaseInfo, running: AppVersion, manual: Bool, now: Date) -> Bool {
        guard release.version > running, !release.isDraft, !release.isPrerelease, release.isComplete else { return false }
        if manual { return true }
        if release.version == skippedVersion { return false }
        if let remindAfter, now < remindAfter { return false }
        return true
    }

    /// The result of a successful check.
    public mutating func recordSuccess(_ release: ReleaseInfo?, running: AppVersion, now: Date) {
        lastCheck = now
        lastSuccess = now
        if let release, release.version > running, release.isComplete {
            lastResult = .available
            availableVersion = release.version
        } else {
            lastResult = .upToDate
            availableVersion = nil
        }
    }

    public mutating func recordFailure(now: Date) {
        lastCheck = now
        lastResult = .failed
    }

    public mutating func remindLater(now: Date) { remindAfter = now.addingTimeInterval(Self.checkInterval) }

    public mutating func skip(_ version: AppVersion) { skippedVersion = version }
}

/// The notes the update window shows: every version newer than the running one up to the offered one, from
/// the release's changelogs, in the app's language where translated (spec 026 `ReleaseNotes.localized`).
public enum UpdateNotes {
    public static func notes(english: String?, translated: String?, running: AppVersion,
                             offered: AppVersion) -> [ReleaseNote] {
        let base = ReleaseNotes.parse(english ?? "")
        let notes = translated.map { ReleaseNotes.localized(base, translated: ReleaseNotes.parse($0)) } ?? base
        return notes.filter { $0.version > running && $0.version <= offered }
    }
}
