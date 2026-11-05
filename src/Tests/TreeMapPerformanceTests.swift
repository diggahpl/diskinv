//
//  TreeMapPerformanceTests.swift
//  Disk Inventory XTests
//
//  Guards the treemap layout and cushion rendering against regressions and
//  measures them.
//
//  The always-on tests use a seeded synthetic tree (no file system involved) and
//  check that layout, hit testing and every rendered pixel stay bit-for-bit
//  identical: a hash recorded from the single-threaded, uncached implementation
//  is pinned below, and the cushion renderer is also compared against a verbatim
//  copy of that implementation's pixel loop.
//
//  The benchmark scans a real folder (default /Applications, override with
//  DIX_BENCH_PATH) and times tree build, layout, rendering and hit testing at a
//  Retina-sized window. It only runs when the DIX_TREEMAP_BENCH environment
//  variable is set (xcodebuild needs the TEST_RUNNER_ prefix to forward it) and
//  is meant for a Release build:
//
//    TEST_RUNNER_DIX_TREEMAP_BENCH=1 xcodebuild test -configuration Release ...
//
//  GPL v3
//

import XCTest
import Cocoa
@testable import Disk_Inventory_Xs

// MARK: - helpers

// SplitMix64: tiny seeded generator so the synthetic tree is identical on every machine.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

// FNV-1a over a byte stream; plenty to detect any changed pixel or rect.
private struct Fnv1a {
    private(set) var value: UInt64 = 0xCBF2_9CE4_8422_5DC5

    mutating func addByte(_ byte: UInt8) {
        value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }

    mutating func addWord(_ number: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            addByte(UInt8(truncatingIfNeeded: number >> UInt64(shift)))
        }
    }

    mutating func addRect(_ rect: NSRect) {
        addWord(Double(rect.origin.x).bitPattern)
        addWord(Double(rect.origin.y).bitPattern)
        addWord(Double(rect.size.width).bitPattern)
        addWord(Double(rect.size.height).bitPattern)
    }

    mutating func addRows(of bitmap: NSBitmapImageRep) {
        guard let pixels = bitmap.bitmapData else { return }
        let rowBytes = bitmap.pixelsWide * 3
        for y in 0..<bitmap.pixelsHigh {
            let row = UnsafeBufferPointer(start: pixels + y * bitmap.bytesPerRow, count: rowBytes)
            for byte in row { addByte(byte) }
        }
    }
}

private func hex(_ value: UInt64) -> String {
    "0x" + String(value, radix: 16, uppercase: true)
}

// MARK: - synthetic data source

private final class SyntheticNode {
    let id: Int
    var weight: UInt64
    var children: [SyntheticNode]
    let isFolder: Bool
    let paletteIndex: Int

    init(id: Int, weight: UInt64, children: [SyntheticNode], isFolder: Bool, paletteIndex: Int) {
        self.id = id
        self.weight = weight
        self.children = children
        self.isFolder = isFolder
        self.paletteIndex = paletteIndex
    }

    var leafCount: Int { isFolder ? children.reduce(0) { $0 + $1.leafCount } : 1 }
}

private enum SyntheticTree {

    // A folder tree with roughly `leaves` files. Like a real disk it has chains
    // of single-child folders, empty folders, zero-sized files and file sizes
    // spread over many orders of magnitude; children are sorted by size (as
    // FSItem keeps them).
    static func make(seed: UInt64, leaves: Int) -> SyntheticNode {
        var rng = SeededGenerator(state: seed)
        var nextId = 0
        let root = build(leaves: leaves, depth: 0, rng: &rng, nextId: &nextId)
        return root
    }

