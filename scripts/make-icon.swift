// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The iCommander Authors

// Renders the app icon: two commander panels on a rounded macOS-style tile.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// Tile (Big Sur+ grid: 824 pt body inside 1024 canvas)
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.set()
NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.18, blue: 0.42, alpha: 1),
                    NSColor(srgbRed: 0.16, green: 0.42, blue: 0.86, alpha: 1)])!
    .draw(in: tilePath, angle: 90)
ctx.restoreGState()

// Two panels
func panel(_ rect: NSRect, active: Bool) {
    let p = NSBezierPath(roundedRect: rect, xRadius: 38, yRadius: 38)
    NSColor.white.withAlphaComponent(active ? 0.96 : 0.80).setFill()
    p.fill()
    // header bar
    let header = NSRect(x: rect.minX, y: rect.maxY - 70, width: rect.width, height: 70)
    let hp = NSBezierPath(roundedRect: header, xRadius: 38, yRadius: 38)
    hp.append(NSBezierPath(rect: NSRect(x: header.minX, y: header.minY, width: header.width, height: 38)))
    (active ? NSColor(srgbRed: 1.0, green: 0.62, blue: 0.10, alpha: 1)
            : NSColor(srgbRed: 0.55, green: 0.62, blue: 0.75, alpha: 1)).setFill()
    hp.fill()
    // rows
    for i in 0..<6 {
        let y = rect.maxY - 120 - CGFloat(i) * 72
        let row = NSRect(x: rect.minX + 34, y: y - 22, width: rect.width - 68, height: 30)
        let isCursor = active && i == 2
        if isCursor {
            NSColor(srgbRed: 0.16, green: 0.42, blue: 0.86, alpha: 0.9).setFill()
            NSBezierPath(roundedRect: row.insetBy(dx: -14, dy: -14), xRadius: 12, yRadius: 12).fill()
        }
        (isCursor ? NSColor.white : NSColor(srgbRed: 0.25, green: 0.30, blue: 0.40, alpha: 0.55)).setFill()
        let w = row.width * [0.85, 0.6, 0.75, 0.5, 0.7, 0.55][i]
        NSBezierPath(roundedRect: NSRect(x: row.minX, y: row.minY, width: w, height: row.height),
                     xRadius: 15, yRadius: 15).fill()
    }
}
panel(NSRect(x: 160, y: 190, width: 335, height: 640), active: true)
panel(NSRect(x: 529, y: 190, width: 335, height: 640), active: false)

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
