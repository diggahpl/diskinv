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
        let drawer = _windowController.selectionListDrawer()
        // NSDrawerClosedState == 0, NSDrawerClosingState == 3 (unavailable in Swift)
        if drawer.state == 0 || drawer.state == 3 {
            drawer.toggle(self)
        }

        let selectedRow = _tableView.selectedRow
        assert(selectedRow >= 0, "kinds tableview should have a selection")
        guard selectedRow >= 0,
              let kindStat = (_kindsTableArrayController.arrangedObjects as? [Any])?[selectedRow] else { return }
        _kindsPopupArrayController.setSelectedObjects([kindStat])
    }

    // MARK: - NSTableView delegate

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any,
                   for tableColumn: NSTableColumn?, row: Int) {
        if tableColumn?.identifier.rawValue == "color", let image = colorImage(forRow: row, column: tableColumn) {
            // the "color" column's data cell is an image cell; set via KVC since
            // NSCell's -setImage: isn't exposed uniformly to Swift
            (cell as? NSCell)?.setValue(image, forKey: "image")
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
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
        }
    }

    // MARK: - private

    // a cushion swatch image for the given row, cached by kind name
    private func colorImage(forRow row: Int, column: NSTableColumn?) -> NSImage? {
        guard let kindStatistic = (_kindsTableArrayController.arrangedObjects as? [Any])?[row] as? FileKindStatistic
        else { return nil }

        let cellSize = NSSize(width: column?.width ?? 0, height: _tableView.rowHeight)

        var image = _cushionImages[kindStatistic.kindName]
        if image == nil || image!.size != cellSize {
            guard let bitmap = NSBitmapImageRep(rgbBitmapWithWidth: Int(cellSize.width), height: Int(cellSize.height))
            else { return image }
            let cushionRenderer = TMVCushionRenderer(rect: NSRect(origin: .zero, size: cellSize))

            cushionRenderer.setColor(document()?.fileTypeColors().color(forKind: kindStatistic.kindName) ?? .black)
            cushionRenderer.addRidge(byHeightFactor: 0.5)
            cushionRenderer.renderCushion(inBitmap: bitmap)

            image = bitmap.suitableImage(for: _tableView)
            _cushionImages[kindStatistic.kindName] = image
        }
        return image
    }

    private func setTableViewFont() {
        let fontSize: CGFloat = UserDefaults.standard.bool(forKey: UseSmallFontInKindStatistic)
            ? NSFont.smallSystemFontSize
            : NSFont.systemFontSize
        _tableView.font = NSFont.systemFont(ofSize: fontSize)
        _tableView.rowHeight = fontSize + 4
    }

    @objc private func documentSelectionChanged(_ notification: Notification) {
        guard let doc = document() else { return }

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