    private static func build(leaves: Int, depth: Int, rng: inout SeededGenerator,
                              nextId: inout Int) -> SyntheticNode {
        let id = nextId
        nextId += 1

        if leaves <= 1 && depth > 0 {
            let zeroSized = rng.unit() < 0.05
            let weight = zeroSized ? 0 : UInt64(exp2(6 + rng.unit() * 20))
            return SyntheticNode(id: id, weight: weight, children: [], isFolder: false,
                                 paletteIndex: Int(rng.next() % 12))
        }

        if depth > 0 && rng.unit() < 0.03 {
            return SyntheticNode(id: id, weight: 0, children: [], isFolder: true, paletteIndex: 0)  // empty folder
        }

        let childCount = (rng.unit() < 0.15 || depth > 30) ? 1 : min(max(leaves, 2), 2 + Int(rng.next() % 9))

        // split the leaves over the children with a skewed distribution
        var shares = (0..<childCount).map { _ in pow(rng.unit(), 2) + 0.01 }
        let shareSum = shares.reduce(0, +)
        shares = shares.map { $0 / shareSum }

        var children: [SyntheticNode] = []
        var assigned = 0
        for (index, share) in shares.enumerated() {
            let remaining = leaves - assigned
            let slotsLeft = childCount - index - 1
            let count = index == childCount - 1 ? remaining
                : min(max(Int((share * Double(leaves)).rounded()), 1), max(remaining - slotsLeft, 1))
            assigned += count
            children.append(build(leaves: count, depth: depth + 1, rng: &rng, nextId: &nextId))
        }
        children.sort { ($0.weight, $1.id) > ($1.weight, $0.id) }

        return SyntheticNode(id: id, weight: children.reduce(0) { $0 + $1.weight }, children: children,
                             isFolder: true, paletteIndex: 0)
    }
}

// Answers the tree map view's informal data source / delegate protocols with the
// same dynamic shape as TreeMapViewController: items arrive as `Any!`, nil means
// the root, every answer goes through an `as?` cast.
private final class SyntheticDataSource: NSObject {
    let root: SyntheticNode
    private let palette: [NSColor]

    init(root: SyntheticNode) {
        self.root = root
        self.palette = (0..<12).map { index in
            let phase = Double(index) / 12 * 2 * .pi
            return TMVCushionRenderer.normalize(NSColor(calibratedRed: 0.5 + 0.5 * CGFloat(cos(phase)),
                                                        green: 0.5 + 0.5 * CGFloat(cos(phase + 2.1)),
                                                        blue: 0.5 + 0.5 * CGFloat(cos(phase + 4.2)),
                                                        alpha: 1))
        }
        super.init()
    }

    @objc func treeMapView(_ view: TreeMapView!, child index: UInt, ofItem item: Any!) -> Any! {
        ((item as? SyntheticNode) ?? root).children[Int(index)]
    }

    @objc func treeMapView(_ view: TreeMapView!, isNode item: Any!) -> Bool {
        ((item as? SyntheticNode) ?? root).isFolder
    }

    @objc func treeMapView(_ view: TreeMapView!, numberOfChildrenOfItem item: Any!) -> UInt32 {
        UInt32(((item as? SyntheticNode) ?? root).children.count)
    }

    @objc func treeMapView(_ view: TreeMapView!, weightByItem item: Any!) -> UInt64 {
        ((item as? SyntheticNode) ?? root).weight
    }

    @objc(treeMapView:willDisplayItem:withRenderer:)
    func treeMapView(_ view: TreeMapView!, willDisplayItem item: Any!, withRenderer renderer: TMVItem!) {
        let node = (item as? SyntheticNode) ?? root
        renderer.setCushionColor(palette[node.paletteIndex])
    }
}

// MARK: - tests

final class TreeMapPerformanceTests: XCTestCase {

    // Hashes recorded from the implementation before it was cached and
    // parallelized (single-threaded shading, dynamic isLeaf()/weight()).
    // Synthetic tree: seed 0xD15C, 4000 leaves, view 1000x700 at scale 1.
    private static let goldenLayoutHash: UInt64 = 0x5FAA18657B8D2FDE
    private static let goldenHitTestHash: UInt64 = 0x093E2772FEBC1CA4
    private static let goldenPixelHash: UInt64 = 0x2EA97F87AC7B5F5D

    private static let imageSize = NSSize(width: 1000, height: 700)

    private func makeView(size: NSSize = TreeMapPerformanceTests.imageSize) -> TreeMapView {
        TreeMapView(frame: NSRect(origin: .zero, size: size))
    }

    private func makeRoot(_ source: SyntheticDataSource, view: TreeMapView) -> TMVItem {
        TMVItem(dataSource: source, delegate: source, renderedItem: nil, treeMapView: view)
    }

    private func leaves(of item: TMVItem) -> [TMVItem] {
        if item.isLeaf() { return [item] }
        return item.childCount() == 0 ? [] : item.childEnumerator().allObjects.flatMap { leaves(of: $0 as! TMVItem) }
    }

    private func layoutHash(_ root: TMVItem) -> UInt64 {
        var hash = Fnv1a()
        func visit(_ item: TMVItem) {
            hash.addRect(item.rect())
            hash.addWord(item.isLeaf() ? 1 : 0)
            hash.addWord(item.weight())
            if !item.isLeaf() {
                for case let child as TMVItem in item.childEnumerator() { visit(child) }
            }
        }
        visit(root)
        return hash.value
    }

