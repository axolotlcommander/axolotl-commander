// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation
import DiskArbitration

public struct VolumeInfo: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let isRemovable: Bool
    public let isNetwork: Bool
    public let isInternal: Bool
    public let totalCapacity: Int64?
    public let availableCapacity: Int64?
    /// The system's "ejectable" flag.
    public let isEjectable: Bool
    /// The startup disk.
    public let isRootFileSystem: Bool
    /// BSD name of the physical disk (e.g. `disk4`); nil for network volumes or when unknown.
    public let wholeDisk: String?

    public var id: URL { url }

    public init(
        url: URL, name: String, isRemovable: Bool = false, isNetwork: Bool = false,
        isInternal: Bool = true, totalCapacity: Int64? = nil, availableCapacity: Int64? = nil,
        isEjectable: Bool = false, isRootFileSystem: Bool = false, wholeDisk: String? = nil
    ) {
        self.url = url
        self.name = name
        self.isRemovable = isRemovable
        self.isNetwork = isNetwork
        self.isInternal = isInternal
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
        self.isEjectable = isEjectable
        self.isRootFileSystem = isRootFileSystem
        self.wholeDisk = wholeDisk
    }
}

public enum Volumes {
    /// Visible mounted volumes, boot volume first.
    public static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsRemovableKey, .volumeIsLocalKey, .volumeIsInternalKey,
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsEjectableKey, .volumeIsRootFileSystemKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        let session = DASessionCreate(kCFAllocatorDefault)
        var infos = urls.map { url -> VolumeInfo in
            let v = try? url.resourceValues(forKeys: Set(keys))
            return VolumeInfo(
                url: url,
                name: v?.volumeName ?? FileManager.default.displayName(atPath: url.path),
                isRemovable: v?.volumeIsRemovable ?? false,
                isNetwork: !(v?.volumeIsLocal ?? true),
                isInternal: v?.volumeIsInternal ?? true,
                totalCapacity: v?.volumeTotalCapacity.map(Int64.init),
                availableCapacity: v?.volumeAvailableCapacityForImportantUsage,
                isEjectable: v?.volumeIsEjectable ?? false,
                isRootFileSystem: v?.volumeIsRootFileSystem ?? false,
                wholeDisk: (v?.volumeIsLocal ?? true) ? wholeDiskName(of: url, session: session) : nil
            )
        }
        if let boot = infos.firstIndex(where: { $0.url.path == "/" }), boot != 0 {
            infos.insert(infos.remove(at: boot), at: 0)
        }
        return infos
    }

    /// BSD name of the physical disk under the volume at `url`, nil when it has none.
    private static func wholeDiskName(of url: URL, session: DASession?) -> String? {
        guard let session, let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
            let whole = DADiskCopyWholeDisk(disk), let name = DADiskGetBSDName(whole)
        else { return nil }
        return String(cString: name)
    }

    /// Mount point of the volume containing `url` ("/" if it cannot be determined).
    public static func root(of url: URL) -> URL {
        let values = try? url.nearestExistingAncestor.resourceValues(forKeys: [.volumeURLKey])
        return values?.volume ?? URL(fileURLWithPath: "/")
    }
}

extension URL {
    /// `self`, or the closest ancestor that exists on disk.
    var nearestExistingAncestor: URL {
        var url = self
        while url.path != "/", !FileManager.default.fileExists(atPath: url.path) {
            url = url.deletingLastPathComponent()
        }
        return url
    }
}
