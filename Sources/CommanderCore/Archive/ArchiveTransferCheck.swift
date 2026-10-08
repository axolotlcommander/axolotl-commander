// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Refuses copies and moves into an archive that would go into themselves. Archives are
/// compared by file identity (device + inode), so the same archive reached through a symlink,
/// a hard link or a path in another letter case is recognized.
public enum ArchiveTransferCheck {
    /// Members `names` of the folder `source` (nil = files on disk) into the folder `target`.
    /// Within the same archive, a member may not go to itself or below itself.
    public static func validate(source: ArchivePath?, names: [String], target: ArchivePath) throws(OperationError) {
        guard let source else { return }
        let sourceID = FileIdentity.of(source.archive)
        let targetID = FileIdentity.of(target.archive)
        guard let sourceID, let targetID else {
            // Both exist (the panels show them), so a missing identity means "can't tell".
            throw .identityUnknown(targetID == nil ? target.archive : source.archive)
        }
        guard sourceID == targetID else { return }
        for name in names {
            let member = source.member(name)
            if target.inner == member || target.inner.hasPrefix(member + "/") {
                throw .intoItself(URL(filePath: member))
            }
        }
    }

    /// Packing `sources` into the archive file `archive` (new or existing): refused when the
    /// archive is one of the sources, or lies inside one of the source folders.
    public static func validatePack(archive: URL, sources: [URL]) throws(OperationError) {
        let archive = archive.standardizedFileURL
        let archiveID = FileIdentity.of(archive)
        let ancestors = TransferPlanner.ancestorIdentities(of: archive.deletingLastPathComponent().path)
        guard !ancestors.unknown else { throw .identityUnknown(archive) }
        for source in sources {
            guard case .exists(let st) = FileProbe.probe(source.standardizedFileURL.path, followingLinks: false),
                  let id = st.identity
            else { throw .identityUnknown(source) }
            if let archiveID, id == archiveID { throw .intoItself(source) }
            if st.isDirectory, ancestors.ids.contains(id) { throw .intoItself(source) }
        }
    }
}
