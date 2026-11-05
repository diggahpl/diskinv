//
//  FSItemScanTests.swift
//  Disk Inventory XTests
//
//  Scans the generated fixture tree (see TestFixtures) with FSItem and asserts
//  the resulting tree's structure and sizes. Uses logical sizes (recalculated
//  explicitly) so the assertions are exact and deterministic.
//
//  GPL v3
//

import XCTest
import Cocoa
@testable import Disk_Inventory_Xs

final class FSItemScanTests: XCTestCase {

    private static var fixturesRoot: URL!

    override class func setUp() {
        super.setUp()
        fixturesRoot = try! TestFixtures.ensure()
    }

    // Scans the fixtures and returns the root FSItem with logical sizes.
    private func scanFixtures() throws -> FSItem {
        let root = FSItem(url: Self.fixturesRoot as NSURL)
        try root.loadChildren()
        // without a delegate the scanner yields logical sizes; recalculating makes
        // sure that the assertions match the exact bytes we wrote
        root.recalculateSize(false, updateParent: false)
        return root
    }

    // MARK: - fixtures

    func testFixturesExist() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: Self.fixturesRoot.path),
                      "fixtures should have been generated")
    }

    // MARK: - structure

    func testRootIsFolder() throws {
        XCTAssertTrue(try scanFixtures().isFolder())
    }

    func testTopLevelChildCount() throws {
        XCTAssertEqual(Int(try scanFixtures().childCount()), TestFixtures.topLevelChildCount)
    }

    func testTotalFileCount() throws {
        XCTAssertEqual(countFiles(try scanFixtures()), TestFixtures.fileCount)
    }

    func testTotalFolderCount() throws {
        // count nested folders (excluding the scanned root itself)
        XCTAssertEqual(countFolders(try scanFixtures()) - 1, TestFixtures.folderCount)
    }

    func testNestedFolderResolves() throws {
        let root = try scanFixtures()
        let folderA = child(of: root, named: "folderA")
        XCTAssertNotNil(folderA)
        let folderA1 = folderA.flatMap { child(of: $0, named: "folderA1") }
        XCTAssertNotNil(folderA1, "folderA/folderA1 should resolve")
        XCTAssertTrue(folderA1!.isFolder())
    }

    func testEmptyFolder() throws {
        let empty = child(of: try scanFixtures(), named: "emptyFolder")
        XCTAssertNotNil(empty)
        XCTAssertTrue(empty!.isFolder())
        XCTAssertEqual(empty!.childCount(), 0)
        XCTAssertEqual(empty!.sizeValue(), 0)
    }

    // MARK: - sizes

    func testTotalLogicalSize() throws {
        XCTAssertEqual(try scanFixtures().sizeValue(), UInt64(TestFixtures.totalBytes))
    }

    func testKnownLeafFileSize() throws {
        let big = child(of: try scanFixtures(), named: "level0_2mb.dixfix")
        XCTAssertNotNil(big)
        XCTAssertFalse(big!.isFolder())
        XCTAssertEqual(big!.sizeValue(), 2 * 1024 * 1024)
    }

    func testFolderSizeAggregatesChildren() throws {
        let folderA = child(of: try scanFixtures(), named: "folderA")
        XCTAssertNotNil(folderA)
        // 1 MB + 512 KB + 256 KB (the last nested in folderA1)
        XCTAssertEqual(folderA!.sizeValue(), UInt64((1024 + 512 + 256) * 1024))
    }

    // MARK: - helpers

    private func child(of item: FSItem, named name: String) -> FSItem? {
        var i: UInt = 0
        while i < item.childCount() {
            if let c = item.child(at: i), c.name() == name { return c }
            i += 1
        }
        return nil
    }

    private func countFiles(_ item: FSItem) -> Int {
        guard item.isFolder() else { return 1 }
        return eachChild(item).reduce(0) { $0 + countFiles($1) }
    }

    private func countFolders(_ item: FSItem) -> Int {
        guard item.isFolder() else { return 0 }
        return 1 + eachChild(item).reduce(0) { $0 + countFolders($1) }
    }

    private func eachChild(_ item: FSItem) -> [FSItem] {
        var result: [FSItem] = []
        var i: UInt = 0
        while i < item.childCount() {
            if let c = item.child(at: i) { result.append(c) }
            i += 1
        }
        return result
    }
}

