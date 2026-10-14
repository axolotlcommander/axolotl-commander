// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

// Marking with the mouse (`specs/024-mouse-selection`). The rules live in `PanelModel` (PanelMouse.swift);
// the views find out what is under the pointer and the panel runs the gesture here.

extension MouseModifiers {
    /// ⌃ or ⌘ toggles, ⇧ makes a range.
    init(_ event: NSEvent) {
        let flags = event.modifierFlags
        self = []
        if !flags.isDisjoint(with: [.control, .command]) { insert(.toggle) }
        if flags.contains(.shift) { insert(.range) }
    }
}

/// What a left press hit in a panel's list.
struct MouseHit {
    /// The item under the pointer; nil for empty space.
    let index: Int?
    /// The pointer is on the item's icon or name text (where drag & drop starts).
    let onName: Bool
}

enum MousePressResult {
    /// The panel handled the press and the tracking that followed.
    case handled
    /// A plain press on a name: the view runs its usual drag & drop and double-click handling, then calls
    /// `mouseReleasedAfterPlainPress(at:)` when no drag began.
    case dragOrClick
}

/// Whether `local` (in `cell`'s coordinates) is on the cell's icon or on the text of its label.
@MainActor
func isOnIconOrText(_ local: NSPoint, in cell: NSView, icon: NSView?, label: NSTextField?) -> Bool {
    if let icon, icon.frame.insetBy(dx: -2, dy: -1).contains(local) { return true }
    guard let label else { return false }
    let width = label.attributedStringValue.size().width + 6
    let text = NSRect(x: label.frame.minX - 2, y: cell.bounds.minY, width: min(width, label.frame.width + 2),
                      height: cell.bounds.height)
    return text.contains(local)
}

/// The selection rectangle drawn while dragging over empty space.
final class RubberBandView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).setFill()
        bounds.fill()
        NSColor.selectedContentBackgroundColor.setStroke()
        let path = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
enum MouseTracking {
    static let dragThreshold: CGFloat = 3
    static let longPress: TimeInterval = 0.5

    /// After a left press in empty space: when the pointer moves before the release, draws a rectangle
    /// in `view` (the list, a document view inside a scroll view) and calls `update` with it until the
    /// release, scrolling while the pointer is outside. Returns false for a click without movement.
    static func rubberBand(in view: NSView, from event: NSEvent, begin: () -> Void, update: (NSRect) -> Void) -> Bool {
        guard let window = view.window else { return false }
        let start = view.convert(event.locationInWindow, from: nil)
        var band: RubberBandView?
        var lastDrag = event
        NSEvent.startPeriodicEvents(afterDelay: 0.1, withPeriod: 0.05)
        defer {
            NSEvent.stopPeriodicEvents()
            band?.removeFromSuperview()
        }
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp, .periodic], timeout: .infinity,
                           mode: .eventTracking) { next, stop in
            guard let next else { return }
            switch next.type {
            case .leftMouseUp:
                stop.pointee = true
                return
            case .periodic:
                guard band != nil else { return }
                view.autoscroll(with: lastDrag)
            default:
                lastDrag = next
            }
            let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if band == nil {
                guard hypot(point.x - start.x, point.y - start.y) > dragThreshold else { return }
                let added = RubberBandView()
                view.addSubview(added)
                band = added
                begin()
            }
            let rect = NSRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y))
            band?.frame = rect
            update(rect)
        }
        return band != nil
    }

    enum RightPress { case click, longPress, drag }

    /// After a right press (the Norton-style mode): a release before half a second is a click, holding
    /// still that long a long press, moving a drag; `dragged` gets every pointer position of a drag (in
    /// `view`'s coordinates), also while the list scrolls with the pointer outside.
    static func rightPress(in view: NSView, from event: NSEvent, dragged: (NSPoint) -> Void) -> RightPress {
        guard let window = view.window else { return .click }
        let start = view.convert(event.locationInWindow, from: nil)
        let began = Date()
        var result = RightPress.click
        var lastDrag = event
        NSEvent.startPeriodicEvents(afterDelay: 0.05, withPeriod: 0.05)
        defer { NSEvent.stopPeriodicEvents() }
        window.trackEvents(matching: [.rightMouseDragged, .rightMouseUp, .periodic], timeout: .infinity,
                           mode: .eventTracking) { next, stop in
            guard let next else { return }
            let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            switch next.type {
            case .rightMouseUp:
                stop.pointee = true
            case .periodic:
                if result == .drag {
                    view.autoscroll(with: lastDrag)
                    dragged(view.convert(window.mouseLocationOutsideOfEventStream, from: nil))
                } else if Date().timeIntervalSince(began) >= longPress {
                    result = .longPress
                    stop.pointee = true
                }
            default:
                lastDrag = next
                if result == .click, hypot(point.x - start.x, point.y - start.y) > dragThreshold { result = .drag }
                if result == .drag { dragged(point) }
            }
        }
        return result
    }
}

