//
//  TMVCushionRenderer.swift
//  Disk Inventory Xs
//
//  Swift port of TMVCushionRenderer.{h,m}. Owns the per-cell cushion
//  (Necker-cube) shading parameters and the per-pixel shader that writes into
//  an NSBitmapImageRep, plus color normalization to a fixed brightness.
//
//  The pixel loop is a translation of the ObjC shader: raw bitmapData pointer
//  arithmetic (3 bytes/pixel, bytesPerRow stride), all per-pixel math in Double,
//  the lx/len quirk for Ly, the 2.5/BASE_BRIGHTNESS scaling, and the
//  clamp/redistribute logic. Validated bit-for-bit against the ObjC build, and
//  since then against the single-threaded loop (TreeMapPerformanceTests). The
//  cushions of one treemap are shaded concurrently (see render(_:inBitmap:)).
//
//  Selectors are pinned with @objc so the existing Swift consumers
//  (FileTypeColors, TreeMapViewController, the FileKinds controllers) and the
//  still-ObjC TMVItem keep working unchanged.
//
//  GPL v3
//

import Cocoa

// The treemap colors all have the "brightness" BASE_BRIGHTNESS.
// Brightness is a number from 0 to 3.0. RGB(0.5, 1, 0), for example, has a
// brightness of 2.5.
private let BASE_BRIGHTNESS: CGFloat = 1.8
private let MAX_RGB_VALUE: CGFloat = 1.0

@objc(TMVCushionRenderer)
final class TMVCushionRenderer: NSObject {

    private static let defaultCushionColor: NSColor =
        TMVCushionRenderer.normalize(NSColor(calibratedRed: 0, green: 0, blue: 0.9, alpha: 1))

    private var _rect: NSRect = .zero
    private var _color: NSColor

    // C array `CGFloat _surface[4]` -> a heap buffer so the raw-pointer
    // surface/setSurface: accessors can still vend a CGFloat* to the (still-ObjC)
    // TMVItem. Holds the quadratic ridge polynomial coefficients [ax, ay, bx, by].
    private let _surface = UnsafeMutablePointer<CGFloat>.allocate(capacity: 4)

    @objc
    override init() {
        _color = TMVCushionRenderer.defaultCushionColor
        _surface.initialize(repeating: 0, count: 4)
        _rect = .zero
        super.init()
    }

    @objc(initWithRect:)
    init(rect: NSRect) {
        _color = TMVCushionRenderer.defaultCushionColor
        _surface.initialize(repeating: 0, count: 4)
        _rect = rect
        super.init()
    }

    deinit {
        _surface.deinitialize(count: 4)
        _surface.deallocate()
    }

    @objc
    func rect() -> NSRect {
        _rect
    }

    @objc(setRect:)
    func setRect(_ rect: NSRect) {
        _rect = rect
    }

    @objc
    func color() -> NSColor {
        _color
    }

    // Converting a color to sRGB costs far more than the rest of a leaf's bookkeeping,
    // and all leaves of one file kind hand in the same NSColor instance, so the latest
    // conversions are remembered. setColor(_:) is only called from the main thread.
    private final class ColorConversionCache {
        private static let slotCount = 64
        private var sources = [NSColor?](repeating: nil, count: ColorConversionCache.slotCount)
        private var converted = [NSColor?](repeating: nil, count: ColorConversionCache.slotCount)

        func srgbColor(for color: NSColor) -> NSColor {
            // identify the instance by its address; the slot keeps it alive, so the address stays valid
            let address = Int(bitPattern: Unmanaged.passUnretained(color).toOpaque())
            let slot = (address >> 4) & (ColorConversionCache.slotCount - 1)
            if sources[slot] === color, let cached = converted[slot] {
                return cached
            }
            let result = color.usingColorSpace(.sRGB) ?? color
            sources[slot] = color
            converted[slot] = result
            return result
        }
    }

    private static let colorConversions = ColorConversionCache()

    @objc(setColor:)
    func setColor(_ newColor: NSColor) {
        // we need the color in the RGB color space
        _color = TMVCushionRenderer.colorConversions.srgbColor(for: newColor)
    }

    @objc
    func surface() -> UnsafeMutablePointer<CGFloat> {
        _surface
    }

    @objc(setSurface:)
    func setSurface(_ newsurface: UnsafePointer<CGFloat>) {
        _surface.update(from: newsurface, count: 4)
    }

    @objc(addRidgeByHeightFactor:)
    func addRidge(byHeightFactor heightFactor: Float) {
        // Optimized (gains 15 ms of 1030):
        // ObjC computes `4 * heightFactor` in float (heightFactor is float, 4 is
        // int) then widens to CGFloat; replicate that float step for bit-fidelity.
        let h4: CGFloat = CGFloat(Float(4) * heightFactor)

        let wf: CGFloat = h4 / _rect.width
        _surface[2] += wf * (_rect.maxX + _rect.minX)
        _surface[0] -= wf

        let hf: CGFloat = h4 / _rect.height
        _surface[3] += hf * (_rect.maxY + _rect.minY)
        _surface[1] -= hf
    }

