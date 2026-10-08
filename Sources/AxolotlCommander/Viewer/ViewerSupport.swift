// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 The Axolotl Commander Authors

import AppKit
import CommanderCore

/// Text colors of the syntax highlighting, one light and one dark shade per token kind
/// (the same palette as code blocks in the Markdown preview).
enum SyntaxColors {
    private static let colors: [SyntaxTokenKind: NSColor] = [
        .keyword: dynamic(0xCF222E, 0xFF7B72),
        .type: dynamic(0x8250DF, 0xD2A8FF),
        .string: dynamic(0x0A3069, 0xA5D6FF),
        .number: dynamic(0x0550AE, 0x79C0FF),
        .comment: dynamic(0x6E7781, 0x8B949E),
        .preprocessor: dynamic(0x953800, 0xFFA657),
        .tag: dynamic(0x116329, 0x7EE787),
        .attribute: dynamic(0x0550AE, 0x79C0FF),
        .variable: dynamic(0x953800, 0xFFA657),
    ]

    static func color(for kind: SyntaxTokenKind) -> NSColor { colors[kind] ?? .textColor }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
    }
}

/// Format and quality controls under the save panel of "Save Image As…".
final class ImageSaveOptions: NSObject {
    let view: NSView
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let slider = NSSlider(value: 85, minValue: 10, maxValue: 100, target: nil, action: nil)
    private let qualityLabel = NSTextField(labelWithString: String(localized: "Quality:"))
    private let qualityValue = NSTextField(labelWithString: "")
    private(set) var format: ImageFormat
    var onChange: ((ImageFormat) -> Void)?

    var quality: Double? { format.hasQuality ? slider.doubleValue / 100 : nil }

    init(format: ImageFormat) {
        self.format = format
        let formatLabel = NSTextField(labelWithString: String(localized: "Format:"))
        for item in ImageFormat.allCases { popup.addItem(withTitle: item.title) }
        popup.selectItem(at: ImageFormat.allCases.firstIndex(of: format) ?? 0)
        slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        qualityValue.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        qualityValue.widthAnchor.constraint(equalToConstant: 44).isActive = true
        let stack = NSStackView(views: [formatLabel, popup, qualityLabel, slider, qualityValue])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        view = stack
        super.init()
        popup.target = self
        popup.action = #selector(formatChanged)
        slider.target = self
        slider.action = #selector(qualityChanged)
        update()
    }

    @objc private func formatChanged() {
        format = ImageFormat.allCases[max(popup.indexOfSelectedItem, 0)]
        update()
        onChange?(format)
    }

    @objc private func qualityChanged() { update() }

    private func update() {
        for control in [qualityLabel, slider, qualityValue] as [NSView] { control.isHidden = !format.hasQuality }
        qualityValue.stringValue = "\(Int(slider.doubleValue)) %"
    }
}
