//
//  DIXToolbarWindowController.swift
//  Disk Inventory Xs
//
//  Swift port of DIXToolbarWindowController.{h,m}. A stock-NSToolbarDelegate
//  window controller that builds its toolbar from a ".toolbar" plist named
//  after the concrete subclass. Base class of OAToolbarWindowControllerEx.
//
//  GPL v3
//

import Cocoa

@objc(DIXToolbarWindowController)
class DIXToolbarWindowController: NSWindowController, NSToolbarDelegate {

    private var _toolbarConfiguration: [String: Any]?

    // override in a subclass; defaults to the concrete class name
    @objc var toolbarConfigurationName: String {
        NSStringFromClass(type(of: self))
    }

    @objc var toolbarConfiguration: [String: Any] {
        if _toolbarConfiguration == nil,
           let path = Bundle.main.path(forResource: toolbarConfigurationName, ofType: "toolbar") {
            _toolbarConfiguration = NSDictionary(contentsOfFile: path) as? [String: Any]
        }
        return _toolbarConfiguration ?? [:]
    }

    @objc(toolbarInfoForItem:)
    func toolbarInfoForItem(_ identifier: String) -> [String: Any]? {
        (toolbarConfiguration["items"] as? [String: Any])?[identifier] as? [String: Any]
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        (toolbarConfiguration["defaultItems"] as? [String])?.map { NSToolbarItem.Identifier($0) } ?? []
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        (toolbarConfiguration["allowedItems"] as? [String])?.map { NSToolbarItem.Identifier($0) } ?? []
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let info = toolbarInfoForItem(itemIdentifier.rawValue) else { return nil }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        if let label = info["label"] as? String {
            item.label = NSLocalizedString(label, comment: "")
            item.paletteLabel = item.label
        }

        if let toolTip = info["toolTip"] as? String {
            item.toolTip = NSLocalizedString(toolTip, comment: "")
        }

        if let imageName = info["imageName"] as? String {
            item.image = NSImage(named: imageName)
        }

        if var actionString = info["action"] as? String {
            if !actionString.hasSuffix(":") {
                actionString += ":"
            }
            item.action = NSSelectorFromString(actionString)
        }

        if let targetPath = info["target"] as? String {
            item.target = self.value(forKeyPath: targetPath) as AnyObject?
        }

        if #available(macOS 10.15, *) {
            item.isBordered = true
        }

        return item
    }
}
