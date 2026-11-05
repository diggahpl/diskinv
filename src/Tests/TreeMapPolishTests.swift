//
//  TreeMapPolishTests.swift
//  Disk Inventory XTests
//
//  Covers the finishing pass of the treemap look: a lit rim on the top and left
//  edge of every cell, a deep-space gutter on its bottom and right edge, and the
//  background fill behind cells too small to be shaded.
//
//  GPL v3
//

import XCTest
import Cocoa
@testable import Disk_Inventory_Xs

// A flat tree: one folder holding files of the given sizes.
private final class FlatDataSource: NSObject {
    let weights: [UInt64]

    init(weights: [UInt64]) {
        self.weights = weights
        super.init()
    }

    @objc func treeMapView(_ view: TreeMapView!, child index: UInt, ofItem item: Any!) -> Any! {
        NSNumber(value: index)
    }

    @objc func treeMapView(_ view: TreeMapView!, isNode item: Any!) -> Bool {
        item == nil
    }

    @objc func treeMapView(_ view: TreeMapView!, numberOfChildrenOfItem item: Any!) -> UInt32 {
        UInt32(weights.count)
    }

    @objc func treeMapView(_ view: TreeMapView!, weightByItem item: Any!) -> UInt64 {
        guard let index = (item as? NSNumber)?.intValue else { return weights.reduce(0, +) }
        return weights[index]
    }
}

final class TreeMapPolishTests: XCTestCase {

    private static let grey: UInt8 = 120

    private func makeLayout(weights: [UInt64], size: NSSize) -> TMVItem {
        let source = FlatDataSource(weights: weights)
        let root = TMVItem(dataSource: source, delegate: nil, renderedItem: nil, treeMapView: nil)
        root.calcLayout(NSRect(origin: .zero, size: size))
        return root
    }

    private func greyBitmap(_ size: NSSize) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(rgbBitmapWithWidth: Int(size.width), height: Int(size.height)))
        memset(try XCTUnwrap(bitmap.bitmapData), Int32(Self.grey), bitmap.bytesPerRow * bitmap.pixelsHigh)
        return bitmap
    }

    private func red(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> Int {
        Int(bitmap.bitmapData![y * bitmap.bytesPerRow + x * 3])
    }

    private func leaves(_ root: TMVItem) -> [TMVItem] {
        root.childEnumerator().allObjects.compactMap { $0 as? TMVItem }
    }

    func testRimIsBrighterAndGutterDarkerThanTheCellInterior() throws {
        let size = NSSize(width: 240, height: 160)
        let root = makeLayout(weights: [400, 300, 200], size: size)
        let bitmap = try greyBitmap(size)
        TreeMapPolish.polish(bitmap, root: root, edge: 1)

        for leaf in leaves(root) {
            let rect = leaf.rect()
            let x0 = Int(rect.minX), y0 = Int(rect.minY), x1 = Int(rect.maxX), y1 = Int(rect.maxY)
            // a point in the middle of the cell, clear of the glint in the upper left
            let interior = red(bitmap, (x0 + x1) / 2 + (x1 - x0) / 5, (y0 + y1) / 2 + (y1 - y0) / 5)

            XCTAssertGreaterThan(red(bitmap, (x0 + x1) / 2, y0), interior, "top rim of \(rect)")
            XCTAssertGreaterThan(red(bitmap, x0, (y0 + y1) / 2), interior, "left rim of \(rect)")
            XCTAssertLessThan(red(bitmap, (x0 + x1) / 2, y1 - 1), interior, "bottom gutter of \(rect)")
            XCTAssertLessThan(red(bitmap, x1 - 1, (y0 + y1) / 2), interior, "right gutter of \(rect)")
        }
    }

    func testEdgeWidthFollowsTheBackingScale() throws {
        let size = NSSize(width: 240, height: 160)
        let root = makeLayout(weights: [1], size: size)

        let oneWide = try greyBitmap(size)
        TreeMapPolish.polish(oneWide, root: root, edge: 1)
        let twoWide = try greyBitmap(size)
        TreeMapPolish.polish(twoWide, root: root, edge: 2)

        let rect = leaves(root)[0].rect()
        let bottom = Int(rect.maxY) - 1, x = Int(rect.midX)
        // the second row from the bottom is gutter only with the wider edge
        XCTAssertGreaterThan(red(oneWide, x, bottom - 1), red(twoWide, x, bottom - 1))
        XCTAssertEqual(red(oneWide, x, bottom), red(twoWide, x, bottom))
    }

    func testCellsTooSmallForEdgesKeepTheirPixels() throws {
        // the first file is huge, the others are specks of a few pixels
        let size = NSSize(width: 100, height: 100)
        let root = makeLayout(weights: [6000, 8, 8, 8, 8, 8, 8, 8, 8], size: size)
        let bitmap = try greyBitmap(size)
        TreeMapPolish.polish(bitmap, root: root, edge: 1)

        // grey stays grey under the grading curve, so a cell interior shows what an
        // untouched pixel turns into
        let big = leaves(root)[0].rect()
        let probeX = Int(big.minX + big.width * 0.75)
        let probeY = Int(big.minY + big.height * 0.75)
        let untouched = red(bitmap, probeX, probeY)

        var specks: [NSRect] = []
        for leaf in leaves(root).dropFirst() {
            let rect = leaf.rect()
            let thin = rect.width < 5 || rect.height < 5
            if rect.width >= 1 && rect.height >= 1 && thin {
                specks.append(rect)
            }
        }
        XCTAssertFalse(specks.isEmpty, "layout produced no specks")
        for rect in specks {
            let corners: [(Int, Int)] = [(Int(rect.minX), Int(rect.minY)), (Int(rect.maxX) - 1, Int(rect.maxY) - 1)]
            for (x, y) in corners {
                XCTAssertEqual(red(bitmap, x, y), untouched, "speck \(rect)")
            }
        }
    }

    func testBackgroundFillIsDarkIndigoAndCoversTheBitmap() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(rgbBitmapWithWidth: 64, height: 48))
        memset(try XCTUnwrap(bitmap.bitmapData), 0xFF, bitmap.bytesPerRow * 48)
        TreeMapGlow.fillBackground(bitmap)

        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for (x, y) in [(0, 0), (63, 0), (0, 47), (63, 47), (30, 20)] {
            let p = pixels + y * bitmap.bytesPerRow + x * 3
            XCTAssertLessThan(Int(p[0]), 40, "red at \(x),\(y)")
            XCTAssertLessThan(Int(p[1]), 40, "green at \(x),\(y)")
            XCTAssertGreaterThan(Int(p[2]), Int(p[0]), "indigo bias at \(x),\(y)")
        }
    }
}
