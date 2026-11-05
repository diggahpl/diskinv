//
//  StatusBarView.swift
//  Disk Inventory Xs
//
//  The readout under the window's panels: a Liquid Glass capsule showing a
//  swatch in the item's cushion color, its name, and its kind and size in
//  width-stable numerals. It adopts the two text fields the nib already wires
//  to TreeMapViewController, so the controller keeps writing to them as before.
//  With Reduce Transparency the glass gives way to a solid panel.
//
//  GPL v3
//

import Cocoa

final class StatusBarView: NSView {

    static let height: CGFloat = 50
    static let margin: CGFloat = 14

    private let nameField: NSTextField
    private let detailField: NSTextField
    private let content = NSView()
    private let swatch = NSView()
    private var backing: NSView?

    /// Replaces the two nib text fields in `contentView` with a glass status bar
    /// along its bottom edge and returns it.
    @discardableResult
    static func install(in contentView: NSView, nameField: NSTextField, detailField: NSTextField) -> StatusBarView {
        let bar = StatusBarView(nameField: nameField, detailField: detailField)
        bar.frame = NSRect(x: margin, y: margin, width: contentView.bounds.width - 2 * margin, height: height)
        bar.autoresizingMask = [.width, .maxYMargin]
        contentView.addSubview(bar)
        return bar
    }

    private init(nameField: NSTextField, detailField: NSTextField) {
        self.nameField = nameField
        self.detailField = detailField
        super.init(frame: .zero)

        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = 4
        swatch.layer?.borderWidth = 1
        swatch.layer?.borderColor = NSColor(white: 1, alpha: 0.35).cgColor
        swatch.isHidden = true

        for field in [nameField, detailField] {
            field.removeFromSuperview()
            field.translatesAutoresizingMaskIntoConstraints = true
            field.drawsBackground = false
            field.isBezeled = false
            field.lineBreakMode = .byTruncatingMiddle
        }
        nameField.font = .systemFont(ofSize: 13, weight: .semibold)
        nameField.textColor = .labelColor
        detailField.font = Theme.numericFont(ofSize: 11.5)
        detailField.textColor = .secondaryLabelColor

        content.addSubview(swatch)
        content.addSubview(nameField)
        content.addSubview(detailField)

        reloadMaterial()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityOptionsChanged(_:)),
                                                          name: Theme.accessibilityOptionsChanged, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("StatusBarView is created in code")
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// The swatch shows what kind the item has; nil hides it.
    func setSwatchColor(_ color: NSColor?) {
        swatch.isHidden = color == nil
        swatch.layer?.backgroundColor = color?.cgColor
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutContent()
    }

    @objc private func accessibilityOptionsChanged(_ notification: Notification) {
        reloadMaterial()
    }

    // glass normally, a solid raised panel with Reduce Transparency
    private func reloadMaterial() {
        backing?.removeFromSuperview()
        content.removeFromSuperview()

        let newBacking: NSView
        if Theme.reduceTransparency {
            let solid = NSView()
            solid.wantsLayer = true
            solid.layer?.backgroundColor = Theme.spaceRaised.cgColor
            solid.layer?.cornerRadius = 14
            solid.layer?.borderWidth = Theme.increaseContrast ? 2 : 1
            solid.layer?.borderColor = (Theme.increaseContrast ? NSColor.white : Theme.hairline).cgColor
            solid.addSubview(content)
            newBacking = solid
        } else {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 14
            glass.contentView = content
            newBacking = glass
        }

        newBacking.frame = bounds
        newBacking.autoresizingMask = [.width, .height]
        addSubview(newBacking)
        backing = newBacking
        layoutContent()
    }

    private func layoutContent() {
        let size = bounds.size
        content.frame = NSRect(origin: .zero, size: size)

        let textX: CGFloat = 38
        let textWidth = max(0, size.width - textX - 16)
        swatch.frame = NSRect(x: 16, y: size.height / 2 - 8, width: 16, height: 16)
        nameField.frame = NSRect(x: textX, y: size.height / 2, width: textWidth, height: 17)
        detailField.frame = NSRect(x: textX, y: size.height / 2 - 17, width: textWidth, height: 15)
    }
}
