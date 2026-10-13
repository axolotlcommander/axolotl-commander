// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors
//
// Drives the screenshot copy of the app (scripts/screenshot/make-screenshot.sh):
//   drive.swift wait <pid>                 waits until the app is frontmost with its main window
//   drive.swift frame <pid> <width> <height>  moves the main window to the top left and sizes it
//   drive.swift keys <pid> <key>...        types keys, e.g. down*2 space opt+cmd+down
//   drive.swift window <pid>               prints the main window's id for screencapture -l
// Keys go only to that app: every key checks that it is still frontmost, otherwise the tool stops.

import AppKit
import ApplicationServices

let args = CommandLine.arguments
let pid: pid_t = {
    guard args.count >= 3, let pid = pid_t(args[2]) else {
        FileHandle.standardError.write(Data("usage: drive.swift wait|frame|keys|window <pid> ...\n".utf8))
        exit(64)
    }
    return pid
}()

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("drive: \(message)\n".utf8))
    exit(1)
}

var isFrontmost: Bool { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }

/// The app's largest normal window on screen.
func mainWindow() -> (id: CGWindowID, bounds: CGRect)? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { info -> (CGWindowID, CGRect)? in
        guard info[kCGWindowOwnerPID as String] as? pid_t == pid, info[kCGWindowLayer as String] as? Int == 0,
              let id = info[kCGWindowNumber as String] as? CGWindowID,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return (id, rect)
    }.max { $0.1.width * $0.1.height < $1.1.width * $1.1.height }
}

let keyCodes: [String: CGKeyCode] = [
    "return": 36, "tab": 48, "space": 49, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
]
let modifiers: [String: CGEventFlags] = ["cmd": .maskCommand, "shift": .maskShift, "opt": .maskAlternate, "ctrl": .maskControl]

func press(_ token: String) {
    let (name, count) = token.split(separator: "*").map(String.init).splitCount
    var parts = name.split(separator: "+").map(String.init)
    guard let code = keyCodes[parts.removeLast()] else { fail("unknown key \(token)") }
    var flags: CGEventFlags = []
    for part in parts {
        guard let flag = modifiers[part] else { fail("unknown modifier \(part)") }
        flags.insert(flag)
    }
    let source = CGEventSource(stateID: .hidSystemState)
    for _ in 0..<count {
        guard isFrontmost else { fail("the app is no longer frontmost; stopped") }
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)!
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)!
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(40_000)
        up.post(tap: .cghidEventTap)
        // Release every modifier, so none stays held.
        let clear = CGEvent(source: source)!
        clear.type = .flagsChanged
        clear.flags = []
        clear.post(tap: .cghidEventTap)
        usleep(250_000)
    }
}

extension Array where Element == String {
    var splitCount: (String, Int) { (self[0], count > 1 ? Int(self[1]) ?? 1 : 1) }
}

switch args[1] {
case "wait":
    for _ in 0..<100 {
        if isFrontmost, mainWindow() != nil { exit(0) }
        usleep(100_000)
    }
    fail("the app did not come to the front with a window")
case "frame":
    guard args.count == 5, let width = Double(args[3]), let height = Double(args[4]) else { fail("frame <pid> <width> <height>") }
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value) == .success, let value else {
        fail("no main window (does the terminal have Accessibility access?)")
    }
    let window = value as! AXUIElement
    let visible = NSScreen.main.map { $0.visibleFrame } ?? .zero
    let full = NSScreen.main.map { $0.frame } ?? .zero
    var origin = CGPoint(x: visible.minX + 40, y: full.maxY - visible.maxY + 40)
    var size = CGSize(width: width, height: height)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
case "keys":
    for token in args.dropFirst(3) { press(token) }
case "window":
    guard let window = mainWindow() else { fail("no window") }
    print(window.id)
default:
    fail("unknown command \(args[1])")
}
