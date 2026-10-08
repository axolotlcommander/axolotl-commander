// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
import Foundation
@testable import CommanderCore

@Suite struct SortingTests {
    let base = URL(fileURLWithPath: "/tmp/x")
    func file(_ n: String, size: Int64 = 0, date: Double = 0) -> FileItem {
        FileItem(url: base.appendingPathComponent(n), size: size, modificationDate: Date(timeIntervalSince1970: date))
    }
    func dir(_ n: String, date: Double = 0) -> FileItem {
        FileItem(url: base.appendingPathComponent(n), isDirectory: true, modificationDate: Date(timeIntervalSince1970: date))
    }
    var sample: [FileItem] {
        [file("b.txt", size: 5, date: 3), file("a10.zip", size: 1, date: 1), dir("zeta", date: 2),
         .parent(of: base), file("a2.md", size: 9, date: 2), dir("Alpha", date: 9)]
    }
    func names(_ s: SortSpec, sizes: [String: Int64] = [:]) -> [String] {
        sortItems(sample, by: s, rules: .apfsDefault, directorySizes: sizes).map(\.name)
    }

    @Test func parentFirstDirsBeforeFiles() {
        #expect(names(.default) == ["..", "Alpha", "zeta", "a2.md", "a10.zip", "b.txt"])
        #expect(names(SortSpec(field: .name, ascending: false)) == ["..", "zeta", "Alpha", "b.txt", "a10.zip", "a2.md"])
    }

    @Test func otherFields() {
        #expect(names(SortSpec(field: .ext)) == ["..", "Alpha", "zeta", "a2.md", "b.txt", "a10.zip"])
        #expect(Array(names(SortSpec(field: .size)).suffix(3)) == ["a10.zip", "b.txt", "a2.md"])
        #expect(names(SortSpec(field: .date, ascending: false)) == ["..", "Alpha", "zeta", "b.txt", "a2.md", "a10.zip"])
    }

    @Test func directorySizesUsedWhenKnown() {
        let sizes = ["zeta": Int64(1), "alpha": Int64(50)]
        #expect(Array(names(SortSpec(field: .size), sizes: sizes).prefix(3)) == ["..", "zeta", "Alpha"])
    }

    @Test func packagesSortWithFiles() {
        let app = FileItem(url: base.appendingPathComponent("Mail.app"), isDirectory: true, isPackage: true)
        #expect(app.baseName == "Mail" && app.fileExtension == "app")
        #expect(dir("x.y").fileExtension.isEmpty && dir("x.y").baseName == "x.y")
        let items = sample + [app]
        let byName = sortItems(items, by: .default, rules: .apfsDefault).map(\.name)
        #expect(byName == ["..", "Alpha", "zeta", "a2.md", "a10.zip", "b.txt", "Mail.app"])
        let byExt = sortItems(items, by: SortSpec(field: .ext), rules: .apfsDefault).map(\.name)
        #expect(byExt == ["..", "Alpha", "zeta", "Mail.app", "a2.md", "b.txt", "a10.zip"])
        let bySize = sortItems(items, by: SortSpec(field: .size), rules: .apfsDefault,
                               directorySizes: ["mail.app": 7]).map(\.name)
        #expect(bySize.suffix(4) == ["a10.zip", "b.txt", "Mail.app", "a2.md"])
    }

    @Test func toggling() {
        let s = SortSpec.default.toggled(.name)
        #expect(s.field == .name && !s.ascending)
        #expect(s.toggled(.name).ascending)
        let e = s.toggled(.size)
        #expect(e.field == .size && e.ascending)
    }

    @Test func fileItemExtension() {
        #expect(file("a.tar.gz").fileExtension == "gz")
        #expect(file("a.tar.gz").baseName == "a.tar")
        #expect(file(".bashrc").fileExtension == "")
        #expect(file(".bashrc").baseName == ".bashrc")
        #expect(dir("x.app").fileExtension == "")
        #expect(dir("x.app").baseName == "x.app")
        #expect(FileItem.parent(of: base).fileExtension == "")
    }
}
