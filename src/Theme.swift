//
//  Theme.swift
//  Disk Inventory Xs
//
//  The visual design language of the app ("Holo Glass"): a dark, deep-space
//  canvas, luminous cyan accent, Liquid Glass chrome and neon cushions. Every
//  color, font and accessibility switch the UI code needs lives here, so the
//  look can be tuned in one place. See "Visual design" in CLAUDE.md.
//
//  GPL v3
//

import Cocoa

enum Theme {

    // MARK: - Colors

    /// The deep-space canvas behind the treemap and the window chrome (#070A12).
    static let space = NSColor(srgbRed: 0.027, green: 0.039, blue: 0.071, alpha: 1)
    /// A slightly lifted space tone for panels sitting on the canvas (#0D1220).
    static let spaceRaised = NSColor(srgbRed: 0.051, green: 0.071, blue: 0.125, alpha: 1)
    /// The one accent of the UI: a luminous cyan (#00E5FF).
    static let accent = NSColor(srgbRed: 0, green: 0.898, blue: 1, alpha: 1)
    /// Hairline used for panel borders and separators.
    static let hairline = NSColor(white: 1, alpha: 0.10)
    /// Free disk space: an empty, dim blue void rather than a bright patch.
    static let freeSpace = NSColor(srgbRed: 0.10, green: 0.14, blue: 0.24, alpha: 1)
    /// What the cushions of kinds out of focus are colored with: dark slate, so the focused
    /// kind is the only thing that shines.
    static let dimmedKind = NSColor(srgbRed: 0.22, green: 0.24, blue: 0.29, alpha: 1)
    /// Space used by things outside the scanned folder: a dim violet.
    static let otherSpace = NSColor(srgbRed: 0.20, green: 0.12, blue: 0.30, alpha: 1)

    /// What a cushion of the given base color looks like on average (the shader
    /// brightens by 2.5 / 1.8 and shades down), for swatches that stand for it.
    static func cushionDisplayColor(_ cushionColor: NSColor) -> NSColor {
        let c = cushionColor.usingColorSpace(.sRGB) ?? cushionColor
        let gain: CGFloat = 2.5 / 1.8 * 0.85
        return NSColor(srgbRed: min(c.redComponent * gain, 1), green: min(c.greenComponent * gain, 1),
                       blue: min(c.blueComponent * gain, 1), alpha: 1)
    }

    // MARK: - Accessibility

    /// Reduce Transparency: glass must turn into plain opaque surfaces.
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// Increase Contrast: no glow, thicker and fully opaque outlines.
    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    /// Posted when the user flips Reduce Transparency / Increase Contrast / ...
    static let accessibilityOptionsChanged = NSWorkspace.accessibilityDisplayOptionsDidChangeNotification

    // MARK: - Fonts

    /// Numerals that keep their width, so sizes line up and do not jitter.
    static func numericFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    // MARK: - Setup

    /// The whole app is dark: it is a viewport onto a dark canvas, and the neon
    /// palette is tuned for it. Called once at launch.
    static func install() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    // MARK: - Toolbar images

    /// An SF Symbol for a toolbar item, or nil if the name is not a symbol.
    static func symbolImage(named name: String, description: String?) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: description)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .medium))
    }
}
