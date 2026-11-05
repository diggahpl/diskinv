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
    private var _placeholder: NSView?

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

        // a flat panel of the same deep space as the main window
        _infoPanel?.backgroundColor = Theme.spaceRaised
        _infoPanel?.titlebarAppearsTransparent = true
        _infoView?.enclosingScrollView?.drawsBackground = false
        _infoView?.enclosingScrollView?.borderType = .noBorder
        _displayNameTextField?.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        _displayNameTextField?.stringValue = ""

        installPlaceholder()
        setEmpty(true)
    }

    // Nothing selected: a quiet hint instead of an empty box with a stray column.
    private func installPlaceholder() {
        guard let content = _infoPanel?.contentView else { return }

        let configuration = NSImage.SymbolConfiguration(pointSize: 30, weight: .light)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 1, alpha: 0.28)]))
        let icon = NSImageView(image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage())
        let label = NSTextField(wrappingLabelWithString: NSLocalizedString("Select a file or folder to see its details.",
                                                                           comment: "information panel without a selection"))
        label.alignment = .center
        label.textColor = NSColor(white: 1, alpha: 0.5)
        label.font = NSFont.systemFont(ofSize: 12)
        label.preferredMaxLayoutWidth = 170

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: 8),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 16)
        ])
        _placeholder = stack
    }

    private func setEmpty(_ empty: Bool) {
        _placeholder?.isHidden = !empty
        _infoView?.isHidden = empty
        _displayNameTextField?.isHidden = empty
        _iconImageView?.isHidden = empty
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
            setEmpty(true)
            return
        }
        setEmpty(false)

        // only refresh if the URL actually changed
        let currentURL = _infoView.url()
        if currentURL == nil || !fileURL.isEqual(to: currentURL! as NSURL) {
            _displayNameTextField.stringValue = fsItem.displayName()
            let doc = NSDocumentController.shared.currentDocument as? FileSystemDoc
            let isNode = doc?.itemIsNode(fsItem) ?? fsItem.isFolder()
            let kindColor = isNode ? nil : doc?.fileTypeColors().color(forItem: fsItem)
            _iconImageView.image = FileIcons.icon(for: fsItem, kindColor: kindColor, size: 32)
            _infoView.setURL(fileURL)
        }
    }
}
