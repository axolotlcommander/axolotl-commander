// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// The parts of a settings file, in the order the import dialog lists them.
public enum SettingsSection: String, CaseIterable, Sendable {
    case keyboard, preferences, appearance, hotPaths, userMenu, connections, toolbar, buttonBar
}

/// What a stored preference may hold. Anything else in an imported file is skipped.
public enum PreferenceKind: Sendable {
    case bool
    /// A string; when `allowed` is given, one of those values.
    case string(allowed: Set<String>?)
    case number(ClosedRange<Double>)
    case stringArray
    /// JSON stored as data; `validate` decodes it into its type.
    case json(validate: @Sendable (Data) -> Bool)
}

public struct PreferenceSpec: Sendable {
    public let key: String
    public let kind: PreferenceKind
    /// Written on export when the key is not stored, so a file from an untouched setup is complete.
    public let defaultValue: JSONValue?

    public init(_ key: String, _ kind: PreferenceKind, default defaultValue: JSONValue? = nil) {
        self.key = key
        self.kind = kind
        self.defaultValue = defaultValue
    }
}

/// A section stored under one UserDefaults key.
public struct BlobSpec: Sendable {
    public enum Storage: Sendable {
        /// JSON data (`Codable` values the app encodes itself).
        case jsonData
        /// A property list dictionary or array (AppKit's own storage, such as the toolbar).
        case propertyList
    }

    public enum Shape: Sendable {
        /// One value, applied whole or skipped.
        case whole(validate: @Sendable (Data) -> Bool)
        /// An array whose elements are checked one by one; bad elements are skipped.
        case list(validateElement: @Sendable (Data) -> Bool)
    }

    public let defaultsKey: String
    public let storage: Storage
    public let shape: Shape
    public let defaultValue: JSONValue?

    public init(defaultsKey: String, storage: Storage = .jsonData, shape: Shape, default defaultValue: JSONValue? = nil) {
        self.defaultsKey = defaultsKey
        self.storage = storage
        self.shape = shape
        self.defaultValue = defaultValue
    }
}

/// Everything export may write and import may change: an allowlist. Keys that are not here are
/// never exported (session state, history, secrets) and never written.
public struct SettingsCatalog: Sendable {
    public var preferences: [PreferenceSpec]
    public var schemeKey: String
    public var bindingsKey: String
    public var blobs: [SettingsSection: BlobSpec]

    public init(preferences: [PreferenceSpec], schemeKey: String, bindingsKey: String,
                blobs: [SettingsSection: BlobSpec]) {
        self.preferences = preferences
        self.schemeKey = schemeKey
        self.bindingsKey = bindingsKey
        self.blobs = blobs
    }

    /// The catalog with the sections of core types: appearance, hot paths, user menu, saved servers
    /// and (when `toolbarKey` is given) the toolbar.
    public static func standard(preferences: [PreferenceSpec], schemeKey: String = "keys.scheme",
                                bindingsKey: String = "keys.bindings", toolbarKey: String? = nil) -> SettingsCatalog {
        var blobs: [SettingsSection: BlobSpec] = [
            .appearance: BlobSpec(defaultsKey: "appearance", shape: .whole(validate: decodes(PanelAppearance.self)),
                                  default: encoded(PanelAppearance())),
            .hotPaths: BlobSpec(defaultsKey: "hotPaths", shape: .whole(validate: decodes(HotPaths.self)),
                                default: encoded(HotPaths())),
            .userMenu: BlobSpec(defaultsKey: "userMenu.items", shape: .list(validateElement: decodes(UserMenuItem.self)),
                                default: .array([])),
            .connections: BlobSpec(defaultsKey: "connections", shape: .list(validateElement: decodes(ConnectionProfile.self)),
                                   default: .array([])),
            // Spec 018; absent from format-1 files written before it.
            .buttonBar: BlobSpec(defaultsKey: ButtonBarStore.key, shape: .list(validateElement: decodes(ButtonBarItem.self)),
                                 default: encoded(ButtonBarStore.samples)),
        ]
        if let toolbarKey {
            blobs[.toolbar] = BlobSpec(defaultsKey: toolbarKey, storage: .propertyList, shape: .whole(validate: isObject))
        }
        return SettingsCatalog(preferences: preferences, schemeKey: schemeKey, bindingsKey: bindingsKey, blobs: blobs)
    }

