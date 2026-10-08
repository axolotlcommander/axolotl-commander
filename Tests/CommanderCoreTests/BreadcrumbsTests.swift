// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// Breadcrumb trails of panel locations and the rule that shortens them (spec 003).
@Suite struct BreadcrumbsTests {
    private let boot = (root: URL(filePath: "/", directoryHint: .isDirectory), name: "Macintosh HD")
    private let home = URL(filePath: "/Users/me", directoryHint: .isDirectory)

    private func dir(_ path: String) -> URL { URL(filePath: path, directoryHint: .isDirectory) }

    private func names(_ trail: [PathSegment]) -> [String] { trail.map(\.name) }

    // MARK: Local

    @Test func bootVolumeFolders() {
        let trail = Breadcrumbs.trail(location: dir("/Users/me/Projects/docs"), volume: boot, home: home)
        #expect(names(trail) == ["Macintosh HD", "Users", "me", "Projects", "docs"])
        #expect(trail.map(\.kind) == [.volume, .folder, .home, .folder, .folder])
        #expect(trail[0].url.path == "/")
        #expect(trail[2].url.path(percentEncoded: false).hasPrefix("/Users/me"))
        #expect(trail.last?.url.path(percentEncoded: false) == "/Users/me/Projects/docs/")
        #expect(trail.allSatisfy { $0.isClickable })
    }

    @Test func volumeRootAlone() {
        #expect(names(Breadcrumbs.trail(location: dir("/"), volume: boot, home: home)) == ["Macintosh HD"])
        let ext = (root: dir("/Volumes/Ext"), name: "Ext")
        let trail = Breadcrumbs.trail(location: dir("/Volumes/Ext"), volume: ext, home: home)
        #expect(names(trail) == ["Ext"])
        #expect(trail[0].kind == .volume)
    }

    @Test func otherVolumeStartsAtItsMountPoint() {
        let ext = (root: dir("/Volumes/Ext"), name: "Backup Disk")
        let trail = Breadcrumbs.trail(location: dir("/Volumes/Ext/photos/2026"), volume: ext, home: home)
        #expect(names(trail) == ["Backup Disk", "photos", "2026"])
        #expect(trail[0].url.path(percentEncoded: false).hasPrefix("/Volumes/Ext"))
        #expect(trail[1].url.path(percentEncoded: false) == "/Volumes/Ext/photos/")
    }

    /// A mount point that is not a prefix of the shown path (firmlinks): start at "/".
    @Test func volumeRootNotAPrefixFallsBackToSlash() {
        let data = (root: dir("/System/Volumes/Data"), name: "Macintosh HD")
        let trail = Breadcrumbs.trail(location: dir("/Users/me"), volume: data, home: home)
        #expect(names(trail) == ["Macintosh HD", "Users", "me"])
        #expect(trail[0].url.path == "/")
    }

    @Test func namesWithSeparatorStayOneSegment() {
        let trail = Breadcrumbs.trail(location: dir("/tmp/a › b/c"), volume: boot, home: home)
        #expect(names(trail) == ["Macintosh HD", "tmp", "a › b", "c"])
    }

    @Test func focusNameIsTheNextSegment() {
        let trail = Breadcrumbs.trail(location: dir("/Users/me/a/b"), volume: boot, home: home)
        #expect(Breadcrumbs.focusName(after: 0, in: trail) == "Users")
        #expect(Breadcrumbs.focusName(after: 3, in: trail) == "b")
        #expect(Breadcrumbs.focusName(after: 4, in: trail) == nil)
    }

    // MARK: Archives, servers, results

