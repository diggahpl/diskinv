//
//  SelectionListTableController.swift
//  Disk Inventory Xs
//
//  Swift port of SelectionListTableController.{h,m}. Controller/delegate for
//  the table in the selection-list drawer: icons in the name column, two-way
//  selection sync with the document (suppressing the echo while it sets the
//  selection itself), drag-out, and suspend/resume of the array controller
//  while the drawer is closed. Nib-wired, so the class name and outlets carry
//  @objc.
//
//  GPL v3
//

import Cocoa

@objc(SelectionListTableController)
class SelectionListTableController: NSObject {

    @IBOutlet private var _tableView: NSTableView!
    @IBOutlet private var _windowController: MainWindowController!
    @IBOutlet private var _selectionListArrayController: GenericArrayController!
    @IBOutlet private var _kindStatisticsArrayController: FileKindsPopupController!

    private static var smallFontContext = 0
    private var _updatesSuspended = false

    @objc func document() -> FileSystemDoc? {
        _windowController?.document as? FileSystemDoc
    }

    override func awakeFromNib() {
        let doc = document()
        let center = NotificationCenter.default

        center.addObserver(self, selector: #selector(sidebarChanged(_:)),
                           name: MainWindowController.sidebarDidChangeNotification, object: _windowController)
        center.addObserver(self, selector: #selector(windowWillClose(_:)),
                           name: NSWindow.willCloseNotification, object: _windowController?.window)

        // the list is only kept up to date while the sidebar shows it
        updateSuspension()

        NSUserDefaultsController.shared.addObserver(self, forKeyPath: "values." + UseSmallFontInSelectionList,
                                                    options: [], context: &Self.smallFontContext)
        doc?.addObserver(self, forKeyPath: DocKeySelectedItem, options: [], context: nil)
        _selectionListArrayController.addObserver(self, forKeyPath: "selection", options: [], context: nil)

        TableColumns.usePlainCell(in: _tableView, columnIdentifier: "size")
        TableColumns.usePlainCell(in: _tableView, columnIdentifier: "displayPath")

        // ImageAndTextCell as the data cell for the "Name" column
        _tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("displayName"))?.dataCell = ImageAndTextCell.cell()

        // initial sort: descending by size
        if let sizeColumn = _tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size")),
           let reversed = sizeColumn.sortDescriptorPrototype?.reversedSortDescriptor as? NSSortDescriptor {
            _selectionListArrayController.sortDescriptors = [reversed]
        }

