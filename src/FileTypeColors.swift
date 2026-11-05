//
//  FileTypeColors.swift
//  Disk Inventory Xs
//
//  Swift port of FileTypeColors.{h,m}. Hands out a stable color per file
//  kind: first from a fixed neon palette, then dim slate greys once the palette
//  is exhausted. The neon colors are normalized via TMVCushionRenderer (exposed
//  via the bridging header) so every kind shines equally bright on the cushion.
//
//  The palette is tuned for the deep-space background and ordered so that the
//  kinds met first (usually the biggest) get the most distinct colors. It keeps
//  a CIEDE2000 distance of at least 5 between any two colors under normal vision
//  and under protan, deutan and tritan color vision (checked at mid-cushion
//  brightness with tools/palette_check.py), so kinds stay telling apart for
//  color-blind users; the file kinds table lists them next to their swatches.
//
//  GPL v3
//

import Cocoa

@objc(FileTypeColors)
final class FileTypeColors: NSObject {

    @objc static let instance = FileTypeColors()

    /// The neon palette as 0xRRGGBB values, in assignment order.
    static let paletteHex: [UInt32] = [
        0x00E5FF,  // cyan
        0xFFB000,  // amber
        0x8A5CFF,  // violet
        0xFF8573,  // salmon
        0x40B3FF,  // azure
        0xFF73D0,  // pink
        0x73FFF6,  // ice
        0xFF5500,  // vermilion
        0xFFFF00,  // yellow
        0x00FF33,  // green
        0xB4FF73,  // lime
        0xFF2BD6   // magenta
    ]

    private var colors: [String: NSColor] = [:]
    private let predefinedColors: [NSColor]

    override init() {
        predefinedColors = Self.paletteHex.map(Self.normalizedColor)
        super.init()
    }

    // normalize() hands its numbers back wrapped in a calibrated RGB space, which
    // the shader's sRGB conversion would then bend; re-wrap them as plain sRGB so
    // the shader reads exactly what was normalized (and what palette_check.py tests)
    private static func normalizedColor(hex: UInt32) -> NSColor {
        let normalized = TMVCushionRenderer.normalize(NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                                                              green: CGFloat((hex >> 8) & 0xFF) / 255,
                                                              blue: CGFloat(hex & 0xFF) / 255,
                                                              alpha: 1))
        return NSColor(srgbRed: normalized.redComponent, green: normalized.greenComponent,
                       blue: normalized.blueComponent, alpha: 1)
    }

    @objc func reset() {
        colors.removeAll()
    }

    @objc(colorForItem:)
    func color(forItem item: FSItem) -> NSColor {
        color(forKind: item.kindName())
    }

    @objc(colorForKind:)
    func color(forKind kind: String) -> NSColor {
        if let existing = colors[kind] {
            return existing
        }

        let color: NSColor
        if predefinedColors.count > colors.count {
            color = predefinedColors[colors.count]
        } else {
            // "dim matter": slate greys, deliberately not normalized so they stay
            // darker than the neon kinds, and a little lighter with every kind
            let level = min(0.30 + CGFloat(colors.count - predefinedColors.count) * 0.035, 0.62)
            color = NSColor(srgbRed: level * 0.92, green: level * 0.97, blue: min(level * 1.08, 1), alpha: 1)
        }

        colors[kind] = color
        return color
    }
}
