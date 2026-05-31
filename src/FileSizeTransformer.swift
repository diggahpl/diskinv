//
//  FileSizeTransformer.swift
//  Disk Inventory Xs
//
//  Swift port of FileSizeTransformer.{h,m}.
//
//  GPL v3
//

import Cocoa

@objc(FileSizeTransformer)
final class FileSizeTransformer: ValueTransformer {

    private let sizeFormatter = FileSizeFormatter()

    @objc class func transformer() -> FileSizeTransformer {
        FileSizeTransformer()
    }

    override class func transformedValueClass() -> AnyClass {
        NSString.self
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let value = value else { return nil }
        return sizeFormatter.string(for: value)
    }
}
