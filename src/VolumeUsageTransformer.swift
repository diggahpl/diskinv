//
//  VolumeUsageTransformer.swift
//  Disk Inventory Xs
//
//  Swift port of VolumeUsageTransformer.{h,m}. Produces a right-aligned
//  attributed string with "Capacity / Used / Free" for the volume usage
//  column. Backed by FileSizeFormatter and the NSURL-Extensions ObjC
//  category (exposed via the bridging header).
//
//  GPL v3
//

import Cocoa

@objc(VolumeUsageTransformer)
final class VolumeUsageTransformer: ValueTransformer {

    private let sizeFormatter = FileSizeFormatter()

    @objc class func transformer() -> VolumeUsageTransformer {
        VolumeUsageTransformer()
    }

    override class func transformedValueClass() -> AnyClass {
        NSString.self
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let volume = value as? NSURL else { return nil }

        var strCapacity = "n/a"
        var strFree = "n/a"
        var strUsed = "n/a"

        if volume.getCachedBoolValue(URLResourceKey.volumeSupportsVolumeSizesKey.rawValue) {
            let numCapacity = volume.cachedVolumeTotalCapacity()
            let numFree = volume.cachedVolumeAvailableCapacity()
            let capacity = numCapacity?.uint64Value ?? 0
            let free = numFree?.uint64Value ?? 0
            let numUsed = NSNumber(value: capacity - free)

            strCapacity = sizeFormatter.string(for: numCapacity) ?? "n/a"
            strFree = sizeFormatter.string(for: numFree) ?? "n/a"
            strUsed = sizeFormatter.string(for: numUsed) ?? "n/a"
        }

        let capacityField = "\(NSLocalizedString("Capacity", comment: "")): \(strCapacity)"
        let usedAndFreeFields = "\n\(NSLocalizedString("Used", comment: "")): \(strUsed)"
            + "\n\(NSLocalizedString("Free", comment: "")): \(strFree)"

        let attribString = NSMutableAttributedString(string: capacityField,
                                                      attributes: Self.capacityStringAttributes)
        attribString.append(NSAttributedString(string: usedAndFreeFields,
                                               attributes: Self.usedAndFreeStringAttributes))
        return attribString
    }

    private static let capacityStringAttributes: [NSAttributedString.Key: Any] = {
        let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        style.alignment = .right
        return [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: style
        ]
    }()

    private static let usedAndFreeStringAttributes: [NSAttributedString.Key: Any] = {
        let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        style.alignment = .right
        return [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .paragraphStyle: style
        ]
    }()
}
