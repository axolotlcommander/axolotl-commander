// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

struct NetworkPlacesTests {
    private let nas = NetworkPlaces.Service(name: "DISKSTATION", kind: .smb)

    @Test func location() {
        #expect(NetworkPlaces.isNetwork(NetworkPlaces.location))
        #expect(!NetworkPlaces.isNetwork(URL(filePath: "/Volumes")))
        #expect(!NetworkPlaces.isNetwork(URL(string: "sftp://host/")!))
    }

    @Test func rowsShowTheProtocolAsExtension() {
        let volumes = [
            VolumeInfo(url: URL(filePath: "/Volumes/share", directoryHint: .isDirectory), name: "share", isNetwork: true),
            VolumeInfo(url: URL(filePath: "/Volumes/USB", directoryHint: .isDirectory), name: "USB", isRemovable: true),
        ]
        let services = [nas, nas, NetworkPlaces.Service(name: "DISKSTATION", kind: .afp),
                        NetworkPlaces.Service(name: "My.Pi", kind: .sftp)]
        let rows = NetworkPlaces.items(services: services, volumes: volumes)
        #expect(rows.map(\.name) == ["DISKSTATION.smb", "DISKSTATION.afp", "My.Pi.sftp", "share"])
        #expect(rows.map(\.fileExtension) == ["smb", "afp", "sftp", ""])
        #expect(rows.map(\.isDirectory) == [false, false, false, true])
        #expect(rows[3].url.path == "/Volumes/share")
    }

    @Test func serviceRoundTrip() {
        for service in [nas, NetworkPlaces.Service(name: "Pi / lab #2", kind: .sftp),
                        NetworkPlaces.Service(name: "Office", kind: .afp, domain: "example.com.")] {
            #expect(NetworkPlaces.isNetwork(service.url))
            #expect(NetworkPlaces.service(of: service.url) == service)
        }
        #expect(NetworkPlaces.service(of: NetworkPlaces.location) == nil)
        #expect(NetworkPlaces.service(of: URL(filePath: "/Volumes/share")) == nil)
        #expect(NetworkPlaces.Service.Kind(type: "_smb._tcp.") == .smb)
        #expect(NetworkPlaces.Service.Kind(type: "_http._tcp") == nil)
    }

    @Test func networkPressesTheNetworkButton() {
        let disk = VolumeInfo(url: URL(filePath: "/"), name: "Macintosh HD")
        let items = VolumeBarModel.items(volumes: [disk], home: URL(filePath: "/Users/t"), iCloud: nil,
                                         servers: [], settings: VolumeBarSettings())
        #expect(VolumeBarModel.pressed(local: NetworkPlaces.location, remote: nil, volumeRoot: nil, items: items,
                                       network: true) == items.firstIndex(of: .network))
        #expect(VolumeBarModel.pressed(local: URL(filePath: "/tmp"), remote: nil, volumeRoot: URL(filePath: "/"),
                                       items: items) == 0)
    }

    @MainActor @Test func networkPanelHasNoParentRowAndGoesBack() async throws {
        // Only reads: the system temporary folder is listed, nothing is written.
        let root = FileManager.default.temporaryDirectory
        let model = PanelModel(location: root)
        try await model.go(to: root)
        try await model.go(to: NetworkPlaces.location)
        #expect(model.isNetwork)
        #expect(model.items.allSatisfy { !$0.isParent })
        try await model.goParent()
        #expect(model.location.standardizedFileURL == root.standardizedFileURL)
    }
}
