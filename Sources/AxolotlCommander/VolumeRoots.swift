// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore
import UniformTypeIdentifiers

/// The volumes that folders are on, read in the background: asking a disk that is asleep or busy
/// with a backup, or a server that stopped answering, would stop the main thread. Until the read
/// finishes, the mount point that the path lies under stands in (`VolumeList.root(of:in:)`); it
/// differs only for a path through a symbolic link into another volume.
final class VolumeRoots {
    static let shared = VolumeRoots()

    /// Posted on the main queue when a read gave another volume than the stand-in.
    static let didResolveNotification = Notification.Name("VolumeRoots.didResolve")

    private var known: [URL: URL] = [:]
    private var pending: Set<URL> = []
    /// Counts the volume list changes, so a read started before one is not kept.
    private var generation = 0
    private let queue = DispatchQueue(label: "VolumeRoots", qos: .userInitiated)
    private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: VolumeList.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.forget() }
        }
    }

    /// The mount point of the volume holding `url`.
    func root(of url: URL) -> URL { lookup(url).root }

    /// The mount point of the volume holding `url`, and whether it was read from the disk (false:
    /// the stand-in, read later).
    func lookup(_ url: URL) -> (root: URL, resolved: Bool) {
        let url = url.standardizedFileURL
        if let root = known[url] { return (root, true) }
        let guess = Self.normalized(VolumeList.root(of: url, in: VolumeList.shared.current))
        guard !pending.contains(url) else { return (guess, false) }
        pending.insert(url)
        let generation = generation
        queue.async {
            let root = Self.normalized(Volumes.root(of: url))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.resolved(url, root: root, guess: guess, generation: generation) }
            }
        }
        return (guess, false)
    }

    private func resolved(_ url: URL, root: URL, guess: URL, generation: Int) {
        guard generation == self.generation else { return }
        pending.remove(url)
        if known.count > 512 { known.removeAll() }
        known[url] = root
        if root != guess {
            NotificationCenter.default.post(name: Self.didResolveNotification, object: nil)
        }
    }

    /// One spelling of a mount point, so roots compare equal: a folder URL of the standardized path.
    private nonisolated static func normalized(_ url: URL) -> URL {
        URL(filePath: url.standardizedFileURL.path(percentEncoded: false), directoryHint: .isDirectory)
    }

    /// Mounting or unmounting changes which volume holds a path.
    private func forget() {
        generation += 1
        known.removeAll()
        pending.removeAll()
        NotificationCenter.default.post(name: Self.didResolveNotification, object: nil)
    }

    /// True for a path on the startup disk, whose items can be asked at once (it never sleeps).
    static func isOnStartupDisk(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return !path.hasPrefix("/Volumes/")
            && VolumeList.root(of: url, in: VolumeList.shared.current).path(percentEncoded: false) == "/"
    }
}

/// Finder's icons of the volumes, read in the background (asking a sleeping disk for its icon waits
/// for it). Until then a generic volume icon stands in.
final class VolumeIcons {
    static let shared = VolumeIcons()

    /// Posted on the main queue when an icon was read.
    static let didLoadNotification = Notification.Name("VolumeIcons.didLoad")

    private var icons: [String: NSImage] = [:]
    private var pending: Set<String> = []
    private let queue = DispatchQueue(label: "VolumeIcons", qos: .userInitiated)

    private var observer: (any NSObjectProtocol)?

    private struct Icon: @unchecked Sendable { let image: NSImage }

    private init() {
        // Another disk may be mounted at the same path.
        observer = NotificationCenter.default.addObserver(forName: VolumeList.didChangeNotification, object: nil,
                                                          queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.icons.removeAll() }
        }
    }

    /// A copy the caller may resize.
    func icon(for root: URL, network: Bool = false) -> NSImage {
        let path = root.path(percentEncoded: false)
        if path == "/" { return NSWorkspace.shared.icon(forFile: path) }
        if let icon = icons[path] { return icon.copy() as? NSImage ?? icon }
        if !pending.contains(path) {
            pending.insert(path)
            queue.async {
                let icon = Icon(image: NSWorkspace.shared.icon(forFile: path))
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self.pending.remove(path)
                        self.icons[path] = icon.image
                        NotificationCenter.default.post(name: Self.didLoadNotification, object: nil)
                    }
                }
            }
        }
        let generic = network ? NSImage(named: NSImage.networkName) ?? NSWorkspace.shared.icon(for: .volume)
            : NSWorkspace.shared.icon(for: .volume)
        return generic.copy() as? NSImage ?? generic
    }
}
