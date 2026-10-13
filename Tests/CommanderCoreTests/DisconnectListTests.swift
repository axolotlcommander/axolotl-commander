// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing

@testable import CommanderCore

@Suite struct DisconnectListTests {
    let e1 = RemoteEndpoint(proto: .sftp, host: "a.example")
    let e2 = RemoteEndpoint(proto: .ftp, host: "b.example")
    let net = VolumeInfo(url: URL(fileURLWithPath: "/Volumes/nas"), name: "nas", isNetwork: true)
    let usb = VolumeInfo(url: URL(fileURLWithPath: "/Volumes/USB"), name: "USB", isRemovable: true, isInternal: false)
    let boot = VolumeInfo(url: URL(fileURLWithPath: "/"), name: "HD", isRootFileSystem: true)
    let data = VolumeInfo(url: URL(fileURLWithPath: "/Volumes/Data"), name: "Data")

    @Test func sectionsAreOrderedAndFiltered() {
        let s = DisconnectList.sections(servers: [e1, e2], volumes: [boot, usb, data, net])
        #expect(s.map(\.title) == [.servers, .networkVolumes, .disks])
        #expect(s[0].items.map(\.name) == ["a.example", "b.example"])
        #expect(s[1].items.map(\.name) == ["nas"])
        #expect(s[2].items.map(\.name) == ["USB"])
    }

    @Test func emptySectionsAreLeftOut() {
        #expect(DisconnectList.sections(servers: [], volumes: [boot, data]).isEmpty)
        #expect(DisconnectList.sections(servers: [e1], volumes: [usb]).map(\.title) == [.servers, .disks])
    }

    @Test func preCheck() {
        let s = DisconnectList.sections(servers: [e1], volumes: [usb])
        #expect(DisconnectList.preChecked(.server(e1), in: s) == s[0].items[0].id)
        #expect(DisconnectList.preChecked(.volume(usb), in: s) == s[1].items[0].id)
        #expect(DisconnectList.preChecked(.server(e2), in: s) == nil)
        #expect(DisconnectList.preChecked(nil, in: s) == nil)
    }

    @Test func idsAreUnique() {
        let s = DisconnectList.sections(servers: [e1, e2], volumes: [usb, net])
        let ids = s.flatMap(\.items).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func confirmTitle() {
        let s = DisconnectList.sections(servers: [e1], volumes: [usb])
        let server = s[0].items[0], disk = s[1].items[0]
        #expect(DisconnectList.confirmTitle(checked: [server]) == String(localized: "Disconnect"))
        #expect(DisconnectList.confirmTitle(checked: [server, disk]) == String(localized: "Eject"))
        #expect(DisconnectList.confirmTitle(checked: [disk]) == String(localized: "Eject"))
    }

    @Test func enabled() {
        #expect(DisconnectList.isEnabled(servers: [e1], volumes: []))
        #expect(DisconnectList.isEnabled(servers: [], volumes: [usb]))
        #expect(!DisconnectList.isEnabled(servers: [], volumes: [boot, data]))
    }
}
