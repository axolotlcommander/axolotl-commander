// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import Foundation
import Testing
@testable import CommanderCore

/// The installer on fake app bundles in a temporary folder (never a real app or user data), and the real
/// signature check on copies of system apps.
@Suite struct UpdateInstallerTests {
    struct Accept: UpdateVerifier { func verify(_ app: URL) throws(UpdateProblem) {} }
    struct Refuse: UpdateVerifier { func verify(_ app: URL) throws(UpdateProblem) { throw .signatureMismatch } }

    static let identifier = "test.axolotl.update"

    let root: URL
    let installed: URL
    let trashFolder: URL
    let work: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateInstallerTests-\(UUID().uuidString)")
        installed = root.appendingPathComponent("Apps/My Axolotl.app")
        trashFolder = root.appendingPathComponent("Trash")
        work = root.appendingPathComponent("Work")
        for folder in [installed.deletingLastPathComponent(), trashFolder, work] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Self.makeApp(at: installed, version: "0.6.0")
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    static func makeApp(at url: URL, identifier: String = identifier, version: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version]
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        try Data(version.utf8).write(to: contents.appendingPathComponent("MacOS/marker"))
    }

    /// A zip like the release's (`ditto -c -k --keepParent`) with the given apps; returns it and its checksum file.
    func archive(_ apps: [(name: String, identifier: String, version: String)], version: String = "0.7.0")
        throws -> (zip: URL, sums: String) {
        let stage = root.appendingPathComponent("Stage-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        for app in apps { try Self.makeApp(at: stage.appendingPathComponent(app.name), identifier: app.identifier, version: app.version) }
        // Each archive in its own folder, so several can be compared in one test.
        let zip = stage.appendingPathExtension("out").appendingPathComponent("Axolotl-Commander-\(version).zip")
        try FileManager.default.createDirectory(at: zip.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = apps.count == 1
            ? ["-c", "-k", "--keepParent", stage.appendingPathComponent(apps[0].name).path, zip.path]
            : ["-c", "-k", stage.path, zip.path]
        try process.run()
        process.waitUntilExit()
        let hash = try UpdateInstaller.sha256(of: zip)
        return (zip, "\(hash)  Axolotl-Commander-\(version).zip\n")
    }

    func installer(_ verifier: any UpdateVerifier = Accept(), trash: (@Sendable (URL) throws -> URL)? = nil) -> UpdateInstaller {
        let trashFolder = trashFolder
        return UpdateInstaller(appURL: installed, bundleIdentifier: Self.identifier, workFolder: work, verifier: verifier,
                               trash: trash ?? { url in
                                   let target = trashFolder.appendingPathComponent(url.lastPathComponent)
                                   try FileManager.default.moveItem(at: url, to: target)
                                   return target
                               })
    }

    func marker(_ app: URL) -> String? {
        (try? Data(contentsOf: app.appendingPathComponent("Contents/MacOS/marker"))).map { String(decoding: $0, as: UTF8.self) }
    }

    let release = UpdateTests.release("0.7.0")

    @Test func installsAndKeepsTheOldAppInTheTrash() throws {
        defer { cleanUp() }
        let (zip, sums) = try archive([("Axolotl Commander.app", Self.identifier, "0.7.0")])
        let installer = installer()
        let app = try installer.verify(archive: zip, checksums: sums, release: release)
        let trashed = try installer.replace(with: app)
        #expect(marker(installed) == "0.7.0")                     // the user's name and place are kept
        #expect(marker(trashed) == "0.6.0")
        installer.cleanUp()
        #expect(!FileManager.default.fileExists(atPath: work.path))
    }

    @Test func refusesWhatDoesNotFit() throws {
        defer { cleanUp() }
        let installer = installer()
        let good = try archive([("A.app", Self.identifier, "0.7.0")])
        #expect(throws: UpdateProblem.checksumMismatch) {
            try installer.verify(archive: good.zip, checksums: String(repeating: "0", count: 64) + "  Axolotl-Commander-0.7.0.zip", release: release)
        }
        #expect(throws: UpdateProblem.checksumMissing) { try installer.verify(archive: good.zip, checksums: "", release: release) }
        let two = try archive([("A.app", Self.identifier, "0.7.0"), ("B.app", Self.identifier, "0.7.0")])
        #expect(throws: UpdateProblem.badArchive) { try installer.verify(archive: two.zip, checksums: two.sums, release: release) }
        let other = try archive([("A.app", "someone.else", "0.7.0")])
        #expect(throws: UpdateProblem.identifierMismatch) { try installer.verify(archive: other.zip, checksums: other.sums, release: release) }
        let old = try archive([("A.app", Self.identifier, "0.6.5")])
        #expect(throws: UpdateProblem.versionMismatch) { try installer.verify(archive: old.zip, checksums: old.sums, release: release) }
        #expect(throws: UpdateProblem.signatureMismatch) {
            try self.installer(Refuse()).verify(archive: good.zip, checksums: good.sums, release: release)
        }
        #expect(marker(installed) == "0.6.0")                     // nothing was replaced
    }

    @Test func rollsBackWhenTheNewAppCannotBeMoved() throws {
        defer { cleanUp() }
        let missing = root.appendingPathComponent("Nowhere.app")
        #expect(throws: UpdateProblem.self) { try installer().replace(with: missing) }
        #expect(marker(installed) == "0.6.0")                     // the old app is back
        #expect(throws: UpdateProblem.self) {
            try installer(trash: { _ in throw CocoaError(.fileWriteNoPermission) }).replace(with: installed)
        }
        #expect(marker(installed) == "0.6.0")
    }

    @Test func capability() throws {
        defer { cleanUp() }
        #expect(InstallCapability.check(appURL: root.appendingPathComponent("bin"), isAdHoc: { _ in false }) == .developmentBuild)
        #expect(InstallCapability.check(appURL: installed, isAdHoc: { _ in true }) == .adHocSignature)
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Axolotl Commander.app")
        #expect(InstallCapability.check(appURL: translocated, isAdHoc: { _ in false }) == .translocated)
        #expect(InstallCapability.check(appURL: installed, isAdHoc: { _ in false }) == nil)
        let folder = installed.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        #expect(InstallCapability.check(appURL: installed, isAdHoc: { _ in false }) == .notWritable)
    }

    /// Signs a small app ad hoc with the system's `codesign` (in the temporary folder only).
    func signedApp(_ name: String, identifier: String) throws -> URL {
        let app = root.appendingPathComponent(name)
        try Self.makeApp(at: app, identifier: identifier, version: "0.7.0")
        let info: NSDictionary = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": "0.7.0",
                                  "CFBundleExecutable": "tool", "CFBundlePackageType": "APPL"]
        try info.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.removeItem(at: app.appendingPathComponent("Contents/MacOS/marker"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: app.appendingPathComponent("Contents/MacOS/tool"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", app.path]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0)
        return app
    }

    /// The real check with the Security framework: an exact copy satisfies the original's requirement, another
    /// app and a changed copy do not.
    @Test func realSignatureCheck() throws {
        defer { cleanUp() }
        let original = try signedApp("One.app", identifier: "test.axolotl.one")
        let other = try signedApp("Two.app", identifier: "test.axolotl.two")
        let copy = root.appendingPathComponent("Copy/One.app")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: original, to: copy)
        let verifier = try #require(CodeSignatureVerifier.forApp(at: original))
        try verifier.verify(copy)
        #expect(throws: UpdateProblem.signatureMismatch) { try verifier.verify(other) }
        try Data("x".utf8).write(to: copy.appendingPathComponent("Contents/added.txt"))
        #expect(throws: UpdateProblem.signatureMismatch) { try verifier.verify(copy) }
        #expect(CodeSignatureVerifier.isAdHoc(original))
        #expect(CodeSignatureVerifier.isAdHoc(installed))           // no signature at all
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        if FileManager.default.fileExists(atPath: calculator.path) { #expect(!CodeSignatureVerifier.isAdHoc(calculator)) }
    }
}
