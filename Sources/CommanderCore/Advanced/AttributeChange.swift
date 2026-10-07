public import Foundation
import Darwin

/// Checkbox state summarised over several items.
public enum TriState: Sendable, Hashable {
    case on, off, mixed

    /// `.off` when no item has it (also for zero items), `.on` when all do, else `.mixed`.
    static func of(_ count: Int, of total: Int) -> TriState {
        count == 0 ? .off : count == total ? .on : .mixed
    }
}

/// Attributes of several selected items, for the "Change Attributes" sheet.
public struct AttributeSummary: Sendable, Equatable {
    public var count: Int
    /// Keys: each of the 12 bits 0o4000…0o0001. Symlinks are not counted (their mode is not
    /// changed, see `AttributeEditor`); with no other items every bit is `.off`.
    public var modeBits: [Int: TriState]
    /// UF_IMMUTABLE (`uchg`).
    public var locked: TriState
    /// UF_HIDDEN (a leading dot in the name is not considered).
    public var hidden: TriState
    /// Finder tag name → number of items having it (symlinks have no tags here).
    public var tags: [String: Int]
    /// Value of the first item when all items agree to the second, else nil.
    public var modified, created, accessed: Date?
    /// Some item is a real folder (not a symlink to one).
    public var containsFolders: Bool

    /// The 12 permission bits, highest first.
    public static let modeBitValues: [Int] = (0..<12).reversed().map { 1 << $0 }

    /// Reads with lstat semantics; never follows the item itself. Throws on the first unreadable item.
    public static func read(_ urls: [URL]) throws -> AttributeSummary {
        var bitCounts = [Int: Int]()
        var modeItems = 0, lockedCount = 0, hiddenCount = 0
        var tags = [String: Int]()
        var containsFolders = false
        var dates: [[Date]] = [[], [], []]

        for url in urls {
            let st = try AttributeIO.lstat(url.path)
            let type = st.st_mode & S_IFMT
            if type == S_IFDIR { containsFolders = true }
            if st.st_flags & UInt32(UF_IMMUTABLE) != 0 { lockedCount += 1 }
            if st.st_flags & UInt32(UF_HIDDEN) != 0 { hiddenCount += 1 }
            if type != S_IFLNK {
                modeItems += 1
                let mode = Int(st.st_mode & 0o7777)
                for bit in modeBitValues where mode & bit != 0 { bitCounts[bit, default: 0] += 1 }
                for tag in Set(AttributeIO.tags(url.path)) { tags[tag, default: 0] += 1 }
            }
            dates[0].append(AttributeIO.date(st.st_mtimespec))
            dates[1].append(AttributeIO.date(st.st_birthtimespec))
            dates[2].append(AttributeIO.date(st.st_atimespec))
        }

        func agreed(_ values: [Date]) -> Date? {
            guard let first = values.first else { return nil }
            let second = first.timeIntervalSince1970.rounded(.down)
            return values.allSatisfy { $0.timeIntervalSince1970.rounded(.down) == second } ? first : nil
        }

        return AttributeSummary(
            count: urls.count,
            modeBits: Dictionary(uniqueKeysWithValues: modeBitValues.map {
                ($0, TriState.of(bitCounts[$0] ?? 0, of: modeItems))
            }),
            locked: .of(lockedCount, of: urls.count),
            hidden: .of(hiddenCount, of: urls.count),
            tags: tags,
            modified: agreed(dates[0]),
            created: agreed(dates[1]),
            accessed: agreed(dates[2]),
            containsFolders: containsFolders)
    }
}

/// A requested change of attributes; nil / empty fields leave the attribute as it is.
public struct AttributeChange: Sendable, Equatable {
    /// Bits to set / clear; bits in neither stay. A bit in both ends up set.
    public var setMode: Int = 0, clearMode: Int = 0
    public var locked: Bool? = nil, hidden: Bool? = nil
    /// Tags to append / remove (a tag in both is removed).
    public var addTags: [String] = [], removeTags: [String] = []
    public var modified: Date? = nil, created: Date? = nil, accessed: Date? = nil
    /// Also everything inside selected folders (never descends into symlinked folders).
    public var recursive = false
    /// Which nested items (when recursive) get the change; the selected items themselves always do.
    /// Anything that is not a real folder (including symlinks) counts as a file.
    public var includeFiles = true, includeFolders = true

