//
//  TreeMapGlow.swift
//  Disk Inventory Xs
//
//  Draws the selection and hover frames of the treemap as luminous outlines:
//  a white-hot core with a soft cyan halo and a thin dark keyline, so the frame
//  stays visible on every cushion color, bright or dark. With Increase Contrast
//  or Reduce Transparency the halo is dropped for a solid, thicker outline.
//
//  GPL v3
//

import Cocoa

enum TreeMapGlow {

    /// How far (in points) the halo reaches beyond a cell. Callers that
    /// invalidate a frame must grow the cell rect by this much.
    static let haloReach: CGFloat = 18

    private static let halo = Theme.accent

    /// Paints the deep-space background into a fresh treemap bitmap, so cells too
    /// small to be rendered read as dim space instead of black holes.
    static func fillBackground(_ bitmap: NSBitmapImageRep) {
        guard let pixels = bitmap.bitmapData else { return }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let bytesPerRow = bitmap.bytesPerRow

        // a diagonal glow from the top left, the same indigo-to-black as the app icon
        let from: (Double, Double, Double) = (16, 22, 46)
        let to: (Double, Double, Double) = (4, 6, 12)
        let span = Double(width + height)

        for y in 0..<height {
            let row = pixels + y * bytesPerRow
            for x in 0..<width {
                let t = Double(x + y) / span
                let pixel = row + x * 3
                pixel[0] = UInt8(from.0 + (to.0 - from.0) * t)
                pixel[1] = UInt8(from.1 + (to.1 - from.1) * t)
                pixel[2] = UInt8(from.2 + (to.2 - from.2) * t)
            }
        }
    }

    /// The selection frame around the cell at `rect` (view coordinates).
    static func drawSelection(in rect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        // frames hug the cell edge; a sliver of a cell gets a plain stroke
        let frame = rect.insetBy(dx: 1, dy: 1)
        let radius = min(3, min(frame.width, frame.height) / 2)
        let path = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)

        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }

        if Theme.increaseContrast || Theme.reduceTransparency {
            // keyline on both sides of a thick white stroke
            NSColor.black.setStroke()
            path.lineWidth = 5
            path.stroke()
            NSColor.white.setStroke()
            path.lineWidth = 3
            path.stroke()
            return
        }

        // 1. dark keyline so the frame reads on light cushions
        NSColor(white: 0, alpha: 0.65).setStroke()
        path.lineWidth = 4
        path.stroke()

        // 2. a wide cyan bloom, then a tight white halo, both cast by a stroke
        // that the core below covers; white stays visible next to cyan cells
        for (blur, color, width) in [(haloReach, halo.withAlphaComponent(0.8), CGFloat(3)),
                                     (haloReach / 2, NSColor.white.withAlphaComponent(0.9), CGFloat(2.5))] {
            let shadow = NSShadow()
            shadow.shadowOffset = .zero
            shadow.shadowBlurRadius = blur
            shadow.shadowColor = color
            shadow.set()
            NSColor.white.setStroke()
            path.lineWidth = width
            path.stroke()
        }

        // 3. white-hot core
        NSShadow().set()
        NSColor.white.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    /// The hover frame: a faint veil and a thin bright edge, quieter than the
    /// selection so the two never compete.
    static func drawHover(in rect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        let frame = rect.insetBy(dx: 0.5, dy: 0.5)
        guard frame.width > 1, frame.height > 1 else { return }

        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }

        let path = NSBezierPath(rect: frame)
        if Theme.increaseContrast {
            NSColor.white.setStroke()
            path.lineWidth = 2
            path.stroke()
            return
        }
        NSColor(white: 1, alpha: 0.12).setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.75).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
