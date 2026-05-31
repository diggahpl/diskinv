//
//  SelectionListController.swift
//  Disk Inventory Xs
//
//  Swift port of SelectionListController.{h,m}. The array controller for the
//  files shown in the selection-list table, and the delegate for the search
//  field. Subclass of GenericArrayController: its collectionModel is the FSItem
//  set for the kind chosen in the popup (or the union across all kinds), and it
//  filters that set through an FSItemIndex for the entered search string.
//  Nib-wired, so class name, outlets, and search actions carry @objc.
//
//  GPL v3
//

import Cocoa

@objc(SelectionListController)
class SelectionListController: GenericArrayController {

    // NB: NSArrayController.initWithCoder: triggers rearrangeObjects() *before*
    // outlets are connected, so this is a plain optional (not IUO) and every
    // access nil-chains — mirroring the ObjC original's safe nil-messaging.
    @IBOutlet private var _progressIndicator: NSProgressIndicator?
    @IBOutlet private var _windowController: NSWindowController!
    @IBOutlet private var _kindsPopupController: GenericArrayController!
    @IBOutlet private var _searchField: NSSearchField!

    @objc var searchString: String?
    private var _indexes: [String: FSItemIndex] = [:]
    private var _indexToSearch: FSItemIndexType = .all

    override func awakeFromNib() {
        _kindsPopupController.addObserver(self, forKeyPath: "arrangedObjects", options: [], context: nil)

        // remove ourselves as observer before _kindsPopupController is deallocated
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification,
                                               object: _windowController.window)

        _indexToSearch = .all