    public init() {}

    public var isEmpty: Bool {
        setMode & 0o7777 == 0 && clearMode & 0o7777 == 0 && locked == nil && hidden == nil
            && addTags.isEmpty && removeTags.isEmpty
            && modified == nil && created == nil && accessed == nil
    }
}

/// Outcome of `AttributeEditor.apply`.
public struct AttributeReport: Sendable, Equatable {
    /// Items where at least one change was actually applied.
    public var changed: Int
    public var failures: [Failure]

    public struct Failure: Sendable, Equatable {
        public var url: URL
        /// "name: strerror".
        public var message: String
    }
}

/// Applies an `AttributeChange` to items (and optionally their contents).
///
/// Never follows symlinks: flags and dates are changed on the link itself; the mode of a symlink
/// is skipped (macOS ignores link permissions for access) and so are its tags. A locked (`uchg`)
/// item is unlocked for the other changes and then gets its final lock state
/// (`change.locked ?? wasLocked`). Only UF_IMMUTABLE and UF_HIDDEN are ever modified; all other
/// `st_flags` bits are preserved. Per-item errors are collected and processing continues.
public enum AttributeEditor {
    /// `progress` gets the number of processed items so far.
    public static func apply(_ change: AttributeChange, to urls: [URL],
                             progress: @Sendable (Int) -> Void = { _ in }) async throws -> AttributeReport {
        var report = AttributeReport(changed: 0, failures: [])
        var processed = 0
        try forEachTarget(urls, change: change, failure: { url, message in
            report.failures.append(.init(url: url, message: message))
        }, body: { url in
            do {
                if try applyItem(change, to: url) { report.changed += 1 }
            } catch let error as ItemError {
                if error.applied { report.changed += 1 }
                report.failures.append(.init(url: url, message: error.message))
            }
            processed += 1
            progress(processed)
        })
        return report
    }

    /// Visits the items that get the change, post-order (a folder after its contents), checking
    /// for cancellation before each item. Enumeration errors go to `failure`.
    static func forEachTarget(_ urls: [URL], change: AttributeChange,
                              failure: (URL, String) -> Void,
                              body: (URL) throws -> Void) throws {
        func visit(_ url: URL, selected: Bool) throws {
            try Task.checkCancellation()
            var st = stat()
            guard Darwin.lstat(url.path, &st) == 0 else {
                failure(url, AttributeIO.message(url, errno))
                return
            }
            let isDirectory = st.st_mode & S_IFMT == S_IFDIR
            if isDirectory && change.recursive {
                do {
                    let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
                    for name in names.sorted() {
                        try visit(url.appendingPathComponent(name), selected: false)
                    }
                } catch let error as CancellationError {
                    throw error
                } catch {
                    failure(url, AttributeIO.message(url, error))
                }
            }
            if selected || (isDirectory ? change.includeFolders : change.includeFiles) {
                try Task.checkCancellation()
                try body(url)
            }
        }
        for url in urls { try visit(url, selected: true) }
    }

    struct ItemError: Error {
        var message: String
        /// Some change was applied before the error.
        var applied: Bool
    }

