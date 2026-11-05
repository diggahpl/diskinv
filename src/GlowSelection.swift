//
//  GlowSelection.swift
//  Disk Inventory Xs
//
//  The selection plate of the app's tables and outline: a rounded translucent cyan
//  pane with a hairline edge instead of the system's flat accent bar. DIXTableView
//  draws it under the cells of a selected row (with the system highlight off, which
//  would paint the cells grey over it), the files outline's FileRowView in its
//  drawSelection. Text keeps the system's color, which the plate is dark enough to
//  carry. With Increase Contrast the plate becomes a solid white outline.
//
//  GPL v3
//

import Cocoa

enum GlowSelection {

    /// One selection plate: `strength` is 1 for the key table and lower for the others.
    static func drawPlate(in plate: NSRect, strength: CGFloat) {
        let path = NSBezierPath(roundedRect: plate, xRadius: 6, yRadius: 6)

        if Theme.increaseContrast {
            NSColor.white.setStroke()
            path.lineWidth = 2
            path.stroke()
            return
        }

        // a soft glass pane: brighter along its top edge, hairline rim in the accent
        let gradient = NSGradient(starting: Theme.accent.withAlphaComponent(0.30 * strength),
                                  ending: Theme.accent.withAlphaComponent(0.12 * strength))
        gradient?.draw(in: path, angle: -90)
        Theme.accent.withAlphaComponent(0.55 * strength).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