        // set the template menu programmatically so our validateMenuItem: is called
        // (known bug: http://www.cocoabuilder.com/archive/message/cocoa/2004/4/21/104991)
        if let cell = _searchField.cell as? NSSearchFieldCell {
            cell.searchMenuTemplate = cell.searchMenuTemplate
        }
    }

    @objc func document() -> FileSystemDoc? {
        _windowController.document as? FileSystemDoc
    }

    override func arrange(_ objects: [Any]) -> [Any] {
        var objects = objects
        if !(searchString ?? "").isEmpty {
            objects = filterItems(objects)
        }
        return super.arrange(objects)
    }

    override func rearrangeObjects() {
        // showing a large number of files can take a moment; animate meanwhile
        let startStop = !progressAnimationIsRunning()
        if startStop { startProgressAnimation() }

        super.rearrangeObjects()

        if startStop { stopProgressAnimation() }
    }

    override func collectionModel() -> Any? {
        let kindStatistic = super.collectionModel()
        if NSIsControllerMarker(kindStatistic) { return kindStatistic }

        guard let kindStatistic = kindStatistic as? NSObject else { return kindStatistic }

        if (kindStatistic as AnyObject).isAllFileKindsItem() {
            let allFSItems = NSMutableSet()
            if let arranged = _kindsPopupController.arrangedObjects as? [Any] {
                for stat in arranged where stat is FileKindStatistic {
                    allFSItems.union((stat as! FileKindStatistic).items as! Set<AnyHashable>)
                }
            }
            return allFSItems
        } else {
            return (kindStatistic as! FileKindStatistic).items
        }
    }

    @IBAction func search(_ sender: Any?) {
        searchString = (sender as? NSControl)?.stringValue
        rearrangeObjects()
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        if object as AnyObject === _kindsPopupController, keyPath == "arrangedObjects" {
            _indexes.removeAll()
        }
    }

    @IBAction func searchInAll(_ sender: Any?) {
        _indexToSearch = .all
        if !(searchString ?? "").isEmpty { rearrangeObjects() }
    }

    @IBAction func searchInNames(_ sender: Any?) {
        _indexToSearch = .name
        if !(searchString ?? "").isEmpty { rearrangeObjects() }
    }

    @IBAction func searchInKindNames(_ sender: Any?) {
        _indexToSearch = .kind
        if !(searchString ?? "").isEmpty { rearrangeObjects() }
    }

    @IBAction func searchInPaths(_ sender: Any?) {
        _indexToSearch = .path
        if !(searchString ?? "").isEmpty { rearrangeObjects() }
    }

    // MARK: - NSMenuValidation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(searchInAll(_:)): menuItem.state = (_indexToSearch == .all) ? .on : .off
        case #selector(searchInNames(_:)): menuItem.state = (_indexToSearch == .name) ? .on : .off
        case #selector(searchInKindNames(_:)): menuItem.state = (_indexToSearch == .kind) ? .on : .off
        case #selector(searchInPaths(_:)): menuItem.state = (_indexToSearch == .path) ? .on : .off
        default: break
        }
        return true
    }

    // MARK: - DIXTableView delegate

    // forwarded by DIXTableView; drag&drop within the app is unsupported, copy out is
    @objc(dixDraggingSourceMaskForLocal:)
    func dixDraggingSourceMask(forLocal isLocal: Bool) -> NSDragOperation {
        isLocal ? [] : .copy
    }

    // MARK: - private

    private func currentIndex(withItems items: [Any]) -> FSItemIndex? {
        let kindStatistic = super.collectionModel()
        if NSIsControllerMarker(kindStatistic) { return nil }
        guard let kindStatistic = kindStatistic as? NSObject else { return nil }

        let isAllKinds = (kindStatistic as AnyObject).isAllFileKindsItem()
        let indexKey = isAllKinds ? "the special index key when all files are shown"
                                  : (kindStatistic as! FileKindStatistic).kindName

        if let existing = _indexes[indexKey] { return existing }

        // all FileKindStatistics if "all kinds", else just the selected kind
        let kindStatistics: NSDictionary
        if isAllKinds {
            kindStatistics = document()?.kindStatistics() ?? NSDictionary()
        } else {
            let kindName = (kindStatistic as! FileKindStatistic).kindName
            if let stat = document()?.kindStatistic(forKind: kindName) {
                kindStatistics = [kindName: stat] as NSDictionary
            } else {
                kindStatistics = NSDictionary()
            }
        }

        let index = FSItemIndex(kindStatistics: kindStatistics)

        let startStop = items.count > 5000 && !progressAnimationIsRunning()
        if startStop { startProgressAnimation() }
        index.addItems(from: items.compactMap { $0 as? FSItem })
        if startStop { stopProgressAnimation() }

        _indexes[indexKey] = index
        return index
    }

    private func filterItems(_ items: [Any]) -> [Any] {
        let kindStatistic = super.collectionModel()
        if NSIsControllerMarker(kindStatistic) { return items }
        guard let kindStatistic = kindStatistic as? NSObject else { return items }

        // shortcut: searching only kind names while showing a single kind
        if _indexToSearch == .kind, !(kindStatistic as AnyObject).isAllFileKindsItem() {
            let kindName = (kindStatistic as! FileKindStatistic).kindName
            if kindName.range(of: searchString ?? "", options: .caseInsensitive) != nil {
                return items
            }
            return []
        }

        guard let index = currentIndex(withItems: items) else { return items }
        return index.searchItems(searchString, inIndex: _indexToSearch)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        _kindsPopupController.removeObserver(self, forKeyPath: "arrangedObjects")
        NotificationCenter.default.removeObserver(self)
    }

    private func startProgressAnimation() {
        _progressIndicator?.usesThreadedAnimation = true
        _progressIndicator?.isHidden = false
        _progressIndicator?.startAnimation(self)
    }

    private func stopProgressAnimation() {
        _progressIndicator?.stopAnimation(self)
        _progressIndicator?.isHidden = true
        _progressIndicator?.usesThreadedAnimation = false
    }

    private func progressAnimationIsRunning() -> Bool {
        // matches ObjC ![_progressIndicator isHidden]: a nil indicator (during
        // early nib decode) reports "running" so rearrange skips the animation
        !(_progressIndicator?.isHidden ?? false)
    }
}