// Behaviour of the parallel scanner on small trees which are built on the fly.
final class FSItemScannerBehaviourTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("DIXScanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private final class Delegate: NSObject, FSItemDelegate {
        var usePhysicalSize = false
        var cancel = false
        var progressCalls = 0

        @objc func fsItemShouldUsePhysicalFileSize(_ item: FSItem) -> Bool { usePhysicalSize }
        @objc func fsItemScanProgress(_ item: FSItem, currentFolder: FSItem?) -> Bool {
            progressCalls += 1
            return !cancel
        }
    }

    // MARK: - helpers

    private func makeFolder(_ relativePath: String) throws {
        try FileManager.default.createDirectory(at: tempRoot.appendingPathComponent(relativePath),
                                                withIntermediateDirectories: true)
    }

    private func makeFile(_ relativePath: String, bytes: Int = 1) throws {
        let url = tempRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }

    private func scan(delegate: Delegate? = nil) throws -> FSItem {
        let root = FSItem(url: tempRoot as NSURL)
        root.setDelegate(delegate)   // not retained by the item
        try withExtendedLifetime(delegate) {
            try root.loadChildren()
        }
        return root
    }

    private func children(of item: FSItem) -> [FSItem] {
        return (0..<item.childCount()).compactMap { item.child(at: $0) }
    }

    // MARK: - tests

    func testDelegateGetsProgressAndCanCancel() throws {
        try makeFile("a/b/c.dat")

        let watching = Delegate()
        XCTAssertEqual(children(of: try scan(delegate: watching)).count, 1)
        XCTAssertGreaterThan(watching.progressCalls, 0)

        let canceling = Delegate()
        canceling.cancel = true
        XCTAssertThrowsError(try scan(delegate: canceling)) { error in
            XCTAssertEqual(error as? FSItemError, .loadingCanceled)
        }
    }

    func testPhysicalAndLogicalSizes() throws {
        try makeFile("tiny.dat", bytes: 1)

        let delegate = Delegate()
        let logicalRoot = try scan(delegate: delegate)
        XCTAssertEqual(logicalRoot.sizeValue(), 1)

        delegate.usePhysicalSize = true
        let root = try scan(delegate: delegate)
        XCTAssertGreaterThan(root.sizeValue(), 1, "a 1 byte file occupies a whole block")

        // switching between the sizes doesn't need the file system
        try FileManager.default.removeItem(at: tempRoot.appendingPathComponent("tiny.dat"))
        let physical = root.sizeValue()
        root.recalculateSize(false, updateParent: false)
        XCTAssertEqual(root.sizeValue(), 1)
        root.recalculateSize(true, updateParent: false)
        XCTAssertEqual(root.sizeValue(), physical)
    }

    func testAppleDoubleFilesAreSkipped() throws {
        // like NSDirectoryEnumerator, which the former scanner used
        try makeFile("kept.dat")
        try makeFile("._kept.dat")
        try makeFolder("._folder")

        XCTAssertEqual(children(of: try scan()).map { $0.name() }, ["kept.dat"])
    }

    func testSymbolicLinksAreNotFollowed() throws {
        try makeFile("real/inside.dat", bytes: 100)
        try FileManager.default.createSymbolicLink(at: tempRoot.appendingPathComponent("link"),
                                                   withDestinationURL: tempRoot.appendingPathComponent("real"))

        let root = try scan()
        let link = try XCTUnwrap(children(of: root).first { $0.name() == "link" })
        XCTAssertFalse(link.isFolder())
        XCTAssertEqual(link.childCount(), 0)
        XCTAssertEqual(children(of: root).count, 2)
    }

    func testPackagesAndKinds() throws {
        try makeFile("Thing.app/Contents/x.txt")
        try makeFile("one.txt")
        try makeFile("two.txt")
        try makeFolder("plain")

        let root = try scan()
        let thing = try XCTUnwrap(children(of: root).first { $0.name() == "Thing.app" })
        let plain = try XCTUnwrap(children(of: root).first { $0.name() == "plain" })
        let one = try XCTUnwrap(children(of: root).first { $0.name() == "one.txt" })
        let two = try XCTUnwrap(children(of: root).first { $0.name() == "two.txt" })

        XCTAssertTrue(thing.isFolder())
        XCTAssertTrue(thing.isPackage())
        XCTAssertTrue(plain.isFolder())
        XCTAssertFalse(plain.isPackage())
        XCTAssertFalse(one.isPackage())

        XCTAssertFalse(one.kindName().isEmpty)
        XCTAssertEqual(one.kindName(), two.kindName())
        XCTAssertNotEqual(one.kindName(), plain.kindName())
        XCTAssertNotEqual(thing.kindName(), plain.kindName())
    }

    func testChildrenAreSortedBySizeAndFoldersSumUpTheirChildren() throws {
        try makeFile("small.dat", bytes: 10)
        try makeFile("big.dat", bytes: 5000)
        try makeFile("sub/medium.dat", bytes: 300)
        try makeFile("sub/deeper/tiny.dat", bytes: 20)

        let root = try scan()
        XCTAssertEqual(root.sizeValue(), 5330)
        XCTAssertEqual(children(of: root).map { $0.name() }, ["big.dat", "sub", "small.dat"])

        let sub = children(of: root)[1]
        XCTAssertEqual(sub.sizeValue(), 320)
        XCTAssertEqual(children(of: sub).map { $0.sizeValue() }, [300, 20])
    }

    func testItemsKnowTheirPathsAndURLs() throws {
        try makeFile("a/b/c.dat")

        let root = try scan()
        let a = try XCTUnwrap(children(of: root).first)
        let b = try XCTUnwrap(children(of: a).first)
        let c = try XCTUnwrap(children(of: b).first)

        XCTAssertEqual(c.path(), tempRoot.appendingPathComponent("a/b/c.dat").path)
        XCTAssertEqual(c.fileURL()?.path, c.path())
        XCTAssertEqual(b.fileURL()?.path, tempRoot.appendingPathComponent("a/b").path)
        XCTAssertTrue(b.isFolder())
        XCTAssertTrue(c.parent() === b)
        XCTAssertTrue(root.findItem(byAbsolutePath: c.path(), allowAncestors: false) === c)
    }

    func testFolderWhichCantBeReadStaysEmpty() throws {
        try makeFile("locked/hidden.dat")
        try makeFile("open.dat")
        let locked = tempRoot.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let root = try scan()
        XCTAssertEqual(children(of: root).count, 2)
        let item = try XCTUnwrap(children(of: root).first { $0.name() == "locked" })
        XCTAssertTrue(item.isFolder())
        XCTAssertEqual(item.childCount(), 0)
    }
}

