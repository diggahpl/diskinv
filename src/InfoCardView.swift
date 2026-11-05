//
//  InfoCardView.swift
//  Disk Inventory Xs
//
//  The information about the selected item, at the bottom of the sidebar (it was a
//  floating panel before, which covered the map): the icon and name, and the
//  details list (DIXFileInfoView). Without a selection it describes the folder the
//  map shows, so the card always has something to say.
//
//  GPL v3
//

import Cocoa

final class InfoCardView: NSView {

    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private let details = DIXFileInfoView(frame: .zero)
    private let separator = NSView()

    private let headerHeight: CGFloat = 52

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.imageScaling = .scaleProportionallyDown
        nameField.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.cell?.usesSingleLineMode = true

        separator.wantsLayer = true
        separator.layer?.backgroundColor = Theme.hairline.cgColor

        for view in [iconView, nameField, details, separator] as [NSView] {
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("InfoCardView is created in code")
    }

    /// Shows `item`, or nothing when it is nil.
    func show(_ item: FSItem?, document: FileSystemDoc?) {
        guard let item = item, let url = item.fileURL() else {
            nameField.stringValue = ""
            iconView.image = nil
            details.setURL(nil)
            return
        }

        // only rebuild the list when the item changed
        if let current = details.url(), url.isEqual(to: current as NSURL) { return }

        let isNode = document?.itemIsNode(item) ?? item.isFolder()
        let kindColor = isNode ? nil : document?.fileTypeColors().color(forItem: item)
        nameField.stringValue = item.displayName()
        iconView.image = FileIcons.icon(for: item, kindColor: kindColor, size: 32)
        details.setURL(url)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 14
        separator.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)

        let top = bounds.height - 1
        iconView.frame = NSRect(x: inset, y: top - headerHeight + 10, width: 32, height: 32)
        let nameHeight = ceil(nameField.intrinsicContentSize.height)
        nameField.frame = NSRect(x: inset + 32 + 10, y: top - headerHeight / 2 - nameHeight / 2,
                                 width: max(bounds.width - inset * 2 - 42, 0), height: nameHeight)
        details.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(top - headerHeight, 0))
    }
}
