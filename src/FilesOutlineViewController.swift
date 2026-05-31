//
//  FilesOutlineViewController.swift
//  Disk Inventory Xs
//
//  Swift port of FilesOutlineViewController.{h,m}. Data source + delegate for
//  the left file-browser outline (a DIXOutlineView): supplies the FSItem tree,
//  keeps selection in sync with the document both ways, drives the context
//  menu and drag-out, and reacts to zoom/view-option/items-changed
//  notifications. Nib-instantiated, so the class name and the IBOutlet/delegate
//  selectors are pinned with @objc.
//
//  GPL v3
//

import Cocoa

@objc(FilesOutlineViewController)
class FilesOutlineViewController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {

    @IBOutlet private var _document: FileSystemDoc!
    @IBOutlet private var _outlineView: DIXOutlineView!
    @IBOutlet private var _contextMenu: NSMenu!

    private var fontPrefKeyPath: String { "values." + UseSmallFontInFilesView }

    override func awakeFromNib() {
        let doc = document()
        let center = NotificationCenter.default

        center.addObserver(self, selector: #selector(zoomedItemChanged(_:)),
                           name: NSNotification.Name.ZoomedItemChanged, object: doc)
        center.addObserver(self, selector: #selector(viewOptionChanged(_:)),
                           name: NSNotification.Name.ViewOptionChanged, object: doc)
        center.addObserver(self, selector: #selector(itemsChanged(_:)),
                           name: NSNotification.Name.FSItemsChanged, object: doc)
        center.addObserver(self, selector: #selector(windowWillClose(_:)),
                           name: NSWindow.willCloseNotification, object: _outlineView?.window)

        // ImageAndTextCell as the data cell for the first (outline) column
        _outlineView?.outlineTableColumn?.dataCell = ImageAndTextCell.cell()

        let sizeFormatter = FileSizeFormatter()
        (_outlineView?.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("size"))?.dataCell as? NSCell)?.formatter = sizeFormatter

        NSUserDefaultsController.shared.addObserver(self, forKeyPath: fontPrefKeyPath, options: [], context: nil)
        doc?.addObserver(self, forKeyPath: DocKeySelectedItem, options: [], context: nil)

