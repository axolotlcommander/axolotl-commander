// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Darwin
import Foundation

/// Low-level placement of single items. Content is always written under a
/// temporary name `.~icmd-<uuid>` next to the target and renamed over it only
/// after the write completed; on failure or cancel the temp is removed and the
/// target is left untouched.
enum FileCopy {
    static let tempPrefix = ".~icmd-"

    enum Outcome: Equatable {
        case placed
        /// A target appeared after the conflict check (exclusive placement failed).
        case targetAppeared
    }

    final class ProgressContext {
        let onBytes: (Int64) -> Void
        var cancelled = false

        init(onBytes: @escaping (Int64) -> Void) {
            self.onBytes = onBytes
        }
    }

    static func tempPath(nextTo target: String) -> String {
        FSPath.join(FSPath.parent(target), tempPrefix + UUID().uuidString)
    }

    /// Regular file via copyfile(3). `onBytes` gets the bytes copied so far
    /// (clone copies may report nothing).
    static func copyFile(
        from source: String,
        to target: String,
        replace: Bool,
        clone: Bool,
        onBytes: @escaping (Int64) -> Void
    ) throws -> Outcome {
        if Task.isCancelled { throw OperationError.cancelled }
        let temp = tempPath(nextTo: target)
        let context = ProgressContext(onBytes: onBytes)
        guard let state = copyfile_state_alloc() else { throw OperationError.io("copyfile_state_alloc failed") }
        defer { copyfile_state_free(state) }

        let callback: copyfile_callback_t = { what, stage, state, _, _, ctx in
            guard let ctx else { return COPYFILE_CONTINUE }
            let context = Unmanaged<FileCopy.ProgressContext>.fromOpaque(ctx).takeUnretainedValue()
            if Task.isCancelled {
                context.cancelled = true
                return COPYFILE_QUIT
            }
            if what == COPYFILE_COPY_DATA && stage == COPYFILE_PROGRESS {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                context.onBytes(Int64(copied))
                if Task.isCancelled {
                    context.cancelled = true
                    return COPYFILE_QUIT
                }
            }
            return COPYFILE_CONTINUE
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(context).toOpaque())

        var flags = COPYFILE_ALL | COPYFILE_NOFOLLOW_SRC | COPYFILE_EXCL
        if clone { flags |= COPYFILE_CLONE }
        let rc = withExtendedLifetime(context) { copyfile(source, temp, state, copyfile_flags_t(flags)) }
        let err = errno
        if rc != 0 {
            unlink(temp)
            if context.cancelled || err == ECANCELED || Task.isCancelled { throw OperationError.cancelled }
            throw OperationError.io(FSPath.errorText(err, "Cannot copy", source))
        }
        return try place(temp: temp, at: target, replace: replace)
    }

    /// Symlink copied as a symlink (never followed).
    static func copySymlink(from source: String, to target: String, replace: Bool) throws -> Outcome {
        if Task.isCancelled { throw OperationError.cancelled }
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let length = readlink(source, &buffer, buffer.count - 1)
        if length < 0 { throw OperationError.io(FSPath.errorText(errno, "Cannot read link", source)) }
        buffer[length] = 0
        let temp = tempPath(nextTo: target)
        if symlink(buffer, temp) != 0 {
            throw OperationError.io(FSPath.errorText(errno, "Cannot create link", target))
        }
        // Best effort: carry over link metadata.
        copyfile(source, temp, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW))
        return try place(temp: temp, at: target, replace: replace)
    }

    /// Finishes a write: temp → target. Cancel after the write still leaves the target untouched.
    private static func place(temp: String, at target: String, replace: Bool) throws -> Outcome {
        if Task.isCancelled {
            unlink(temp)
            throw OperationError.cancelled
        }
        let rc = replace ? rename(temp, target) : renamex_np(temp, target, UInt32(RENAME_EXCL))
        if rc == 0 { return .placed }
        let err = errno
        unlink(temp)
        if err == EEXIST && !replace { return .targetAppeared }
        throw OperationError.io(FSPath.errorText(err, "Cannot place", target))
    }

    /// Creates a directory owned-writable so its content can be written; the
    /// source's mode is applied afterwards by `copyDirectoryMetadata`.
    static func makeDirectory(_ path: String) throws -> Outcome {
        if mkdir(path, 0o700) == 0 { return .placed }
        let err = errno
        if err == EEXIST { return .targetAppeared }
        throw OperationError.io(FSPath.errorText(err, "Cannot create folder", path))
    }

    /// Best effort: mode, dates, ACL and xattrs of a copied directory.
    static func copyDirectoryMetadata(from source: String, to target: String) {
        copyfile(source, target, nil, copyfile_flags_t(COPYFILE_METADATA | COPYFILE_NOFOLLOW_SRC))
    }
}