// Regression coverage for Swift image ownership when AppKit copies NSCells.
final class ImageAndTextCellTests: XCTestCase {

    func testRepeatedCopiesKeepCachedIconAliveAndReleaseItAfterwards() {
        weak var cachedImage: NSImage?
        autoreleasepool {
            let cache = NSMutableDictionary()
            let original = ImageAndTextCell(textCell: "source")
            autoreleasepool {
                let image = NSImage(size: NSSize(width: 16, height: 16))
                cachedImage = image
                original.image = image
                cache.setObject(image, forKey: "icon" as NSString)
            }
            for _ in 0..<1000 {
                autoreleasepool {
                    let copy = original.copy() as! ImageAndTextCell
                    XCTAssertTrue(copy.image === original.image)
                    XCTAssertEqual(copy.stringValue, "source")
                }
                XCTAssertNotNil(cachedImage)
            }
            withExtendedLifetime((cache, original)) {}
        }
        XCTAssertNil(cachedImage, "the copied cells must not leak the image")
    }

    func testCopyKeepsImageAfterOriginalIsReleased() {
        weak var image: NSImage?
        let copy: ImageAndTextCell = autoreleasepool {
            let original = ImageAndTextCell(textCell: "source")
            let icon = NSImage(size: NSSize(width: 16, height: 16))
            image = icon
            original.image = icon
            return original.copy() as! ImageAndTextCell
        }
        XCTAssertNotNil(image)
        XCTAssertTrue(copy.image === image)
        copy.image = nil
        XCTAssertNil(image)
    }

    func testReplacingCopiedImagePreservesOriginal() {
        let original = ImageAndTextCell(textCell: "source")
        let image = NSImage(size: NSSize(width: 16, height: 16))
        original.image = image
        let copy = original.copy() as! ImageAndTextCell
        copy.image = NSImage(size: NSSize(width: 32, height: 32))
        XCTAssertTrue(original.image === image)
        XCTAssertFalse(copy.image === image)
        let empty = ImageAndTextCell(textCell: "empty").copy() as! ImageAndTextCell
        XCTAssertNil(empty.image)
        XCTAssertEqual(empty.stringValue, "empty")
    }
}
