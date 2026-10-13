// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Arrow keys in alerts and sheets move the default button, so Return presses the chosen one; Esc
/// keeps pressing the button it pressed before. Arrows stay with text fields, lists and pop-ups.
@MainActor
enum DialogKeys {
    private static var monitor: Any?
    /// The key equivalent each moved button had, to give it back when the default moves on.
    private static let originals = NSMapTable<NSButton, NSString>.weakToStrongObjects()

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
    }

    private static func handle(_ event: NSEvent) -> Bool {
        guard let window = event.window, window is NSPanel || window.isSheet,
              let content = window.contentView,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              takesArrows(window.firstResponder, in: window) else { return false }
        switch event.keyCode {
        case 123, 126: return move(in: content, window: window, step: -1)  // ← ↑
        case 124, 125: return move(in: content, window: window, step: 1)   // → ↓
        case 53: return pressMovedCancel(in: content)                      // Esc
        default: return false
        }
    }

    /// Only when nothing that uses arrows itself has the focus.
    private static func takesArrows(_ responder: NSResponder?, in window: NSWindow) -> Bool {
        guard let responder, responder !== window, responder !== window.contentView else { return true }
        return responder is NSButton && !(responder is NSPopUpButton)
    }

    private static func pushButtons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { sub -> [NSButton] in
            if let button = sub as? NSButton, !(button is NSPopUpButton) {
                let usable = button.bezelStyle == .push && button.isEnabled && !button.isHiddenOrHasHiddenAncestor
                return usable && !button.title.isEmpty ? [button] : []
            }
            return pushButtons(in: sub)
        }
    }

    private static func move(in content: NSView, window: NSWindow, step: Int) -> Bool {
        let buttons = pushButtons(in: content)
        guard buttons.count > 1 else { return false }
        let current = buttons.firstIndex { $0.keyEquivalent == "\r" }
        guard let target = DialogButtons.next(frames: buttons.map { $0.convert($0.bounds, to: nil) },
                                              current: current, step: step) else { return false }
        if target != current { makeDefault(buttons[target], replacing: current.map { buttons[$0] }, in: window) }
        return true
    }

    private static func makeDefault(_ button: NSButton, replacing old: NSButton?, in window: NSWindow) {
        for each in [old, button].compactMap({ $0 }) where originals.object(forKey: each) == nil {
            originals.setObject(each.keyEquivalent as NSString, forKey: each)
        }
        if let old {
            let own = originals.object(forKey: old).map { $0 as String } ?? ""
            old.keyEquivalent = own == "\r" ? "" : own
            old.needsDisplay = true
        }
        button.keyEquivalent = "\r"
        window.defaultButtonCell = button.cell as? NSButtonCell
        button.needsDisplay = true
    }

    /// The Esc button lost its key while it was the default: Esc still presses it.
    private static func pressMovedCancel(in content: NSView) -> Bool {
        guard let cancel = pushButtons(in: content).first(where: {
            originals.object(forKey: $0) == "\u{1b}" && $0.keyEquivalent != "\u{1b}"
        }) else { return false }
        cancel.performClick(nil)
        return true
    }
}
