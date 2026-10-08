// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

/// The row of F1–F12 buttons at the bottom of the main window. What each button shows comes
/// from the key map, so the bar always names the command the key press runs.
public enum FunctionKeyBar {
    public static let count = 12

    /// The command each of F1…F12 runs with exactly `modifiers` held, in order; nil = empty.
    public static func slots(in map: KeyMap, modifiers: KeyChord.Modifiers) -> [Command?] {
        (1...count).map { map.command(for: KeyChord(.function($0), modifiers)) }
    }
}

extension CommandRegistry {
    /// English short name for the function key bar when the title is too long; nil = use the title.
    public static func shortTitle(_ command: Command) -> String? { shortTitles[command] }

    private static let shortTitles: [Command: String] = [
        .help: "Help", .delete: "Trash", .deletePermanently: "Delete", .makeDirectory: "Folder",
        .userMenu: "Menu", .revealInFinder: "Finder", .changeDirectory: "Go to", .contextMenu: "Menu",
        .leftVolumeMenu: "Left", .rightVolumeMenu: "Right", .loadSelection: "Apply",
        .saveSelection: "Remember", .calculateSizes: "Sizes", .occupiedSpace: "Map",
        .workingDirectories: "Folders", .sortByName: "Name", .sortByExtension: "Ext",
        .sortByDate: "Date", .sortBySize: "Size", .comparePanels: "Compare", .maximizePanel: "Maximize",
        .changeCase: "Case", .find: "Find", .quickLook: "Look",
    ]
}
