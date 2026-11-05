//
//  TreeMapPolish.swift
//  Disk Inventory Xs
//
//  The finishing pass of the treemap's "holo glass" look. It runs on the bitmap
//  after the cushion shader (TMVCushionRenderer, whose pixels stay as they are)
//  and gives every cell of a few pixels or more
//    - a rim light on its lit top and left edge, a brightened copy of the cell's
//      own color, so the edge glows in the kind color,
//    - a gutter of deep space on its bottom and right edge, so the cells float
//      apart instead of touching,
//    - and, for large cells, a soft glint where a glass pane would catch the light.
//  Cells overlap neither each other nor any other cell's edge, so the pass shades
//  them concurrently. With Increase Contrast the gutters are firmer and the glints
//  are left out.
//
//  GPL v3
//

import Cocoa

enum TreeMapPolish {

    // the smallest cell (in pixels, either side) that gets rim and gutter
    private static let minimumEdgeCell = 5
    // the smallest cell that also gets a glint
    private static let minimumGlintCell = 28

    private struct Cell {
        var x0: Int, y0: Int, x1: Int, y1: Int   // half-open pixel rect
    }

    /// Polishes the cells below `root` in `bitmap`. `edge` is the width in pixels
    /// of rim and gutter (the backing scale, so they are a point wide).
    static func polish(_ bitmap: NSBitmapImageRep, root: TMVItem, edge: Int) {
        guard let pixels = bitmap.bitmapData else { return }
        let edge = max(edge, 1)
        let bytesPerRow = bitmap.bytesPerRow
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh

        grade(pixels: pixels, bytesPerRow: bytesPerRow, width: width, height: height)

        var cells: [Cell] = []
        collectCells(of: root, edge: edge, width: width, height: height, into: &cells)
        if cells.isEmpty { return }

        let contrast = Theme.increaseContrast
        let gutterStrength = contrast ? 230 : 150     // of 256
        let rimBoost = contrast ? 1 : 0               // firmer rim light

        // chunks of cells, so each thread has a fair amount of work
        let chunkCount = min(max(cells.count / 256, 1), ProcessInfo.processInfo.activeProcessorCount * 4)
        cells.withUnsafeBufferPointer { cells in
            DispatchQueue.concurrentPerform(iterations: chunkCount) { chunk in
                let start = cells.count * chunk / chunkCount
                let end = cells.count * (chunk + 1) / chunkCount
                for index in start..<end {
                    polishCell(cells[index], pixels: pixels, bytesPerRow: bytesPerRow, edge: edge,
                               gutterStrength: gutterStrength, rimBoost: rimBoost, glint: !contrast)
                }
            }
        }
    }

    // Colour grading of the whole bitmap: more saturation and a slightly steeper
    // tone curve, so the shaded cushions glow like neon on deep space instead of
    // looking washed out. Concurrent over bands of rows.
    private static let gradeTable: [UInt8] = (0..<256).map { value in
        UInt8(min(255, (pow(Double(value) / 255, 1.12) * 255).rounded()))
    }

    private static func grade(pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int, width: Int, height: Int) {
        let saturation = 352                         // 1.375 in 8.8 fixed point
        let bandCount = max(min(height / 32, ProcessInfo.processInfo.activeProcessorCount * 4), 1)

        gradeTable.withUnsafeBufferPointer { table in
            DispatchQueue.concurrentPerform(iterations: bandCount) { band in
                for y in (height * band / bandCount)..<(height * (band + 1) / bandCount) {
                    var pixel = pixels + y * bytesPerRow
                    for _ in 0..<width {
                        let r = Int(pixel[0]), g = Int(pixel[1]), b = Int(pixel[2])
                        let luma = (77 * r + 150 * g + 29 * b) >> 8
                        pixel[0] = table[min(255, max(0, luma + (((r - luma) * saturation) >> 8)))]
                        pixel[1] = table[min(255, max(0, luma + (((g - luma) * saturation) >> 8)))]
                        pixel[2] = table[min(255, max(0, luma + (((b - luma) * saturation) >> 8)))]
                        pixel += 3
                    }
                }
            }
        }
    }

