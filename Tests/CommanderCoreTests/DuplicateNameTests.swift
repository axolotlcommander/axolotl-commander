// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

@Suite struct DuplicateNameTests {
    func name(_ original: String, folder: Bool = false, word: String = "copy", taken: Set<String> = []) -> String {
        DuplicateName.name(for: original, isDirectory: folder, word: word) { taken.contains($0) }
    }

    @Test func fileGetsTheWordBeforeItsExtension() {
        #expect(name("report.pdf") == "report copy.pdf")
        #expect(name("report.pdf", word: "kopie") == "report kopie.pdf")
        #expect(name("archive.tar.gz") == "archive.tar copy.gz")
    }

    @Test func takenNamesCountOn() {
        #expect(name("report.pdf", taken: ["report copy.pdf"]) == "report copy 2.pdf")
        #expect(name("report.pdf", taken: ["report copy.pdf", "report copy 2.pdf", "report copy 3.pdf"])
                == "report copy 4.pdf")
        #expect(name("zpráva.txt", word: "kopie", taken: ["zpráva kopie.txt"]) == "zpráva kopie 2.txt")
    }

    @Test func namesWithoutAnExtensionAndFoldersGetTheWordAtTheEnd() {
        #expect(name("Makefile") == "Makefile copy")
        #expect(name(".env") == ".env copy")
        #expect(name("trailing.") == "trailing. copy")
        #expect(name("Photos", folder: true) == "Photos copy")
        #expect(name("Project.v2", folder: true) == "Project.v2 copy")
        #expect(name("Photos", folder: true, taken: ["Photos copy"]) == "Photos copy 2")
    }

    @Test func longNamesStayWithinTheLimit() {
        let long = String(repeating: "é", count: 127) + ".pdf"
        let result = name(long, taken: [])
        #expect(result.utf8.count <= PathRules.maxNameBytes)
        #expect(result.hasSuffix(" copy.pdf"))
        let second = name(long, taken: [result])
        #expect(second.utf8.count <= PathRules.maxNameBytes)
        #expect(second.hasSuffix(" copy 2.pdf"))
    }

    @Test func standardFolders() {
        let home = URL(filePath: "/Users/someone/", directoryHint: .isDirectory)
        #expect(StandardFolder.desktop.url(home: home).path(percentEncoded: false) == "/Users/someone/Desktop/")
        #expect(StandardFolder.documents.url(home: home).path(percentEncoded: false) == "/Users/someone/Documents/")
        #expect(StandardFolder.downloads.url(home: home).path(percentEncoded: false) == "/Users/someone/Downloads/")
        #expect(StandardFolder.applications.url(home: home).path(percentEncoded: false) == "/Applications/")
    }
}
