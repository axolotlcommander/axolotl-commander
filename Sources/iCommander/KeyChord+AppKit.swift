// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

import AppKit
import CommanderCore

extension KeyChord {
    /// Translates a key-down event. Characters for chords with ⌘ or ⌃ are read
    /// through the Command-key layout so shortcuts survive non-US layouts
    /// (Czech top row types `+ěšč…` but ⌃1 must still be ⌃1).
    init?(event: NSEvent) {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags
        var mods: Modifiers = []
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }

        guard let raw = event.charactersIgnoringModifiers?.unicodeScalars.first else { return nil }
        let numpad = flags.contains(.numericPad)

        let key: Key
        switch Int(raw.value) {
        case NSF1FunctionKey...NSF20FunctionKey: key = .function(Int(raw.value) - NSF1FunctionKey + 1)
        case NSUpArrowFunctionKey: key = .up
        case NSDownArrowFunctionKey: key = .down
        case NSLeftArrowFunctionKey: key = .left
        case NSRightArrowFunctionKey: key = .right
        case NSHomeFunctionKey: key = .home
        case NSEndFunctionKey: key = .end
        case NSPageUpFunctionKey: key = .pageUp
        case NSPageDownFunctionKey: key = .pageDown
        case NSDeleteFunctionKey: key = .forwardDelete
        case NSInsertFunctionKey, NSHelpFunctionKey: key = .insert
        case 0x09, 0x19: key = .tab              // 0x19 = back-tab with Shift
        case 0x0D: key = .enter
        case 0x03: key = numpad ? .numEnter : .enter
        case 0x1B: key = .escape
        case 0x7F, 0x08: key = .backspace
        case 0x20: key = .space
        default:
            if numpad {
                switch raw {
                case "+": key = .numPlus
                case "-": key = .numMinus
                case "*": key = .numStar
                case "/": key = .numSlash
                default: key = KeyChord.characterKey(event: event, mods: mods) ?? .space
                }
            } else {
                guard let k = KeyChord.characterKey(event: event, mods: mods) else { return nil }
                key = k
            }
        }
        self.init(key, mods)
    }

    private static func characterKey(event: NSEvent, mods: Modifiers) -> Key? {
        let text: String?
        if !mods.isDisjoint(with: [.command, .control, .option]) {
            text = event.characters(byApplyingModifiers: .command)
        } else {
            text = event.charactersIgnoringModifiers
        }
        guard let c = text?.lowercased().first else { return nil }
        return .character(c)
    }

    /// Key equivalent string and mask for NSMenuItem.
    var menuKeyEquivalent: (String, NSEvent.ModifierFlags)? {
        let s: String
        switch key {
        case .function(let n): s = String(UnicodeScalar(UInt32(NSF1FunctionKey + n - 1))!)
        case .character(let c): s = String(c)
        case .up: s = String(UnicodeScalar(UInt32(NSUpArrowFunctionKey))!)
        case .down: s = String(UnicodeScalar(UInt32(NSDownArrowFunctionKey))!)
        case .left: s = String(UnicodeScalar(UInt32(NSLeftArrowFunctionKey))!)
        case .right: s = String(UnicodeScalar(UInt32(NSRightArrowFunctionKey))!)
        case .pageUp: s = String(UnicodeScalar(UInt32(NSPageUpFunctionKey))!)
        case .pageDown: s = String(UnicodeScalar(UInt32(NSPageDownFunctionKey))!)
        case .home: s = String(UnicodeScalar(UInt32(NSHomeFunctionKey))!)
        case .end: s = String(UnicodeScalar(UInt32(NSEndFunctionKey))!)
        case .forwardDelete: s = String(UnicodeScalar(UInt32(NSDeleteFunctionKey))!)
        case .backspace: s = "\u{8}"
        case .tab: s = "\t"
        case .enter: s = "\r"
        case .space: s = " "
        case .escape: s = "\u{1b}"
        case .insert, .numPlus, .numMinus, .numStar, .numSlash, .numEnter: return nil
        }
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { mask.insert(.control) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.command) { mask.insert(.command) }
        return (s, mask)
    }
}
