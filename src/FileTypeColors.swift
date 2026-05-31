//
//  FileTypeColors.swift
//  Disk Inventory Xs
//
//  Swift port of FileTypeColors.{h,m}. Hands out a stable color per file
//  kind: first from a fixed palette, then generated greys once the palette
//  is exhausted. Colors are normalized via TMVCushionRenderer (exposed via
//  the bridging header).
//
//  GPL v3
//

import Cocoa

@objc(FileTypeColors)
final class FileTypeColors: NSObject {

    @objc static let instance = FileTypeColors()

    private var colors: [String: NSColor] = [:]
    private let predefinedColors: [NSColor]

    override init() {
        let palette: [NSColor] = [
            NSColor(calibratedRed: 0,    green: 0,    blue: 1,    alpha: 1),
            NSColor(calibratedRed: 1,    green: 0,    blue: 0,    alpha: 1),
            NSColor(calibratedRed: 0,    green: 1,    blue: 0,    alpha: 1),
            NSColor(calibratedRed: 0,    green: 1,    blue: 1,    alpha: 1),
            NSColor(calibratedRed: 1,    green: 0,    blue: 1,    alpha: 1),
            NSColor(calibratedRed: 1,    green: 1,    blue: 0,    alpha: 1),
            NSColor(calibratedRed: 0.58, green: 0.58, blue: 1,    alpha: 1),
            NSColor(calibratedRed: 1,    green: 0.58, blue: 0.58, alpha: 1),
            NSColor(calibratedRed: 0.58, green: 1,    blue: 0.58, alpha: 1),
            NSColor(calibratedRed: 0.58, green: 1,    blue: 1,    alpha: 1),
            NSColor(calibratedRed: 1,    green: 0.58, blue: 1,    alpha: 1),
            NSColor(calibratedRed: 1,    green: 1,    blue: 0.58, alpha: 1)
        ]
        predefinedColors = palette.map { TMVCushionRenderer.normalize($0) }
        super.init()
    }

    @objc func reset() {
        colors.removeAll()
    }

    @objc(colorForItem:)
    func color(forItem item: FSItem) -> NSColor {
        color(forKind: item.kindName() ?? "")
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
            var rgbComponent = CGFloat(colors.count) * 0.05
            if rgbComponent > 0.9 {
                rgbComponent = 0.9
            }
            color = TMVCushionRenderer.normalize(
                NSColor(calibratedRed: rgbComponent, green: rgbComponent, blue: rgbComponent, alpha: 1.0))
        }

        colors[kind] = color
        return color
    }
}
