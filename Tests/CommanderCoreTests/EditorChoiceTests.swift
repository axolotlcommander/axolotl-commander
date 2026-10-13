// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Testing
@testable import CommanderCore

@Test func editorChoiceDefaultsToTextEdit() {
    #expect(EditorChoice.resolve(chosen: nil) { _ in true } == .app(bundleID: "com.apple.TextEdit"))
    #expect(EditorChoice.resolve(chosen: "") { _ in true } == .app(bundleID: "com.apple.TextEdit"))
}

@Test func editorChoiceUsesSystemDefault() {
    #expect(EditorChoice.resolve(chosen: "system") { _ in false } == .systemDefault)
}

/// A chosen editor that is gone is reported, not silently replaced by TextEdit.
@Test func editorChoiceReportsMissingEditor() {
    let installed: Set = ["com.apple.TextEdit"]
    #expect(EditorChoice.resolve(chosen: "com.coteditor.CotEditor") { installed.contains($0) }
            == .missing(bundleID: "com.coteditor.CotEditor"))
    #expect(EditorChoice.resolve(chosen: "com.coteditor.CotEditor") { _ in true }
            == .app(bundleID: "com.coteditor.CotEditor"))
    #expect(EditorChoice.resolve(chosen: nil) { _ in false } == .missing(bundleID: "com.apple.TextEdit"))
}
