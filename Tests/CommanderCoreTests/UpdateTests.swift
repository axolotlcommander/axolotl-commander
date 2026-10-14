// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct UpdateTests {
    static func answer(tag: String = "v0.7.0", draft: Bool = false, prerelease: Bool = false,
                       assets: [String] = ["Axolotl-Commander-0.7.0.zip", "Axolotl-Commander-0.7.0.dmg",
                                           "SHA256SUMS.txt", "CHANGELOG.md", "CHANGELOG.cs.md"],
                       scheme: String = "https") -> Data {
        let files = assets.map {
            #"{"name": "\#($0)", "size": 10, "browser_download_url": "\#(scheme)://example.org/dl/\#($0)"}"#
        }.joined(separator: ",")
        return Data("""
            {"tag_name": "\(tag)", "name": "Axolotl Commander", "draft": \(draft), "prerelease": \(prerelease),
             "html_url": "https://example.org/releases/\(tag)", "published_at": "2026-10-20T08:30:00Z",
             "body": "notes", "assets": [\(files)]}
            """.utf8)
    }

    static func release(_ version: String, complete: Bool = true) -> ReleaseInfo {
        let url = URL(string: "https://example.org/f")!
        return ReleaseInfo(version: AppVersion(version)!, published: nil, page: url,
                           archive: complete ? url : nil, checksums: complete ? url : nil)
    }

    let v060 = AppVersion("0.6.0")!
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func parsesTheAnswer() throws {
        let release = try ReleaseInfo.parse(Self.answer())
        #expect(release.version == AppVersion("0.7.0"))
        #expect(release.page.absoluteString == "https://example.org/releases/v0.7.0")
        #expect(release.archive?.lastPathComponent == "Axolotl-Commander-0.7.0.zip")
        #expect(release.checksums?.lastPathComponent == "SHA256SUMS.txt")
        #expect(release.changelog?.lastPathComponent == "CHANGELOG.md")
        #expect(release.czechChangelog?.lastPathComponent == "CHANGELOG.cs.md")
        #expect(release.published == ISO8601DateFormatter().date(from: "2026-10-20T08:30:00Z"))
        #expect(release.isComplete && !release.isDraft && !release.isPrerelease)
    }

    @Test func incompleteOrOddReleases() throws {
        #expect(try ReleaseInfo.parse(Self.answer(draft: true)).isDraft)
        #expect(try ReleaseInfo.parse(Self.answer(prerelease: true)).isPrerelease)
        #expect(try !ReleaseInfo.parse(Self.answer(assets: ["Axolotl-Commander-0.7.0.zip"])).isComplete)
        // The zip of another version does not count.
        #expect(try !ReleaseInfo.parse(Self.answer(assets: ["Axolotl-Commander-0.6.9.zip", "SHA256SUMS.txt"])).isComplete)
        #expect(try !ReleaseInfo.parse(Self.answer(scheme: "http")).isComplete)
        // Plain HTTP only to this Mac (the GUI check's local server).
        #expect(ReleaseInfo.isSafe(URL(string: "http://127.0.0.1:8123/x.zip")!))
        #expect(ReleaseInfo.isSafe(URL(string: "http://localhost/x.zip")!))
        #expect(!ReleaseInfo.isSafe(URL(string: "http://127.0.0.1.example.org/x.zip")!))
        #expect(!ReleaseInfo.isSafe(URL(string: "ftp://example.org/x.zip")!))
        #expect(throws: ReleaseInfo.ParseError.notAVersion("nightly")) { try ReleaseInfo.parse(Self.answer(tag: "nightly")) }
        #expect(throws: ReleaseInfo.ParseError.malformed) { try ReleaseInfo.parse(Data("{\"message\": \"Not Found\"}".utf8)) }
        #expect(throws: ReleaseInfo.ParseError.malformed) { try ReleaseInfo.parse(Data("<html>".utf8)) }
    }

    @Test func checksumFile() {
        let hash = String(repeating: "ab", count: 32)
        let sums = ChecksumFile.parse("""
            \(hash)  Axolotl-Commander-0.7.0.zip
            \(hash.uppercased()) *Axolotl-Commander-0.7.0.dmg
            nonsense
            1234  short.zip
            """)
        #expect(sums == ["Axolotl-Commander-0.7.0.zip": hash, "Axolotl-Commander-0.7.0.dmg": hash])
    }

    @Test func whenTheCheckIsDue() {
        var state = UpdateState()
        #expect(state.isDue(now: now))                                  // never checked
        state.recordSuccess(nil, running: v060, now: now)
        #expect(!state.isDue(now: now.addingTimeInterval(23 * 3600)))
        #expect(state.isDue(now: now.addingTimeInterval(25 * 3600)))
        state.recordFailure(now: now)
        #expect(!state.isDue(now: now.addingTimeInterval(59 * 60)))
        #expect(state.isDue(now: now.addingTimeInterval(61 * 60)))
        // Another copy has just written the attempt: not due for it.
        state.recordSuccess(nil, running: v060, now: now.addingTimeInterval(-30 * 3600))
        state.lastCheck = now
        #expect(!state.isDue(now: now.addingTimeInterval(60)))
        // The clock moved back: a check in the future counts as due.
        state.lastCheck = now.addingTimeInterval(3600 * 48)
        #expect(state.isDue(now: now))
        state.automatic = false
        #expect(!state.isDue(now: now))
    }

    @Test func whatIsOffered() {
        var state = UpdateState()
        let newer = Self.release("0.7.0")
        #expect(state.offers(newer, running: v060, manual: false, now: now))
        #expect(!state.offers(Self.release("0.6.0"), running: v060, manual: true, now: now))
        #expect(!state.offers(Self.release("0.5.9"), running: v060, manual: true, now: now))
        #expect(!state.offers(Self.release("0.7.0", complete: false), running: v060, manual: true, now: now))
        state.skip(AppVersion("0.7.0")!)
        #expect(!state.offers(newer, running: v060, manual: false, now: now))
        #expect(state.offers(newer, running: v060, manual: true, now: now))       // a manual check ignores it
        #expect(state.offers(Self.release("0.7.1"), running: v060, manual: false, now: now))
        state = UpdateState()
        state.remindLater(now: now)
        #expect(!state.offers(newer, running: v060, manual: false, now: now.addingTimeInterval(23 * 3600)))
        #expect(state.offers(newer, running: v060, manual: false, now: now.addingTimeInterval(25 * 3600)))
        #expect(state.offers(newer, running: v060, manual: true, now: now))
    }

    @Test func resultsAreRemembered() throws {
        let defaults = try #require(UserDefaults(suiteName: "UpdateTests.\(UUID().uuidString)"))
        var state = UpdateState(defaults)
        #expect(state.automatic && state.lastResult == nil)
        state.recordSuccess(Self.release("0.7.0"), running: v060, now: now)
        state.skip(AppVersion("0.6.5")!)
        state.remindLater(now: now)
        state.save(to: defaults)
        let loaded = UpdateState(defaults)
        #expect(loaded == state)
        #expect(loaded.lastResult == .available && loaded.availableVersion == AppVersion("0.7.0"))
        var upToDate = loaded
        upToDate.recordSuccess(Self.release("0.6.0"), running: v060, now: now)
        #expect(upToDate.lastResult == .upToDate && upToDate.availableVersion == nil)
    }

    @Test func notesOfTheOffer() {
        let english = """
            ## [Unreleased]
            - Soon.
            ## [0.8.0] - 2026-11-01
            - Eight.
            ## [0.7.0] - 2026-10-20
            - Seven.
            ## [0.6.1] - 2026-10-16
            - Fix.
            ## [0.6.0] - 2026-10-14
            - Six.
            """
        let czech = """
            ## [0.7.0] - 2026-10-20
            - Sedm.
            """
        let notes = UpdateNotes.notes(english: english, translated: czech, running: v060, offered: AppVersion("0.7.0")!)
        #expect(notes.map(\.version.description) == ["0.7.0", "0.6.1"])
        #expect(notes.map(\.body) == ["- Sedm.", "- Fix."])
        #expect(UpdateNotes.notes(english: nil, translated: nil, running: v060, offered: AppVersion("0.7.0")!).isEmpty)
    }
}
