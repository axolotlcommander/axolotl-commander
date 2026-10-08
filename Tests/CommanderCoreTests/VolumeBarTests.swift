// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct ServerLabelsTests {
    @Test func uniqueHostsShowTheHost() {
        let a = RemoteEndpoint(proto: .sftp, host: "127.0.0.1", port: 2222, user: "tester")
        let b = RemoteEndpoint(proto: .ftp, host: "files.example.org")
        #expect(ServerLabels.labels(for: [a, b]) == [a: "127.0.0.1", b: "files.example.org"])
        #expect(ServerLabels.labels(for: []).isEmpty)
    }

    @Test func sameHostOtherUsersShowTheUser() {
        let jan = RemoteEndpoint(proto: .sftp, host: "server", user: "jan")
        let eva = RemoteEndpoint(proto: .sftp, host: "server", user: "eva")
        let other = RemoteEndpoint(proto: .sftp, host: "other", user: "jan")
        #expect(ServerLabels.labels(for: [jan, eva, other]) == [jan: "jan@server", eva: "eva@server", other: "other"])
    }

    @Test func sameUserOtherPortsShowThePort() {
        let standard = RemoteEndpoint(proto: .sftp, host: "server", port: 22, user: "jan")
        let custom = RemoteEndpoint(proto: .sftp, host: "server", port: 2222, user: "jan")
        let anonymous = RemoteEndpoint(proto: .sftp, host: "server", port: 2200)
        let labels = ServerLabels.labels(for: [standard, custom, anonymous])
        // Without a user, `user@host` is the host, which is unique once the others show their user.
        #expect(labels == [standard: "jan@server", custom: "jan@server:2222", anonymous: "server"])
    }

    @Test func otherProtocolsShowTheProtocol() {
        let sftp = RemoteEndpoint(proto: .sftp, host: "server", user: "jan")
        let ftp = RemoteEndpoint(proto: .ftp, host: "server", user: "jan")
        let labels = ServerLabels.labels(for: [sftp, ftp])
        #expect(labels == [sftp: "sftp://jan@server", ftp: "ftp://jan@server"])
    }

    @Test func labelsNeverHoldAPassword() throws {
        let typed = try #require(RemoteURL.parse(typed: "sftp://jan:tajné@server:2222/data"))
        let other = RemoteEndpoint(proto: .ftp, host: "server", port: 2222, user: "jan")
        for label in ServerLabels.labels(for: [typed.location.endpoint, other]).values {
            #expect(!label.contains("tajné"))
        }
    }
}

@Suite struct ConnectionPlacesTests {
    private let server = RemoteEndpoint(proto: .sftp, host: "server", user: "jan")
    private let other = RemoteEndpoint(proto: .ftp, host: "other")

    @Test func ownPanelThenAnyPanelThenLoginFolder() {
        var places = ConnectionPlaces<Int>()
        #expect(places.place(for: server, panel: 1) == RemoteLocation(endpoint: server, path: ""))

        places.visit(RemoteLocation(endpoint: server, path: "/data/sub"), panel: 1)
        #expect(places.place(for: server, panel: 1).path == "/data/sub")
        // A panel that was never there gets the last folder of any panel.
        #expect(places.place(for: server, panel: 2).path == "/data/sub")

        places.visit(RemoteLocation(endpoint: server, path: "/home"), panel: 2)
        #expect(places.place(for: server, panel: 1).path == "/data/sub")
        #expect(places.place(for: server, panel: 2).path == "/home")
        #expect(places.place(for: server, panel: 3).path == "/home")
        #expect(places.place(for: other, panel: 1).path == "")
    }

    @Test func unresolvedLoginFolderIsIgnored() {
        var places = ConnectionPlaces<Int>()
        places.visit(RemoteLocation(endpoint: server, path: "/data"), panel: 1)
        places.visit(RemoteLocation(endpoint: server, path: ""), panel: 1)
        #expect(places.place(for: server, panel: 1).path == "/data")
    }

    @Test func forgetDropsOnlyThatConnection() {
        var places = ConnectionPlaces<Int>()
        places.visit(RemoteLocation(endpoint: server, path: "/data"), panel: 1)
        places.visit(RemoteLocation(endpoint: other, path: "/pub"), panel: 1)
        places.forget(server)
        #expect(places.place(for: server, panel: 1).path == "")
        #expect(places.place(for: server, panel: 2).path == "")
        #expect(places.place(for: other, panel: 1).path == "/pub")
    }
}

