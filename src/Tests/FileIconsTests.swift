//
//  FileIconsTests.swift
//  Disk Inventory XTests
//
//  Covers the symbol the files outline shows for a file type: the type hierarchy
//  decides, so every kind of image is a photo and every archive an archive box.
//
//  GPL v3
//

import XCTest
@testable import Disk_Inventory_Xs

final class FileIconsTests: XCTestCase {

    func testSymbolFollowsTheFileTypesHierarchy() {
        let expected: [String: String] = [
            "png": "photo", "heic": "photo", "jpg": "photo",
            "mp4": "film", "mov": "film",
            "mp3": "waveform", "wav": "waveform",
            "zip": "archivebox",
            "dmg": "opticaldiscdrive",
            "pdf": "doc.richtext",
            "swift": "chevron.left.forwardslash.chevron.right",
            "txt": "doc.text"
        ]
        for (ext, symbol) in expected {
            XCTAssertEqual(FileIcons.symbolName(forExtension: ext), symbol, "extension \(ext)")
        }
    }

    func testUnknownAndMissingExtensionsGetThePlainDocument() {
        XCTAssertEqual(FileIcons.symbolName(forExtension: ""), "doc")
        XCTAssertEqual(FileIcons.symbolName(forExtension: "zzqqxx"), "doc")
    }
}
