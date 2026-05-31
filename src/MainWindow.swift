//
//  MainWindow.swift
//  Disk Inventory Xs
//
//  Swift port of MainWindow.{h,m}. The main document window (nib customClass).
//  Its only behavior is to opt out of window state restoration. Nib-wired, so
//  the class name is pinned with @objc(MainWindow).
//
//  GPL v3
//

import Cocoa

@objc(MainWindow)
class MainWindow: NSWindow {

    // kept for the nib connection (the mouseMoved forwarding that used it is gone)
    @IBOutlet private var _treeMapView: NSView!

    // prevent a window that was open at last quit from being restored at launch
    // (NSWindowRestoration class method, not an NSWindow override)
    @objc(restoreWindowWithIdentifier:state:completionHandler:)
    class func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier,
                             state: NSCoder,
                             completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        completionHandler(nil, nil)
    }
}
