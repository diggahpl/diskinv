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

    @objc func document() -> FileSystemDoc? {
        _windowController?.document as? FileSystemDoc
    }

    override func awakeFromNib() {
        let doc = document()
        let center = NotificationCenter.default
        let drawer = _windowController.selectionListDrawer()

        center.addObserver(self, selector: #selector(onDrawerClosed(_:)),
                           name: NSDrawer.didCloseNotification, object: drawer)
        center.addObserver(self, selector: #selector(onDrawerOpened(_:)),
                           name: NSDrawer.willOpenNotification, object: drawer)
        center.addObserver(self, selector: #selector(windowWillClose(_:)),
                           name: NSWindow.willCloseNotification, object: _windowController?.window)

        if drawer.state == 0 {  // NSDrawerClosedState
            _selectionListArrayController.suspendArrangedObjectsUpdates()
        }

        NSUserDefaultsController.shared.addObserver(self, forKeyPath: "values." + UseSmallFontInSelectionList,
                                                    options: [], context: &Self.smallFontContext)
        doc?.addObserver(self, forKeyPath: DocKeySelectedItem, options: [], context: nil)
        _selectionListArrayController.addObserver(self, forKeyPath: "selection", options: [], context: nil)

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

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any,
                   for tableColumn: NSTableColumn?, row: Int) {
        if tableColumn?.identifier.rawValue == "displayName",
           let item = (_selectionListArrayController.arrangedObjects as? [Any])?[row] as? FSItem,
           let cell = cell as? ImageAndTextCell {
            // default-font row height is 17px, so subtract 1
            cell.image = item.icon(withSize: UInt32(tableView.rowHeight - 1))
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
        _tableView.rowHeight = fontSize + 4
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

    @objc private func onDrawerOpened(_ notification: Notification) {
        _selectionListArrayController.resumeArrangedObjectsUpdates()
    }

    @objc private func onDrawerClosed(_ notification: Notification) {
        _selectionListArrayController.suspendArrangedObjectsUpdates()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        document()?.removeObserver(self, forKeyPath: DocKeySelectedItem)
        NSUserDefaultsController.shared.removeObserver(self, forKeyPath: "values." + UseSmallFontInSelectionList)
        _selectionListArrayController.removeObserver(self, forKeyPath: "selection")
        NotificationCenter.default.removeObserver(self)
    }
}
