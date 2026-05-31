//
//  OAToolbarWindowControllerEx.swift
//  Disk Inventory Xs
//
//  Swift port of OAToolbarWindowControllerEx.{h,m}. Adds to the base
//  DIXToolbarWindowController: localized toolbar-item labels/tooltips pulled
//  from the matching menu item, multi-state toolbar images, and unified
//  menu/toolbar command validation (see `CommandValidation`).
//
//  The original routed toolbar-item validation through -validateMenuItem: by
//  wrapping the toolbar item in an NSInvocation-forwarding proxy
//  (NSToolbarItemValidationAdapter) that impersonated an NSMenuItem and
//  translated -setState: into a toolbar icon swap. That proxy is gone: the
//  per-command decision is now a plain `CommandValidation` value that both
//  validateMenuItem(_:) and validateToolbarItem(_:) compute and apply to their
//  own item type.
//
//  GPL v3
//

import Cocoa

/// The validation result for a command, independent of whether it is shown as a
/// menu item or a toolbar item: whether it's enabled, an optional title that
/// toggles (e.g. "Show…" ↔ "Hide…"), and an optional on/off state that a toolbar
/// button renders as a different icon (where a menu item would show a checkmark).
struct CommandValidation {
    var isEnabled: Bool = true
    var title: String? = nil                        // localization key, e.g. "Hide Free Space"
    var toolbarState: NSControl.StateValue? = nil   // drives the toolbar icon swap; nil = no toggle
}

@objc(OAToolbarWindowControllerEx)
class OAToolbarWindowControllerEx: DIXToolbarWindowController, NSMenuItemValidation {

    private static let stateImages = NSMutableDictionary()  // configName -> (itemId -> (imageKey -> NSImage))

    // image for a toolbar item in a given on/off/mixed state — a toolbar button's
    // equivalent of a menu item's checkmark. Image names come from the .toolbar
    // plist (imageName / imageNameOffState / imageNameMixedState); cached per
    // toolbar config + item.
    private func stateImage(for item: NSToolbarItem, state: NSControl.StateValue) -> NSImage? {
        let imageKey: String
        switch state {
        case .on: imageKey = "imageName"
        case .off: imageKey = "imageNameOffState"
        case .mixed: imageKey = "imageNameMixedState"
        default: return nil
        }

        let toolbarImageCache: NSMutableDictionary
        if let existing = Self.stateImages[toolbarConfigurationName] as? NSMutableDictionary {
            toolbarImageCache = existing
        } else {
            toolbarImageCache = NSMutableDictionary()
            Self.stateImages[toolbarConfigurationName] = toolbarImageCache
        }

        let itemId = item.itemIdentifier.rawValue
        let itemImageCache: NSMutableDictionary
        if let existing = toolbarImageCache[itemId] as? NSMutableDictionary {
            itemImageCache = existing
        } else {
            itemImageCache = NSMutableDictionary()
            toolbarImageCache[itemId] = itemImageCache
        }

        if let image = itemImageCache[imageKey] as? NSImage {
            return image
        }

        // call super to skip the menu-synchronisation done in our override below
        let itemInfo = super.toolbarInfoForItem(itemId)
        let imageName = (itemInfo?[imageKey] as? String) ?? (itemInfo?["imageName"] as? String)
        guard let imageName = imageName, let image = NSImage(named: imageName) else { return nil }

        itemImageCache[imageKey] = image
        return image
    }