@Suite struct VolumeBarModelTests {
    private let boot = VolumeInfo(url: URL(filePath: "/", directoryHint: .isDirectory), name: "Macintosh HD")
    private let stick = VolumeInfo(url: URL(filePath: "/Volumes/Stick", directoryHint: .isDirectory), name: "Stick",
                                   isRemovable: true)
    private let home = URL(filePath: "/Users/jan", directoryHint: .isDirectory)
    private let iCloud = URL(filePath: "/Users/jan/Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
    private let server = RemoteEndpoint(proto: .sftp, host: "server", user: "jan")
    private let ftp = RemoteEndpoint(proto: .ftp, host: "files")

    private func items(_ settings: VolumeBarSettings = VolumeBarSettings(), iCloud: URL? = nil,
                       servers: [RemoteEndpoint]? = nil) -> [VolumeBarModel.Item] {
        VolumeBarModel.items(volumes: [boot, stick], home: home, iCloud: iCloud ?? self.iCloud,
                             servers: servers ?? [server, ftp], settings: settings)
    }

    @Test func defaultOrder() {
        #expect(items() == [.volume(boot), .volume(stick), .iCloud(iCloud), .network,
                            .server(server, label: "server"), .server(ftp, label: "files")])
    }

    @Test func everyItemShown() {
        let all = VolumeBarSettings(showHome: true)
        #expect(items(all) == [.volume(boot), .volume(stick), .home(home), .iCloud(iCloud), .network,
                               .server(server, label: "server"), .server(ftp, label: "files")])
    }

    @Test func onlyVolumes() {
        let none = VolumeBarSettings(showHome: false, showICloud: false, showNetwork: false, showServers: false)
        #expect(items(none) == [.volume(boot), .volume(stick)])
    }

    @Test func eachSettingHidesItsItem() {
        #expect(!items(VolumeBarSettings(showICloud: false)).contains(.iCloud(iCloud)))
        #expect(!items(VolumeBarSettings(showNetwork: false)).contains(.network))
        #expect(items(VolumeBarSettings(showServers: false)) == [.volume(boot), .volume(stick), .iCloud(iCloud), .network])
        #expect(items(VolumeBarSettings(showHome: true)).contains(.home(home)))
    }

    @Test func missingICloudDriveHasNoButton() {
        let bar = VolumeBarModel.items(volumes: [boot], home: home, iCloud: nil, servers: [], settings: VolumeBarSettings())
        #expect(bar == [.volume(boot), .network])
    }

    @Test func serversKeepOpeningOrderAndGetDistinctLabels() {
        let eva = RemoteEndpoint(proto: .sftp, host: "server", user: "eva")
        let bar = items(servers: [server, eva, server])
        #expect(Array(bar.suffix(2)) == [.server(server, label: "jan@server"), .server(eva, label: "eva@server")])
    }

    @Test func settingsReadSavedValues() {
        #expect(VolumeBarSettings(value: { _ in nil }) == VolumeBarSettings())
        let saved: [String: Any] = [VolumeBarSettings.homeKey: true, VolumeBarSettings.networkKey: false]
        let settings = VolumeBarSettings(value: { saved[$0] })
        #expect(settings == VolumeBarSettings(showHome: true, showICloud: true, showNetwork: false, showServers: true))
    }

    private func pressed(_ path: String?, remote: RemoteEndpoint? = nil, root: String? = "/",
                         in bar: [VolumeBarModel.Item]) -> Int? {
        VolumeBarModel.pressed(local: path.map { URL(filePath: $0) }, remote: remote,
                               volumeRoot: root.map { URL(filePath: $0, directoryHint: .isDirectory) }, items: bar)
    }

    @Test func remoteLocationPressesItsServer() {
        let bar = items()
        #expect(pressed(nil, remote: ftp, root: nil, in: bar) == 5)
        #expect(pressed(nil, remote: server, root: nil, in: bar) == 4)
        // A server without a button presses nothing (no volume either).
        #expect(pressed(nil, remote: server, root: nil, in: items(VolumeBarSettings(showServers: false))) == nil)
    }

    @Test func iCloudDriveWinsOverTheVolume() {
        let bar = items()
        #expect(pressed(iCloud.path, in: bar) == 2)
        #expect(pressed(iCloud.path + "/Documents/a", in: bar) == 2)
        #expect(pressed(iCloud.path + " copy", in: bar) == 0)
        #expect(pressed("/Users/jan/Library/Mobile Documents", in: bar) == 0)
        // Without the iCloud Drive button the volume is pressed.
        #expect(pressed(iCloud.path, in: items(VolumeBarSettings(showICloud: false))) == 0)
    }

    @Test func homeOnlyWhenExactlyHome() {
        let bar = items(VolumeBarSettings(showHome: true))
        #expect(pressed("/Users/jan", in: bar) == 2)
        #expect(pressed("/Users/jan/", in: bar) == 2)
        #expect(pressed("/Users/jan/Documents", in: bar) == 0)
        #expect(pressed("/Users/jan", in: items()) == 0)
    }

    @Test func otherwiseTheVolume() {
        let bar = items()
        #expect(pressed("/Volumes/Stick/photos", root: "/Volumes/Stick", in: bar) == 1)
        #expect(pressed("/tmp", in: bar) == 0)
        #expect(pressed("/Volumes/Gone/x", root: "/Volumes/Gone", in: bar) == nil)
        #expect(pressed("/tmp", root: nil, in: bar) == nil)
    }
}

/// The volume bar's texts have Czech translations in the String Catalog.
@Suite struct VolumeBarTextsTests {
    private let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func newTextsAreTranslated() throws {
        let data = try Data(contentsOf: root.appending(path: "Resources/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])
        for key in ["Home", "iCloud Drive", "Network", "Servers", "Connect to Server…", "Open in Other Panel",
                    "Copy Address", "Disconnect", "Disconnect %@", "Volume bar shows:", "Server connections"] {
            let entry = strings[key] as? [String: Any]
            let czech = (entry?["localizations"] as? [String: Any])?["cs"] as? [String: Any]
            let value = (czech?["stringUnit"] as? [String: Any])?["value"] as? String
            #expect(value?.isEmpty == false, "\(key): missing Czech translation")
        }
    }
}
