// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import Testing
import Foundation
import Darwin
@testable import CommanderCore

// All file system work happens inside a UUID-named directory under
// FileManager.default.temporaryDirectory. Before removal every item in it is unlocked
// (flags cleared, u+rwx) — `uchg` items cannot be deleted otherwise.

private func withSandbox(_ body: (URL) async throws -> Void) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("icmd-attr-\(UUID().uuidString)", isDirectory: true)
        .resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer {
        unlockTree(root.path)
        try? FileManager.default.removeItem(at: root)
    }
    try await body(root)
}

/// Clears all user flags and grants u+rwx on everything below `path`; never follows symlinks.
private func unlockTree(_ path: String) {
    var st = stat()
    guard lstat(path, &st) == 0 else { return }
    _ = lchflags(path, 0)
    guard st.st_mode & S_IFMT != S_IFLNK else { return }
    _ = chmod(path, (st.st_mode & 0o7777) | 0o700)
    guard st.st_mode & S_IFMT == S_IFDIR,
          let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
    for name in names { unlockTree(path + "/" + name) }
}

private extension URL {
    func sub(_ name: String) -> URL { appendingPathComponent(name) }
}

private func makeFile(_ url: URL, mode: mode_t = 0o644) throws {
    try Data("x".utf8).write(to: url)
    #expect(chmod(url.path, mode) == 0)
}

private func makeDir(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
}

private func st(_ url: URL) -> stat {
    var s = stat()
    _ = lstat(url.path, &s)
    return s
}