    @Test func archiveTrail() {
        let archive = ArchivePath(archive: URL(filePath: "/tmp/t/pack.zip"), inner: "inner/deep", format: .zip)
        let trail = Breadcrumbs.trail(location: archive.url, archive: archive, volume: boot, home: home)
        #expect(names(trail) == ["Macintosh HD", "tmp", "t", "pack.zip", "inner", "deep"])
        #expect(trail.map(\.kind) == [.volume, .folder, .folder, .archive, .archiveFolder, .archiveFolder])
        #expect(trail[3].url.path(percentEncoded: false) == "/tmp/t/pack.zip")
        #expect(trail[4].url.path(percentEncoded: false) == "/tmp/t/pack.zip/inner/")
        // Leaving the archive to its folder puts the cursor on the archive file.
        #expect(Breadcrumbs.focusName(after: 2, in: trail) == "pack.zip")
    }

    /// The archive's own path may be spelled differently from the panel location ("/tmp" vs
    /// "/private/tmp"); the archive segment is still found.
    @Test func archiveWithDifferentlySpelledPath() {
        let archive = ArchivePath(archive: URL(filePath: "/tmp/t/pack.zip"), inner: "inner", format: .zip)
        let location = URL(filePath: "/private/tmp/t/pack.zip/inner", directoryHint: .isDirectory)
        let trail = Breadcrumbs.trail(location: location, archive: archive, volume: boot, home: home)
        #expect(names(trail) == ["Macintosh HD", "private", "tmp", "t", "pack.zip", "inner"])
        #expect(trail.map(\.kind) == [.volume, .folder, .folder, .folder, .archive, .archiveFolder])
    }

    @Test func archiveRoot() {
        let archive = ArchivePath(archive: URL(filePath: "/tmp/pack.zip"), format: .zip)
        let trail = Breadcrumbs.trail(location: archive.url, archive: archive, volume: boot, home: home)
        #expect(trail.map(\.kind) == [.volume, .folder, .archive])
    }

    @Test func remoteTrail() {
        let endpoint = RemoteEndpoint(proto: .sftp, host: "example.org", port: 2222, user: "tester")
        let remote = RemoteLocation(endpoint: endpoint, path: "/home/tester/www")
        let trail = Breadcrumbs.trail(location: remote.url, remote: remote, volume: boot, home: home)
        #expect(names(trail) == ["tester@example.org:2222", "home", "tester", "www"])
        #expect(trail.map(\.kind) == [.server, .remoteFolder, .remoteFolder, .remoteFolder])
        #expect(RemoteURL.parse(trail[0].url)?.path == "/")
        #expect(RemoteURL.parse(trail[2].url)?.path == "/home/tester")
        #expect(RemoteURL.parse(trail[2].url)?.endpoint == endpoint)
    }

    @Test func remoteBeforeLoginFolderIsKnown() {
        let remote = RemoteLocation(endpoint: RemoteEndpoint(proto: .ftp, host: "ftp.example.org"), path: "")
        let trail = Breadcrumbs.trail(location: remote.url, remote: remote, volume: boot, home: home)
        #expect(names(trail) == ["ftp.example.org"])
    }

    @Test func resultsTrail() {
        let listing = ResultsListing(title: "Search Results", urls: [
            URL(filePath: "/tmp/t/a/one.txt"), URL(filePath: "/tmp/t/b/two.txt"),
        ])
        let trail = Breadcrumbs.trail(location: listing.root, results: listing, volume: boot, home: home)
        #expect(names(trail) == ["Search Results", "Macintosh HD", "tmp", "t"])
        #expect(trail[0].kind == .results)
        #expect(!trail[0].isClickable)
        #expect(trail.dropFirst().allSatisfy { $0.isClickable })
        #expect(Breadcrumbs.focusName(after: 3, in: trail) == nil)
    }

    // MARK: Fitting

    @Test func everythingFits() {
        let fit = Breadcrumbs.fit(widths: [50, 40, 40], available: 200, ellipsis: 10, separator: 5)
        #expect(fit == BreadcrumbFit(visible: [0, 1, 2]))
        // Exactly the needed width: 130 + 2 × 5.
        #expect(Breadcrumbs.fit(widths: [50, 40, 40], available: 140, ellipsis: 10, separator: 5).hidden == nil)
    }