    /// Applies the change to one item; returns whether anything changed.
    static func applyItem(_ change: AttributeChange, to url: URL) throws(ItemError) -> Bool {
        let path = url.path
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else {
            throw ItemError(message: AttributeIO.message(url, errno), applied: false)
        }
        let isLink = st.st_mode & S_IFMT == S_IFLNK
        let immutable = UInt32(UF_IMMUTABLE), hiddenFlag = UInt32(UF_HIDDEN)
        let oldFlags = st.st_flags
        let wasLocked = oldFlags & immutable != 0

        let oldMode = Int(st.st_mode & 0o7777)
        let newMode = (oldMode & ~(change.clearMode & 0o7777)) | (change.setMode & 0o7777)
        let modeChange = !isLink && newMode != oldMode

        var newTags: [String]?
        if !isLink && !(change.addTags.isEmpty && change.removeTags.isEmpty) {
            let old = AttributeIO.tags(path)
            let remove = Set(change.removeTags)
            var tags = old.filter { !remove.contains($0) }
            for tag in change.addTags where !remove.contains(tag) && !tags.contains(tag) {
                tags.append(tag)
            }
            if Set(tags) != Set(old) { newTags = tags }
        }

        let datesChange = change.modified != nil || change.accessed != nil || change.created != nil

        var finalFlags = oldFlags
        if let hidden = change.hidden {
            finalFlags = hidden ? finalFlags | hiddenFlag : finalFlags & ~hiddenFlag
        }
        finalFlags = (change.locked ?? wasLocked) ? finalFlags | immutable : finalFlags & ~immutable

        var currentFlags = oldFlags
        var applied = false
        var firstError: String?
        func record(_ message: String) { if firstError == nil { firstError = message } }

        if wasLocked && (modeChange || newTags != nil || datesChange) {
            guard lchflags(path, oldFlags & ~immutable) == 0 else {
                throw ItemError(message: AttributeIO.message(url, errno), applied: false)
            }
            currentFlags = oldFlags & ~immutable
        }

        if modeChange {
            if lchmod(path, mode_t(newMode)) == 0 { applied = true } else { record(AttributeIO.message(url, errno)) }
        }
        if let newTags {
            do {
                try (URL(fileURLWithPath: path) as NSURL).setResourceValue(newTags, forKey: .tagNamesKey)
                applied = true
            } catch {
                record(AttributeIO.message(url, error))
            }
        }
        if change.modified != nil || change.accessed != nil {
            let omit = timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT))
            var times = [change.accessed.map(AttributeIO.timespec) ?? omit,
                         change.modified.map(AttributeIO.timespec) ?? omit]
            if utimensat(AT_FDCWD, path, &times, AT_SYMLINK_NOFOLLOW) == 0 {
                applied = true
            } else {
                record(AttributeIO.message(url, errno))
            }
        }
        if let created = change.created {
            // After utimensat: setting mtime before the creation date moves the latter back.
            if AttributeIO.setCreationDate(path, created) == 0 {
                applied = true
            } else {
                record(AttributeIO.message(url, errno))
            }
        }

        if finalFlags != currentFlags {
            if lchflags(path, finalFlags) == 0 {
                if finalFlags != oldFlags { applied = true }
            } else {
                record(AttributeIO.message(url, errno))
            }
        }

        if let firstError { throw ItemError(message: firstError, applied: applied) }
        return applied
    }
}

/// Low-level helpers shared by the summary and the editor.
enum AttributeIO {
    static func lstat(_ path: String) throws -> stat {
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return st
    }

    /// Finder tags of the item; a fresh URL avoids stale cached resource values.
    static func tags(_ path: String) -> [String] {
        (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
    }

    static func date(_ t: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1e9)
    }

    static func timespec(_ date: Date) -> Darwin.timespec {
        let t = date.timeIntervalSince1970
        let seconds = t.rounded(.down)
        let nanos = min(999_999_999, Int(((t - seconds) * 1e9).rounded()))
        return Darwin.timespec(tv_sec: Int(seconds), tv_nsec: nanos)
    }

    /// Sets ATTR_CMN_CRTIME without following a symlink; returns 0 or -1 (errno set).
    static func setCreationDate(_ path: String, _ date: Date) -> Int32 {
        var list = attrlist()
        list.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        list.commonattr = attrgroup_t(ATTR_CMN_CRTIME)
        var ts = timespec(date)
        return setattrlist(path, &list, &ts, MemoryLayout<Darwin.timespec>.size, UInt32(FSOPT_NOFOLLOW))
    }

    static func message(_ url: URL, _ code: Int32) -> String {
        "\(url.lastPathComponent): \(String(cString: strerror(code)))"
    }

    static func message(_ url: URL, _ error: any Error) -> String {
        if let posix = error as? POSIXError { return message(url, posix.code.rawValue) }
        let ns = error as NSError
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain {
            return message(url, Int32(underlying.code))
        }
        return "\(url.lastPathComponent): \(ns.localizedDescription)"
    }
}