    override func toolbarInfoForItem(_ identifier: String) -> [String: Any]? {
        let itemInfo = NSMutableDictionary(dictionary: super.toolbarInfoForItem(identifier) ?? [:])

        // localize the display strings
        for key in ["label", "paletteLabel", "toolTip"] {
            if let s = itemInfo[key] as? String, !s.isEmpty {
                itemInfo[key] = NSLocalizedString(s, comment: "")
            }
        }

        // ensure the action string ends with ':' (actions take a sender)
        var actionString = itemInfo["action"] as? String
        if let a = actionString, !a.isEmpty, !a.hasSuffix(":") {
            actionString = a + ":"
            itemInfo["action"] = actionString
        }

        // Pull the label/tooltip from the menu item with the same action, so the
        // strings only need to be defined/localized in the menu, not the .toolbar.
        if let a = actionString, !a.isEmpty,
           itemInfo["label"] == nil || itemInfo["toolTip"] == nil {
            let action = NSSelectorFromString(a)
            if let menuItem = NSApp.mainMenu?.menuItem(withAction: action) {
                if itemInfo["label"] == nil, !menuItem.title.isEmpty {
                    itemInfo["label"] = Self.titleByStrippingTrailingDots(menuItem.title)
                }
                if itemInfo["toolTip"] == nil, let tt = menuItem.toolTip, !tt.isEmpty {
                    itemInfo["toolTip"] = tt
                }
            }
        }

        // paletteLabel (the customization-sheet title) falls back to label
        if itemInfo["paletteLabel"] == nil, let label = itemInfo["label"] {
            itemInfo["paletteLabel"] = label
        }

        return itemInfo as? [String: Any]
    }

    // strip trailing periods/whitespace, e.g. "Preferences..." -> "Preferences"
    private static func titleByStrippingTrailingDots(_ title: String) -> String {
        var chars = Array(title)
        var end = chars.count
        while end > 0, let last = chars[0..<end].last, last == "." || last.isWhitespace {
            end -= 1
        }
        return String(chars[0..<end])
    }

    override func toolbar(_ toolbar: NSToolbar,
                          itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                          willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let toolbarItem = super.toolbar(toolbar, itemForItemIdentifier: itemIdentifier, willBeInsertedIntoToolbar: flag)

        // we take labels/tooltips from the menu item, so we don't use a toolbar
        // .strings file; just make sure the tooltip is set
        if toolbarItem?.toolTip == nil,
           let toolTip = toolbarInfoForItem(itemIdentifier.rawValue)?["toolTip"] as? String {
            toolbarItem?.toolTip = toolTip
        }

        return toolbarItem
    }

    // KVC targets a toolbar item's "target" property can resolve to
    @objc var documentController: NSDocumentController { NSDocumentController.shared }
    @objc var application: NSApplication { NSApp }

    // The single source of truth for command validation. Subclasses override
    // this; the menu and toolbar validators below both call it and apply the
    // result to their own item type. (Replaces the old menu-item-impersonating
    // NSToolbarItemValidationAdapter.)
    func commandValidation(forAction action: Selector?) -> CommandValidation { CommandValidation() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let v = commandValidation(forAction: menuItem.action)
        // a menu item conveys on/off via its title ("Show…"/"Hide…"), not a checkmark
        if let title = v.title { menuItem.title = NSLocalizedString(title, comment: "") }
        return v.isEnabled
    }

    @objc func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard window?.isKeyWindow == true else { return false }
        let v = commandValidation(forAction: item.action)

        // NSToolbarItem.title is 10.15+ (deployment target is 10.13); the original
        // proxy set it dynamically only if the item responded, so do the same.
        if let title = v.title {
            let localized = NSLocalizedString(title, comment: "")
            if item.responds(to: NSSelectorFromString("setTitle:")) {
                item.setValue(localized, forKey: "title")
            }
        }

        // a toolbar button shows on/off as a different icon (what the proxy did by
        // intercepting -setState:)
        if let state = v.toolbarState, let image = stateImage(for: item, state: state), image != item.image {
            item.image = image
        }

        return v.isEnabled
    }
}

extension NSMenu {
    // linear (recursive) search for a menu item with the given action
    @objc(menuItemWithAction:)
    func menuItem(withAction action: Selector) -> NSMenuItem? {
        var i = numberOfItems
        while i > 0 {
            i -= 1
            guard let item = self.item(at: i) else { continue }
            if item.action == action { return item }
            if item.hasSubmenu, let found = item.submenu?.menuItem(withAction: action) {
                return found
            }
        }
        return nil
    }
}
