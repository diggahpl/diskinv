//
//  FileSizeFormatter.swift
//  Disk Inventory Xs
//
//  Swift port of FileSizeFormatter.{h,m}.
//
//  GPL v3
//

import Foundation

@objc(FileSizeFormatter)
final class FileSizeFormatter: NumberFormatter, @unchecked Sendable {

    private static let units = ["Bytes", "kB", "MB", "GB", "TB"]
    private static let unitFactor = 1000.0 // not 1024

    override init() {
        super.init()
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        formatterBehavior = .behavior10_0
        localizesFormat = true
        format = "#,#0.0"
    }

    override func string(for obj: Any?) -> String? {
        guard let number = obj as? NSNumber else { return super.string(for: obj) }

        var dsize = number.doubleValue
        var i = 0
        while dsize >= Self.unitFactor && i < Self.units.count - 1 {
            dsize /= Self.unitFactor
            i += 1
        }

        if i <= 1 {
            // Bytes and kB are displayed as integers (like the Finder does)
            return "\(Int(dsize.rounded())) \(Self.units[i])"
        }

        // MB, GB or TB
        let formatted = super.string(for: NSNumber(value: dsize)) ?? ""
        return "\(formatted) \(Self.units[i])"
    }
}