        setOutlineViewFont()
        reloadData()
    }

    @objc func document() -> FileSystemDoc? {
        if _document == nil, let outlineView = _outlineView {
            // mirror MainWindowController.documentForView: — the window's delegate
            // is the window controller, whose `document` is our FileSystemDoc
            _document = (outlineView.window?.delegate as? NSWindowController)?.document as? FileSystemDoc
        }
        return _document
    }

    @objc func rootItem() -> FSItem? {
        document()?.zoomedItem()
    }

    // MARK: - NSOutlineView data source

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let fsItem = (item as? FSItem) ?? rootItem()
        return fsItem?.child(at: UInt(index)) as Any
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let fsItem = item as? FSItem else { return false }
        return document()?.itemIsNode(fsItem) ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let fsItem = (item as? FSItem) ?? rootItem()
        return Int(fsItem?.childCount() ?? 0)
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        guard let columnTag = tableColumn?.identifier.rawValue, let fsItem = item as? FSItem else { return nil }
        return fsItem.value(forKey: columnTag)
    }

    func outlineView(_ outlineView: NSOutlineView, writeItems items: [Any], to pasteboard: NSPasteboard) -> Bool {
        // we only support single selection
        guard let item = items.first as? FSItem else { return false }
        if !item.isSpecialItem() && item.exists() {
            item.writeToPasteboard(pasteboard)
            return true
        }
        return false
    }

    // MARK: - NSOutlineView delegate

    func outlineView(_ outlineView: NSOutlineView, willDisplayCell cell: Any,
                     for tableColumn: NSTableColumn?, item: Any) {
        if tableColumn?.identifier.rawValue == "displayName",
           let fsItem = item as? FSItem,
           let cell = cell as? ImageAndTextCell {
            // default-font row height is 17px, so subtract 1
            cell.image = fsItem.icon(withSize: UInt32(outlineView.rowHeight - 1))
        }
    }

    // DIXOutlineView forwards its context-menu query here (informal protocol)
    @objc func outlineView(_ outlineView: NSOutlineView, menuForTableColumn column: NSTableColumn, item: Any) -> NSMenu? {
        _contextMenu
    }

    // DIXOutlineView forwards its drag-source mask here (private contract selector,
    // not the reserved NSDraggingSource one which is unavailable in Swift).
    // drag&drop within the app is not supported, copy/link out is.
    @objc(dixDraggingSourceMaskForLocal:)
    func dixDraggingSourceMask(forLocal isLocal: Bool) -> NSDragOperation {
        isLocal ? [] : [.link, .copy]
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let item = _outlineView?.selectedItem() as? FSItem
        let doc = document()
        // don't echo a selection we set ourselves (in onDocumentSelectionChanged)
        if item !== doc?.selectedItem() {
            doc?.setSelectedItem(item)
        }
    }

    // MARK: - document notifications

    @objc private func zoomedItemChanged(_ notification: Notification) { reloadData() }
    @objc private func itemsChanged(_ notification: Notification) { reloadData() }

    @objc private func viewOptionChanged(_ notification: Notification) {
        let theOption = notification.userInfo?[ChangedViewOption] as? String

        if theOption == ShowPackageContents {
            let selectedItem = _outlineView?.selectedItem()
            _outlineView?.deselectAll(self)

            reloadPackages(nil)

            // try to restore the selection
            if let selectedItem = selectedItem, let row = _outlineView?.row(forItem: selectedItem), row >= 0 {
                _outlineView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            // the view doesn't redraw properly, so invalidate it
            _outlineView?.needsDisplay = true
        } else if theOption == ShowPhysicalFileSize {
            reloadData()
        }
    }

    // MARK: - window notifications

    @objc private func windowWillClose(_ notification: Notification) {
        document()?.removeObserver(self, forKeyPath: DocKeySelectedItem)
        NSUserDefaultsController.shared.removeObserver(self, forKeyPath: fontPrefKeyPath)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == fontPrefKeyPath {
            setOutlineViewFont()
        } else if keyPath == DocKeySelectedItem {
            onDocumentSelectionChanged()
        }
    }

    // MARK: - private

    private func onDocumentSelectionChanged() {
        let item = document()?.selectedItem()
        if item === (_outlineView?.selectedItem() as? FSItem) { return }

        guard let outlineView = _outlineView else { return }
        guard let item = item else {
            outlineView.deselectAll(nil)
            return
        }

        var row = outlineView.row(forItem: item)
        if row < 0 {
            // the parents aren't expanded yet; expand along the path to the item
            let path = item.fsItemPath()
            var i = 1
            while i < path.count {
                row = outlineView.row(forItem: item)
                if row <= 0 {
                    // stop if the next node isn't expandable (e.g. a package with
                    // package contents hidden)
                    if !(document()?.itemIsNode(path[i]) ?? false) { break }
                    outlineView.expandItem(path[i])
                }
                i += 1
            }
            row = outlineView.row(forItem: document()?.selectedItem())
        }

        if row < 0 {
            outlineView.deselectAll(nil)
        } else {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }
    }

    private func setOutlineViewFont() {
        let fontSize: CGFloat = UserDefaults.standard.bool(forKey: UseSmallFontInFilesView)
            ? NSFont.smallSystemFontSize
            : NSFont.systemFontSize
        _outlineView?.font = NSFont.systemFont(ofSize: fontSize)
        _outlineView?.rowHeight = fontSize + 4
    }

    private func reloadData() {
        _outlineView?.reloadData()
        onDocumentSelectionChanged()
    }

    private func reloadPackages(_ parent: FSItem?) {
        guard let doc = document(), let outlineView = _outlineView else { return }
        guard let parent = parent ?? rootItem() else { return }

        var i: UInt = 0
        while i < parent.childCount() {
            defer { i += 1 }
            guard let child = parent.child(at: i) else { continue }

            // only items shown in the outline need reloading
            if child.isFolder() && outlineView.row(forItem: child) >= 0 {
                // collapse if it's no longer expandable
                if !doc.itemIsNode(child) && outlineView.isItemExpanded(child) {
                    outlineView.collapseItem(child, collapseChildren: true)
                }
                if child.isPackage() {
                    outlineView.reloadItem(child)
                }
                if doc.itemIsNode(child) {
                    reloadPackages(child)
                }
            }
        }
    }
}
