//
//  FSItemSupport.swift
//  Disk Inventory Xs
//
//  Swift port of FSItemSupport.{h,m}. The non-class support symbols extracted
//  from FSItem: the scan counters, the FSItemType enum, and the
//  compareAsFilesystemName: NSString helper. Every consumer is now Swift.
//
//  GPL v3
//

import Cocoa

// scan counters (debugging/logging)
var g_fileCount: UInt32 = 0
var g_folderCount: UInt32 = 0

@objc enum FSItemType: Int {
    case fileFolderItem = 0  // regular file or folder
    case otherSpaceItem = 1  // "other" space (the rest of the volume's files)
    case freeSpaceItem = 2   // free space on the volume
}

// Bare-name aliases preserving the original C-enum constant names so the
// existing FSItem / TreeMapViewController call sites (assignments, comparisons,
// and `switch … default:` blocks) compile unchanged.
let FileFolderItem = FSItemType.fileFolderItem
let OtherSpaceItem = FSItemType.otherSpaceItem
let FreeSpaceItem = FSItemType.freeSpaceItem

extension NSString {
    // numeric + case-insensitive compare. The @objc selector is
    // compareAsFilesystemName: (used by NSSortDescriptor via that selector); the
    // Swift name is compare(asFilesystemName:) — what the ObjC category imported
    // as, so the existing FSItem call sites are unchanged.
    @objc(compareAsFilesystemName:)
    func compare(asFilesystemName other: String) -> ComparisonResult {
        compare(other, options: [.numeric, .caseInsensitive])
    }
}
