// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import CryptoKit
public import Foundation
import Security

/// Why the app cannot install an update itself; the user gets the manual download with this reason.
public enum UpdateProblem: Error, Equatable, Sendable {
    // Known before the download (`InstallCapability`)
    case developmentBuild
    case adHocSignature
    case translocated
    case readOnlyVolume
    case notWritable
    // Found while installing (`UpdateInstaller`)
    case checksumMissing
    case checksumMismatch
    case badArchive
    case identifierMismatch
    case versionMismatch
    case signatureMismatch
    case replaceFailed(String)
}

/// Checks that a downloaded app is signed like the running one.
public protocol UpdateVerifier: Sendable {
    func verify(_ app: URL) throws(UpdateProblem)
}

/// The real check: the new app's signature must be valid and satisfy the designated requirement of the
/// running app's own signature (the same certificate and identifier).
public struct CodeSignatureVerifier: UpdateVerifier {
    /// The designated requirement as text (`SecRequirement` itself is not `Sendable`).
    public let requirement: String

    /// The requirement of the running app; nil when it has none (unsigned or ad-hoc builds need the manual way).
    public static func forRunningApp() -> CodeSignatureVerifier? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return forApp(staticCode)
    }

    /// The requirement of the app at `url` (tests use copies of system apps).
    public static func forApp(at url: URL) -> CodeSignatureVerifier? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return forApp(staticCode)
    }

    private static func forApp(_ code: SecStaticCode) -> CodeSignatureVerifier? {
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { return nil }
        return CodeSignatureVerifier(requirement: text as String)
    }

    public func verify(_ app: URL) throws(UpdateProblem) {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(self.requirement as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            throw .signatureMismatch
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw .signatureMismatch }
    }

    /// Whether the code at `url` carries an ad-hoc signature (or none): its requirement names one exact build.
    public static func isAdHoc(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return true }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any] else { return true }
        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return info[kSecCodeInfoIdentifier as String] == nil || flags & SecCodeSignatureFlags.adhoc.rawValue != 0
    }
}

/// Whether the app at its location can be replaced by the user without an administrator password.
public enum InstallCapability {
    public static func check(appURL: URL, fileManager: FileManager = .default,
                             isAdHoc: (URL) -> Bool = CodeSignatureVerifier.isAdHoc) -> UpdateProblem? {
        guard appURL.pathExtension == "app" else { return .developmentBuild }
        if isAdHoc(appURL) { return .adHocSignature }
        if appURL.path.contains("/AppTranslocation/") { return .translocated }
        if (try? appURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true { return .readOnlyVolume }
        let parent = appURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parent.path), fileManager.isWritableFile(atPath: appURL.path) else {
            return .notWritable
        }
        return nil
    }
}

/// The steps after the download (spec 027, R4 and R5). Touches only `workFolder`, the app at `appURL` and the
/// old app's place in the Trash.
public struct UpdateInstaller: Sendable {
    public let appURL: URL
    public let bundleIdentifier: String
    public let workFolder: URL
    public let verifier: any UpdateVerifier
    /// Moves an item to the Trash and returns where it went (injected in tests).
    public let trash: @Sendable (URL) throws -> URL

    public init(appURL: URL, bundleIdentifier: String, workFolder: URL, verifier: any UpdateVerifier,
                trash: @escaping @Sendable (URL) throws -> URL = UpdateInstaller.moveToTrash) {
        self.appURL = appURL
        self.bundleIdentifier = bundleIdentifier
        self.workFolder = workFolder
        self.verifier = verifier
        self.trash = trash
    }

    public static func moveToTrash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let result else { throw CocoaError(.fileWriteUnknown) }
        return result as URL
    }

    /// The lowercase hex SHA-256 of a file, read in 1 MB pieces.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1 << 20), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Checks the archive and the app inside it; returns the unpacked app, ready to replace the running one.
    public func verify(archive: URL, checksums: String, release: ReleaseInfo) throws(UpdateProblem) -> URL {
        guard let expected = ChecksumFile.parse(checksums)[release.archiveName] else { throw .checksumMissing }
        guard let actual = try? Self.sha256(of: archive), actual == expected else { throw .checksumMismatch }
        let unpacked = workFolder.appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: unpacked)
        guard (try? FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)) != nil,
              Self.unzip(archive, into: unpacked) else { throw .badArchive }
        let apps = ((try? FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first,
              let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { throw .badArchive }
        guard info["CFBundleIdentifier"] as? String == bundleIdentifier else { throw .identifierMismatch }
        guard (info["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init) == release.version else {
            throw .versionMismatch
        }
        try verifier.verify(app)
        return app
    }

    /// Puts `newApp` where the running app is (same name and folder); the old app goes to the Trash. On a
    /// failure the old app is put back. Returns the old app's place in the Trash.
    @discardableResult
    public func replace(with newApp: URL) throws(UpdateProblem) -> URL {
        let trashed: URL
        do { trashed = try trash(appURL) } catch { throw .replaceFailed(error.localizedDescription) }
        do {
            try FileManager.default.moveItem(at: newApp, to: appURL)
        } catch {
            try? FileManager.default.moveItem(at: trashed, to: appURL)
            throw .replaceFailed(error.localizedDescription)
        }
        return trashed
    }

    /// Removes the downloads and the unpacked app.
    public func cleanUp() {
        try? FileManager.default.removeItem(at: workFolder)
    }

    private static func unzip(_ archive: URL, into folder: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