    // Leaves of at least the edge-cell size; nodes smaller than that hold nothing bigger.
    private static func collectCells(of item: TMVItem, edge: Int, width: Int, height: Int,
                                     into cells: inout [Cell]) {
        let rect = item.rect()
        let w = Int(rect.width), h = Int(rect.height)
        if w < minimumEdgeCell * edge || h < minimumEdgeCell * edge { return }

        if item.isLeaf() {
            let cell = Cell(x0: Int(rect.minX), y0: Int(rect.minY), x1: Int(rect.maxX), y1: Int(rect.maxY))
            if cell.x0 >= 0, cell.y0 >= 0, cell.x1 <= width, cell.y1 <= height {
                cells.append(cell)
            }
            return
        }

        for index in 0..<item.childCount() {
            if let child = item.child(at: UInt(index)) {
                collectCells(of: child, edge: edge, width: width, height: height, into: &cells)
            }
        }
    }

    // deep-space tone the gutters fade to (like the background fill)
    private static let space: (Int, Int, Int) = (6, 9, 18)

    private static func polishCell(_ cell: Cell, pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int,
                                   edge: Int, gutterStrength: Int, rimBoost: Int, glint: Bool) {
        let w = cell.x1 - cell.x0
        let h = cell.y1 - cell.y0

        // glint first, so rim and gutter sit on top of it
        if glint, w >= minimumGlintCell * edge, h >= minimumGlintCell * edge {
            addGlint(cell, pixels: pixels, bytesPerRow: bytesPerRow)
        }

        // rim light: top rows and left columns, a brightened copy of the pixel itself
        for e in 0..<edge {
            for x in cell.x0..<cell.x1 {
                rim(pixels + (cell.y0 + e) * bytesPerRow + x * 3, boost: rimBoost)
            }
            for y in cell.y0..<cell.y1 {
                rim(pixels + y * bytesPerRow + (cell.x0 + e) * 3, boost: rimBoost)
            }
        }

        // gutter: bottom rows and right columns fade towards deep space
        for e in 0..<edge {
            for x in cell.x0..<cell.x1 {
                gutter(pixels + (cell.y1 - 1 - e) * bytesPerRow + x * 3, strength: gutterStrength)
            }
            for y in cell.y0..<cell.y1 {
                gutter(pixels + y * bytesPerRow + (cell.x1 - 1 - e) * 3, strength: gutterStrength)
            }
        }
    }

    @inline(__always)
    private static func rim(_ pixel: UnsafeMutablePointer<UInt8>, boost: Int) {
        // p * 1.3 + 16 (+ a little more with Increase Contrast), clamped
        for channel in 0..<3 {
            let p = Int(pixel[channel])
            pixel[channel] = UInt8(min(255, ((p * (333 + boost * 80)) >> 8) + 16 + boost * 12))
        }
    }

    @inline(__always)
    private static func gutter(_ pixel: UnsafeMutablePointer<UInt8>, strength: Int) {
        pixel[0] = UInt8((Int(pixel[0]) * (256 - strength) + space.0 * strength) >> 8)
        pixel[1] = UInt8((Int(pixel[1]) * (256 - strength) + space.1 * strength) >> 8)
        pixel[2] = UInt8((Int(pixel[2]) * (256 - strength) + space.2 * strength) >> 8)
    }

    // A soft white highlight in the upper left of the cell, an ellipse of up to
    // 120 px per half-axis whose intensity falls off with the square of the distance.
    private static func addGlint(_ cell: Cell, pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int) {
        let w = Double(cell.x1 - cell.x0)
        let h = Double(cell.y1 - cell.y0)
        let rx = min(w * 0.34, 120)
        let ry = min(h * 0.30, 120)
        let cx = Double(cell.x0) + w * 0.27
        let cy = Double(cell.y0) + h * 0.22

        let xStart = max(Int(cx - rx), cell.x0), xEnd = min(Int(cx + rx) + 1, cell.x1)
        let yStart = max(Int(cy - ry), cell.y0), yEnd = min(Int(cy + ry) + 1, cell.y1)

        for y in yStart..<yEnd {
            let dy = (Double(y) + 0.5 - cy) / ry
            let row = pixels + y * bytesPerRow
            for x in xStart..<xEnd {
                let dx = (Double(x) + 0.5 - cx) / rx
                let d2 = dx * dx + dy * dy
                if d2 >= 1 { continue }
                let falloff = (1 - d2) * (1 - d2)
                let add = Int(falloff * 46)
                let pixel = row + x * 3
                pixel[0] = UInt8(min(255, Int(pixel[0]) + add))
                pixel[1] = UInt8(min(255, Int(pixel[1]) + add))
                pixel[2] = UInt8(min(255, Int(pixel[2]) + add))
            }
        }
    }
}
