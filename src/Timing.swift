//
//  Timing.swift
//  Disk Inventory Xs
//
//  Swift port of Timing.{h,c}. A mach_absolute_time stopwatch used to throttle
//  the scan progress panel and to time the render/layout benchmarks. Swift-only
//  callers, so these are plain global functions.
//
//  GPL v3
//

import Foundation

// seconds per mach tick — computed once (the C version cached it in a static)
private let secondsPerTick: Double = {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return 1e-9 * Double(timebase.numer) / Double(timebase.denom)
}()

func getTime() -> UInt64 {
    mach_absolute_time()
}

func subtractTime(_ endTime: UInt64, _ startTime: UInt64) -> Double {
    Double(endTime - startTime) * secondsPerTick
}