        setTableViewFont()
    }

    // MARK: - NSTableView delegate

    // The table is nib-wired to this plain NSObject, which declares no delegate
    // conformance, so the selector has to be exposed for the icons to appear.
    @objc(tableView:willDisplayCell:forTableColumn:row:)
    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any,
                   for tableColumn: NSTableColumn?, row: Int) {
        // the nib's cells paint their own background over the selection plate
        (cell as? NSTextFieldCell)?.drawsBackground = false

        if tableColumn?.identifier.rawValue == "displayName",
           let item = (_selectionListArrayController.arrangedObjects as? [Any])?[row] as? FSItem,
           let cell = cell as? ImageAndTextCell {
            let isNode = document()?.itemIsNode(item) ?? item.isFolder()
            let kindColor = isNode ? nil : document()?.fileTypeColors().color(forItem: item)
            cell.image = FileIcons.icon(for: item, kindColor: kindColor, size: 16)
        }
    }

    // forwarded by DIXTableView; drag&drop within the app is unsupported, copy out is
    @objc(dixDraggingSourceMaskForLocal:)
    func dixDraggingSourceMask(forLocal isLocal: Bool) -> NSDragOperation {
        isLocal ? [] : .copy
    }

    // MARK: - NSTableView data source

    func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet,
                   to pboard: NSPasteboard) -> Bool {
        // we only support single selection
        guard let rowIndex = rowIndexes.first,
              let item = (_selectionListArrayController.arrangedObjects as? [Any])?[rowIndex] as? FSItem
        else { return false }

        if !item.isSpecialItem() && item.exists() {
            item.writeToPasteboard(pboard)
            return true
        }
        return false
    }

    // MARK: - NSMenuValidation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context == &Self.smallFontContext {
            setTableViewFont()
        } else if object as AnyObject === document(), keyPath == DocKeySelectedItem {
            onDocumentSelectionChanged()
        } else if object as AnyObject === _selectionListArrayController, keyPath == "selection" {
            onSelectionListSelectionChanged()
        }
    }

    // MARK: - private

    private func setTableViewFont() {
        let fontSize: CGFloat = UserDefaults.standard.bool(forKey: UseSmallFontInSelectionList)
            ? NSFont.smallSystemFontSize
            : NSFont.systemFontSize
        _tableView.font = NSFont.systemFont(ofSize: fontSize)
        _tableView.rowHeight = (fontSize * 1.7).rounded()

        // the nib's cells paint their own background over the selection plate
        for column in _tableView.tableColumns {
            (column.dataCell as? NSTextFieldCell)?.drawsBackground = false
        }

        // sizes in width-stable digits; the path loses its head when it is too long, as the
        // end of a path says more than its start, and is a step quieter than the name
        (_tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size"))?.dataCell as? NSTextFieldCell)?
            .font = Theme.numericFont(ofSize: fontSize)
        if let pathCell = _tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("displayPath"))?
            .dataCell as? NSTextFieldCell {
            pathCell.lineBreakMode = .byTruncatingHead
            pathCell.textColor = .secondaryLabelColor
        }
    }

    private func onDocumentSelectionChanged() {
        var item = document()?.selectedItem()

        var listSelection: Any? = _selectionListArrayController.selection
        if (listSelection as AnyObject) === (NSNoSelectionMarker as AnyObject) { listSelection = nil }
        assert(!NSIsControllerMarker(listSelection as Any), "unsupported controller marker detected")

        if (item as AnyObject?) !== (listSelection as AnyObject?) {
            // stop observing while we set the selection ourselves, so the change
            // isn't propagated back to the document (see onSelectionListSelectionChanged)
            _selectionListArrayController.removeObserver(self, forKeyPath: "selection")

            // optimization: drop the selection if the item is a folder or its kind
            // isn't the one shown in the list (so it isn't present anyway)
            if let theItem = item {
                let selectedStat = _kindStatisticsArrayController.selection
                let isAll = (selectedStat as AnyObject).isAllFileKindsItem?() ?? false
                let statKind = (selectedStat as? FileKindStatistic)?.kindName
                if NSIsControllerMarker(selectedStat)
                    || (!isAll && statKind != theItem.kindName())
                    || (document()?.itemIsNode(theItem) ?? false) {
                    item = nil
                }
            }

            if let item = item {
                _selectionListArrayController.setSelectedObjects([item])
            } else {
                _selectionListArrayController.setSelectionIndexes(IndexSet())
            }

            _selectionListArrayController.addObserver(self, forKeyPath: "selection", options: [], context: nil)
        }
    }

    private func onSelectionListSelectionChanged() {
        guard let doc = document() else { return }

        var listSelection: Any? = _selectionListArrayController.selection
        if (listSelection as AnyObject) === (NSNoSelectionMarker as AnyObject) { listSelection = nil }
        assert(!NSIsControllerMarker(listSelection as Any), "unsupported controller marker detected")

        if (listSelection as AnyObject?) !== (doc.selectedItem() as AnyObject?) {
            doc.setSelectedItem(listSelection as? FSItem)
        }
    }

    @objc private func sidebarChanged(_ notification: Notification) {
        updateSuspension()
    }

    // suspend and resume are counted by the array controller, so keep them balanced
    private func updateSuspension() {
        let showing = _windowController?.isSidebarShowing(.selection) ?? false
        if showing && _updatesSuspended {
            _selectionListArrayController.resumeArrangedObjectsUpdates()
            _updatesSuspended = false
        } else if !showing && !_updatesSuspended {
            _selectionListArrayController.suspendArrangedObjectsUpdates()
            _updatesSuspended = true
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        document()?.removeObserver(self, forKeyPath: DocKeySelectedItem)
        NSUserDefaultsController.shared.removeObserver(self, forKeyPath: "values." + UseSmallFontInSelectionList)
        _selectionListArrayController.removeObserver(self, forKeyPath: "selection")
        NotificationCenter.default.removeObserver(self)
    }
}