    private func hitTestHash(_ root: TMVItem, size: NSSize, points: Int) -> UInt64 {
        var rng = SeededGenerator(state: 0xB17)
        var hash = Fnv1a()
        for _ in 0..<points {
            let point = NSPoint(x: (rng.unit() * Double(size.width)).rounded(.down) + 0.5,
                                y: (rng.unit() * Double(size.height)).rounded(.down) + 0.5)
            if let hit = root.hitTest(point), let node = hit.item() as? SyntheticNode {
                hash.addWord(UInt64(node.id) + 1)
            } else {
                hash.addWord(0)
            }
        }
        return hash.value
    }

    private func renderedBitmap(_ root: TMVItem, size: NSSize) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(rgbBitmapWithWidth: Int(size.width), height: Int(size.height)))
        // pixels no leaf covers (tiny or zero-sized cells) keep this value
        if let pixels = bitmap.bitmapData {
            memset(pixels, 0xAB, bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        root.drawCushion(inBitmap: bitmap)
        return bitmap
    }

    // MARK: baseline equality

    func testSyntheticTreeShapeIsStable() {
        let tree = SyntheticTree.make(seed: 0xD15C, leaves: 4000)
        print("[TMBENCH] synthetic tree: \(tree.leafCount) files, root weight \(tree.weight)")
        XCTAssertGreaterThan(tree.leafCount, 1000)
        XCTAssertEqual(tree.weight, tree.children.reduce(0) { $0 + $1.weight })
    }

    func testLayoutAndHitTestingMatchBaseline() {
        let size = Self.imageSize
        let source = SyntheticDataSource(root: SyntheticTree.make(seed: 0xD15C, leaves: 4000))
        let root = makeRoot(source, view: makeView())
        root.calcLayout(NSRect(origin: .zero, size: size))

        let layout = layoutHash(root)
        let hits = hitTestHash(root, size: size, points: 20_000)
        print("[TMBENCH] synthetic layoutHash=\(hex(layout)) hitTestHash=\(hex(hits))")

        XCTAssertEqual(layout, Self.goldenLayoutHash, "layout changed: \(hex(layout))")
        XCTAssertEqual(hits, Self.goldenHitTestHash, "hit testing changed: \(hex(hits))")
    }

    func testRenderedPixelsMatchBaseline() throws {
        let size = Self.imageSize
        let source = SyntheticDataSource(root: SyntheticTree.make(seed: 0xD15C, leaves: 4000))
        let root = makeRoot(source, view: makeView())
        root.calcLayout(NSRect(origin: .zero, size: size))

        let bitmap = try renderedBitmap(root, size: size)
        var hash = Fnv1a()
        hash.addRows(of: bitmap)
        print("[TMBENCH] synthetic pixelHash=\(hex(hash.value))")

        XCTAssertEqual(hash.value, Self.goldenPixelHash, "rendered pixels changed: \(hex(hash.value))")
    }

    // Rendering the same laid-out tree twice must give the same picture.
    func testRenderingIsRepeatable() throws {
        let size = Self.imageSize
        let source = SyntheticDataSource(root: SyntheticTree.make(seed: 0xD15C, leaves: 4000))
        let root = makeRoot(source, view: makeView())
        root.calcLayout(NSRect(origin: .zero, size: size))

        var first = Fnv1a(), second = Fnv1a()
        first.addRows(of: try renderedBitmap(root, size: size))
        second.addRows(of: try renderedBitmap(root, size: size))
        XCTAssertEqual(first.value, second.value)
    }

    // The leaves tile the root without overlapping, which is what allows shading them concurrently.
    func testLeafRectsDoNotOverlap() {
        let size = Self.imageSize
        let source = SyntheticDataSource(root: SyntheticTree.make(seed: 0xD15C, leaves: 4000))
        let root = makeRoot(source, view: makeView())
        root.calcLayout(NSRect(origin: .zero, size: size))

        var coverage = [UInt8](repeating: 0, count: Int(size.width * size.height))
        var overlaps = 0
        for leaf in leaves(of: root) {
            let rect = leaf.rect()
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    if coverage[y * Int(size.width) + x] != 0 { overlaps += 1 }
                    coverage[y * Int(size.width) + x] = 1
                }
            }
        }
        XCTAssertEqual(overlaps, 0)
    }

    // After the data changes, refresh(withItem:) must produce what a fresh tree would.
    func testRefreshPicksUpChangedData() {
        let size = Self.imageSize
        let tree = SyntheticTree.make(seed: 0xD15C, leaves: 400)
        let source = SyntheticDataSource(root: tree)
        let view = makeView()
        let root = makeRoot(source, view: view)
        root.calcLayout(NSRect(origin: .zero, size: size))
        let before = layoutHash(root)

        // change sizes, turn a folder into an empty one and a file into a folder
        func mutate(_ node: SyntheticNode, _ counter: inout Int) {
            counter += 1
            if node.isFolder {
                for child in node.children { mutate(child, &counter) }
                if !node.children.isEmpty { node.weight = node.children.reduce(0) { $0 + $1.weight } }
            } else if counter % 3 == 0 {
                node.weight = node.weight / 2 + 1
            }
        }
        var counter = 0
        mutate(tree, &counter)
        tree.children.sort { ($0.weight, $1.id) > ($1.weight, $0.id) }
        tree.children.removeLast()
        tree.weight = tree.children.reduce(0) { $0 + $1.weight }

        root.refresh(withItem: nil)
        root.calcLayout(NSRect(origin: .zero, size: size))
        let refreshed = layoutHash(root)

        let fresh = makeRoot(source, view: view)
        fresh.calcLayout(NSRect(origin: .zero, size: size))

        XCTAssertNotEqual(before, refreshed)
        XCTAssertEqual(refreshed, layoutHash(fresh))
    }

    // MARK: shader against the verbatim pre-optimization pixel loop

    // Copy of the original per-pixel loop of TMVCushionRenderer.renderCushion, kept as ground truth.
    private func referenceShade(into bitmap: NSBitmapImageRep, rect: NSRect,
                                surface: UnsafePointer<CGFloat>, color: NSColor) {
        let Ia = 0.15
        let lx = -1.0, ly = -1.0, lz = 10.0
        let Is = 1 - Ia
        let len = (lx * lx + ly * ly + lz * lz).squareRoot()
        let Lx = lx / len
        let Ly = lx / len
        let Lz = lz / len

        let colR = Double(color.redComponent)
        let colG = Double(color.greenComponent)
        let colB = Double(color.blueComponent)

        let pixels = bitmap.bitmapData!
        let bytesPerRow = bitmap.bytesPerRow
        let s0 = Double(surface[0]), s1 = Double(surface[1]), s2 = Double(surface[2]), s3 = Double(surface[3])

        for iy in Int(rect.minY)..<Int(rect.maxY) {
            let rowStart = pixels + iy * bytesPerRow
            let ny = -(2 * s1 * (Double(iy) + 0.5) + s3)
            for ix in Int(rect.minX)..<Int(rect.maxX) {
                let nx = -(2 * s0 * (Double(ix) + 0.5) + s2)
                let cosa = (nx * Lx + ny * Ly + Lz) / (nx * nx + ny * ny + 1.0).squareRoot()
                var brightness = Is * cosa
                brightness = brightness < 0 ? Ia : (brightness + Ia)
                brightness *= 2.5 / 1.8

                var red = CGFloat(colR * brightness)
                var green = CGFloat(colG * brightness)
                var blue = CGFloat(colB * brightness)
                TMVCushionRenderer.normalizeColorRed(&red, green: &green, blue: &blue)

                let pixel = rowStart + ix * 3
                pixel[0] = UInt8(red * 255)
                pixel[1] = UInt8(green * 255)
                pixel[2] = UInt8(blue * 255)
            }
        }
    }

    // Bitmaps up to 120x90 are shaded on the calling thread; the big ones are cut into bands and
    // shaded concurrently.
    func testCushionRendererMatchesReferenceShader() throws {
        var rng = SeededGenerator(state: 0x5EED)

        for iteration in 0..<310 {
            let (width, height) = iteration < 300 ? (120, 90) : (900, 700)
            let bitmapA = try XCTUnwrap(NSBitmapImageRep(rgbBitmapWithWidth: width, height: height))
            let bitmapB = try XCTUnwrap(NSBitmapImageRep(rgbBitmapWithWidth: width, height: height))
            memset(bitmapA.bitmapData!, 0x5A, bitmapA.bytesPerRow * height)
            memset(bitmapB.bitmapData!, 0x5A, bitmapB.bytesPerRow * height)

            let x0 = Int(rng.next() % UInt64(width)), y0 = Int(rng.next() % UInt64(height))
            let w = 1 + Int(rng.next() % UInt64(width - x0)), h = 1 + Int(rng.next() % UInt64(height - y0))
            let rect = NSRect(x: x0, y: y0, width: w, height: h)

            let renderer = TMVCushionRenderer(rect: rect)
            // the app only ever shades with normalized colors (see FileTypeColors)
            renderer.setColor(TMVCushionRenderer.normalize(
                NSColor(calibratedRed: rng.unit(), green: rng.unit(), blue: rng.unit(), alpha: 1)))
            // random ridge stack, like the nested folders above a leaf
            var ridge = 0.5 as Float
            for _ in 0..<Int(rng.next() % 6) {
                let ancestor = TMVCushionRenderer(rect: NSRect(x: 0, y: 0, width: width, height: height))
                renderer.setSurface(ancestor.surface())
                renderer.addRidge(byHeightFactor: ridge)
                ridge *= 0.9
            }
            renderer.addRidge(byHeightFactor: ridge)

            renderer.renderCushion(inBitmap: bitmapA)
            referenceShade(into: bitmapB, rect: rect, surface: renderer.surface(), color: renderer.color())

            var hashA = Fnv1a(), hashB = Fnv1a()
            hashA.addRows(of: bitmapA)
            hashB.addRows(of: bitmapB)
            XCTAssertEqual(hashA.value, hashB.value, "rect \(rect)")
        }
    }

    // A zero-width cell gives its surface infinite coefficients; a cell that inherits them is
    // shaded with NaN, which must come out as plain bytes instead of trapping the conversion.
    func testDegenerateSurfaceDoesNotTrap() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(rgbBitmapWithWidth: 40, height: 40))
        memset(bitmap.bitmapData!, 0xAB, bitmap.bytesPerRow * 40)

        let degenerate = TMVCushionRenderer(rect: NSRect(x: 5, y: 5, width: 0, height: 10))
        degenerate.addRidge(byHeightFactor: 0.5)

        let cushion = TMVCushionRenderer(rect: NSRect(x: 5, y: 5, width: 8, height: 8))
        cushion.setSurface(degenerate.surface())
        cushion.addRidge(byHeightFactor: 0.45)
        cushion.renderCushion(inBitmap: bitmap)

        let pixels = bitmap.bitmapData!
        for y in 0..<40 {
            for x in 0..<40 {
                let expected: UInt8 = (5..<13).contains(x) && (5..<13).contains(y) ? 0 : 0xAB
                for component in 0..<3 {
                    XCTAssertEqual(pixels[y * bitmap.bytesPerRow + x * 3 + component], expected, "pixel \(x),\(y)")
                }
            }
        }
    }

    // MARK: real-folder benchmark

    private func millis(_ seconds: Double) -> String {
        String(format: "%.2f ms", seconds * 1000)
    }

    private func median(_ samples: [Double]) -> Double {
        samples.sorted()[samples.count / 2]
    }

    private func measure(runs: Int, warmup: Int = 1, _ block: () -> Void) -> [Double] {
        for _ in 0..<warmup { block() }
        return (0..<runs).map { _ in
            let start = getTime()
            block()
            return subtractTime(getTime(), start)
        }
    }

    func testBenchmarkRealFolder() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["DIX_TREEMAP_BENCH"] != nil, "set DIX_TREEMAP_BENCH to run the benchmark")

        let path = environment["DIX_BENCH_PATH"] ?? "/Applications"
        let pixelSize = NSSize(width: 3000, height: 1800)

        // the scan, with package contents shown, as the app does it for a disk
        let document = BenchmarkDocument()
        let scanStart = getTime()
        let scanRoot = FSItem(url: URL(fileURLWithPath: path) as NSURL)
        scanRoot.setDelegate(document)
        try scanRoot.loadChildren()
        scanRoot.recalculateSize(false, updateParent: false)
        print("[TMBENCH] scan of \(path): \(millis(subtractTime(getTime(), scanStart))), "
              + "\(scanRoot.sizeValue() / 1_000_000) MB")

        // data source = the real TreeMapViewController on a document that serves the scanned tree
        document.benchmarkRoot = scanRoot

        let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false      // ARC owns it; the default would release it a second time
        let scale = max(window.backingScaleFactor, 1)
        let view = TreeMapView(frame: NSRect(x: 0, y: 0, width: pixelSize.width / scale,
                                             height: pixelSize.height / scale))
        window.setContentSize(view.frame.size)
        window.contentView = view

        let controller = TreeMapViewController()
        controller.setValue(view, forKey: "_treeMapView")
        controller.setValue(document, forKey: "_document")
        view.dataSource = controller
        view.delegate = controller
        controller.awakeFromNib()
        defer { window.close() }

        // DIX_BENCH_RUNS lengthens the layout/render/hit test phases (for attaching a profiler)
        let runs = Int(environment["DIX_BENCH_RUNS"] ?? "") ?? 8

        print("[TMBENCH] phase build")
        var buildRoot: TMVItem!
        let build = measure(runs: 3) {
            buildRoot = TMVItem(dataSource: controller, delegate: controller, renderedItem: nil, treeMapView: view)
        }
        let root = buildRoot!

        let rectA = NSRect(origin: .zero, size: pixelSize)
        let rectB = NSRect(x: 0, y: 0, width: pixelSize.width - 8, height: pixelSize.height - 4)
        var flip = false
        print("[TMBENCH] phase layout")
        let layout = measure(runs: runs) {
            root.calcLayout(flip ? rectB : rectA)
            flip.toggle()
        }
        root.calcLayout(rectA)

        let allLeaves = leaves(of: root)
        let visible = allLeaves.filter { $0.rect().width >= 1 && $0.rect().height >= 1 }
        let drawn = visible.filter { Int($0.rect().width) > 0 }
        let pixelCount = visible.reduce(0.0) { $0 + Double($1.rect().width * $1.rect().height) }

        let bitmap = try XCTUnwrap(NSBitmapImageRep(rgbBitmapWithWidth: Int(pixelSize.width),
                                                    height: Int(pixelSize.height)))
        print("[TMBENCH] phase render")
        let render = measure(runs: runs) { root.drawCushion(inBitmap: bitmap) }

        var rng = SeededGenerator(state: 0xB17)
        let points = (0..<200_000).map { _ in
            NSPoint(x: rng.unit() * Double(pixelSize.width), y: rng.unit() * Double(pixelSize.height))
        }
        print("[TMBENCH] phase hit")
        let hits = measure(runs: max(runs * 5 / 8, 1)) {
            var found = 0
            for point in points where root.hitTest(point) != nil { found += 1 }
            XCTAssertGreaterThan(found, 0)
        }

        var hash = Fnv1a()
        hash.addRows(of: bitmap)

        // the finish and the labels, which run after the shader (the hash above is the shader's)
        print("[TMBENCH] phase polish")
        let polish = measure(runs: runs) { TreeMapPolish.polish(bitmap, root: root, edge: Int(scale)) }
        let sizeFormatter = FileSizeFormatter()
        print("[TMBENCH] phase labels")
        var labelCount = 0
        let labels = measure(runs: runs) {
            labelCount = TreeMapLabels.collect(root: root, view: view, bitmap: bitmap,
                                               name: { controller.treeMapView(view, getToolTipByItem: $0) },
                                               size: { sizeFormatter.string(for: NSNumber(value: $0)) ?? "" }).count
        }

        print("""
            [TMBENCH] ----------------------------------------------------------
            [TMBENCH] folder \(path), backing scale \(scale), image \(Int(pixelSize.width))x\(Int(pixelSize.height)), \
            cores \(ProcessInfo.processInfo.activeProcessorCount)
            [TMBENCH] leaves \(allLeaves.count) (shaded \(drawn.count), \(Int(pixelCount)) px)
            [TMBENCH] tree build   median \(millis(median(build)))   min \(millis(build.min()!))
            [TMBENCH] layout       median \(millis(median(layout)))   min \(millis(layout.min()!))
            [TMBENCH] render       median \(millis(median(render)))   min \(millis(render.min()!))
            [TMBENCH] hitTest x\(points.count)  median \(millis(median(hits)))   min \(millis(hits.min()!))
            [TMBENCH] polish       median \(millis(median(polish)))   min \(millis(polish.min()!))
            [TMBENCH] labels (\(labelCount))  median \(millis(median(labels)))   min \(millis(labels.min()!))
            [TMBENCH] bitmap hash \(hex(hash.value))
            [TMBENCH] ----------------------------------------------------------
            """)
    }
}

// A document that serves a scanned tree directly: shows package contents (so a
// scan of /Applications is a realistic number of items) and no free/other space.
private final class BenchmarkDocument: FileSystemDoc {
    var benchmarkRoot: FSItem?

    override func rootItem() -> FSItem? { benchmarkRoot }
    override func showPackageContents() -> Bool { true }
    override func showFreeSpace() -> Bool { false }
    override func showOtherSpace() -> Bool { false }
}
