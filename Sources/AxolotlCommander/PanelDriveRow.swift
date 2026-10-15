// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// The drive row and the free space of the panel's disk (spec 020).
extension PanelViewController {
    func configureDriveRow() {
        driveRow.onOpenMenu = { [weak self] anchor in
            guard let self else { return }
            router?.activate(side)
            showVolumeMenu(from: anchor)
        }
        for label in [driveRow.freeSpace, volumeBar.freeSpace, statusSpace] {
            label.onClick = { [weak self] in
                guard let self, let folder = diskSpace.folder else { return }
                VolumeInfoSheet.show(for: folder, in: view.window)
            }
        }
        volumeBar.onPressedChange = { [weak self] in self?.updateDriveRow() }
        diskSpace.onChange = { [weak self] space in
            guard let self else { return }
            for label in [driveRow.freeSpace, volumeBar.freeSpace, statusSpace] { label.space = space }
            volumeBar.needsLayout = true
        }
        // Other apps and the other panel change the disk too.
        diskSpace.start(interval: 3) { [weak self] in
            guard let self, let window = view.window, window.occlusionState.contains(.visible) else { return false }
            return DriveRowSettings.saved.freeSpacePlace != .hidden && !view.isHiddenOrHasHiddenAncestor
        }
        NotificationCenter.default.addObserver(self, selector: #selector(driveRowSettingsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
        applyDriveRowSettings()
    }

    /// The folder whose disk the free space describes: the folder shown, the folder holding an
    /// archive, the root of a flat listing; nil for a server and the Network folder.
    var spaceFolder: URL? {
        if model.remote != nil || model.isNetwork { return nil }
        return model.archive?.archive.deletingLastPathComponent() ?? model.location
    }

    /// The combo shows what the volume bar shows pressed, otherwise the place itself.
    func updateDriveRow() {
        diskSpace.watch(spaceFolder)
        switch volumeBar.pressedItem {
        case .volume(let volume)?:
            driveRow.show(title: volume.name, icon: VolumeIcons.shared.icon(for: volume.url, network: volume.isNetwork))
        case .home?:
            driveRow.show(title: String(localized: "Home"), icon: Self.symbol("house"))
        case .iCloud?:
            driveRow.show(title: String(localized: "iCloud Drive"), icon: Self.symbol("icloud"))
        case .network?:
            driveRow.show(title: String(localized: "Network"), icon: Self.symbol("network"))
        case .server(_, let label)?:
            driveRow.show(title: label, icon: Self.symbol("network"))
        case nil:
            if let remote = model.remote {
                driveRow.show(title: ServerConnectionsUI.shared.label(for: remote.endpoint), icon: Self.symbol("network"))
            } else if model.isNetwork {
                driveRow.show(title: String(localized: "Network"), icon: Self.symbol("network"))
            } else {
                // Nothing here asks the disk: this runs on every cursor move.
                let root = VolumeRoots.shared.root(of: spaceFolder ?? model.location)
                let volume = VolumeList.shared.current.first { $0.url.standardizedFileURL == root.standardizedFileURL }
                let name = volume?.name ?? (root.path(percentEncoded: false) == "/"
                    ? FileManager.default.displayName(atPath: "/") : root.lastPathComponent)
                driveRow.show(title: name, icon: VolumeIcons.shared.icon(for: root, network: volume?.isNetwork ?? false))
            }
        }
    }

    @objc private func driveRowSettingsChanged() { applyDriveRowSettings() }

    private func applyDriveRowSettings() {
        let settings = DriveRowSettings.saved
        if volumeBar.isHidden == settings.showVolumeBar { volumeBar.isHidden = !settings.showVolumeBar }
        if driveRow.isHidden == settings.showRow { driveRow.isHidden = !settings.showRow }
        let place = settings.freeSpacePlace
        volumeBar.showsFreeSpace = place == .volumeBar
        if statusSpace.isHidden == (place == .statusLine) { statusSpace.isHidden = place != .statusLine }
    }

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .regular))
    }
}

extension DriveRowSettings {
    static var saved: DriveRowSettings { DriveRowSettings { UserDefaults.standard.object(forKey: $0) } }
}