private func mode(_ url: URL) -> Int { Int(st(url).st_mode & 0o7777) }
private func isLocked(_ url: URL) -> Bool { st(url).st_flags & UInt32(UF_IMMUTABLE) != 0 }
private func isHidden(_ url: URL) -> Bool { st(url).st_flags & UInt32(UF_HIDDEN) != 0 }
private func lock(_ url: URL) { #expect(lchflags(url.path, st(url).st_flags | UInt32(UF_IMMUTABLE)) == 0) }

private func tags(_ url: URL) -> [String] {
    (try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
}

private func setTags(_ url: URL, _ tags: [String]) throws {
    try (URL(fileURLWithPath: url.path) as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
}

private func change(_ edit: (inout AttributeChange) -> Void) -> AttributeChange {
    var c = AttributeChange()
    edit(&c)
    return c
}

private func seconds(_ t: timespec) -> Int { t.tv_sec }

@Suite struct AttributeSummaryTests {
    @Test func mixedModesLockedTagsDates() async throws {
        try await withSandbox { root in
            let a = root.sub("a"), b = root.sub("b"), c = root.sub("c")
            try makeFile(a, mode: 0o644)
            try makeFile(b, mode: 0o600)
            try makeFile(c, mode: 0o644)
            try setTags(a, ["icmd-test-a", "icmd-test-b"])
            try setTags(b, ["icmd-test-a"])
            let date = Date(timeIntervalSince1970: 1_600_000_000)
            _ = try await AttributeEditor.apply(change { $0.modified = date }, to: [a, b, c])
            lock(c)

            var s = try AttributeSummary.read([a, b, c])
            #expect(s.count == 3)
            #expect(s.modeBits.count == 12)
            #expect(s.modeBits[0o400] == .on)
            #expect(s.modeBits[0o200] == .on)
            #expect(s.modeBits[0o040] == .mixed)
            #expect(s.modeBits[0o004] == .mixed)
            #expect(s.modeBits[0o001] == .off)
            #expect(s.modeBits[0o4000] == .off)
            #expect(s.locked == .mixed)
            #expect(s.hidden == .off)
            #expect(s.tags == ["icmd-test-a": 2, "icmd-test-b": 1])
            #expect(s.modified == date)
            #expect(s.containsFolders == false)

            s = try AttributeSummary.read([c])
            #expect(s.locked == .on)
            #expect(s.tags.isEmpty)

            let d = root.sub("d")
            try makeDir(d)
            s = try AttributeSummary.read([a, d])
            #expect(s.containsFolders)
            #expect(s.modified == nil)

            #expect(throws: (any Error).self) { try AttributeSummary.read([root.sub("missing")]) }
            let empty = try AttributeSummary.read([])
            #expect(empty.count == 0 && empty.locked == .off && empty.modified == nil)
        }
    }

    @Test func isEmpty() {
        #expect(AttributeChange().isEmpty)
        #expect(change { $0.recursive = true }.isEmpty)
        #expect(!change { $0.setMode = 0o100 }.isEmpty)
        #expect(!change { $0.locked = false }.isEmpty)
        #expect(!change { $0.removeTags = ["x"] }.isEmpty)
        #expect(!change { $0.created = Date() }.isEmpty)
    }
}

@Suite struct AttributeEditorTests {
    @Test func setAndClearModeBits() async throws {
        try await withSandbox { root in
            let f = root.sub("f")
            try makeFile(f, mode: 0o644)
            var r = try await AttributeEditor.apply(change { $0.clearMode = 0o044 }, to: [f])
            #expect(mode(f) == 0o600)
            #expect(r == AttributeReport(changed: 1, failures: []))
            r = try await AttributeEditor.apply(change { $0.setMode = 0o100 }, to: [f])
            #expect(mode(f) == 0o700)
            #expect(r.changed == 1)
            // Nothing to change.
            r = try await AttributeEditor.apply(change { $0.setMode = 0o100 }, to: [f])
            #expect(r.changed == 0 && r.failures.isEmpty)
        }
    }

    private func tree(_ root: URL) throws -> (dir: URL, f1: URL, sub: URL, f2: URL) {
        let dir = root.sub("dir"), sub = dir.sub("sub")
        try makeDir(dir)
        try makeDir(sub)
        let f1 = dir.sub("f1"), f2 = sub.sub("f2")
        try makeFile(f1)
        try makeFile(f2)
        return (dir, f1, sub, f2)
    }

    @Test func recursiveFilesOnly() async throws {
        try await withSandbox { root in
            let t = try tree(root)
            let r = try await AttributeEditor.apply(change {
                $0.setMode = 0o002; $0.recursive = true; $0.includeFolders = false
            }, to: [t.dir])
            #expect(mode(t.dir) & 0o002 != 0)   // selected item always changes
            #expect(mode(t.sub) & 0o002 == 0)
            #expect(mode(t.f1) & 0o002 != 0)
            #expect(mode(t.f2) & 0o002 != 0)
            #expect(r.changed == 3)
        }
    }

    @Test func recursiveFoldersOnly() async throws {
        try await withSandbox { root in
            let t = try tree(root)
            let r = try await AttributeEditor.apply(change {
                $0.hidden = true; $0.recursive = true; $0.includeFiles = false
            }, to: [t.dir])
            #expect(isHidden(t.dir) && isHidden(t.sub))
            #expect(!isHidden(t.f1) && !isHidden(t.f2))
            #expect(r.changed == 2)
        }
    }

    @Test func notRecursiveLeavesContents() async throws {
        try await withSandbox { root in
            let t = try tree(root)
            _ = try await AttributeEditor.apply(change { $0.hidden = true }, to: [t.dir])
            #expect(isHidden(t.dir) && !isHidden(t.sub) && !isHidden(t.f1))
        }
    }

    @Test func lockAndUnlock() async throws {
        try await withSandbox { root in
            let f = root.sub("f")
            try makeFile(f)
            var r = try await AttributeEditor.apply(change { $0.locked = true }, to: [f])
            #expect(isLocked(f) && r.changed == 1)
            #expect(open(f.path, O_WRONLY) == -1)   // really immutable
            r = try await AttributeEditor.apply(change { $0.locked = true }, to: [f])
            #expect(r.changed == 0)
            r = try await AttributeEditor.apply(change { $0.locked = false }, to: [f])
            #expect(!isLocked(f) && r.changed == 1 && r.failures.isEmpty)
        }
    }

    @Test func chmodOnLockedFileKeepsLock() async throws {
        try await withSandbox { root in
            let f = root.sub("f")
            try makeFile(f, mode: 0o644)
            lock(f)
            let r = try await AttributeEditor.apply(change { $0.clearMode = 0o004 }, to: [f])
            #expect(r == AttributeReport(changed: 1, failures: []))
            #expect(mode(f) == 0o640)
            #expect(isLocked(f))
        }
    }

    @Test func recursiveLockIsPostOrder() async throws {
        try await withSandbox { root in
            let t = try tree(root)
            var order: [String] = []
            try AttributeEditor.forEachTarget([t.dir], change: change { $0.recursive = true },
                                              failure: { _, _ in }, body: { order.append($0.lastPathComponent) })
            #expect(order == ["f1", "f2", "sub", "dir"])

            let r = try await AttributeEditor.apply(change {
                $0.locked = true; $0.setMode = 0o001; $0.recursive = true
            }, to: [t.dir])
            #expect(r == AttributeReport(changed: 4, failures: []))
            for u in [t.dir, t.sub, t.f1, t.f2] {
                #expect(isLocked(u))
                #expect(mode(u) & 0o001 != 0)
            }
            // Changing a locked tree unlocks each item temporarily and keeps the lock.
            let r2 = try await AttributeEditor.apply(change { $0.clearMode = 0o001; $0.recursive = true },
                                                     to: [t.dir])
            #expect(r2 == AttributeReport(changed: 4, failures: []))
            for u in [t.dir, t.sub, t.f1, t.f2] {
                #expect(isLocked(u) && mode(u) & 0o001 == 0)
            }
            _ = try await AttributeEditor.apply(change { $0.locked = false; $0.recursive = true }, to: [t.dir])
            for u in [t.dir, t.sub, t.f1, t.f2] { #expect(!isLocked(u)) }
        }
    }

    @Test func hiddenFlagPreservesOtherFlags() async throws {
        try await withSandbox { root in
            let f = root.sub("f")
            try makeFile(f)
            lock(f)
            var r = try await AttributeEditor.apply(change { $0.hidden = true }, to: [f])
            #expect(r == AttributeReport(changed: 1, failures: []))
            #expect(isHidden(f) && isLocked(f))
            #expect(try AttributeSummary.read([f]).hidden == .on)
            r = try await AttributeEditor.apply(change { $0.hidden = false }, to: [f])
            #expect(!isHidden(f) && isLocked(f) && r.changed == 1)
        }
    }

    @Test func addAndRemoveTags() async throws {
        try await withSandbox { root in
            let f = root.sub("f")
            try makeFile(f)
            try setTags(f, ["icmd-test-b"])
            var r = try await AttributeEditor.apply(change { $0.addTags = ["icmd-test-a", "icmd-test-b"] }, to: [f])
            #expect(tags(f) == ["icmd-test-b", "icmd-test-a"])
            #expect(r.changed == 1)
            r = try await AttributeEditor.apply(change { $0.addTags = ["icmd-test-a"] }, to: [f])
            #expect(r.changed == 0)
            lock(f)
            r = try await AttributeEditor.apply(change {
                $0.removeTags = ["icmd-test-b"]; $0.addTags = ["icmd-test-c"]
            }, to: [f])
            #expect(r == AttributeReport(changed: 1, failures: []))
            #expect(tags(f) == ["icmd-test-a", "icmd-test-c"])
            #expect(isLocked(f))
        }
    }

    @Test func dates() async throws {
        try await withSandbox { root in
            let f = root.sub("f"), g = root.sub("g")
            try makeFile(f)
            try makeFile(g)
            lock(g)
            let created = Date(timeIntervalSince1970: 1_500_000_000)
            let modified = Date(timeIntervalSince1970: 1_550_000_000.25)
            let accessed = Date(timeIntervalSince1970: 1_560_000_000)
            let r = try await AttributeEditor.apply(change {
                $0.created = created; $0.modified = modified; $0.accessed = accessed
            }, to: [f, g])
            #expect(r == AttributeReport(changed: 2, failures: []))
            for u in [f, g] {
                let s = st(u)
                #expect(seconds(s.st_birthtimespec) == 1_500_000_000)
                #expect(seconds(s.st_mtimespec) == 1_550_000_000)
                #expect(seconds(s.st_atimespec) == 1_560_000_000)
            }
            #expect(isLocked(g))
            let summary = try AttributeSummary.read([f, g])
            #expect(summary.created == created)
            #expect(summary.accessed == accessed)
            #expect(abs((summary.modified ?? .distantPast).timeIntervalSince(modified)) < 0.001)

            // Only the modified date; access date stays.
            let later = Date(timeIntervalSince1970: 1_570_000_000)
            _ = try await AttributeEditor.apply(change { $0.modified = later }, to: [f])
            #expect(seconds(st(f).st_mtimespec) == 1_570_000_000)
            #expect(seconds(st(f).st_atimespec) == 1_560_000_000)
        }
    }

    @Test func symlinksAreNotFollowed() async throws {
        try await withSandbox { root in
            let target = root.sub("target"), link = root.sub("link")
            try makeFile(target, mode: 0o644)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            let realDir = root.sub("real"), inner = realDir.sub("inner"), dirLink = root.sub("dirlink")
            try makeDir(realDir)
            try makeFile(inner)
            try FileManager.default.createSymbolicLink(at: dirLink, withDestinationURL: realDir)

            let r = try await AttributeEditor.apply(change {
                $0.setMode = 0o111; $0.addTags = ["icmd-test-a"]; $0.hidden = true; $0.recursive = true
            }, to: [link, dirLink])
            #expect(r.failures.isEmpty)
            #expect(mode(target) == 0o644)
            #expect(tags(target).isEmpty)
            #expect(!isHidden(target))
            #expect(isHidden(link))          // flags change the link itself
            #expect(!isHidden(realDir) && !isHidden(inner))
            #expect(mode(inner) == 0o644)
            #expect(r.changed == 2)

            let summary = try AttributeSummary.read([link])
            #expect(summary.hidden == .on && summary.containsFolders == false)
        }
    }

    @Test func failuresDoNotAbort() async throws {
        try await withSandbox { root in
            let a = root.sub("a"), b = root.sub("b"), missing = root.sub("vanished")
            try makeFile(a)
            try makeFile(b)
            let r = try await AttributeEditor.apply(change { $0.setMode = 0o100 }, to: [a, missing, b])
            #expect(r.changed == 2)
            #expect(r.failures.count == 1)
            #expect(r.failures.first?.url == missing)
            #expect(r.failures.first?.message.hasPrefix("vanished: ") == true)
            #expect(mode(a) == 0o744 && mode(b) == 0o744)
        }
    }

    @Test func cancellation() async throws {
        try await withSandbox { root in
            let files = (0..<3).map { root.sub("f\($0)") }
            for f in files { try makeFile(f) }
            let task = Task {
                try await AttributeEditor.apply(change { $0.setMode = 0o100 }, to: files) { done in
                    if done == 1 { withUnsafeCurrentTask { $0?.cancel() } }
                }
            }
            await #expect(throws: CancellationError.self) { _ = try await task.value }
            #expect(mode(files[0]) == 0o744)
            #expect(mode(files[1]) == 0o644 && mode(files[2]) == 0o644)
        }
    }
}
