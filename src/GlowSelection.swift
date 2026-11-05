//
//  GlowSelection.swift
//  Disk Inventory Xs
//
//  Selection drawing for the app's tables and outline: a rounded translucent
//  cyan plate with a hairline edge instead of the system's flat accent bar. The
//  tables are cell-based, so DIXTableView and DIXOutlineView call this from
//  highlightSelection(inClipRect:). Text keeps the system's selected-row color
//  (white on an active table), which the plate is dark enough to carry. With
//  Increase Contrast the plate becomes a solid white outline.
//
//  GPL v3
//

import Cocoa

enum GlowSelection {

    /// Draws the plates of all selected rows of `table` that intersect `clipRect`.
    static func highlightSelectedRows(of table: NSTableView, in clipRect: NSRect) {
        // a plate that is not the key table is dimmer, like the system's own
        let isActive = table.window?.isKeyWindow == true && table.window?.firstResponder === table
        let strength: CGFloat = isActive ? 1 : 0.55

        for row in table.selectedRowIndexes {
            let rowRect = table.rect(ofRow: row)
            guard rowRect.intersects(clipRect) else { continue }
            drawPlate(in: rowRect.insetBy(dx: 4, dy: 1), strength: strength)
        }
    }

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
