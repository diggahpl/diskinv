//
//  FileSystemDocSupport.swift
//  Disk Inventory Xs
//
//  Swift port of FileSystemDocSupport.{h,m}. The KVO-key and notification
//  constants that were extracted from FileSystemDoc when it was ported. Every
//  consumer is now Swift, so these are plain Swift constants.
//
//  The notification names matter: the ObjC importer used to map each
//  `extern NSString *XxxNotification` to `NSNotification.Name.Xxx` (suffix
//  stripped). Reproduce that here as an explicit extension, preserving the exact
//  string VALUES (note ViewOptionChanged's value is "ViewOptionsChangedNotification",
//  which differs from its name).
//
//  GPL v3
//

import Foundation

extension NSNotification.Name {
    static let GlobalSelectionChanged = NSNotification.Name("GlobalSelectionChanged") // userInfo: new + old selection
    static let ZoomedItemChanged = NSNotification.Name("ZoomedItemChanged")           // userInfo: new + old zoomed item
    static let FSItemsChanged = NSNotification.Name("FSItemsChanged")                  // items modified/added/deleted; userInfo nil
    static let ViewOptionChanged = NSNotification.Name("ViewOptionsChangedNotification") // userInfo[ChangedViewOption] = option
}

/* KVO key */
let DocKeySelectedItem = "selectedItem"

/* notification userInfo keys */
let ChangedViewOption = "ChangedViewOption"
let NewItem = "NewItem"
let OldItem = "OldItem"
