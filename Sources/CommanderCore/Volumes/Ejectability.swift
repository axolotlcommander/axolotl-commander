// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation

/// Which volumes the user may eject, and which volumes share a physical disk.
public enum Ejectability {
    /// False for the startup disk; true for ejectable, removable, external and network volumes.
    public static func canEject(_ v: VolumeInfo) -> Bool {
        !v.isRootFileSystem && v.url.path != "/" && (v.isEjectable || v.isRemovable || !v.isInternal || v.isNetwork)
    }

    /// Other volumes on the same physical disk as `v` (never any when the disk is unknown).
    public static func otherVolumes(onDiskOf v: VolumeInfo, in volumes: [VolumeInfo]) -> [VolumeInfo] {
        guard let disk = v.wholeDisk else { return [] }
        return volumes.filter { $0.wholeDisk == disk && $0.url != v.url }
    }
}
