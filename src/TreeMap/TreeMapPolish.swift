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
//    - and, for large cells, a flatter cushion with a diagonal sheen, like a glass
//      pane catching the light, instead of a round hot spot.
//  Folders get a luminous outline, so the tree behind the cells shows. Cells overlap
//  neither each other nor any other cell's edge, so the pass shades them
//  concurrently; the folder outlines are drawn afterwards. With Increase Contrast
//  the gutters and outlines are firmer and the sheen is left out.
//
//  GPL v3
//

import Cocoa

enum TreeMapPolish {

    // the smallest cell (in pixels, either side) that gets rim and gutter
    private static let minimumEdgeCell = 5
    // the smallest cell that is also flattened and gets a sheen
    private static let minimumSheenCell = 28
    // the smallest folder that gets an outline
    private static let minimumFrame = 24

    private struct Cell {
        var x0: Int, y0: Int, x1: Int, y1: Int   // half-open pixel rect
    }

    private struct Frame {
        var x0: Int, y0: Int, x1: Int, y1: Int   // half-open pixel rect
        var depth: Int                           // 1 for the folders directly below the root
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
        var frames: [Frame] = []
        collectCells(of: root, depth: 0, edge: edge, width: width, height: height, cells: &cells, frames: &frames)
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
                               gutterStrength: gutterStrength, rimBoost: rimBoost, sheen: !contrast)
                }
            }
        }

        for frame in frames {
            outline(frame, pixels: pixels, bytesPerRow: bytesPerRow, edge: edge, contrast: contrast)
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

    // Leaves of at least the edge-cell size, and the folders big enough for an outline;
    // nodes smaller than that hold nothing bigger.
    private static func collectCells(of item: TMVItem, depth: Int, edge: Int, width: Int, height: Int,
                                     cells: inout [Cell], frames: inout [Frame]) {
        let rect = item.rect()
        let w = Int(rect.width), h = Int(rect.height)
        if w < minimumEdgeCell * edge || h < minimumEdgeCell * edge { return }

        let inside = Int(rect.minX) >= 0 && Int(rect.minY) >= 0 && Int(rect.maxX) <= width && Int(rect.maxY) <= height

        if item.isLeaf() {
            if inside {
                cells.append(Cell(x0: Int(rect.minX), y0: Int(rect.minY), x1: Int(rect.maxX), y1: Int(rect.maxY)))
            }
            return
        }

        if depth > 0, inside, w >= minimumFrame * edge, h >= minimumFrame * edge {
            frames.append(Frame(x0: Int(rect.minX), y0: Int(rect.minY), x1: Int(rect.maxX), y1: Int(rect.maxY),
                                depth: depth))
        }

        for index in 0..<item.childCount() {
            if let child = item.child(at: UInt(index)) {
                collectCells(of: child, depth: depth + 1, edge: edge, width: width, height: height,
                             cells: &cells, frames: &frames)
            }
        }
    }

    // deep-space tone the gutters fade to (like the background fill)
    private static let space: (Int, Int, Int) = (6, 9, 18)

    private static func polishCell(_ cell: Cell, pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int,
                                   edge: Int, gutterStrength: Int, rimBoost: Int, sheen: Bool) {
        let w = cell.x1 - cell.x0
        let h = cell.y1 - cell.y0

        // flatten and sheen first, so rim and gutter sit on top of them
        if w >= minimumSheenCell * edge, h >= minimumSheenCell * edge {
            flatten(cell, pixels: pixels, bytesPerRow: bytesPerRow, sheen: sheen)
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

    // The shader's cushions bulge a lot, which makes big cells look like pillows. Pull
    // every pixel 40% of the way to the cell's average color, then tilt the cell with
    // a diagonal sheen: lighter at the upper left, darker at the lower right.
    private static func flatten(_ cell: Cell, pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int, sheen: Bool) {
        let w = cell.x1 - cell.x0
        let h = cell.y1 - cell.y0

        // the average, from a grid of samples
        var sum = (0, 0, 0)
        let steps = 8
        for j in 0..<steps {
            let row = pixels + (cell.y0 + h * (2 * j + 1) / (2 * steps)) * bytesPerRow
            for i in 0..<steps {
                let p = row + (cell.x0 + w * (2 * i + 1) / (2 * steps)) * 3
                sum.0 += Int(p[0]); sum.1 += Int(p[1]); sum.2 += Int(p[2])
            }
        }
        let mean = (sum.0 / (steps * steps), sum.1 / (steps * steps), sum.2 / (steps * steps))

        let keep = 154                                    // 0.6 in 8.8 fixed point
        let amplitude = sheen ? 22 : 0
        for y in cell.y0..<cell.y1 {
            let row = pixels + y * bytesPerRow
            let ty = (y - cell.y0) * 512 / h              // 0...512, half the diagonal
            for x in cell.x0..<cell.x1 {
                let t = ((x - cell.x0) * 512 / w + ty) / 2    // 0 at the upper left, 512 at the lower right
                let tilt = (256 - t) * amplitude / 256
                let p = row + x * 3
                p[0] = UInt8(max(0, min(255, mean.0 + (((Int(p[0]) - mean.0) * keep) >> 8) + tilt)))
                p[1] = UInt8(max(0, min(255, mean.1 + (((Int(p[1]) - mean.1) * keep) >> 8) + tilt)))
                p[2] = UInt8(max(0, min(255, mean.2 + (((Int(p[2]) - mean.2) * keep) >> 8) + tilt)))
            }
        }
    }

    // A luminous line around a folder, so the tree shows behind the cells: two pixels
    // wide around the folders directly below the root, one around the deeper ones.
    private static func outline(_ frame: Frame, pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int,
                                edge: Int, contrast: Bool) {
        let strengths = contrast ? [210, 170, 140] : [120, 84, 56]       // of 256, by depth
        let strength = strengths[min(frame.depth, strengths.count) - 1]
        let lineWidth = (frame.depth == 1 ? 2 : 1) * edge

        for e in 0..<lineWidth {
            for x in frame.x0..<frame.x1 {
                lighten(pixels + (frame.y0 + e) * bytesPerRow + x * 3, strength: strength)
                lighten(pixels + (frame.y1 - 1 - e) * bytesPerRow + x * 3, strength: strength)
            }
            for y in (frame.y0 + lineWidth)..<(frame.y1 - lineWidth) {
                lighten(pixels + y * bytesPerRow + (frame.x0 + e) * 3, strength: strength)
                lighten(pixels + y * bytesPerRow + (frame.x1 - 1 - e) * 3, strength: strength)
            }
        }
    }

    @inline(__always)
    private static func lighten(_ pixel: UnsafeMutablePointer<UInt8>, strength: Int) {
        for channel in 0..<3 {
            let p = Int(pixel[channel])
            pixel[channel] = UInt8(p + (((255 - p) * strength) >> 8))
        }
    }
}