    @objc(renderCushionInBitmap:)
    func renderCushion(inBitmap bitmap: NSBitmapImageRep) {
        TMVCushionRenderer.render([makeJob()], inBitmap: bitmap)
    }

    // MARK: - Shading

    // Everything the shader needs to paint one cushion, as plain values: shading
    // runs on several threads, so it must not touch the renderer or its NSColor.
    struct CushionJob {
        var xStart: Int, xEnd: Int, yStart: Int, yEnd: Int      // pixel rect
        var s0: Double, s1: Double, s2: Double, s3: Double      // surface: [ax, ay, bx, by]
        var colR: Double, colG: Double, colB: Double
    }

    func makeJob() -> CushionJob {
        let baseColor = color()
        return CushionJob(xStart: Int(_rect.minX), xEnd: Int(_rect.maxX),
                          yStart: Int(_rect.minY), yEnd: Int(_rect.maxY),
                          s0: Double(_surface[0]), s1: Double(_surface[1]),
                          s2: Double(_surface[2]), s3: Double(_surface[3]),
                          colR: Double(baseColor.redComponent),
                          colG: Double(baseColor.greenComponent),
                          colB: Double(baseColor.blueComponent))
    }

    // A run of rows of one job; the unit of work handed to a thread.
    private struct Band {
        var job: Int32
        var yStart: Int32
        var yEnd: Int32
    }

    // Below this many pixels, waking the worker threads costs more than it saves.
    private static let parallelPixelThreshold = 1 << 15

    // Shades the cushions into the bitmap. The pixel rects of different cushions
    // never overlap (the layout tiles the parent rect), so they are shaded
    // concurrently: big cushions are cut into bands of rows, tiny ones are batched,
    // and every thread works on chunks of about the same number of pixels.
    static func render(_ jobs: [CushionJob], inBitmap bitmap: NSBitmapImageRep) {
        // we're expecting a bitmap which is at least as big as our rectangles,
        // has a 24 Bit color depth in RGB space (3 * 8 bytes) with no alpha channel
        assert(bitmap.bitsPerSample == 8, "expecting bitmap to have 8 bits per RGB component")
        assert(!bitmap.hasAlpha, "not expecting the bitmap to have alpha component")
        assert(jobs.allSatisfy { $0.yEnd <= bitmap.pixelsHigh }, "_rect exeeds bitmap height")
        assert(jobs.allSatisfy { $0.xEnd <= bitmap.pixelsWide }, "_rect exeeds bitmap width")

        guard let pixels = bitmap.bitmapData else { return }
        let bytesPerRow = bitmap.bytesPerRow

        var totalPixels = 0
        for job in jobs {
            totalPixels += max(job.xEnd - job.xStart, 0) * max(job.yEnd - job.yStart, 0)
        }
        if totalPixels == 0 { return }

        let workers = ProcessInfo.processInfo.activeProcessorCount
        if workers < 2 || totalPixels < parallelPixelThreshold {
            for job in jobs {
                shade(job, yStart: job.yStart, yEnd: job.yEnd, pixels: pixels, bytesPerRow: bytesPerRow)
            }
            return
        }

        // Several chunks per thread, as the performance and efficiency cores differ in speed.
        let chunkPixels = max(totalPixels / (workers * 8), 1 << 14)
        var bands: [Band] = []
        var chunkStarts = [0]       // index in `bands` of the first band of each chunk
        var pixelsInChunk = 0
        for (index, job) in jobs.enumerated() {
            let width = job.xEnd - job.xStart
            guard width > 0, job.yEnd > job.yStart else { continue }
            let rowsPerBand = max(chunkPixels / width, 1)

            var y = job.yStart
            while y < job.yEnd {
                let bandEnd = min(y + rowsPerBand, job.yEnd)
                bands.append(Band(job: Int32(index), yStart: Int32(y), yEnd: Int32(bandEnd)))
                pixelsInChunk += width * (bandEnd - y)
                if pixelsInChunk >= chunkPixels {
                    chunkStarts.append(bands.count)
                    pixelsInChunk = 0
                }
                y = bandEnd
            }
        }
        if chunkStarts.last! != bands.count {
            chunkStarts.append(bands.count)
        }

        jobs.withUnsafeBufferPointer { jobs in
            bands.withUnsafeBufferPointer { bands in
                chunkStarts.withUnsafeBufferPointer { chunkStarts in
                    DispatchQueue.concurrentPerform(iterations: chunkStarts.count - 1) { chunk in
                        for bandIndex in chunkStarts[chunk]..<chunkStarts[chunk + 1] {
                            let band = bands[bandIndex]
                            shade(jobs[Int(band.job)], yStart: Int(band.yStart), yEnd: Int(band.yEnd),
                                  pixels: pixels, bytesPerRow: bytesPerRow)
                        }
                    }
                }
            }
        }
    }

