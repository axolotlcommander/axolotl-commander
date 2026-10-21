// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

public import Foundation

/// Panel behavior options from Settings → Panels (`specs/011-panel-behavior-options`).
/// The keys are part of the settings file and are never renamed.
public struct PanelBehavior: Equatable, Sendable {
    public static let spaceKey = "panel.spaceMovesDown"
    public static let typingKey = "panel.typingToCommandLine"
    public static let arrowsKey = "panel.arrowsTargetPointedPanel"
    public static let volumesKey = "panel.volumeButtonsFollow"
    public static let rightButtonKey = "panel.rightButtonMarks"
    public static let alwaysShowTabsKey = "panel.alwaysShowTabs"
    public static let tabsNextToCurrentKey = "panel.newTabsNextToCurrent"
    public static let clickToRenameKey = "panel.clickToRename"
    public static let tabLookKey = "panel.tabLook"

    /// Space marks the item and moves the cursor down (off: the cursor stays).
    public var spaceMovesDown = true
    /// Characters typed in a panel go to the command line; ⌥ + character starts quick search.
    public var typingToCommandLine = false
    /// Open in Left / Right Panel change the panel the arrow points to.
    public var arrowsTargetPointedPanel = false
    /// A volume button opens the other panel's folder or the last folder used on the volume.
    public var volumeButtonsFollow = false
    /// The right mouse button marks items, a long right press opens the context menu
    /// (`specs/024-mouse-selection`).
    public var rightButtonMarks = false
    /// The tab bar shows even for a single tab (`specs/028-tab-locking`); off: it hides with one tab.
    public var alwaysShowTabs = false
    /// New tabs open right after the active tab; off: after the last tab.
    public var newTabsNextToCurrent = false
    /// A slow click on the name of the cursor item renames it in place (`specs/035-click-rename`).
    public var clickToRename = true
    /// How the tabs are drawn (`specs/036-tab-reorder-look`).
    public var tabLook = TabLook.standard

    public var mouseSelectionMode: MouseSelectionMode { rightButtonMarks ? .rightButtonMarks : .standard }

    public init() {}

    public init(defaults: UserDefaults) {
        func bool(_ key: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
        }
        spaceMovesDown = bool(Self.spaceKey, true)
        typingToCommandLine = bool(Self.typingKey, false)
        arrowsTargetPointedPanel = bool(Self.arrowsKey, false)
        volumeButtonsFollow = bool(Self.volumesKey, false)
        rightButtonMarks = bool(Self.rightButtonKey, false)
        alwaysShowTabs = bool(Self.alwaysShowTabsKey, false)
        newTabsNextToCurrent = bool(Self.tabsNextToCurrentKey, false)
        clickToRename = bool(Self.clickToRenameKey, true)
        tabLook = defaults.string(forKey: Self.tabLookKey).flatMap(TabLook.init(rawValue:)) ?? .standard
    }
}

/// Settings → Panels → Tab look: Standard (light fills) or Prominent (separated tabs, the active panel's
/// active tab in the accent color).
public enum TabLook: String, CaseIterable, Sendable {
    case standard, prominent
}

extension Side {
    public var other: Side { self == .left ? .right : .left }
}

/// Where a key typed in a panel goes while "Typing goes to the command line" is on.
public enum PanelTyping {
    public enum Action: Equatable, Sendable {
        /// Today's handling (commands, movement, quick search).
        case none
        case append(String)
        case deleteLast
        case clear
        case run
        case startQuickSearch(String)
    }

    /// - Parameters:
    ///   - text: what the key types (`NSEvent.characters`).
    ///   - baseText: what the key types without ⌥, for ⌥ + character.
    ///   - isBound: the chord runs a command or a user menu item. It only matters for ⌥ + character:
    ///     plain characters never reached commands (quick search took them first), and Return,
    ///     Backspace, Esc and Space act on a line with text by design.
    public static func route(key: KeyChord.Key, modifiers: KeyChord.Modifiers, text: String?, baseText: String?,
                             lineIsEmpty: Bool, quickSearchActive: Bool, isBound: Bool) -> Action {
        if quickSearchActive { return .none }
        if case .character = key {
            if modifiers.isSubset(of: .shift), let text, !text.isEmpty { return .append(text) }
            if !isBound, modifiers.contains(.option), modifiers.isDisjoint(with: [.command, .control]),
               let baseText, !baseText.isEmpty {
                return .startQuickSearch(baseText)
            }
            return .none
        }
        guard !lineIsEmpty, modifiers.isEmpty else { return .none }
        switch key {
        case .enter, .numEnter: return .run
        case .backspace: return .deleteLast
        case .escape: return .clear
        case .space: return .append(" ")
        default: return .none
        }
    }
}

/// Open in Left Panel / Open in Right Panel: which panel gives the item, which opens it and which
/// keeps the focus.
public enum OpenInPanel {
    public struct Plan: Equatable, Sendable {
        public var source: Side
        public var target: Side
        public var focus: Side
        public init(source: Side, target: Side, focus: Side) {
            self.source = source
            self.target = target
            self.focus = focus
        }
    }

    /// - Parameter command: the side the command names (Open in Left Panel = `.left`).
    /// - Parameter classic: the arrow names the panel that changes; the other panel is the source.
    public static func plan(target command: Side, active: Side, classic: Bool) -> Plan {
        if classic { return Plan(source: command.other, target: command, focus: active) }
        // Always into the other panel; the arrow pointing at it also moves the focus there.
        return Plan(source: active, target: active.other, focus: command == active.other ? active.other : active)
    }
}

/// Where a volume button takes a panel while "Volume buttons open the other panel's folder or the
/// last folder used there" is on.
public enum VolumeChoice {
    public enum Target: Equatable, Sendable {
        /// The panel is on that volume already (and the other panel is not): it stays and reads its
        /// folder again.
        case refresh
        case open(URL)
    }

    /// - Parameters:
    ///   - panelVolume: the volume this panel shows a folder on; nil for an archive, a server or Network.
    ///   - otherFolder / otherVolume: the other panel's folder and its volume, nil in the same cases.
    ///   - remembered: the last folder this panel showed on `volume`.
    public static func target(volume: URL, panelVolume: URL?, otherFolder: URL?, otherVolume: URL?,
                              remembered: URL?, exists: (URL) -> Bool) -> Target {
        if let otherFolder, let otherVolume, same(otherVolume, volume) { return .open(otherFolder) }
        if let panelVolume, same(panelVolume, volume) { return .refresh }
        if let remembered, exists(remembered) { return .open(remembered) }
        return .open(volume)
    }

    static func same(_ a: URL, _ b: URL) -> Bool { key(a) == key(b) }

    static func key(_ url: URL) -> String {
        var path = url.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

/// The last folder a panel showed on each volume, in memory only.
public struct VolumePlaces: Sendable {
    private var folders: [String: URL] = [:]

    public init() {}

    public mutating func visit(_ folder: URL, volume: URL) {
        folders[VolumeChoice.key(volume)] = folder
    }

    public func folder(on volume: URL) -> URL? {
        folders[VolumeChoice.key(volume)]
    }
}
