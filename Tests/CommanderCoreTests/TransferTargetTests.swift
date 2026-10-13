// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// The "To:" text of the copy/move dialog (spec 021).
@Suite struct TransferTargetTests {
    private func substring(_ text: String, _ range: NSRange?) -> String? {
        range.map { (text as NSString).substring(with: $0) }
    }

    @Test func textJoins() {
        #expect(TransferTarget.text(folder: "/", name: "x") == "/x")
        #expect(TransferTarget.text(folder: "/a/", name: "x") == "/a/x")
        #expect(TransferTarget.text(folder: "/a", name: "x") == "/a/x")
        #expect(TransferTarget.text(folder: "", name: "x") == "x")
    }

    @Test func resolveCases() {
        let folders: Set<String> = ["/exists"]
        let isFolder: (String) -> Bool = { folders.contains($0) }
        func go(_ t: String) -> (folder: String, name: String) {
            TransferTarget.resolve(t, sourceName: "src.txt", isFolder: isFolder)
        }
        #expect(go("/a/b/") == (folder: "/a/b", name: "src.txt"))
        #expect(go("/") == (folder: "/", name: "src.txt"))
        #expect(go("/exists") == (folder: "/exists", name: "src.txt"))
        #expect(go("/a/new.txt") == (folder: "/a", name: "new.txt"))
        #expect(go("new.txt") == (folder: "", name: "new.txt"))
        #expect(go("/x") == (folder: "/", name: "x"))
        #expect(go("  /a/new.txt \n") == (folder: "/a", name: "new.txt"))
        #expect(go("  /exists  ") == (folder: "/exists", name: "src.txt"))
    }

    @Test func rangesOfFile() {
        let text = "/a/b/x.txt"
        #expect(substring(text, TransferTarget.range(of: .name, in: text, isDirectory: false)) == "x")
        #expect(substring(text, TransferTarget.range(of: .extension, in: text, isDirectory: false)) == "txt")
        #expect(substring(text, TransferTarget.range(of: .folder, in: text, isDirectory: false)) == "/a/b")
        #expect(substring(text, TransferTarget.range(of: .all, in: text, isDirectory: false)) == text)
    }

    @Test func rangesUseLastDotAndHandleNoExtension() {
        let tar = "/d/a.tar.gz"
        #expect(substring(tar, TransferTarget.range(of: .name, in: tar, isDirectory: false)) == "a.tar")
        #expect(substring(tar, TransferTarget.range(of: .extension, in: tar, isDirectory: false)) == "gz")
        let plain = "/d/noext"
        #expect(substring(plain, TransferTarget.range(of: .name, in: plain, isDirectory: false)) == "noext")
        #expect(TransferTarget.range(of: .extension, in: plain, isDirectory: false) == nil)
        let hidden = "/d/.zshrc"
        #expect(substring(hidden, TransferTarget.range(of: .name, in: hidden, isDirectory: false)) == ".zshrc")
        #expect(TransferTarget.range(of: .extension, in: hidden, isDirectory: false) == nil)
        #expect(TransferTarget.range(of: .folder, in: "x.txt", isDirectory: false) == nil)
        #expect(TransferTarget.range(of: .all, in: "", isDirectory: false) == nil)
    }

    @Test func rangesOfFolderItemAndRoot() {
        let text = "/a/my.folder"
        #expect(substring(text, TransferTarget.range(of: .name, in: text, isDirectory: true)) == "my.folder")
        #expect(TransferTarget.range(of: .extension, in: text, isDirectory: true) == nil)
        let root = "/x"
        #expect(substring(root, TransferTarget.range(of: .folder, in: root, isDirectory: false)) == "/")
        #expect(TransferTarget.range(of: .name, in: "/a/", isDirectory: false) == nil)
    }

    @Test func rangesCountUTF16() {
        let text = "/Složka/😀 čaj.txt"
        #expect(substring(text, TransferTarget.range(of: .name, in: text, isDirectory: false)) == "😀 čaj")
        #expect(substring(text, TransferTarget.range(of: .extension, in: text, isDirectory: false)) == "txt")
        #expect(substring(text, TransferTarget.range(of: .folder, in: text, isDirectory: false)) == "/Složka")
        #expect(TransferTarget.range(of: .all, in: text, isDirectory: false)?.length == (text as NSString).length)
    }

    @Test func nextCycles() {
        let text = "/a/x.txt"
        #expect(TransferTarget.next(after: .name, in: text, isDirectory: false) == .extension)
        #expect(TransferTarget.next(after: .extension, in: text, isDirectory: false) == .folder)
        #expect(TransferTarget.next(after: .folder, in: text, isDirectory: false) == .all)
        #expect(TransferTarget.next(after: .all, in: text, isDirectory: false) == .name)
    }

    @Test func nextSkipsMissingParts() {
        #expect(TransferTarget.next(after: .name, in: "/a/noext", isDirectory: false) == .folder)
        #expect(TransferTarget.next(after: .name, in: "/a/x.txt", isDirectory: true) == .folder)
        #expect(TransferTarget.next(after: .all, in: "/a/", isDirectory: false) == .folder)
        #expect(TransferTarget.next(after: .name, in: "noext", isDirectory: false) == .all)
    }
}
