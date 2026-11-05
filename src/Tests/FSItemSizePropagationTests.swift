//
//  FSItemSizePropagationTests.swift
//  Disk Inventory XTests
//
//  Covers how FSItem propagates a size change up the tree when a subtree is
//  replaced (the "refresh item" path). Each test builds its own small tree in a
//  temporary directory, so it does not depend on TestFixtures.
//
//  GPL v3
//

import XCTest
import Cocoa
@testable import Disk_Inventory_Xs

final class FSItemSizePropagationTests: XCTestCase {

    private static let block = 4096

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("DIXSizePropagation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // A refreshed folder that grows by more than all of its ancestors' other
    // children together must not trap on UInt64 underflow while the new size
    // propagates up through ancestors that have no (or only small) siblings.
    func testReplacingChildWithLargerSubtreeUpdatesAncestorSizes() throws {
        try write(Self.block, to: "outer/inner/small.dixfix")

        let root = try scan(tempRoot)
        let outer = try XCTUnwrap(child(of: root, named: "outer"))
        let oldInner = try XCTUnwrap(child(of: outer, named: "inner"))
        XCTAssertEqual(root.sizeValue(), UInt64(Self.block))

        // inner grows by 1 MB, far more than the 4 KB the ancestors held before
        try write(1024 * 1024, to: "outer/inner/big.dixfix")
        let newInner = try scan(oldInner.fileURL() as URL?)
        XCTAssertEqual(newInner.sizeValue(), UInt64(Self.block + 1024 * 1024))

        outer.replaceChild(oldInner, with: newInner, updateParent: true)

        XCTAssertEqual(outer.sizeValue(), newInner.sizeValue())
        XCTAssertEqual(root.sizeValue(), newInner.sizeValue())
        XCTAssertEqual(root.childCount(), 1)
    }

    // When a child's size changes, its parent keeps the children ordered by size
    // (descending) and its own size equals the sum of its children.
    func testChildSizeChangeReordersSiblingsAndKeepsSums() throws {
        try write(Self.block, to: "p/a/x.dixfix")           // p = 4 KB
        try write(2 * Self.block, to: "q/y.dixfix")         // q = 8 KB

        let root = try scan(tempRoot)
        let p = try XCTUnwrap(child(of: root, named: "p"))
        let q = try XCTUnwrap(child(of: root, named: "q"))
        let oldA = try XCTUnwrap(child(of: p, named: "a"))
        XCTAssertTrue(root.child(at: 0) === q, "larger child must come first")
        XCTAssertEqual(root.sizeValue(), UInt64(3 * Self.block))

        // a grows to 16 KB, which makes p (16 KB) larger than q (8 KB)
        try write(4 * Self.block, to: "p/a/x.dixfix")
        let newA = try scan(oldA.fileURL() as URL?)

        p.replaceChild(oldA, with: newA, updateParent: true)

        XCTAssertEqual(p.sizeValue(), UInt64(4 * Self.block))
        XCTAssertEqual(root.sizeValue(), UInt64(6 * Self.block))
        XCTAssertTrue(root.child(at: 0) === p, "grown child must move to the front")
        XCTAssertTrue(root.child(at: 1) === q)
        XCTAssertTrue(p.parent() === root)
    }

    // MARK: - helpers

    private func write(_ bytes: Int, to relativePath: String) throws {
        let url = tempRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    // Scans a folder and returns its root FSItem with logical sizes (the scanner
    // ends with a physical-size recalc; redo it so sizes are the exact bytes written).
    private func scan(_ url: URL?) throws -> FSItem {
        let folder = try XCTUnwrap(url)
        let item = FSItem(url: folder as NSURL)
        try item.loadChildren()
        item.recalculateSize(false, updateParent: false)
        return item
    }

    private func child(of item: FSItem, named name: String) -> FSItem? {
        var i: UInt = 0
        while i < item.childCount() {
            if let c = item.child(at: i), c.name() == name { return c }
            i += 1
        }
        return nil
    }
}
