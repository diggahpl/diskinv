//
//  ThemeTests.swift
//  Disk Inventory XTests
//
//  Covers the parts of the visual design that are logic rather than pixels:
//  the file-kind palette handed out by FileTypeColors and the helpers in Theme.
//
//  GPL v3
//

import XCTest
import Cocoa
@testable import Disk_Inventory_Xs

final class ThemeTests: XCTestCase {

    private func rgb(_ color: NSColor) -> [CGFloat] {
        let c = color.usingColorSpace(.sRGB)!
        return [c.redComponent, c.greenComponent, c.blueComponent]
    }

    func testKindColorIsStablePerKind() {
        let colors = FileTypeColors()
        let first = colors.color(forKind: "PNG image")
        XCTAssertEqual(rgb(colors.color(forKind: "PNG image")), rgb(first))
        XCTAssertNotEqual(rgb(colors.color(forKind: "Folder")), rgb(first))
    }

    func testNeonPaletteHasDistinctColorsBrightEnoughForSpace() {
        let colors = FileTypeColors()
        var seen: [[CGFloat]] = []
        for index in 0..<FileTypeColors.paletteHex.count {
            let components = rgb(colors.color(forKind: "kind \(index)"))
            // normalized to the cushion brightness: components sum to 1.8, none above 1
            XCTAssertEqual(components.reduce(0, +), 1.8, accuracy: 0.001)
            XCTAssertLessThanOrEqual(components.max()!, 1.0 + 1e-6)
            XCTAssertFalse(seen.contains(components), "palette color \(index) repeats")
            seen.append(components)
        }
    }

    func testKindsBeyondThePaletteGetDimSlateGreys() {
        let colors = FileTypeColors()
        for index in 0..<FileTypeColors.paletteHex.count {
            _ = colors.color(forKind: "kind \(index)")
        }
        let grey = rgb(colors.color(forKind: "one kind too many"))
        // dimmer than any neon cushion, bluish rather than neutral
        XCTAssertLessThan(grey.reduce(0, +), 1.8)
        XCTAssertGreaterThan(grey[2], grey[0])
    }

    func testResetStartsThePaletteOver() {
        let colors = FileTypeColors()
        let first = rgb(colors.color(forKind: "a"))
        _ = colors.color(forKind: "b")
        colors.reset()
        XCTAssertEqual(rgb(colors.color(forKind: "b")), first)
    }

    func testCushionDisplayColorStaysInGamut() {
        let bright = Theme.cushionDisplayColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        XCTAssertEqual(rgb(bright), [1, 1, 1])
        let dim = rgb(Theme.cushionDisplayColor(Theme.freeSpace))
        XCTAssertTrue(dim.allSatisfy { $0 > 0 && $0 < 1 })
    }

    func testOnlyTheFirstKindsGetPaletteColors() {
        let colors = FileTypeColors()
        let palette = FileTypeColors.paletteHex.count
        for index in 0..<(palette + 3) {
            _ = colors.color(forKind: "kind \(index)")
        }
        for index in 0..<palette {
            XCTAssertTrue(colors.hasPaletteColor(forKind: "kind \(index)"), "kind \(index)")
        }
        for index in palette..<(palette + 3) {
            XCTAssertFalse(colors.hasPaletteColor(forKind: "kind \(index)"), "kind \(index) shares the dim greys")
        }
        XCTAssertFalse(colors.hasPaletteColor(forKind: "never asked for"))
    }

    func testToolbarSymbolsAllExist() throws {
        let path = try XCTUnwrap(Bundle(for: FileTypeColors.self).path(forResource: "MainWindowToolbar", ofType: "toolbar"))
        let config = try XCTUnwrap(NSDictionary(contentsOfFile: path) as? [String: Any])
        let items = try XCTUnwrap(config["itemInfoByIdentifier"] as? [String: [String: Any]])

        for (identifier, info) in items {
            for key in ["symbolName", "symbolNameOffState"] {
                guard let name = info[key] as? String else { continue }
                XCTAssertNotNil(Theme.symbolImage(named: name, description: nil), "\(identifier): no SF Symbol '\(name)'")
            }
        }
    }
}
