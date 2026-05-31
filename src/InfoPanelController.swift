//
//  InfoPanelController.swift
//  Disk Inventory Xs
//
//  Swift port of InfoPanelController.{h,m}. Shared singleton owning
//  InfoPanel.nib; shows the inspector panel for an FSItem (display name, icon,
//  and the DIXFileInfoView detail list — which stays Objective-C). Nib owner,
//  so the class name and outlets carry @objc.
//
//  GPL v3
//

import Cocoa

@objc(InfoPanelController)
class InfoPanelController: NSObject {

    @IBOutlet private var _infoView: DIXFileInfoView!
    @IBOutlet private var _infoPanel: NSWindow!
    @IBOutlet private var _displayNameTextField: NSTextField!
    @IBOutlet private var _iconImageView: NSImageView!
    private var _nibTopLevelObjects: [Any]?

    private static let sharedInstance = InfoPanelController()

    // returns IUO to match the ObjC +sharedController (callers use it both
    // optionally and directly); the singleton is never actually nil
    @objc(sharedController)
    class func shared() -> InfoPanelController! { sharedInstance }

    @objc override init() {
        super.init()

        var topLevelObjects: NSArray?
        if !Bundle.main.loadNibNamed("InfoPanel", owner: self, topLevelObjects: &topLevelObjects) {
            assertionFailure("couldn't load InfoPanel.nib")
        }
        _nibTopLevelObjects = topLevelObjects as? [Any]

        // the nib has "release when closed = YES"; turn it off so the panel's
        // lifetime is governed by _nibTopLevelObjects only (else closing frees
        // it while the array holds a stale pointer → zombie crash)
        _infoPanel?.isReleasedWhenClosed = false
    }

    @objc func panelIsVisible() -> Bool { panel().isVisible }

    @objc func showPanel() { panel().orderFront(nil) }

    @objc func hidePanel() { panel().orderOut(nil) }

    @objc func panel() -> NSWindow { _infoPanel }

    @objc(showPanelWithFSItem:)
    func showPanel(with fsItem: FSItem?) {
        showPanel()

        guard let fsItem = fsItem, let fileURL = fsItem.fileURL() else {
            _displayNameTextField.stringValue = ""
            _iconImageView.image = nil
            _infoView.setURL(nil)
            return
        }

        // only refresh if the URL actually changed
        let currentURL = _infoView.url()
        if currentURL == nil || !fileURL.isEqual(to: currentURL! as NSURL) {
            _displayNameTextField.stringValue = fsItem.displayName()
            _iconImageView.image = fsItem.icon(withSize: 32)
            _infoView.setURL(fileURL)
        }
    }
}
