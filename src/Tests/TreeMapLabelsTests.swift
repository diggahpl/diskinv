//
//  TreeMapLabelsTests.swift
//  Disk Inventory XTests
//
//  Covers which cells of the treemap get a name written on them: big files get
//  their name, folders a pill at their upper left, small cells nothing, and the ink
//  follows the lightness of the cell.
//
//  GPL v3
//

import XCTest
import Cocoa
@testable import Disk_Inventory_Xs

final class TreeMapLabelsTests: XCTestCase {

    private static let size = NSSize(width: 420, height: 300)

    private func greyBitmap(_ grey: UInt8) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(rgbBitmapWithWidth: Int(Self.size.width), height: Int(Self.size.height)))
        memset(try XCTUnwrap(bitmap.bitmapData), Int32(grey), bitmap.bytesPerRow * bitmap.pixelsHigh)
        return bitmap
    }

    private func labels(source: NSObject, grey: UInt8 = 60,
                        isDimmed: @escaping (Any) -> Bool = { _ in false }) throws -> [TreeMapLabel] {
        let view = TreeMapView(frame: NSRect(origin: .zero, size: Self.size))
        let root = TMVItem(dataSource: source, delegate: nil, renderedItem: nil, treeMapView: view)
        root.calcLayout(NSRect(origin: .zero, size: Self.size))
        return TreeMapLabels.collect(root: root, view: view, bitmap: try greyBitmap(grey),
                                     name: { "item \(($0 as? NSNumber)?.intValue ?? -1)" },
                                     size: { "\($0) bytes" }, isDimmed: isDimmed)
    }

    func testBigFilesAreNamedAndSmallCellsAreNot() throws {
        // one dominant file and a few specks
        let found = try labels(source: FlatDataSource(weights: [9000, 300, 40, 30, 20, 10]))

        XCTAssertEqual(found.first?.name, "item 0")
        XCTAssertNotNil(found.first?.detail, "the biggest cell has room for its size")
        XCTAssertFalse(found.contains { $0.name == "item 5" }, "a speck has no room for a name")
        XCTAssertTrue(found.allSatisfy { !$0.isFolder })
    }

    func testFoldersGetAPillAtTheirCorner() throws {
        let found = try labels(source: NestedDataSource())

        let folders = found.filter { $0.isFolder }
        XCTAssertFalse(folders.isEmpty)
        // folder 1 is the first child of the root: its pill must not be hidden by a file label
        XCTAssertTrue(folders.contains { $0.name == "item 1" })
        for folder in folders {
            XCTAssertNil(folder.detail)
        }
    }

    func testLeavesOutOfFocusAreNotNamed() throws {
        let source = FlatDataSource(weights: [9000, 6000])
        let all = try labels(source: source)
        XCTAssertEqual(all.map(\.name).sorted(), ["item 0", "item 1"])

        // only item 1 is in focus
        let focused = try labels(source: source, isDimmed: { ($0 as? NSNumber)?.intValue != 1 })
        XCTAssertEqual(focused.map(\.name), ["item 1"])
    }

    func testInkFollowsTheLightnessOfTheCell() throws {
        let source = FlatDataSource(weights: [9000, 300])
        XCTAssertEqual(try labels(source: source, grey: 40).first?.darkInk, false, "light ink on a dark cell")
        XCTAssertEqual(try labels(source: source, grey: 230).first?.darkInk, true, "dark ink on a light cell")
    }
}