    /// A validator that accepts JSON decoding into `type`.
    public static func decodes<T: Decodable & SendableMetatype>(_ type: T.Type) -> @Sendable (Data) -> Bool {
        { (try? JSONDecoder().decode(T.self, from: $0)) != nil }
    }

    private static func encoded(_ value: some Encodable) -> JSONValue? {
        (try? JSONEncoder().encode(value)).flatMap { try? JSONValue(data: $0) }
    }

    private static let isObject: @Sendable (Data) -> Bool = { data in
        (try? JSONValue(data: data))?.objectValue != nil
    }
}

public enum SettingsArchiveError: Error, Equatable, Sendable {
    /// The file is not JSON (or is damaged).
    case notJSON
    /// JSON, but not an Axolotl Commander settings file.
    case notSettingsFile
}

/// A settings file that was read and recognized, before anything is applied.
public struct SettingsContents: Sendable {
    public let formatVersion: Int
    public let appVersion: String?
    public let exported: String?
    public let sections: [SettingsSection: JSONValue]
    /// Top-level entries this version does not know.
    public let unknownSections: [String]

    /// Written by a newer format; the known parts can still be imported.
    public var isNewer: Bool { formatVersion > SettingsArchive.formatVersion }

    /// The sections present, in display order.
    public var availableSections: [SettingsSection] {
        SettingsSection.allCases.filter { sections[$0] != nil }
    }
}

public enum SkipReason: String, Error, Sendable {
    case unknownSection, unknownKey, unknownCommand, malformedChord, wrongType, outOfRange
    case unknownScheme, invalidEntry
}

public struct SkippedEntry: Hashable, Sendable {
    public let section: String
    public let item: String
    public let reason: SkipReason
}

public struct ImportReport: Sendable {
    public var applied: [SettingsSection] = []
    public var skipped: [SkippedEntry] = []
    public var newerFormat = false
}

/// Export and import of the app's settings as one JSON file
/// (`specs/010-keyboard-schemes/contracts/settings-file.md`).
public enum SettingsArchive {
    public static let format = "axolotl-commander-settings"
    public static let formatVersion = 1
    private static let headerKeys: Set<String> = ["format", "formatVersion", "appVersion", "exported"]

    // MARK: Export

    /// The current settings as a settings file. Only catalog keys are read.
    public static func export(from defaults: UserDefaults, catalog: SettingsCatalog,
                              appVersion: String, date: Date = Date()) throws -> Data {
        var root: [String: JSONValue] = [
            "format": .string(format),
            "formatVersion": .number(Double(formatVersion)),
            "appVersion": .string(appVersion),
            "exported": .string(date.formatted(.iso8601)),
        ]

        let scheme = defaults.string(forKey: catalog.schemeKey) ?? KeyScheme.axolotl.rawValue
        let bindings = defaults.data(forKey: catalog.bindingsKey).flatMap { try? JSONValue(data: $0) } ?? .object([:])
        root[SettingsSection.keyboard.rawValue] = .object(["scheme": .string(scheme), "bindings": bindings])

        var preferences: [String: JSONValue] = [:]
        for spec in catalog.preferences {
            if let value = storedPreference(spec, in: defaults) ?? spec.defaultValue { preferences[spec.key] = value }
        }
        root[SettingsSection.preferences.rawValue] = .object(preferences)

        for (section, blob) in catalog.blobs {
            if let value = storedBlob(blob, in: defaults) ?? blob.defaultValue { root[section.rawValue] = value }
        }
        return try JSONValue.object(root).data()
    }

    private static func storedPreference(_ spec: PreferenceSpec, in defaults: UserDefaults) -> JSONValue? {
        if case .json = spec.kind {
            return defaults.data(forKey: spec.key).flatMap { try? JSONValue(data: $0) }
        }
        return defaults.object(forKey: spec.key).flatMap { JSONValue(propertyList: $0) }
    }

