//
//  FileKindsTableController.swift
//  Disk Inventory Xs
//
//  Swift port of FileKindsTableController.{h,m}. Controller/delegate for the
//  file-kind statistics table in the kinds drawer: draws the per-row cushion
//  color swatch, keeps the table selection in sync with the document
//  selection, and (via the toolbar/menu) reveals the selected kind in the
//  selection-list drawer. Nib-wired, so the class name, outlets, and the
//  showFilesInSelectionList: action are pinned with @objc.
//
//  GPL v3
//

import Cocoa

@objc(FileKindsTableController)
class FileKindsTableController: NSObject {

    @IBOutlet private var _tableView: NSTableView!
    @IBOutlet private var _windowController: MainWindowController!
    @IBOutlet private var _kindsPopupArrayController: NSArrayController!
    @IBOutlet private var _kindsTableArrayController: NSArrayController!

    private var _cushionImages: [String: NSImage] = [:]
    private var _largestKindSize: UInt64?
    private var _focusedKind: String?
    // set while the table follows the document's selection, which is not the user's pick
    private var _followingDocument = false

    private static var smallFontContext = 0
    private static var shareKindColorsContext = 0

    override func awakeFromNib() {
        let doc = document()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(documentSelectionChanged(_:)),
                           name: NSNotification.Name.GlobalSelectionChanged, object: doc)
        center.addObserver(self, selector: #selector(windowWillClose(_:)),
                           name: NSWindow.willCloseNotification, object: _windowController?.window)

        let defs = NSUserDefaultsController.shared
        defs.addObserver(self, forKeyPath: "values." + UseSmallFontInKindStatistic,
                         options: [], context: &Self.smallFontContext)
        defs.addObserver(self, forKeyPath: "values." + ShareKindColors,
                         options: [], context: &Self.shareKindColorsContext)

        _kindsTableArrayController.addObserver(self, forKeyPath: "arrangedObjects", options: [], context: nil)
        center.addObserver(self, selector: #selector(kindFocusChanged(_:)), name: KindFocus.changedNotification, object: doc)

        TableColumns.usePlainCell(in: _tableView, columnIdentifier: "size")
        TableColumns.usePlainCell(in: _tableView, columnIdentifier: "fileCount")

        // the kind's name with a bar for its share, in place of the nib's plain text cell
        if let kindColumn = _tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("kindName")) {
            let cell = ShareBarCell(textCell: "")
            cell.lineBreakMode = .byTruncatingTail
            cell.truncatesLastVisibleLine = true
            kindColumn.dataCell = cell
        }

        setTableViewFont()

