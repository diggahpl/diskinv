//
//  VolumeNameTransformer.swift
//  Disk Inventory Xs
//
//  Swift port of VolumeNameTransformer.{h,m}. Produces a two-line
//  attributed string ("<volume display name>\n <volume format>") for the
//  volume name column. Backed by the NSURL-Extensions ObjC category
//  (exposed via the bridging header).
//
//  GPL v3
//

import Cocoa

@objc(VolumeNameTransformer)
final class VolumeNameTransformer: ValueTransformer {

    @objc class func transformer() -> VolumeNameTransformer {
        VolumeNameTransformer()
    }

    override class func transformedValueClass() -> AnyClass {
        NSAttributedString.self
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let vol = value as? NSURL else { return nil }

        let name = vol.cachedDisplayName()
        let volumeType = vol.cachedVolumeFormatName()

        // volume display name
        let attribString = NSMutableAttributedString(string: name,
                                                      attributes: Self.volumeTitleAttributes)

        // volume type (e.g. "HFS+") on a second line
        if !volumeType.isEmpty {
            attribString.append(NSAttributedString(string: "\n "))
            attribString.append(NSAttributedString(string: volumeType,
                                                    attributes: Self.volumeTypeAttributes))
        }

        return attribString
    }

    private static let volumeTitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 0) // default size
    ]

    private static let volumeTypeAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    ]
}