    private static func storedBlob(_ blob: BlobSpec, in defaults: UserDefaults) -> JSONValue? {
        switch blob.storage {
        case .jsonData: defaults.data(forKey: blob.defaultsKey).flatMap { try? JSONValue(data: $0) }
        case .propertyList: defaults.object(forKey: blob.defaultsKey).flatMap { JSONValue(propertyList: $0) }
        }
    }

    // MARK: Read

    /// Recognizes a settings file; nothing is applied yet.
    public static func read(_ data: Data) throws(SettingsArchiveError) -> SettingsContents {
        let root: [String: JSONValue]
        do {
            guard let object = try JSONValue(data: data).objectValue else { throw SettingsArchiveError.notSettingsFile }
            root = object
        } catch let error as SettingsArchiveError {
            throw error
        } catch {
            throw .notJSON
        }
        guard root["format"]?.stringValue == format,
              case .number(let version)? = root["formatVersion"], version >= 1, version.rounded() == version
        else { throw .notSettingsFile }

        var sections: [SettingsSection: JSONValue] = [:]
        var unknown: [String] = []
        for (key, value) in root where !headerKeys.contains(key) {
            if let section = SettingsSection(rawValue: key) { sections[section] = value } else { unknown.append(key) }
        }
        return SettingsContents(formatVersion: Int(version), appVersion: root["appVersion"]?.stringValue,
                                exported: root["exported"]?.stringValue, sections: sections,
                                unknownSections: unknown.sorted())
    }

    // MARK: Apply

    /// Applies the chosen sections to `defaults`. Everything is checked first and written after;
    /// entries that cannot be applied are skipped and reported, never guessed.
    public static func apply(_ contents: SettingsContents, sections chosen: Set<SettingsSection>,
                             to defaults: UserDefaults, catalog: SettingsCatalog) -> ImportReport {
        var report = ImportReport(newerFormat: contents.isNewer)
        var writes: [(key: String, value: Any?)] = []

        for name in contents.unknownSections {
            report.skipped.append(SkippedEntry(section: name, item: name, reason: .unknownSection))
        }
        for section in contents.availableSections where chosen.contains(section) {
            guard let value = contents.sections[section] else { continue }
            let skippedBefore = report.skipped.count
            var sectionWrites: [(key: String, value: Any?)]?
            switch section {
            case .keyboard:
                sectionWrites = keyboardWrites(value, catalog: catalog, report: &report)
            case .preferences:
                sectionWrites = preferenceWrites(value, catalog: catalog, report: &report)
            default:
                if let blob = catalog.blobs[section] {
                    sectionWrites = blobWrites(value, blob: blob, section: section, report: &report)
                } else {
                    report.skipped.append(SkippedEntry(section: section.rawValue, item: section.rawValue, reason: .unknownSection))
                }
            }
            guard let sectionWrites else { continue }
            writes += sectionWrites
            if !sectionWrites.isEmpty || report.skipped.count == skippedBefore { report.applied.append(section) }
        }

        for write in writes {
            if let value = write.value { defaults.set(value, forKey: write.key) } else { defaults.removeObject(forKey: write.key) }
        }
        return report
    }

