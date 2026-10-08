// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

// Renders the app icon: the outline of an axolotl seen from above (head with three gill
// fronds per side, body, four legs, curved tail) drawn as one continuous line on a rounded
// macOS-style tile whose two halves hint at the two commander panels.
// Usage: swift scripts/make-icon.swift <output.png>
// (scripts/make-icon.sh turns it into Resources/AppIcon.icns and docs/images/icon.png).
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let line = rgb(246, 150, 172)
let lineWidth: CGFloat = 17

// MARK: Background: tile with a lighter left ("active") and a darker right panel

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

func drawBackground() {
    let left = CGGradient(colorsSpace: nil, colors: [rgb(16, 46, 62), rgb(28, 88, 104)] as CFArray, locations: nil)!
    let right = CGGradient(colorsSpace: nil, colors: [rgb(12, 36, 50), rgb(22, 72, 88)] as CFArray, locations: nil)!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: 0, y: 0, width: size / 2, height: size))
    ctx.drawLinearGradient(left, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.clip(to: CGRect(x: size / 2, y: 0, width: size / 2, height: size))
    ctx.drawLinearGradient(right, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])
    ctx.restoreGState()
}

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(rgb(16, 46, 62))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
drawBackground()

// MARK: Shapes (areas); their union is outlined

/// A cubic curve from `a` to `d`, widening linearly from `w0` to `w1`, with round ends.
func tapered(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ w0: CGFloat, _ w1: CGFloat) -> [CGPath] {
    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x,
                       y: u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y)
    }
    let n = 48
    var left: [CGPoint] = [], right: [CGPoint] = []
    for i in 0...n {
        let t = CGFloat(i) / CGFloat(n)
        let p = point(t), q = point(min(1, t + 0.01)), o = point(max(0, t - 0.01))
        var tx = q.x - o.x, ty = q.y - o.y
        let len = max(hypot(tx, ty), 0.0001)
        tx /= len; ty /= len
        let w = (w0 + (w1 - w0) * t) / 2
        left.append(CGPoint(x: p.x - ty * w, y: p.y + tx * w))
        right.append(CGPoint(x: p.x + ty * w, y: p.y - tx * w))
    }
    let body = CGMutablePath()
    body.addLines(between: left + right.reversed())
    body.closeSubpath()
    return [body,
            CGPath(ellipseIn: CGRect(x: a.x - w0 / 2, y: a.y - w0 / 2, width: w0, height: w0), transform: nil),
            CGPath(ellipseIn: CGRect(x: d.x - w1 / 2, y: d.y - w1 / 2, width: w1, height: w1), transform: nil)]
}

func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

var parts: [CGPath] = []
let cx: CGFloat = 512

// Head
parts.append(CGPath(ellipseIn: CGRect(x: cx - 160, y: 600, width: 320, height: 240), transform: nil))
// Body
parts += tapered(p(cx, 640), p(cx, 560), p(cx - 4, 460), p(cx + 10, 380), 160, 120)
// Tail: sweeps down and curls to the right
parts += tapered(p(cx + 8, 450), p(cx + 22, 290), p(cx + 150, 170), p(cx + 280, 235), 118, 10)

for s in [-1.0, 1.0] as [CGFloat] {
    // Gills: three fronds from the back corners of the head, fanning outwards
    let root = p(cx + s * 130, 700)
    parts += tapered(root, p(cx + s * 175, 770), p(cx + s * 205, 815), p(cx + s * 225, 845), 34, 18)
    parts += tapered(root, p(cx + s * 195, 735), p(cx + s * 250, 760), p(cx + s * 285, 775), 34, 18)
    parts += tapered(root, p(cx + s * 200, 700), p(cx + s * 255, 690), p(cx + s * 290, 680), 34, 18)
    // Front legs: out and forwards
    parts += tapered(p(cx + s * 55, 560), p(cx + s * 110, 555), p(cx + s * 150, 548), p(cx + s * 182, 580), 38, 30)
    // Back legs: out and backwards
    parts += tapered(p(cx + s * 48, 430), p(cx + s * 100, 420), p(cx + s * 140, 400), p(cx + s * 168, 362), 38, 30)
}

// MARK: Outline of the union: stroke every part, then refill all interiors with the background

ctx.setStrokeColor(line)
ctx.setLineWidth(lineWidth * 2)
ctx.setLineJoin(.round)
for part in parts {
    ctx.addPath(part)
    ctx.strokePath()
}
for part in parts {
    ctx.saveGState()
    ctx.addPath(part)
    ctx.clip()
    drawBackground()
    ctx.restoreGState()
}

// Eyes
ctx.setFillColor(line)
for s in [-1.0, 1.0] as [CGFloat] {
    ctx.fillEllipse(in: CGRect(x: cx + s * 72 - 16, y: 712, width: 32, height: 32))
}
ctx.restoreGState()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
