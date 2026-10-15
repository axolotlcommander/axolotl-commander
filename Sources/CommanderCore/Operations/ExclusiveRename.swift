// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Darwin

/// rename(2) that never replaces an existing item.
enum ExclusiveRename {
    /// Renames `from` to `to` unless `to` exists. Returns 0, or -1 with `errno` set (EEXIST when the
    /// target exists). Volumes without an exclusive rename (SMB shares, exFAT) answer ENOTSUP; there
    /// the target is checked first and a plain rename follows (a case-only rename of the same entry
    /// is not a conflict).
    static func rename(_ from: String, _ to: String,
                       exclusive: (String, String) -> Int32 = { renamex_np($0, $1, UInt32(RENAME_EXCL)) }) -> Int32 {
        if exclusive(from, to) == 0 { return 0 }
        let err = errno
        guard err == ENOTSUP || err == EINVAL else {
            errno = err
            return -1
        }
        var target = stat()
        if lstat(to, &target) == 0 {
            var source = stat()
            // The same entry under another spelling (a case-only rename) is not a conflict.
            guard FSPath.parent(from) == FSPath.parent(to),
                  FSPath.name(from).lowercased() == FSPath.name(to).lowercased(),
                  lstat(from, &source) == 0, source.st_dev == target.st_dev, source.st_ino == target.st_ino else {
                errno = EEXIST
                return -1
            }
        } else if errno != ENOENT {
            return -1
        }
        return Darwin.rename(from, to)
    }
}