    // Component (0...1) to byte. A NaN or negative component becomes 0 and anything
    // above the range becomes 255, so a degenerate surface can't trap the conversion.
    @inline(__always)
    private static func byte(from component: Double) -> UInt8 {
        let scaled = component * 255
        if !(scaled > 0) { return 0 }
        return scaled >= 255 ? 255 : UInt8(scaled)
    }

    // The per-pixel shader for the rows yStart..<yEnd of one cushion. It is the
    // original loop with the parts that don't depend on the pixel hoisted out, so
    // every pixel is bit-for-bit what the single-threaded implementation produced.
    private static func shade(_ job: CushionJob, yStart: Int, yEnd: Int,
                              pixels: UnsafeMutablePointer<UInt8>, bytesPerRow: Int) {
        // Cushion parameters
        let Ia = 0.15  // ambient light

        // where is the light:
        let lx = -1.0  // negative = left
        let ly = -1.0  // negative = top
        let lz = 10.0

        // Derived parameters
        let Is = 1 - Ia  // brightness

        let len = (lx * lx + ly * ly + lz * lz).squareRoot()
        let Lx = lx / len
        let Ly = lx / len   // BUG (preserved): uses lx, not ly
        let Lz = lz / len

        let brightnessScale = 2.5 / Double(BASE_BRIGHTNESS)
        let twoS0 = 2 * job.s0
        let twoS1 = 2 * job.s1

        var iy = yStart
        while iy < yEnd {
            let rowStart = pixels + iy * bytesPerRow
            let ny = -(twoS1 * (Double(iy) + 0.5) + job.s3)
            let nyLy = ny * Ly
            let nyny = ny * ny

            var ix = job.xStart
            while ix < job.xEnd {
                let nx = -(twoS0 * (Double(ix) + 0.5) + job.s2)

                let cosa = (nx * Lx + nyLy + Lz) / (nx * nx + nyny + 1.0).squareRoot()

                var brightness = Is * cosa
                brightness = brightness < 0 ? Ia : (brightness + Ia)

                assert(!(brightness > 1.0), "brightness must be <=1")   // false for NaN, which byte(from:) handles

                brightness *= brightnessScale

                var red = CGFloat(job.colR * brightness)
                var green = CGFloat(job.colG * brightness)
                var blue = CGFloat(job.colB * brightness)

                if red > MAX_RGB_VALUE || green > MAX_RGB_VALUE || blue > MAX_RGB_VALUE {
                    normalizeColorRed(&red, green: &green, blue: &blue)
                }

                let pixel = rowStart + (ix * 3)
                pixel[0] = byte(from: red)
                pixel[1] = byte(from: green)
                pixel[2] = byte(from: blue)

                ix += 1
            }
            iy += 1
        }
    }

    @objc(normalizeColorRed:green:blue:)
    static func normalizeColorRed(_ red: UnsafeMutablePointer<CGFloat>,
                                  green: UnsafeMutablePointer<CGFloat>,
                                  blue: UnsafeMutablePointer<CGFloat>) {
        // This eats 50% of function time
        if red.pointee > MAX_RGB_VALUE {
            distributeRGB1(red, toRGB2: green, toRGB3: blue)
        } else if green.pointee > MAX_RGB_VALUE {
            distributeRGB1(green, toRGB2: red, toRGB3: blue)
        } else if blue.pointee > MAX_RGB_VALUE {
            distributeRGB1(blue, toRGB2: red, toRGB3: green)
        }
    }

    @objc(normalizeColor:)
    static func normalize(_ color: NSColor) -> NSColor {
        // we need the color in the RGB color space
        var color = color
        if let rgbColor = color.usingColorSpace(.sRGB) {
            color = rgbColor
        }

        var red = color.redComponent
        var green = color.greenComponent
        var blue = color.blueComponent
        let alpha = color.alphaComponent

        let componentSum = red + green + blue
        let f: CGFloat = (componentSum != 0.0) ? (BASE_BRIGHTNESS / componentSum) : 1
        red *= f
        green *= f
        blue *= f

        normalizeColorRed(&red, green: &green, blue: &blue)

        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    // MARK: - Private

    private static func distributeRGB1(_ first: UnsafeMutablePointer<CGFloat>,
                                       toRGB2 second: UnsafeMutablePointer<CGFloat>,
                                       toRGB3 third: UnsafeMutablePointer<CGFloat>) {
        var h: CGFloat = (first.pointee - MAX_RGB_VALUE) / 2.0
        first.pointee = MAX_RGB_VALUE
        second.pointee += h
        third.pointee += h

        if second.pointee > MAX_RGB_VALUE {
            h = second.pointee - MAX_RGB_VALUE
            second.pointee = MAX_RGB_VALUE
            third.pointee += h
            assert(third.pointee <= MAX_RGB_VALUE, "color error")
        } else if third.pointee > MAX_RGB_VALUE {
            h = third.pointee - MAX_RGB_VALUE
            third.pointee = MAX_RGB_VALUE
            second.pointee += h
            assert(second.pointee <= MAX_RGB_VALUE, "color error")
        }
    }
}
