// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing

@testable import CommanderCore

private func vol(
    _ path: String, name: String? = nil, removable: Bool = false, network: Bool = false, internal isInternal: Bool = true,
    ejectable: Bool = false, root: Bool = false, disk: String? = nil
) -> VolumeInfo {
    VolumeInfo(
        url: URL(fileURLWithPath: path), name: name ?? (path as NSString).lastPathComponent, isRemovable: removable,
        isNetwork: network, isInternal: isInternal, isEjectable: ejectable, isRootFileSystem: root, wholeDisk: disk)
}

@Suite struct EjectabilityTests {
    @Test func startupDiskIsNeverEjectable() {
        #expect(!Ejectability.canEject(vol("/", internal: false, ejectable: true, root: true)))
        #expect(!Ejectability.canEject(vol("/", internal: false)))
    }

    @Test func internalNonEjectableIsNot() {
        #expect(!Ejectability.canEject(vol("/Volumes/Data")))
    }

    @Test func removableExternalEjectableNetwork() {
        #expect(Ejectability.canEject(vol("/Volumes/A", removable: true)))
        #expect(Ejectability.canEject(vol("/Volumes/B", internal: false)))
        #expect(Ejectability.canEject(vol("/Volumes/C", ejectable: true)))
        #expect(Ejectability.canEject(vol("/Volumes/D", network: true)))
    }

    @Test func siblingsShareWholeDisk() {
        let a = vol("/Volumes/A", disk: "disk4")
        let b = vol("/Volumes/B", disk: "disk4")
        let c = vol("/Volumes/C", disk: "disk5")
        #expect(Ejectability.otherVolumes(onDiskOf: a, in: [a, b, c]) == [b])
    }

    @Test func unknownDiskHasNoSiblings() {
        let a = vol("/Volumes/A")
        let b = vol("/Volumes/B")
        #expect(Ejectability.otherVolumes(onDiskOf: a, in: [a, b]).isEmpty)
    }
}

@Suite struct EjectTargetTests {
    let boot = vol("/", name: "Macintosh HD", root: true)
    let usb = vol("/Volumes/USB", removable: true, internal: false, disk: "disk4")
    let data = vol("/Volumes/Data")
    let rootOf: (URL) -> URL = { url in
        let parts = url.standardizedFileURL.pathComponents
        if parts.count >= 3, parts[1] == "Volumes" { return URL(fileURLWithPath: "/Volumes/" + parts[2]) }
        return URL(fileURLWithPath: "/")
    }

    func resolve(_ path: String, archive: String? = nil, network: Bool = false, remote: RemoteEndpoint? = nil) -> EjectTarget? {
        EjectTarget.resolve(
            location: URL(fileURLWithPath: path), archiveFile: archive.map { URL(fileURLWithPath: $0) }, isNetwork: network,
            remoteEndpoint: remote, volumes: [boot, usb, data], rootOf: rootOf)
    }

    @Test func localVolume() { #expect(resolve("/Volumes/USB/photos") == .volume(usb)) }
    @Test func archiveOnVolume() { #expect(resolve("/Users/me", archive: "/Volumes/USB/a.zip") == .volume(usb)) }
    @Test func server() {
        let e = RemoteEndpoint(proto: .sftp, host: "example.com")
        #expect(resolve("/Volumes/USB", remote: e) == .server(e))
    }
    @Test func networkIsNil() { #expect(resolve("/Volumes/USB", network: true) == nil) }
    @Test func startupDiskIsNil() { #expect(resolve("/Users/me") == nil) }
    @Test func internalVolumeIsNil() { #expect(resolve("/Volumes/Data/x") == nil) }

    @Test func titles() {
        #expect(EjectTarget.title(for: .volume(vol("/Volumes/Q", name: "He said \"hi\" 🎉", removable: true))).contains("He said \"hi\" 🎉"))
        #expect(EjectTarget.title(for: .server(RemoteEndpoint(proto: .sftp, host: "h", user: "u"))).contains("u@h"))
        #expect(!EjectTarget.title(for: nil).isEmpty)
    }
}

@Suite struct VolumeUseTests {
    let root = URL(fileURLWithPath: "/Volumes/A")

    @Test func prefixRules() {
        #expect(VolumeUse.isOnVolume(URL(fileURLWithPath: "/Volumes/A"), root: root))
        #expect(VolumeUse.isOnVolume(URL(fileURLWithPath: "/Volumes/A/x/../y"), root: root))
        #expect(!VolumeUse.isOnVolume(URL(fileURLWithPath: "/Volumes/AB/x"), root: root))
        #expect(!VolumeUse.isOnVolume(URL(fileURLWithPath: "/Users/me"), root: root))
        #expect(!VolumeUse.isOnVolume(URL(fileURLWithPath: "/Users/me"), root: URL(fileURLWithPath: "/")))
    }

    @Test func blockingReturnsFirstUser() {
        let u1 = VolumeUser(title: "one", urls: [URL(fileURLWithPath: "/Users/me")])
        let u2 = VolumeUser(title: "two", urls: [URL(fileURLWithPath: "/Users/me"), URL(fileURLWithPath: "/Volumes/A/f")])
        let u3 = VolumeUser(title: "three", urls: [URL(fileURLWithPath: "/Volumes/A")])
        #expect(VolumeUse.blocking(root, users: [u1, u2, u3]) == u2)
        #expect(VolumeUse.blocking(root, users: [u1]) == nil)
    }
}

@Suite struct TabRedirectTests {
    @Test func redirectsInactiveMatchingTabsOnly() {
        let a = URL(fileURLWithPath: "/Volumes/A/x")
        let home = URL(fileURLWithPath: "/Users/me")
        let hist = PanelState.Place(url: a)
        var list = TabList(PanelState(location: a, cursorName: "c", back: [hist], selectedNames: ["s"]))
        list.open(PanelState(location: URL(fileURLWithPath: "/tmp")), activate: false)
        list.open(PanelState(location: a, cursorName: "d", selectedNames: ["t"]), activate: false)
        let n = list.redirect(where: { $0.path.hasPrefix("/Volumes/A") }, to: home)
        #expect(n == 1)
        #expect(list.tabs[0].location == a)
        #expect(list.tabs[0].cursorName == "c")
        #expect(list.tabs[1].location == home)
        #expect(list.tabs[2].location.path == "/tmp")
        #expect(list.tabs[1].cursorName == nil)
        #expect(list.tabs[1].selectedNames.isEmpty)
    }

    @Test func keepsHistory() {
        let a = URL(fileURLWithPath: "/Volumes/A")
        let hist = PanelState.Place(url: a)
        var list = TabList(PanelState(location: URL(fileURLWithPath: "/tmp")))
        list.open(PanelState(location: a, back: [hist]), activate: false)
        list.redirect(where: { _ in true }, to: URL(fileURLWithPath: "/"))
        #expect(list.tabs[1].back == [hist])
    }
}