extension PanelViewController {
    var mouseSelectionMode: MouseSelectionMode { PanelBehavior(defaults: .standard).mouseSelectionMode }

    /// A left press in the list (`view`, the table or the Brief grid). `covered` gives the items under a
    /// rectangle in the list's coordinates.
    func mousePressed(_ event: NSEvent, hit: MouseHit, in view: NSView, covered: (NSRect) -> IndexSet) -> MousePressResult {
        let mode = mouseSelectionMode
        let modifiers = MouseModifiers(event)
        if let index = hit.index, hit.onName {
            let plain = model.mousePressed(at: index, modifiers: modifiers, mode: mode)
            marksChanged()
            return plain ? .dragOrClick : .handled
        }
        // Empty space, or a row outside its icon and name: a drag draws the rectangle.
        var band: RubberBand?
        let dragged = MouseTracking.rubberBand(in: view, from: event, begin: {
            band = model.beginRubberBand(modifiers: modifiers)
            marksChanged()
        }, update: { rect in
            guard band != nil else { return }
            model.updateRubberBand(&band!, covering: covered(rect))
            marksChanged()
        })
        if dragged { return .handled }
        if let index = hit.index {
            // A click in a row's empty part is a click on the row.
            if model.mousePressed(at: index, modifiers: modifiers, mode: mode) {
                model.mouseReleased(at: index, mode: mode)
                if event.clickCount == 2 { perform(.open) }
            }
        } else {
            model.mousePressedOnEmptySpace(mode: mode)
        }
        marksChanged()
        return .handled
    }

    /// The release of a plain press on a name that did not become a drag.
    func mouseReleasedAfterPlainPress(at index: Int) {
        model.mouseReleased(at: index, mode: mouseSelectionMode)
        marksChanged()
    }

    /// A right press in the list. Returns false when the view should do its default (the context menu):
    /// always unless "Right mouse button marks" is on, and for ⌃ + right click.
    func rightMousePressed(_ event: NSEvent, index: Int?, in view: NSView, itemAt: (NSPoint) -> Int?) -> Bool {
        guard mouseSelectionMode == .rightButtonMarks, !event.modifierFlags.contains(.control) else { return false }
        view.window?.makeFirstResponder(listView)
        var marking: Bool?
        var last = index
        let press = MouseTracking.rightPress(in: view, from: event) { point in
            guard let row = itemAt(point) else { return }
            if marking == nil {
                let first = last ?? row
                marking = model.beginRightDrag(at: first)
                last = first
            }
            if let marking, let from = last { model.rightDrag(from: from, to: row, marking: marking) }
            last = row
            marksChanged()
        }
        switch press {
        case .click:
            if let index {
                model.toggleMarkByRightClick(at: index)
                marksChanged()
            }
        case .longPress:
            if let menu = contextMenu(at: index) { NSMenu.popUpContextMenu(menu, with: event, for: view) }
        case .drag:
            break
        }
        return true
    }
}
