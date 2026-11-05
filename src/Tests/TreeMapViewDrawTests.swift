//
//  TreeMapViewDrawTests.swift
//  Disk Inventory XTests
//
//  Covers how TreeMapView paints the cached treemap bitmap. Hovering a cell
//  repaints only that cell's rect; the view is flipped and the cache image is
//  not, so the source rect of such a partial repaint has to be mirrored.
//
//  GPL v3
//

import XCTest
import Cocoa
@testable import Disk_Inventory_Xs

final class TreeMapViewDrawTests: XCTestCase {

    private static let size = NSSize(width: 240, height: 160)

    // keeps the data source and window alive for as long as the view is used
    private struct Fixture {
        let view: TreeMapView
        let window: NSWindow
        let source: FlatDataSource
    }

    private func makeFixture() -> Fixture {
        let view = TreeMapView(frame: NSRect(origin: .zero, size: Self.size))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false      // ARC owns it; the default would release it a second time
        window.contentView = view

        // uneven cells, so a mirrored source area looks different from the right one
        let source = FlatDataSource(weights: [500, 300, 120, 60, 20])
        view.dataSource = source
        view.reloadData()
        return Fixture(view: view, window: window, source: source)
    }

    private func channel(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int, _ channel: Int) -> Int {
        var pixel = [Int](repeating: 0, count: 4)
        bitmap.getPixel(&pixel, atX: x, y: y)
        return pixel[channel]
    }

    // Number of pixels of `part` that differ between painting just that rect and
    // painting the whole view.
    private func differingPixels(_ view: TreeMapView, part: NSRect) throws -> Int {
        let full = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: full)
        let partial = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: part))
        view.cacheDisplay(in: part, to: partial)

        let scale = full.pixelsWide / Int(Self.size.width)
        XCTAssertEqual(partial.pixelsWide, Int(part.width) * scale)

        var differing = 0
        for y in 0..<partial.pixelsHigh {
            for x in 0..<partial.pixelsWide {
                let fullX = Int(part.minX) * scale + x
                let fullY = Int(part.minY) * scale + y
                for c in 0..<3 where abs(channel(partial, x, y, c) - channel(full, fullX, fullY, c)) > 3 {
                    differing += 1
                    break
                }
            }
        }
        return differing
    }

    func testPartialRepaintShowsTheSamePixelsAsTheFullRepaint() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }

        // an area near the bottom of the view, away from its vertical middle
        let part = NSRect(x: 20, y: 110, width: 100, height: 40)
        XCTAssertEqual(try differingPixels(fixture.view, part: part), 0,
                       "pixels of the partial repaint that differ from the full repaint")
    }

    func testRepaintOfAHoveredCellShowsTheSamePixelsAsTheFullRepaint() throws {
        let fixture = makeFixture()
        defer { fixture.window.close() }
        let view = fixture.view

        // the layout is calculated by the first paint
        let first = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: first)

        // hover a cell near the bottom of the view; the window's y axis points up
        let viewPoint = NSPoint(x: 40, y: 140)
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: NSPoint(x: viewPoint.x, y: Self.size.height - viewPoint.y),
            modifierFlags: [], timestamp: 0, windowNumber: fixture.window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        view.mouseMoved(with: event)

        let cell = try XCTUnwrap(view.cellId(by: viewPoint, inViewCoords: true), "no cell under the pointer")
        let part = view.itemRect(byCellId: cell).insetBy(dx: -1, dy: -1).intersection(view.bounds)
        XCTAssertGreaterThan(part.width, 4)
        XCTAssertGreaterThan(part.minY, Self.size.height / 2, "the hovered cell should be in the lower half")
        XCTAssertEqual(try differingPixels(view, part: part), 0,
                       "pixels of the hovered cell's repaint that differ from the full repaint")
    }
}
