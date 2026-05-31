//
//  NSString+DIX.swift
//  Disk Inventory Xs
//
//  Swift port of NSString+DIXExtensions and NSString+DIXUnicode
//  (replacements for OmniFoundation NSString helpers).
//
//  GPL v3
//

import Foundation

@objc extension NSString {

    @objc(isEmptyString:)
    class func isEmptyString(_ string: String?) -> Bool {
        guard let string = string else { return true }
        return string.isEmpty
    }

    @objc(horizontalEllipsisString)
    class func horizontalEllipsis() -> String {
        // Unicode horizontal ellipsis character U+2026
        "\u{2026}"
    }
}