    private static func keyboardWrites(_ value: JSONValue, catalog: SettingsCatalog,
                                       report: inout ImportReport) -> [(key: String, value: Any?)]? {
        let section = SettingsSection.keyboard.rawValue
        guard let object = value.objectValue else {
            report.skipped.append(SkippedEntry(section: section, item: section, reason: .wrongType))
            return nil
        }
        var writes: [(key: String, value: Any?)] = []
        if let schemeValue = object["scheme"] {
            if let scheme = schemeValue.stringValue.flatMap(KeyScheme.init(rawValue:)) {
                writes.append((catalog.schemeKey, scheme == .axolotl ? nil : scheme.rawValue))
            } else {
                report.skipped.append(SkippedEntry(section: section, item: "scheme", reason: .unknownScheme))
            }
        }
        if let bindingsValue = object["bindings"] {
            guard let entries = bindingsValue.objectValue else {
                report.skipped.append(SkippedEntry(section: section, item: "bindings", reason: .wrongType))
                return writes
            }
            var overrides: [String: [String]] = [:]
            for (name, chordsValue) in entries {
                guard let command = Command(rawValue: name) else {
                    report.skipped.append(SkippedEntry(section: section, item: name, reason: .unknownCommand))
                    continue
                }
                let texts = chordsValue.arrayValue?.map(\.stringValue)
                let chords = texts?.compactMap { $0.flatMap(KeyChord.init(storageString:)) }
                guard let texts, let chords, chords.count == texts.count else {
                    report.skipped.append(SkippedEntry(section: section, item: name, reason: .malformedChord))
                    continue
                }
                overrides[command.rawValue] = chords.map(\.storageString)
            }
            let data = overrides.isEmpty ? nil : try? JSONEncoder().encode(overrides)
            writes.append((catalog.bindingsKey, data))
        }
        return writes
    }

    private static func preferenceWrites(_ value: JSONValue, catalog: SettingsCatalog,
                                         report: inout ImportReport) -> [(key: String, value: Any?)]? {
        let section = SettingsSection.preferences.rawValue
        guard let object = value.objectValue else {
            report.skipped.append(SkippedEntry(section: section, item: section, reason: .wrongType))
            return nil
        }
        let specs = Dictionary(catalog.preferences.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var writes: [(key: String, value: Any?)] = []
        for (key, entry) in object.sorted(by: { $0.key < $1.key }) {
            guard let spec = specs[key] else {
                report.skipped.append(SkippedEntry(section: section, item: key, reason: .unknownKey))
                continue
            }
            switch validated(entry, kind: spec.kind) {
            case .success(let stored): writes.append((key, stored))
            case .failure(let reason): report.skipped.append(SkippedEntry(section: section, item: key, reason: reason))
            }
        }
        return writes
    }

    private static func validated(_ value: JSONValue, kind: PreferenceKind) -> Result<Any, SkipReason> {
        switch (kind, value) {
        case (.bool, .bool(let flag)):
            return .success(flag)
        case (.string(let allowed), .string(let text)):
            if let allowed, !allowed.contains(text) { return .failure(.outOfRange) }
            return .success(text)
        case (.number(let range), .number(let number)):
            return range.contains(number) ? .success(number) : .failure(.outOfRange)
        case (.stringArray, .array(let items)):
            let strings = items.compactMap(\.stringValue)
            return strings.count == items.count ? .success(strings) : .failure(.wrongType)
        case (.json(let validate), _):
            guard let data = try? value.data(), validate(data) else { return .failure(.invalidEntry) }
            return .success(data)
        default:
            return .failure(.wrongType)
        }
    }

    private static func blobWrites(_ value: JSONValue, blob: BlobSpec, section: SettingsSection,
                                   report: inout ImportReport) -> [(key: String, value: Any?)]? {
        let name = section.rawValue
        let accepted: JSONValue
        switch blob.shape {
        case .whole(let validate):
            guard let data = try? value.data(), validate(data) else {
                report.skipped.append(SkippedEntry(section: name, item: name, reason: .invalidEntry))
                return nil
            }
            accepted = value
        case .list(let validateElement):
            guard let items = value.arrayValue else {
                report.skipped.append(SkippedEntry(section: name, item: name, reason: .wrongType))
                return nil
            }
            var kept: [JSONValue] = []
            for (index, item) in items.enumerated() {
                if let data = try? item.data(), validateElement(data) {
                    kept.append(item)
                } else {
                    report.skipped.append(SkippedEntry(section: name, item: "\(name)[\(index)]", reason: .invalidEntry))
                }
            }
            accepted = .array(kept)
        }
        switch blob.storage {
        case .jsonData:
            guard let data = try? accepted.data() else { return nil }
            return [(blob.defaultsKey, data)]
        case .propertyList:
            guard let plist = accepted.propertyList else {
                report.skipped.append(SkippedEntry(section: name, item: name, reason: .invalidEntry))
                return nil
            }
            return [(blob.defaultsKey, plist)]
        }
    }
}