    @Test func middleCollapsesKeepingNeighborsOfTheLast() {
        // 0:50 1:40 2:40 3:40 4:40 5:30 — first + … + 4 + 5 = 50+5+10+5+40+5+30 = 145
        let widths: [Double] = [50, 40, 40, 40, 40, 30]
        let fit = Breadcrumbs.fit(widths: widths, available: 150, ellipsis: 10, separator: 5)
        #expect(fit == BreadcrumbFit(visible: [0, 4, 5], hidden: 1..<4))
        let wider = Breadcrumbs.fit(widths: widths, available: 190, ellipsis: 10, separator: 5)
        #expect(wider == BreadcrumbFit(visible: [0, 3, 4, 5], hidden: 1..<3))
    }

    @Test func onlyFirstEllipsisAndLast() {
        let fit = Breadcrumbs.fit(widths: [50, 40, 40, 30], available: 100, ellipsis: 10, separator: 5)
        #expect(fit == BreadcrumbFit(visible: [0, 3], hidden: 1..<3))
    }

    @Test func lastIsTruncatedOnlyWhenNothingElseHelps() {
        let fit = Breadcrumbs.fit(widths: [50, 40, 40, 300], available: 120, ellipsis: 10, separator: 5)
        #expect(fit == BreadcrumbFit(visible: [0, 3], hidden: 1..<3, lastWidth: 50))
        let two = Breadcrumbs.fit(widths: [50, 300], available: 120, ellipsis: 10, separator: 5)
        #expect(two == BreadcrumbFit(visible: [0, 1], lastWidth: 65))
        let one = Breadcrumbs.fit(widths: [300], available: 120, ellipsis: 10, separator: 5)
        #expect(one == BreadcrumbFit(visible: [0], lastWidth: 120))
        #expect(Breadcrumbs.fit(widths: [], available: 120, ellipsis: 10, separator: 5).visible.isEmpty)
    }

    @Test func invariantsHoldForManyWidths() {
        for count in 1...12 {
            let widths = (0..<count).map { Double(20 + ($0 * 37) % 60) }
            for available in stride(from: 0.0, through: 700, by: 13) {
                let fit = Breadcrumbs.fit(widths: widths, available: available, ellipsis: 12, separator: 6)
                #expect(fit.visible.first == 0)
                #expect(fit.visible.last == count - 1)
                #expect(fit.visible == fit.visible.sorted())
                if let hidden = fit.hidden {
                    #expect(hidden.lowerBound == 1 && hidden.upperBound <= count - 1 && !hidden.isEmpty)
                    #expect(fit.visible.count == count - hidden.count)
                } else {
                    #expect(fit.visible.count == count)
                }
                if fit.lastWidth == nil {
                    let shown = fit.visible.map { widths[$0] }.reduce(0, +)
                        + (fit.hidden == nil ? 0 : 12 + 6) + 6 * Double(fit.visible.count - 1)
                    #expect(shown <= available)
                }
            }
        }
    }

    // MARK: Localization

    /// Texts of the path bar, its menu and settings are translated (looked up by English text).
    @Test func pathBarTextsAreTranslated() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])
        func czech(_ key: String) -> String? {
            let entry = strings[key] as? [String: Any]
            let cs = (entry?["localizations"] as? [String: Any])?["cs"] as? [String: Any]
            return (cs?["stringUnit"] as? [String: Any])?["value"] as? String
        }
        let keys = [
            "Path", "Hidden folders", "Open in Other Panel", "Open in New Tab", "Copy Path", "Set as Hot Path",
            "Show in Finder", "Path bar:", "Breadcrumbs", "Text field", "Show icons in path bar",
            CommandRegistry.spec(.editPath).title,
        ]
        for key in keys {
            #expect(czech(key) != nil, "missing Czech translation for \"\(key)\"")
        }
    }
}