        // initial sort: descending by size
        if let sizeColumn = _tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size")),
           let reversed = sizeColumn.sortDescriptorPrototype?.reversedSortDescriptor as? NSSortDescriptor {
            _kindsTableArrayController.sortDescriptors = [reversed]
        }
    }

    @objc func document() -> FileSystemDoc? {
        _windowController?.document as? FileSystemDoc
    }

    @IBAction func showFilesInSelectionList(_ sender: Any?) {
        _windowController.showSidebar(.selection)

        let selectedRow = _tableView.selectedRow
        assert(selectedRow >= 0, "kinds tableview should have a selection")
        guard selectedRow >= 0,
              let kindStat = (_kindsTableArrayController.arrangedObjects as? [Any])?[selectedRow] else { return }
        _kindsPopupArrayController.setSelectedObjects([kindStat])
    }

    // MARK: - NSTableView delegate

    // The table is nib-wired to this plain NSObject, which declares no delegate
    // conformance, so the selector has to be exposed for the swatches to appear.
    @objc(tableView:willDisplayCell:forTableColumn:row:)
    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any,
                   for tableColumn: NSTableColumn?, row: Int) {
        // the nib's cells paint their own background over the selection plate
        (cell as? NSTextFieldCell)?.drawsBackground = false

        if tableColumn?.identifier.rawValue == "color", let image = colorImage(forRow: row, column: tableColumn) {
            // the "color" column's data cell is an image cell; set via KVC since
            // NSCell's -setImage: isn't exposed uniformly to Swift
            (cell as? NSCell)?.setValue(image, forKey: "image")
        } else if tableColumn?.identifier.rawValue == "kindName", let cell = cell as? ShareBarCell,
                  let statistic = kindStatistic(atRow: row) {
            let share = largestKindSize > 0 ? CGFloat(statistic.size) / CGFloat(largestKindSize) : 0
            let colors = document()?.fileTypeColors()
            let hasColor = colors?.hasPaletteColor(forKind: statistic.kindName) ?? false
            let barColor = hasColor ? Theme.cushionDisplayColor(colors!.color(forKind: statistic.kindName))
                                    : NSColor(white: 1, alpha: 0.30)
            cell.setBar(share: share, color: barColor)
        }
    }

    private func kindStatistic(atRow row: Int) -> FileKindStatistic? {
        (_kindsTableArrayController.arrangedObjects as? [Any])?[row] as? FileKindStatistic
    }

    // the biggest kind, which a full bar stands for
    private var largestKindSize: UInt64 {
        if let cached = _largestKindSize { return cached }
        let kinds = (_kindsTableArrayController.arrangedObjects as? [Any]) ?? []
        let largest = kinds.compactMap { ($0 as? FileKindStatistic)?.size }.max() ?? 0
        _largestKindSize = largest
        return largest
    }

    // Picking a kind in the legend focuses the map on it; the table following the selected
    // item of the document, or letting go of its row, does not.
    @objc(tableViewSelectionDidChange:)
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !_followingDocument else { return }

        let row = _tableView.selectedRow
        let kind = row >= 0 ? kindStatistic(atRow: row)?.kindName : nil
        let userInfo: [AnyHashable: Any] = kind.map { [KindFocus.kindKey: $0] } ?? [:]
        NotificationCenter.default.post(name: KindFocus.changedNotification, object: document(), userInfo: userInfo)
    }

    @objc private func kindFocusChanged(_ notification: Notification) {
        _focusedKind = notification.userInfo?[KindFocus.kindKey] as? String
        // cleared from elsewhere (the pill over the map): the legend lets go of its row
        if _focusedKind == nil, _tableView.selectedRow >= 0 {
            _followingDocument = true
            _kindsTableArrayController.setSelectionIndexes(IndexSet())
            _followingDocument = false
        }
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context == &Self.smallFontContext {
            setTableViewFont()
        } else if context == &Self.shareKindColorsContext {
            _cushionImages.removeAll()
            _tableView.needsDisplay = true
        } else if object as AnyObject === _kindsTableArrayController, keyPath == "arrangedObjects" {
            _cushionImages.removeAll()
            _largestKindSize = nil
        }
    }

    // MARK: - private

    // the legend chip for the given row, cached by kind name: a small rounded pane in the
    // color the kind has on the map
    private func colorImage(forRow row: Int, column: NSTableColumn?) -> NSImage? {
        guard let kindStatistic = (_kindsTableArrayController.arrangedObjects as? [Any])?[row] as? FileKindStatistic
        else { return nil }

        let cellSize = NSSize(width: column?.width ?? 0, height: _tableView.rowHeight)

        var image = _cushionImages[kindStatistic.kindName]
        if image == nil || image!.size != cellSize {
            let colors = document()?.fileTypeColors()
            let kindColor = colors?.color(forKind: kindStatistic.kindName) ?? .black
            // kinds past the palette share dim greys that tell nothing apart: a hollow chip
            let hasColor = colors?.hasPaletteColor(forKind: kindStatistic.kindName) ?? false
            image = hasColor ? Self.chip(color: Theme.cushionDisplayColor(kindColor), size: cellSize)
                             : Self.hollowChip(size: cellSize)
            _cushionImages[kindStatistic.kindName] = image
        }
        return image
    }

    // kinds past the palette have no color of their own: a small dim dot, not a button
    private static func hollowChip(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let dot = NSRect(x: rect.midX - 3, y: rect.midY - 3, width: 6, height: 6)
            NSColor(white: 1, alpha: 0.28).setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
    }

    private static func chip(color: NSColor, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let chip = rect.insetBy(dx: 5, dy: max((rect.height - 12) / 2, 2))
            let path = NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4)
            let top = color.blended(withFraction: 0.30, of: .white) ?? color
            let bottom = color.blended(withFraction: 0.22, of: .black) ?? color
            NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: -90)
            NSColor(white: 1, alpha: 0.28).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }

    private func setTableViewFont() {
        let fontSize: CGFloat = UserDefaults.standard.bool(forKey: UseSmallFontInKindStatistic)
            ? NSFont.smallSystemFontSize
            : NSFont.systemFontSize
        _tableView.font = NSFont.systemFont(ofSize: fontSize)
        _tableView.rowHeight = (fontSize * 1.7).rounded()

        // the nib's cells paint their own background over the selection plate
        for column in _tableView.tableColumns {
            (column.dataCell as? NSTextFieldCell)?.drawsBackground = false
        }

        for id in ["size", "fileCount"] {
            let cell = _tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id))?.dataCell as? NSTextFieldCell
            cell?.font = Theme.numericFont(ofSize: fontSize)
            cell?.textColor = id == "size" ? .labelColor : .secondaryLabelColor
        }
        (_tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("kindName"))?.dataCell as? NSTextFieldCell)?
            .font = NSFont.systemFont(ofSize: fontSize)
    }

    @objc private func documentSelectionChanged(_ notification: Notification) {
        // with a focus the legend keeps showing the focused kind, not the selected item's
        guard let doc = document(), _focusedKind == nil else { return }

        // optimization: a folder isn't in the kinds list, so clear the selection
        let item = doc.selectedItem()
        let stat: FileKindStatistic?
        if let item = item, !doc.itemIsNode(item) {
            stat = doc.kindStatistic(forItem: item)
        } else {
            stat = nil
        }

        var tableViewSelection = _kindsTableArrayController.selection as Any?
        if (tableViewSelection as AnyObject) === (NSNoSelectionMarker as AnyObject) {
            tableViewSelection = nil
        }

        if (stat as AnyObject?) !== (tableViewSelection as AnyObject?) {
            _followingDocument = true
            defer { _followingDocument = false }
            if let stat = stat {
                _kindsTableArrayController.setSelectedObjects([stat])
            } else {
                _kindsTableArrayController.setSelectionIndexes(IndexSet())
            }
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        let defs = NSUserDefaultsController.shared
        defs.removeObserver(self, forKeyPath: "values." + UseSmallFontInKindStatistic)
        defs.removeObserver(self, forKeyPath: "values." + ShareKindColors)
        _kindsTableArrayController.removeObserver(self, forKeyPath: "arrangedObjects")
        NotificationCenter.default.removeObserver(self)
    }
}
