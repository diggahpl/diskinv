//
//  TreeMapLabels.swift
//  Disk Inventory Xs
//
//  The names written on the treemap, so big cells say what they are instead of being
//  anonymous blobs: a centered name (and size) on big files, and a small pill with
//  the folder's name at the upper left of big folders. The labels are collected when
//  the cache bitmap is rendered and drawn over it by TreeMapView.draw; they are not
//  part of the bitmap, so the shader's pixels stay as they are.
//
//  GPL v3
//

import Cocoa

struct TreeMapLabel {
    let rect: NSRect          // the cell, in view points
    let name: String
    let detail: String?       // the size, on the biggest cells
    let isFolder: Bool
    let darkInk: Bool         // dark text, as the cell is light
}

enum TreeMapLabels {

    private static let minimumLeafSize = NSSize(width: 84, height: 26)
    private static let minimumDetailHeight: CGFloat = 44
    private static let minimumFolderSize = NSSize(width: 130, height: 52)
    private static let maximumFolderDepth = 3

    /// The labels of the cells below `root`. `bitmap` is the rendered cache (its pixels
    /// decide between light and dark ink), `name` and `size` ask the data source.
    static func collect(root: TMVItem, view: TreeMapView, bitmap: NSBitmapImageRep,
                        name: (Any) -> String?, size: (UInt64) -> String) -> [TreeMapLabel] {
        guard let pixels = bitmap.bitmapData else { return [] }

        var labels: [TreeMapLabel] = []
        var pills: [NSRect] = []

        func lightness(atPixel x: Int, _ y: Int) -> Int {
            let cx = min(max(x, 0), bitmap.pixelsWide - 1), cy = min(max(y, 0), bitmap.pixelsHigh - 1)
            let p = pixels + cy * bitmap.bytesPerRow + cx * 3
            return (77 * Int(p[0]) + 150 * Int(p[1]) + 29 * Int(p[2])) >> 8
        }

        func visit(_ item: TMVItem, depth: Int) {
            let pixelRect = item.rect()
            let rect = view.convertRectFromBackingRespectingFlipped(pixelRect)
            if rect.width < minimumLeafSize.width || rect.height < minimumLeafSize.height { return }

            if item.isLeaf() {
                guard let object = item.item(), let text = name(object) else { return }
                // a label under a folder's pill would be a mess
                let textRect = rect.insetBy(dx: 8, dy: 4)
                if pills.contains(where: { $0.intersects(textRect) }) { return }

                let detail = rect.height >= minimumDetailHeight ? size(item.weight()) : nil
                let dark = lightness(atPixel: Int(pixelRect.midX), Int(pixelRect.midY)) > 150
                labels.append(TreeMapLabel(rect: rect, name: text, detail: detail, isFolder: false, darkInk: dark))
                return
            }

            if depth > 0, depth <= maximumFolderDepth,
               rect.width >= minimumFolderSize.width, rect.height >= minimumFolderSize.height,
               let object = item.item(), let text = name(object) {
                let pill = pillRect(for: text, in: rect)
                // the first folder inside a folder starts at the same corner: keep the outer name
                if !pills.contains(where: { $0.intersects(pill) }) {
                    pills.append(pill)
                    labels.append(TreeMapLabel(rect: rect, name: text, detail: nil, isFolder: true, darkInk: false))
                }
            }

            for index in 0..<item.childCount() {
                if let child = item.child(at: UInt(index)) {
                    visit(child, depth: depth + 1)
                }
            }
        }

        visit(root, depth: 0)
        return labels
    }

    // MARK: - Drawing

    private static let pillFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
    private static let leafFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let detailFont = Theme.numericFont(ofSize: 10)

    private static func pillRect(for text: String, in rect: NSRect) -> NSRect {
        let width = (text as NSString).size(withAttributes: [.font: pillFont]).width + 14
        return NSRect(x: rect.minX + 6, y: rect.minY + 6, width: min(width, rect.width - 12), height: 18)
    }

    /// Draws the labels that intersect `dirtyRect`.
    static func draw(_ labels: [TreeMapLabel], in dirtyRect: NSRect) {
        for label in labels where label.rect.intersects(dirtyRect) {
            if label.isFolder {
                drawPill(label)
            } else {
                drawLeaf(label)
            }
        }
    }

    private static func drawPill(_ label: TreeMapLabel) {
        let pill = pillRect(for: label.name, in: label.rect)
        let path = NSBezierPath(roundedRect: pill, xRadius: 9, yRadius: 9)
        Theme.space.withAlphaComponent(Theme.reduceTransparency ? 1 : 0.74).setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.16).setStroke()
        path.lineWidth = 1
        path.stroke()

        draw(label.name, font: pillFont, color: NSColor(white: 1, alpha: 0.95), alignment: .left,
             in: NSRect(x: pill.minX + 7, y: pill.minY + 2, width: pill.width - 12, height: pill.height - 4), shadow: false)
    }

    private static func drawLeaf(_ label: TreeMapLabel) {
        let ink = label.darkInk ? NSColor(white: 0, alpha: 0.78) : NSColor(white: 1, alpha: 0.95)
        let quiet = label.darkInk ? NSColor(white: 0, alpha: 0.6) : NSColor(white: 1, alpha: 0.72)
        let area = label.rect.insetBy(dx: 8, dy: 4)

        let nameHeight = ceil(leafFont.ascender - leafFont.descender)
        let detailHeight = label.detail == nil ? 0 : ceil(detailFont.ascender - detailFont.descender) + 1
        var y = area.midY - (nameHeight + detailHeight) / 2

        draw(label.name, font: leafFont, color: ink, alignment: .center,
             in: NSRect(x: area.minX, y: y, width: area.width, height: nameHeight), shadow: !label.darkInk)
        y += nameHeight + 1
        if let detail = label.detail {
            draw(detail, font: detailFont, color: quiet, alignment: .center,
                 in: NSRect(x: area.minX, y: y, width: area.width, height: detailHeight), shadow: !label.darkInk)
        }
    }

    private static func draw(_ text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment,
                             in rect: NSRect, shadow: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        // light ink gets a dark copy one point below it, so it reads on bright cells too
        if shadow {
            let dark: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph,
                                                       .foregroundColor: NSColor(white: 0, alpha: 0.55)]
            (text as NSString).draw(in: rect.offsetBy(dx: 0, dy: 1), withAttributes: dark)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph, .foregroundColor: color]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}
