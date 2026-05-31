//
//  FSItemIndexType.swift
//  Disk Inventory Xs
//
//  Swift port of FSItemIndexType.h (an NS_OPTIONS bitmask). Selects which
//  index(es) a selection-list search covers. Swift-only consumers now, so it's
//  a Swift OptionSet.
//
//  GPL v3
//

import Foundation

struct FSItemIndexType: OptionSet {
    let rawValue: UInt

    static let name = FSItemIndexType(rawValue: 1)
    static let kind = FSItemIndexType(rawValue: 2)
    static let path = FSItemIndexType(rawValue: 4)
    static let all = FSItemIndexType(rawValue: 0xffff)
}
