//
//  FileOutlineCells.swift
//  Disk Inventory Xs
//
//  The views of the files outline (a view-based NSOutlineView): the name cell
//  with its icon, the size cell with a thin bar for the item's share of its
//  parent, the glass selection row and the flat header. They replace the
//  cell-based ImageAndTextCell, whose hand-placed icon did not follow the
//  indentation of the outline any more.
//
//  GPL v3
//

import Cocoa

// MARK: - Name

final class FileNameCellView: NSTableCellView {

    static let identifier = NSUserInterfaceItemIdentifier("FileNameCellView")

    private let iconView = NSImageView()
    private let nameField = NSTextField(labelWithString: "")
    private var iconSize: CGFloat = 16

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier

        iconView.imageScaling = .scaleNone
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.cell?.usesSingleLineMode = true
        addSubview(iconView)
        addSubview(nameField)

        // the outlets let AppKit recolor the text when the row is selected
        imageView = iconView
        textField = nameField
    }

    required init?(coder: NSCoder) {
        fatalError("FileNameCellView is created in code")
    }

    func configure(name: String, icon: NSImage?, iconSize: CGFloat, fontSize: CGFloat, emphasized: Bool) {
        self.iconSize = iconSize
        iconView.image = icon
        nameField.stringValue = name
        nameField.font = NSFont.systemFont(ofSize: fontSize, weight: emphasized ? .medium : .regular)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let gap: CGFloat = 7
        iconView.frame = NSRect(x: 0, y: ((bounds.height - iconSize) / 2).rounded(), width: iconSize, height: iconSize)

        let textHeight = nameField.intrinsicContentSize.height
        let textX = iconSize + gap
        nameField.frame = NSRect(x: textX, y: ((bounds.height - textHeight) / 2).rounded(),
                                 width: max(bounds.width - textX, 0), height: textHeight)
    }
}

// MARK: - Size

final class FileSizeCellView: NSTableCellView {

    static let identifier = NSUserInterfaceItemIdentifier("FileSizeCellView")

    private let sizeField = NSTextField(labelWithString: "")
    private var share: CGFloat = 0
    private var barColor = Theme.accent

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
        sizeField.alignment = .right
        sizeField.lineBreakMode = .byClipping
        sizeField.cell?.usesSingleLineMode = true
        addSubview(sizeField)
        textField = sizeField
    }

    required init?(coder: NSCoder) {
        fatalError("FileSizeCellView is created in code")
    }

    /// `share` is the item's size in relation to its parent, 0...1.
    func configure(size: NSNumber, share: CGFloat, color: NSColor, fontSize: CGFloat) {
        self.share = max(0, min(share, 1))
        barColor = color

        // the number in full strength, the unit a step quieter
        let text = FileSizeFormatter().string(for: size) ?? ""
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: Theme.numericFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor
        ])
        if let space = text.lastIndex(of: " ") {
            let unit = NSRange(space..., in: text)
            attributed.addAttributes([.font: NSFont.systemFont(ofSize: fontSize - 1),
                                      .foregroundColor: NSColor.secondaryLabelColor], range: unit)
        }
        sizeField.attributedStringValue = attributed
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let textHeight = sizeField.intrinsicContentSize.height
        sizeField.frame = NSRect(x: 0, y: ((bounds.height - textHeight) / 2).rounded() - 1,
                                 width: max(bounds.width - 6, 0), height: textHeight)
    }

    // the share bar under the text: a faint track and a lit part of it
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard share > 0 else { return }

        let track = NSRect(x: 4, y: bounds.height - 4, width: max(bounds.width - 10, 0), height: 2)
        NSColor(white: 1, alpha: 0.07).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).fill()

        let lit = NSRect(x: track.minX, y: track.minY, width: max(track.width * share, 2), height: track.height)
        barColor.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: lit, xRadius: 1, yRadius: 1).fill()
    }
}

// MARK: - Row

/// The row of the files outline; the selection is a glass plate.
final class FileRowView: NSTableRowView {

    static let identifier = NSUserInterfaceItemIdentifier("FileRowView")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.identifier
    }

    required init?(coder: NSCoder) {
        fatalError("FileRowView is created in code")
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        GlowSelection.drawPlate(in: bounds.insetBy(dx: 4, dy: 1), strength: isEmphasized ? 1 : 0.55)
    }
}

// MARK: - Header

/// A header cell without the system's grey bar: a small caps label on the panel.
final class FlatHeaderCell: NSTableHeaderCell {

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Theme.spaceRaised.setFill()
        cellFrame.fill()

        Theme.hairline.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(white: 1, alpha: 0.55),
            .kern: 0.8,
            .paragraphStyle: paragraph
        ]
        let title = NSAttributedString(string: stringValue.uppercased(), attributes: attributes)
        let height = title.size().height
        title.draw(in: NSRect(x: cellFrame.minX + 8, y: cellFrame.midY - height / 2,
                              width: cellFrame.width - 16, height: height))
    }
}

final class FlatHeaderView: NSTableHeaderView {

    /// Gives `table` the flat header: the same titles, no grey bar. A narrow first
    /// column (the color swatches) keeps an empty title, as its text would be cut off.
    /// The other columns share the width the table gets, the swatches keep theirs.
    static func install(in table: NSTableView) {
        let oldHeader = table.headerView
        table.headerView = FlatHeaderView(frame: NSRect(x: 0, y: 0, width: oldHeader?.frame.width ?? 100, height: 26))
        for (index, column) in table.tableColumns.enumerated() {
            let swatch = index == 0 && column.width < 70 && table.tableColumns.count > 2
            let header = FlatHeaderCell(textCell: swatch ? "" : column.headerCell.stringValue)
            header.alignment = column.headerCell.alignment
            column.headerCell = header
            if swatch {
                column.resizingMask = .userResizingMask
            }
        }
        if table.tableColumns.count > 2 {
            table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.spaceRaised.setFill()
        bounds.fill()

        guard let table = tableView else { return }
        let sorted = table.sortDescriptors.first
        for (index, column) in table.tableColumns.enumerated() {
            let rect = headerRect(ofColumn: index)
            guard rect.intersects(dirtyRect) else { continue }
            column.headerCell.draw(withFrame: rect, in: self)

            if let sorted = sorted, sorted.key != nil, column.sortDescriptorPrototype?.key == sorted.key {
                drawSortIndicator(ascending: sorted.ascending, in: rect, titleAtRight: column.headerCell.alignment == .right)
            }
        }
    }

    // a small accent chevron on the side of the title that has room
    private func drawSortIndicator(ascending: Bool, in rect: NSRect, titleAtRight: Bool) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [Theme.accent]))
        guard let image = NSImage(systemSymbolName: ascending ? "chevron.up" : "chevron.down",
                                  accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return }
        let size = image.size
        let x = titleAtRight ? rect.minX + 6 : rect.maxX - size.width - 6
        image.draw(in: NSRect(x: x, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }
}
