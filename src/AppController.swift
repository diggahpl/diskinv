//
//  AppController.swift
//  Disk Inventory Xs
//
//  Swift port of AppController.{h,m}. NSApplicationDelegate instantiated from
//  MainMenu.nib; it only installs the app-wide look at launch. Nib-wired, so
//  the class name is pinned with @objc(AppController).
//
//  GPL v3
//

import Cocoa

@objc(AppController)
class AppController: NSObject, NSApplicationDelegate {

    func applicationWillFinishLaunching(_ notification: Notification) {
        Theme.install()
    }
}
