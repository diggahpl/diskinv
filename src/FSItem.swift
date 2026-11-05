//
//  FSItem.swift
//  Disk Inventory X
//
//  Swift port of the central model class FSItem: the recursive folder
//  scanner and tree node. Ported from the original Objective-C
//  FSItem.h/.m. ARC throughout.
//
//  The folder scanner (see "the scanner" below) reads the folders with
//  getattrlistbulk on background threads, one task per folder, and merges
//  the results folder by folder. The items keep only compact data (name,
//  sizes, flags); their NSURLs are built lazily.
//
//  Non-class support symbols (FSItemType enum, g_fileCount/g_folderCount
//  globals, the exception name constants, and the NSString
//  compareAsFilesystemName: category) live in FSItemSupport.h/.m and are
//  visible here via the bridging header.
//
//  GPL v3
//

import Cocoa
import CoreServices
import UniformTypeIdentifiers
import os.lock

//MARK: - delegate informal protocol -> @objc protocol

@objc protocol FSItemDelegate: NSObjectProtocol {
    //Called about 20 times per second by "loadChildren" (on the thread which called it) while the folders are
    //scanned on background threads. currentFolder is a folder near the top of the tree (4 levels deep at most)
    //which is being scanned; for the content of a package it is the package. It is nil as long as there is none.
    //The delegate may return NO to stop loading.
    @objc optional func fsItemScanProgress(_ item: FSItem, currentFolder: FSItem?) -> Bool
    @objc optional func fsItemShouldIgnoreCreatorCode(_ item: FSItem) -> Bool   //default is NO (if not implemented)
    @objc optional func fsItemShouldLookIntoPackages(_ item: FSItem) -> Bool    //default is NO (if not implemented)
    @objc optional func fsItemShouldUsePhysicalFileSize(_ item: FSItem) -> Bool
}

private func isImageUTI(_ uti: String?) -> Bool {
    guard let uti = uti, let type = UTType(uti) else { return false }
    return type.conforms(to: .image)
}

//MARK: - scan errors (replaces the former ObjC NSException-based cancellation)

//Errors thrown by the recursive scanner. Both FSItem and its sole caller
//(FileSystemDoc) are now Swift, so idiomatic Swift errors replace the
//former FSItemLoadingCanceledException / FSItemLoadingFailedException
//NSExceptions.
enum FSItemError: Error {
    case loadingCanceled   //delegate canceled the loading
    case loadingFailed     //error while enumerating files/folders
}

fileprivate struct FSItemFlags: OptionSet {
    let rawValue: UInt8
    static let folder = FSItemFlags(rawValue: 1)
    static let package = FSItemFlags(rawValue: 2)
    static let scannedSizes = FSItemFlags(rawValue: 4)   //_physicalSize and _logicalSize are valid
}

//The ObjC runtime name must not be "FSItem": FSKit.framework (loaded into every app
//on current systems) defines a class of that name, and two classes with the same
//name make the runtime warn about "spurious casting failures and mysterious crashes".
@objc(DIXFSItem) final class FSItem: NSObject {

    //The URL of a root item. The other items build theirs lazily from their parent's path and their name
    //(see fileURL()), so a scanned tree doesn't carry an NSURL and its resource cache for every file.
    private var _fileURL: NSURL?
    //only valid for non-root items (non-owning back-reference); the original
    //used __unsafe_unretained because parents own children via _childs.
    private unowned(unsafe) var _parent: FSItem?
    private var _icons: NSMutableDictionary?   //holds icons in various sizes (see iconWithSize:)
    private var _type: FSItemType = FileFolderItem
    private var _flags: FSItemFlags = []
    private var _kind: UInt32 = 0   //index into FSItemKinds, 0 = not determined yet
    private var _name: String = ""
    private var _size: NSNumber?
    private var _sizeValue: UInt64 = 0
    //sizes of a scanned file, so that switching between them doesn't need the file system
    private var _physicalSize: UInt64 = 0
    private var _logicalSize: UInt64 = 0
    private var _childs: [FSItem]?
    //non-owning, like the original __unsafe_unretained id
    private unowned(unsafe) var _delegate: AnyObject?

    //MARK: initializers

    @objc(initWithPath:)
    init(path: String) {
        super.init()
        let url = NSURL(fileURLWithPath: path)
        commonInit(url: url)
    }

    @objc(initWithURL:)
    init(url: NSURL) {
        super.init()
        commonInit(url: url)
    }

    private func commonInit(url: NSURL) {
        _type = FileFolderItem
        _fileURL = url
        _name = url.cachedName()
        if url.isDirectory() {
            _flags.insert(.folder)
            _childs = []
        }
        if url.isPackage() {
            _flags.insert(.package)
        }
        _parent = nil   //we are the root item
    }

    @objc(initAsOtherSpaceItemForParent:)
    init(asOtherSpaceItemForParent parent: FSItem) {
        super.init()
        _type = OtherSpaceItem
        _parent = parent   //weak reference
        recalculateSize(false, updateParent: false)
    }

    @objc(initAsFreeSpaceItemForParent:)
    init(asFreeSpaceItemForParent parent: FSItem) {
        super.init()
        _type = FreeSpaceItem
        _parent = parent
        recalculateSize(false, updateParent: false)
    }

    //designated initializer used by the scanner: no file system access, the scanner has all the data
    fileprivate init(scannedName name: String, parent: FSItem, flags: FSItemFlags, kind: UInt32,
                     physicalSize: UInt64, logicalSize: UInt64, usePhysicalSize: Bool) {
        _name = name
        _parent = parent   //no retain
        _flags = flags
        _kind = kind
        if flags.contains(.folder) {
            _childs = []
        } else {
            _flags.insert(.scannedSizes)
            _physicalSize = physicalSize
            _logicalSize = logicalSize
            _sizeValue = usePhysicalSize ? physicalSize : logicalSize
        }
        super.init()
    }

    deinit {
        //nil out children's non-owning back-reference before ARC releases _childs
        if let childs = _childs {
            for child in childs {
                child.onParentDealloc()
            }
        }
    }

    //MARK: delegate

    @objc(delegate)
    func delegate() -> AnyObject? {
        return root()._delegate
    }

    @objc(setDelegate:)
    func setDelegate(_ delegate: AnyObject?) {
        _delegate = delegate   //no retain
    }

    //convenience: typed access to the delegate's optional methods
    private var delegateAsFSItemDelegate: FSItemDelegate? {
        return delegate() as? FSItemDelegate
    }

    //MARK: type / basics

    @objc(type)
    func type() -> FSItemType {
        return _type
    }

    @objc(isSpecialItem)
    func isSpecialItem() -> Bool {
        return _type != FileFolderItem
    }

    @objc(fileURL)
    func fileURL() -> NSURL? {
        if isSpecialItem() {
            return root().fileURL()
        }
        if _fileURL == nil && _parent != nil {
            //not the root item: build the URL from the parent's path and our name
            _fileURL = NSURL(fileURLWithPath: path(), isDirectory: _flags.contains(.folder))
        }
        return _fileURL
    }

    @objc(setFileURL:)
    func setFileURL(_ url: NSURL?) {
        assert(!isSpecialItem(), "free and other space items don't have a NTFileDesc object")
        _fileURL = url
        if let url = url {
            _name = url.cachedName()   //the item may have got a new name (e.g. when it is moved to the trash)
        }
    }

    override func isEqual(_ object: Any?) -> Bool {
        //We don't check real equality here. This method is only intended to support NSSet.
        return (object as AnyObject?) === self
    }

    override var description: String {
        switch _type {
        case FileFolderItem:
            return fileURL()?.description ?? ""
        case FreeSpaceItem:
            return "FreeSpaceItem"
        case OtherSpaceItem:
            return "OtherSpaceItem"
        default:
            assert(false, "unknown item type")
            return ""
        }
    }

    //MARK: tree navigation

    @objc(parent)
    func parent() -> FSItem? {
        return _parent
    }

    @objc(root)
    func root() -> FSItem {
        if isRoot() {
            return self
        } else {
            return parent()!.root()
        }
    }

    @objc(isRoot)
    func isRoot() -> Bool {
        return _parent == nil
    }

    @objc(setParent:)
    func setParent(_ parent: FSItem?) {
        _parent = parent   //weak reference (parent owns us)
        _delegate = nil    //we use our parent's delegate
    }

    @objc(onParentDealloc)
    func onParentDealloc() {
        _parent = nil
    }

    //MARK: file kind predicates

    @objc(isFolder)
    func isFolder() -> Bool {
        //returns NO for an alias pointing to a directory
        if !isSpecialItem() {
            return _flags.contains(.folder)
        } else {
            return false
        }
    }

    @objc(isPackage)
    func isPackage() -> Bool {
        if !isSpecialItem() {
            return _flags.contains(.package)
        } else {
            return false
        }
    }

    @objc(isAlias)
    func isAlias() -> Bool {
        if !isSpecialItem() {
            return fileURL()?.cachedIsAliasOrSymbolicLink() ?? false
        } else {
            return false
        }
    }

    @objc(exists)
    func exists() -> Bool {
        return fileURL()?.stillExists() ?? false
    }

    @objc(iconWithSize:)
    func icon(withSize iconSize: UInt32) -> NSImage? {
        //items for free space and other space don't have an icon
        if isSpecialItem() {
            return nil
        }

        if _icons == nil {
            _icons = NSMutableDictionary()
        }

        let key = NSNumber(value: iconSize)
        var icon = _icons?.object(forKey: key) as AnyObject?
        if icon == nil {
            let img = NSWorkspace.shared.icon(forFile: fileURL()?.path ?? "")
            img.size = NSMakeSize(CGFloat(iconSize), CGFloat(iconSize))
            icon = img
            if icon == nil {
                icon = NSNull()
            }
            _icons?.setObject(icon!, forKey: key)
        }

        if icon is NSNull {
            return nil
        }
        return icon as? NSImage
    }

    //MARK: ----------------- child handlers -----------------------

    @objc(childEnumerator)
    func childEnumerator() -> NSEnumerator? {
        if !isSpecialItem() {
            return FSItemChildEnumerator(_childs ?? [])
        } else {
            return nil
        }
    }

    @objc(childAtIndex:)
    func child(at index: UInt) -> FSItem? {
        if !isSpecialItem() {
            return _childs?[Int(index)]
        } else {
            return nil
        }
    }

    @objc(childCount)
    func childCount() -> UInt {
        if !isSpecialItem() {
            return UInt(_childs?.count ?? 0)
        } else {
            return 0
        }
    }

    @objc(removeChild:updateParent:)
    func removeChild(_ child: FSItem, updateParent: Bool) {
        assert(!isSpecialItem(), "removeChild is illegal call for special item")

        guard let index = _childs?.firstIndex(where: { $0 === child }) else { return }

        let myOldSize = sizeValue()
        let myNewSize = myOldSize - child.sizeValue()

        setSizeValue(myNewSize)

        _childs?.remove(at: index)

        if updateParent && !isRoot() {
            parent()!.childChanged(self, oldSize: myOldSize, newSize: myNewSize)
        }
    }

    @objc(insertChild:updateParent:)
    func insertChild(_ newChild: FSItem, updateParent: Bool) {
        let myOldSize = sizeValue()

        newChild.setParent(self)

        guard insertSorted(newChild) else { return }

        setSizeValue(sizeValue() + newChild.sizeValue())

        if updateParent && !isRoot() {
            parent()!.childChanged(self, oldSize: myOldSize, newSize: sizeValue())
        }
    }

    //inserts the child into the size-sorted child array; does no size bookkeeping
    private func insertSorted(_ child: FSItem) -> Bool {
        guard let childs = _childs else { return false }

        //binary search for the first child which has to follow the new one
        var low = 0
        var high = childs.count
        while low < high {
            let mid = (low + high) / 2
            if childs[mid].compareSizeDescendingly(child) == .orderedAscending {
                low = mid + 1
            } else {
                high = mid
            }
        }
        _childs?.insert(child, at: low)
        return true
    }

    @objc(replaceChild:withItem:updateParent:)
    func replaceChild(_ oldChild: FSItem, with newChild: FSItem, updateParent: Bool) {
        if oldChild !== newChild {
            let myOldSize = sizeValue()

            removeChild(oldChild, updateParent: false)
            insertChild(newChild, updateParent: false)

            if updateParent && !isRoot() {
                parent()!.childChanged(self, oldSize: myOldSize, newSize: sizeValue())
            }
        }
    }

    //if this is a folder, load all containing files
    //Called only by FileSystemDoc (now Swift), so no @objc exposure is needed.
    func loadChildren() throws {
        var usePhysicalSize = false

        if let d = delegateAsFSItemDelegate, let result = d.fsItemShouldUsePhysicalFileSize?(self) {
            usePhysicalSize = result
        }

        //use new optimized version of loadChilds
        try loadChildrenAndSetKindStrings(true, usePhysicalSize: usePhysicalSize)
    }

    //MARK: ----------------- sizes -----------------------

    @objc(size)
    func size() -> NSNumber {
        if _size == nil {
            _size = NSNumber(value: _sizeValue)
        }
        return _size!
    }

    @objc(sizeValue)
    func sizeValue() -> UInt64 {
        return _sizeValue
    }

    @objc(setSize:)
    func setSize(_ newSize: NSNumber) {
        assert(true)
        if _size !== newSize {
            _size = newSize
            _sizeValue = newSize.uint64Value
        }
    }

    @objc(setSizeValue:)
    func setSizeValue(_ newSize: UInt64) {
        _sizeValue = newSize
        _size = nil
    }

    @objc(recalculateSize:updateParent:)
    func recalculateSize(_ usePhysicalSize: Bool, updateParent: Bool) {
        //just recalculates size (no file system access)
        let oldSize = sizeValue()
        var size: UInt64 = 0

        switch _type {
        case FileFolderItem:
            if isFolder() {
                if let childs = _childs {
                    for child in childs {
                        child.recalculateSize(usePhysicalSize, updateParent: false)
                        size += child.sizeValue()
                    }
                    sortChildren()
                }
            } else if _flags.contains(.scannedSizes) {
                size = usePhysicalSize ? _physicalSize : _logicalSize
            } else {
                //File which wasn't scanned
                if usePhysicalSize {
                    size = fileURL()?.cachedPhysicalSize().uint64Value ?? 0
                } else {
                    size = fileURL()?.cachedLogicalSize().uint64Value ?? 0
                }
            }

        case FreeSpaceItem:
            let freeSpace = fileURL()?.getCachedNumberValue(URLResourceKey.volumeAvailableCapacityKey.rawValue)
            size = freeSpace?.uint64Value ?? 0

        case OtherSpaceItem:
            let totalSpace = fileURL()?.getCachedNumberValue(URLResourceKey.volumeTotalCapacityKey.rawValue)
            let freeSpace = fileURL()?.getCachedNumberValue(URLResourceKey.volumeAvailableCapacityKey.rawValue)

            let totalSpaceVal: UInt64 = totalSpace?.uint64Value ?? 0
            let freeSpaceVal: UInt64 = freeSpace?.uint64Value ?? 0

            //the root item must have finished calculating its size, otherwise this doesn't work
            size = totalSpaceVal &- root().sizeValue() &- freeSpaceVal

        default:
            break
        }

        setSizeValue(size)

        if updateParent && !isRoot() {
            parent()!.childChanged(self, oldSize: oldSize, newSize: size)
        }
    }

    //MARK: kind name

    //get display string for kind ("Application", "Simple Text Document", ...)
    @objc(kindName)
    func kindName() -> String {
        if !isSpecialItem() {
            if _kind == 0 {
                setKindString()
            }
            return FSItemKinds.shared.name(at: _kind) ?? ""
        } else {
            return ""
        }
    }

    @objc(setKindString)
    func setKindString() {
        //will ask delegate whether to ignore creator codes
        var ignoreCreatorCode = false
        if let d = delegateAsFSItemDelegate, let result = d.fsItemShouldIgnoreCreatorCode?(self) {
            ignoreCreatorCode = result
        }
        _ = ignoreCreatorCode   //preserved for parity with original (unused beyond the query)

        setKindStringIncludingChildren(false)
    }

    //determines the kind of the file/folder as shown in Finder's Get Info.
    //(The type/creator-based code in the original is commented out; only the
    //live UTI-based code is ported.)
    @objc(setKindStringIncludingChildren:)
    func setKindStringIncludingChildren(_ includingChildren: Bool) {
        //The scanner determines the kinds without asking the file system; this slow way is only
        //used for items which the scanner didn't set up (e.g. the root item).
        if let url = fileURL() {
            _kind = FSItemKinds.shared.kind(for: url)
        }

        //let our childs do the same
        if includingChildren && isFolder() {
            var i = childCount()
            while i > 0 {
                i -= 1
                child(at: i)?.setKindStringIncludingChildren(true)
            }
        }
    }

    //MARK: names / paths

    @objc(name)
    func name() -> String {
        switch _type {
        case FileFolderItem:
            return _name
        case FreeSpaceItem:
            return "FreeSpaceItem"
        case OtherSpaceItem:
            return "OtherSpaceItem"
        default:
            assert(false, "unknown item type")
            return ""
        }
    }

    @objc(path)
    func path() -> String {
        if !isSpecialItem() {
            if isRoot() {
                return fileURL()?.cachedPath() ?? ""
            } else {
                //parent path + "/" + name
                return (parent()!.path() as NSString).appendingPathComponent(name())
            }
        } else {
            return name()
        }
    }

    @objc(folderName)
    func folderName() -> String {
        if !isSpecialItem() {
            if let parent = parent() {
                return parent.path()
            } else {
                return (path() as NSString).deletingLastPathComponent
            }
        } else {
            return ""
        }
    }

    //display string for name (with or without extension; localized file names)
    @objc(displayName)
    func displayName() -> String {
        switch _type {
        case FileFolderItem:
            var name = fileURL()?.cachedDisplayName()
            if name == nil {
                name = fileURL()?.cachedName()
            }
            if name == nil {
                name = ""
            }
            return name!
        case FreeSpaceItem:
            return NSLocalizedString("free space on drive", comment: "")
        case OtherSpaceItem:
            return NSLocalizedString("space occupied by other files and folders", comment: "")
        default:
            assert(false, "unknown item type")
            return ""
        }
    }

    @objc(displayFolderName)
    func displayFolderName() -> String {
        //folder name relative to root item, not "/"
        if !isSpecialItem() {
            if let parent = parent() {
                return (parent.displayFolderName() as NSString).appendingPathComponent(parent.displayName())
            } else {
                return ""
            }
        } else {
            return ""
        }
    }

    @objc(displayPath)
    func displayPath() -> String {
        //path relative to root item, not "/"
        if !isSpecialItem() {
            return (displayFolderName() as NSString).appendingPathComponent(displayName())
        } else {
            return displayName()
        }
    }

    //MARK: ----------------- comparison helpers -----------------------

    @objc(compareSize:)
    func compareSize(_ other: FSItem) -> ComparisonResult {
        //if just one of the 2 FSItems (self xor other) is a special item, then the special
        //item is considered to be smaller (so the special items are at the end of the child array)
        if isSpecialItem() != other.isSpecialItem() {
            return .orderedDescending
        }

        let mySize = sizeValue()
        let otherSize = other.sizeValue()

        if mySize > otherSize {
            return .orderedDescending
        }
        if mySize < otherSize {
            return .orderedAscending
        }

        //if both FSItems have the same size, order by their names
        return (name() as NSString).compare(asFilesystemName:other.name())
    }

    @objc(compareDisplayName:)
    func compareDisplayName(_ other: FSItem) -> ComparisonResult {
        return (displayName() as NSString).compare(asFilesystemName:other.displayName())
    }

    //compare the size of 2 FSItems (descending)
    @objc(compareSizeDescendingly:)
    func compareSizeDescendingly(_ other: FSItem) -> ComparisonResult {
        //flip result of compareSize:
        switch compareSize(other) {
        case .orderedDescending:
            return .orderedAscending
        case .orderedAscending:
            return .orderedDescending
        default:
            return .orderedSame
        }
    }

    //MARK: ----------------- child change propagation -----------------------

    @objc(childChanged:oldSize:newSize:)
    func childChanged(_ child: FSItem, oldSize: UInt64, newSize: UInt64) {
        if oldSize == newSize {
            return
        }

        let myOldSize = sizeValue()
        let myNewSize = myOldSize &- oldSize &+ newSize

        //keep childs array sorted. The child's size has already changed while ours has
        //not, so only move the child within the array: removeChild/insertChild would
        //subtract the child's new size from our old one, which can underflow.
        if let index = _childs?.firstIndex(where: { $0 === child }) {
            _childs?.remove(at: index)
            _ = insertSorted(child)
        }

        setSizeValue(myNewSize)

        if !isRoot() {
            parent()!.childChanged(self, oldSize: myOldSize, newSize: myNewSize)
        }
    }

    //MARK: ----------------- the scanner -----------------------

    //keeps the children ordered by size (descending), see compareSizeDescendingly
    fileprivate func sortChildren() {
        _childs?.sort(by: { $0.compareSizeDescendingly($1) == .orderedAscending })
    }

    //Called by the scanner when all children of this folder are complete: the folder's size is the
    //sum of theirs. Used in place of a recursive recalculateSize pass over the whole tree.
    fileprivate func finishScannedFolder() {
        var size: UInt64 = 0
        if let childs = _childs {
            for child in childs {
                size += child.sizeValue()
            }
        }
        sortChildren()
        setSizeValue(size)
    }

    fileprivate func setScannedChildren(_ childs: [FSItem]) {
        _childs = childs
    }

    //Scans the folder with all its sub folders. The folders are read on background threads (all
    //cores are used); the calling thread only waits and tells the delegate about the progress
    //(fsItemScanProgress), which may cancel the scan.
    //
    //The sizes of the files are the physical sizes (the allocated space) if usePhysicalSize is set,
    //the logical ones otherwise. (The Objective-C original always ended the scan with a pass which
    //set the physical sizes, whatever the option said, so the sizes didn't match the option until it
    //was toggled twice.)
    func loadChildrenAndSetKindStrings(_ setKindStringsParam: Bool, usePhysicalSize: Bool) throws {
        if !isFolder() {
            return
        }

        var setKindStrings = setKindStringsParam
        let delegate = delegateAsFSItemDelegate

        _childs = []

        //should the kind strings of our childs be set initially? (optimization)
        if setKindStrings && !isRoot() {
            var lookInto = false
            if let d = delegate, let result = d.fsItemShouldLookIntoPackages?(self) {
                lookInto = result
            }
            if !lookInto {
                setKindStrings = !isPackage()
            }
        }

        FSItemKinds.shared.forgetItemClasses()
        let scan = FSItemScan(root: self, path: path(), setKindStrings: setKindStrings, usePhysicalSize: usePhysicalSize)
        scan.start()

        //without a delegate nobody is interested in the progress, so we can sleep until the scan is done
        let progressInterval: TimeInterval? = (delegate == nil) ? nil : 0.05
        while !scan.waitUntilFinished(timeout: progressInterval) {
            //should we cancel the loading?
            if delegate?.fsItemScanProgress?(self, currentFolder: scan.currentFolder) == false {
                scan.cancel()
            }
        }

        if scan.isCanceled {
            throw FSItemError.loadingCanceled
        }

        g_fileCount &+= scan.fileCount
        g_folderCount &+= scan.folderCount
    }

    //MARK: ----------------- pasteboard support -----------------------

    @objc(supportedPasteboardTypes)
    func supportedPasteboardTypes() -> [NSPasteboard.PasteboardType] {
        //match the original ordering: Filenames, String, FileContents
        var types: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            .string,
            NSPasteboard.PasteboardType("NSFileContentsPboardType")
        ]

        let uti = fileURL()?.cachedUTI()

        func testType(_ test: UTType, _ type: NSPasteboard.PasteboardType) {
            if let uti = uti, uti == test.identifier {
                types.append(type)
            }
        }

        testType(.rtf, NSPasteboard.PasteboardType.rtf)
        testType(.rtfd, NSPasteboard.PasteboardType.rtfd)
        testType(.html, NSPasteboard.PasteboardType.html)
        testType(.pdf, NSPasteboard.PasteboardType.pdf)

        // add TIFF if this is an image
        if isImageUTI(uti) {
            types.append(NSPasteboard.PasteboardType.tiff)
        }

        return types
    }

    @objc(supportsPasteboardType:)
    func supportsPasteboardType(_ type: String) -> Bool {
        let uti = fileURL()?.cachedUTI()

        //this is derived from NTFilePasteboardSource's "- (NSArray*)pasteboardTypes:"
        return type == "NSFilenamesPboardType"
            || type == NSPasteboard.PasteboardType.string.rawValue
            || type == "NSFileContentsPboardType"
            || (type == NSPasteboard.PasteboardType.tiff.rawValue && isImageUTI(uti))
            || (type == NSPasteboard.PasteboardType.rtf.rawValue && uti == UTType.rtf.identifier)
            || (type == NSPasteboard.PasteboardType.rtfd.rawValue && uti == UTType.flatRTFD.identifier)
            || (type == NSPasteboard.PasteboardType.html.rawValue && uti == NSPasteboard.PasteboardType.html.rawValue)
            || (type == NSPasteboard.PasteboardType.pdf.rawValue && uti == NSPasteboard.PasteboardType.pdf.rawValue)
    }

    @objc(writeToPasteboard:)
    func writeToPasteboard(_ pboard: NSPasteboard) {
        pboard.declareTypes(supportedPasteboardTypes(), owner: self)
    }

    @objc(writeToPasteboard:withTypes:)
    func writeToPasteboard(_ pasteboard: NSPasteboard, withTypes types: [Any]) {
        let pbTypes = types.compactMap { ($0 as? String).map { NSPasteboard.PasteboardType($0) } }
        NTFilePasteboardSource.file(fileURL() as URL?, to: pasteboard, types: pbTypes)
    }

    @objc(pasteboard:provideDataForType:)
    func pasteboard(_ pboard: NSPasteboard, provideDataForType type: String) {
        guard let url = fileURL() else { return }
        let path = url.cachedPath()
        let uti = url.cachedUTI()

        if type == "NSFilenamesPboardType" {
            let pathsArray = [path as Any]
            pboard.setPropertyList(pathsArray, forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        } else if type == NSPasteboard.PasteboardType.string.rawValue {
            pboard.setString(path, forType: .string)
        } else if type == "NSFileContentsPboardType" {
            // write the contents
            pboard.writeFileContents(path)
        } else if type == NSPasteboard.PasteboardType.tiff.rawValue {
            if uti == UTType.tiff.identifier {
                if let data = NSData(contentsOfFile: path) as Data? {
                    pboard.setData(data, forType: .tiff)
                }
            } else if isImageUTI(uti) {
                // open the image and return TIFFRepresentation
                if let image = NSImage(contentsOfFile: url.path ?? ""),
                   let data = image.tiffRepresentation {
                    pboard.setData(data, forType: .tiff)
                }
            }
        } else if type == NSPasteboard.PasteboardType.rtf.rawValue {
            if uti == UTType.rtf.identifier, let data = NSData(contentsOfFile: path) as Data? {
                pboard.setData(data, forType: .rtf)
            }
        } else if type == NSPasteboard.PasteboardType.rtfd.rawValue {
            if uti == UTType.flatRTFD.identifier {
                if let tempRTFDData = try? FileWrapper(url: URL(fileURLWithPath: path), options: []) {
                    pboard.setData(tempRTFDData.serializedRepresentation ?? Data(), forType: .rtfd)
                }
            }
        } else if type == NSPasteboard.PasteboardType.html.rawValue {
            if uti == UTType.html.identifier, let data = NSData(contentsOfFile: path) as Data? {
                pboard.setData(data, forType: .html)
            }
        } else if type == NSPasteboard.PasteboardType.pdf.rawValue {
            if uti == UTType.pdf.identifier, let data = NSData(contentsOfFile: path) as Data? {
                pboard.setData(data, forType: .pdf)
            }
        }
    }
}

//MARK: - enumerator for the children

//NSEnumerator over a Swift array of items (what childEnumerator() hands out)
private final class FSItemChildEnumerator: NSEnumerator {
    private let items: [FSItem]
    private var index = 0

    init(_ items: [FSItem]) {
        self.items = items
        super.init()
    }

    override func nextObject() -> Any? {
        if index < items.count {
            index += 1
            return items[index - 1]
        }
        return nil
    }
}

//MARK: - helpers for the scanner

fileprivate final class UnfairLock {
    private let lockPtr = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)

    init() {
        lockPtr.initialize(to: os_unfair_lock())
    }

    deinit {
        lockPtr.deallocate()
    }

    func lock() {
        os_unfair_lock_lock(lockPtr)
    }

    func unlock() {
        os_unfair_lock_unlock(lockPtr)
    }
}

//Kind names ("Application", "PNG image", ...) of all items: the items only hold an index into this table.
//Thread safe, because the scanner's threads determine the kinds concurrently.
//
//The kind of a file comes from its UTI. Asking the file system for the UTI of every single file is
//what made the old scanner slow, but the UTI of an item is determined by few of its properties
//(for a file mostly the name extension), so it's asked for once per distinct combination of these
//properties and remembered (see ItemClass).
fileprivate final class FSItemKinds {

    static let shared = FSItemKinds()

    //The properties which determine the UTI and the package state of an item
    struct ItemClass: Hashable {
        var ext: String        //name extension, empty if there is none
        var name: String       //the whole name for a file without extension (there are types for names like "Makefile")
        var traits: UInt64     //see FSItemScan.itemTraits
    }

    struct ItemInfo {
        var kind: UInt32
        var isPackage: Bool
    }

    private let lock = UnfairLock()
    private var kindNames: [String] = [""]                 //index 0: no kind
    private var kindIndexes: [String: UInt32] = [:]
    private var kindNameForUTI: [String: String] = [:]      //cache for UTTypeCopyDescription
    private var infoForClass: [ItemClass: ItemInfo] = [:]

    //The classes are remembered for one scan only; Launch Services may know other types at the next one.
    func forgetItemClasses() {
        lock.lock()
        infoForClass.removeAll()
        lock.unlock()
    }

    func name(at index: UInt32) -> String? {
        if index == 0 {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return kindNames[Int(index)]
    }

    //Kind of the file/folder as shown in Finder's Get Info. (The type/creator-based code in the
    //original is commented out; only the live UTI-based code is ported.) This asks the file system.
    func kind(for url: NSURL) -> UInt32 {
        return kind(forUTI: url.cachedUTI(), url: url)
    }

    private func kind(forUTI uti: String?, url: NSURL) -> UInt32 {
        var kindName: String? = nil

        if let uti = uti {
            lock.lock()
            kindName = kindNameForUTI[uti]
            lock.unlock()

            if kindName == nil {
                kindName = UTType(uti)?.localizedDescription

                //remember kind name for similar files
                if let kn = kindName {
                    lock.lock()
                    kindNameForUTI[uti] = kn
                    lock.unlock()
                }
            }
        }

        if kindName == nil {
            kindName = url.getCachedStringValue(URLResourceKey.localizedTypeDescriptionKey.rawValue)
        }

        guard let name = kindName else {
            return 0
        }

        lock.lock()
        defer { lock.unlock() }
        if let index = kindIndexes[name] {
            return index
        }
        kindNames.append(name)
        let index = UInt32(kindNames.count - 1)
        kindIndexes[name] = index
        return index
    }

    //Kind and package state of an item of the given class. url() is asked for only if we don't know the class yet,
    //or if askEveryTime is set, because the items of the class differ (see FSItemScan.readEntries).
    func info(for itemClass: ItemClass, askEveryTime: Bool = false, url: () -> NSURL) -> ItemInfo {
        if !askEveryTime {
            lock.lock()
            let known = infoForClass[itemClass]
            lock.unlock()
            if let known = known {
                return known
            }
        }

        let itemURL = url()
        let values = try? (itemURL as URL).resourceValues(forKeys: [.typeIdentifierKey, .isPackageKey])

        guard let uti = values?.typeIdentifier else {
            //The file system doesn't tell (e.g. the item is gone already or we have no access to it): don't remember
            //that, and take what we know about the items which just have no name extension.
            if askEveryTime {
                var plainClass = itemClass
                plainClass.ext = ""
                plainClass.name = ""
                return info(for: plainClass, url: url)
            }
            return ItemInfo(kind: kind(forUTI: nil, url: itemURL), isPackage: false)
        }

        let info = ItemInfo(kind: kind(forUTI: uti, url: itemURL), isPackage: values?.isPackage ?? false)
        if !askEveryTime {
            lock.lock()
            infoForClass[itemClass] = info
            lock.unlock()
        }
        return info
    }
}

//One scan of a folder with all its sub folders (see loadChildrenAndSetKindStrings).
//
//There is one task per folder on a concurrent queue. A task reads the entries of its folder, creates the items
//(the FSItems of a folder are only touched by the task of that folder until it is complete) and schedules a task
//for every sub folder. The bookkeeping which is shared between the tasks (cancel flag, counts, the countdown of the
//unfinished sub folders of every folder, the buffers) is guarded by one lock. When the last sub folder of a
//folder is complete, the task which finished it calculates the folder's size and sorts its children, then does
//the same for the parent if that was its last unfinished sub folder, and so on up to the root.
fileprivate final class FSItemScan {

    //A folder which is being scanned. Lives until the folder and everything below it is complete.
    private final class Folder {
        let item: FSItem
        let path: String
        let parent: Folder?
        let inPackage: Bool    //one of the ancestors is a package
        //the folder which is shown as progress while this one is scanned: we display only folders 4 levels deep
        //(the root folder is level 1) and we don't go into packages, i.e. inside of a package it's the package
        let progressFolder: FSItem?
        var pending = 1        //folders below this one which are not complete yet, plus 1 until its own content is read

        init(item: FSItem, path: String, parent: Folder?) {
            self.item = item
            self.path = path
            self.parent = parent
            self.inPackage = parent.map { $0.inPackage || $0.item.isPackage() } ?? false

            var level = 1
            var ancestor = parent
            while let a = ancestor {
                level += 1
                ancestor = a.parent
            }
            if level <= 4 && !inPackage {
                self.progressFolder = item
            } else {
                self.progressFolder = parent?.progressFolder
            }
        }
    }

    //values of ATTR_CMN_OBJTYPE
    private static let vreg: UInt32 = 1
    private static let vdir: UInt32 = 2
    private static let vlnk: UInt32 = 5

    //ItemClass.traits: bits 0...3 object type, then flags, type code of the file in the upper half
    private static let traitBundleBit: UInt64 = 1 << 8      //Finder "has bundle" bit of a folder
    private static let traitAlias: UInt64 = 1 << 9          //Finder alias file
    private static let traitExecutable: UInt64 = 1 << 10    //executable file without extension
    private static let traitMountPoint: UInt64 = 1 << 11    //root of another volume

    //ATTR_DIR_MOUNTSTATUS: DIR_MNTSTATUS_MNTPOINT | DIR_MNTSTATUS_TRIGGER (a mount point, or one which isn't mounted yet)
    private static let mountStatusMask: UInt32 = 0x1 | 0x2

    private static let bufferSize = 128 * 1024

    private let rootFolder: Folder
    private let usePhysicalSize: Bool
    private let setKindStrings: Bool
    private let firmlinks = NSURL.firmlinkPaths
    private let queue = DispatchQueue(label: "DiskInventoryX.scan", qos: .userInitiated, attributes: .concurrent)
    private let group = DispatchGroup()

    private let lock = UnfairLock()
    //guarded by lock
    private var canceled = false
    private var files: UInt32 = 0
    private var folders: UInt32 = 0
    private var latestFolder: FSItem?
    private var freeBuffers: [UnsafeMutableRawPointer] = []

    init(root: FSItem, path: String, setKindStrings: Bool, usePhysicalSize: Bool) {
        self.rootFolder = Folder(item: root, path: path, parent: nil)
        self.setKindStrings = setKindStrings
        self.usePhysicalSize = usePhysicalSize
    }

    deinit {
        for buffer in freeBuffers {
            buffer.deallocate()
        }
    }

    func start() {
        schedule(rootFolder)
    }

    //true if the scan is complete, false if the timeout ran out (nil = wait as long as it takes)
    func waitUntilFinished(timeout: TimeInterval?) -> Bool {
        guard let timeout = timeout else {
            group.wait()
            return true
        }
        return group.wait(timeout: .now() + timeout) == .success
    }

    func cancel() {
        lock.lock()
        canceled = true
        lock.unlock()
    }

    var isCanceled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return canceled
    }

    //the counts are only valid once the scan is complete
    var fileCount: UInt32 { return files }
    var folderCount: UInt32 { return folders }

    //the folder which is shown as progress (see Folder.progressFolder)
    var currentFolder: FSItem? {
        lock.lock()
        defer { lock.unlock() }
        return latestFolder
    }

    private func schedule(_ folder: Folder) {
        group.enter()
        queue.async {
            autoreleasepool {
                self.scan(folder)
            }
            self.group.leave()
        }
    }

    private func takeBuffer() -> UnsafeMutableRawPointer {
        lock.lock()
        let buffer = freeBuffers.popLast()
        lock.unlock()
        return buffer ?? UnsafeMutableRawPointer.allocate(byteCount: FSItemScan.bufferSize, alignment: 8)
    }

    private func giveBack(_ buffer: UnsafeMutableRawPointer) {
        lock.lock()
        freeBuffers.append(buffer)
        lock.unlock()
    }

    //The task for one folder: reads its entries, creates the items, schedules the sub folders. When
    //everything below a folder is complete, its size is calculated and its children are sorted.
    private func scan(_ folder: Folder) {
        if isCanceled {
            return
        }

        if let progressFolder = folder.progressFolder {
            lock.lock()
            latestFolder = progressFolder
            lock.unlock()
        }

        var childs: [FSItem] = []
        var subFolders: [Folder] = []
        var scannedFiles: UInt32 = 0
        var scannedFolders: UInt32 = 0

        let fd = open(folder.path, O_RDONLY | O_DIRECTORY)
        if fd >= 0 {
            readEntries(of: folder, fd: fd, childs: &childs, subFolders: &subFolders,
                        fileCount: &scannedFiles, folderCount: &scannedFolders)
            close(fd)
        }
        //else: the folder can't be read (no permission, ...), it just stays empty

        folder.item.setScannedChildren(childs)

        lock.lock()
        files &+= scannedFiles
        folders &+= scannedFolders
        folder.pending += subFolders.count - 1
        let isComplete = folder.pending == 0
        lock.unlock()

        for subFolder in subFolders {
            schedule(subFolder)
        }

        if isComplete {
            finish(folder)
        }
    }

    //Calculates the size of the folder and sorts its children. Then the parent may be complete as well.
    private func finish(_ completeFolder: Folder) {
        var folder = completeFolder
        while true {
            folder.item.finishScannedFolder()

            guard let parent = folder.parent else {
                return
            }

            lock.lock()
            parent.pending -= 1
            let isComplete = parent.pending == 0
            lock.unlock()

            if !isComplete {
                return
            }
            folder = parent
        }
    }

    private func readEntries(of folder: Folder, fd: Int32, childs: inout [FSItem], subFolders: inout [Folder],
                             fileCount: inout UInt32, folderCount: inout UInt32) {
        var attributes = attrlist()
        attributes.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = UInt32(truncatingIfNeeded: ATTR_CMN_RETURNED_ATTRS) | UInt32(ATTR_CMN_NAME)
            | UInt32(ATTR_CMN_OBJTYPE) | UInt32(ATTR_CMN_FNDRINFO) | UInt32(ATTR_CMN_ACCESSMASK)
        attributes.dirattr = UInt32(ATTR_DIR_MOUNTSTATUS)
        attributes.fileattr = UInt32(ATTR_FILE_TOTALSIZE) | UInt32(ATTR_FILE_DATAALLOCSIZE) | UInt32(ATTR_FILE_RSRCALLOCSIZE)

        let errorAttribute = UInt32(truncatingIfNeeded: ATTR_CMN_ERROR)
        let buffer = takeBuffer()
        defer { giveBack(buffer) }

        let kinds = FSItemKinds.shared
        let parentPrefix = (folder.path == "/") ? "/" : folder.path + "/"

        while !isCanceled {
            let entryCount = getattrlistbulk(fd, &attributes, buffer, FSItemScan.bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if entryCount <= 0 {
                break
            }

            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<Int(entryCount) {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                defer { entry += length }

                //the layout of an entry: length, returned attributes, [error], name reference, object type,
                //finder info, access mask, [mount status of a folder | sizes of a file]; the name itself
                //follows the fixed part
                var field = entry + 4
                let returned = field.loadUnaligned(as: attribute_set_t.self)
                field += MemoryLayout<attribute_set_t>.size
                if returned.commonattr & errorAttribute != 0 {
                    field += 4
                }

                let nameReference = field
                let nameOffset = Int(field.loadUnaligned(as: Int32.self))
                let nameLength = Int(field.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) - 1   //without the terminating 0
                field += 8
                let objectType = field.loadUnaligned(as: UInt32.self)
                field += 4
                let finderInfo = field
                field += 32
                let mode = field.loadUnaligned(as: UInt32.self)
                field += 4

                let nameBytes = UnsafeBufferPointer(start: (nameReference + nameOffset).assumingMemoryBound(to: UInt8.self),
                                                    count: max(nameLength, 0))

                //NSDirectoryEnumerator, which the former scanner used, doesn't return the AppleDouble
                //files ("._*"); the scan results (and sizes) stay the same if we skip them too
                if nameBytes.count >= 2 && nameBytes[0] == UInt8(ascii: ".") && nameBytes[1] == UInt8(ascii: "_") {
                    continue
                }

                let name = String(decoding: nameBytes, as: UTF8.self)

                var flags: FSItemFlags = []
                var physicalSize: UInt64 = 0
                var logicalSize: UInt64 = 0
                var isMountPoint = false
                var subPath = ""

                if objectType == FSItemScan.vdir {
                    flags.insert(.folder)
                    folderCount &+= 1

                    subPath = parentPrefix + name
                    //The root of another volume: the folder is listed, but not entered. (Firmlinks are
                    //entered, they are how the system and data volumes make up the file system.)
                    if field + 4 <= entry + length && field.loadUnaligned(as: UInt32.self) & FSItemScan.mountStatusMask != 0 {
                        isMountPoint = !firmlinks.contains(subPath)
                    }
                } else {
                    fileCount &+= 1
                    //sizes follow the access mask (only if they are valid, e.g. not for an entry with an error)
                    if field + 24 <= entry + length {
                        logicalSize = field.loadUnaligned(as: UInt64.self)
                        physicalSize = field.loadUnaligned(fromByteOffset: 8, as: UInt64.self)
                            &+ field.loadUnaligned(fromByteOffset: 16, as: UInt64.self)
                    }
                }

                var kind: UInt32 = 0
                if setKindStrings || objectType == FSItemScan.vdir {
                    let itemClass = FSItemScan.itemClass(name: name, nameBytes: nameBytes, objectType: objectType, mode: mode,
                                                         finderInfo: finderInfo, isMountPoint: isMountPoint, path: subPath)
                    //The UTI of a file is determined by its class, but whether a folder with a name extension is
                    //a package depends on more than the extension (the Finder bit, Info.plist, ... or the way
                    //Launch Services feels), so these are asked for one by one (there are not so many).
                    let info = kinds.info(for: itemClass, askEveryTime: objectType == FSItemScan.vdir && !itemClass.ext.isEmpty, url: {
                        NSURL(fileURLWithPath: parentPrefix + name, isDirectory: objectType == FSItemScan.vdir)
                    })
                    if setKindStrings {
                        kind = info.kind
                    }
                    if info.isPackage {
                        flags.insert(.package)
                    }
                }

                let item = FSItem(scannedName: name, parent: folder.item, flags: flags, kind: kind,
                                  physicalSize: physicalSize, logicalSize: logicalSize, usePhysicalSize: usePhysicalSize)
                childs.append(item)

                if objectType == FSItemScan.vdir && !isMountPoint {
                    subFolders.append(Folder(item: item, path: subPath, parent: folder))
                }
            }
        }
    }

    //The properties of an item which determine its UTI and whether it is a package
    private static func itemClass(name: String, nameBytes: UnsafeBufferPointer<UInt8>, objectType: UInt32, mode: UInt32,
                                  finderInfo: UnsafeRawPointer, isMountPoint: Bool, path: String) -> FSItemKinds.ItemClass {
        let finderFlags = UInt16(bigEndian: finderInfo.loadUnaligned(fromByteOffset: 8, as: UInt16.self))
        var traits = UInt64(objectType)
        var ext = ""
        var wholeName = ""

        if isMountPoint {
            //(has to ask for the volumes one by one)
            traits |= traitMountPoint
            wholeName = path
        } else if objectType == vlnk {
            //it's a symbolic link, whatever its name is
        } else {
            //the name extension is what follows the last dot, if it isn't the first or last character
            var dot = nameBytes.count - 1
            while dot > 0 && nameBytes[dot] != UInt8(ascii: ".") {
                dot -= 1
            }
            if dot > 0 && dot < nameBytes.count - 1 {
                ext = String(decoding: UnsafeBufferPointer(rebasing: nameBytes[(dot + 1)...]), as: UTF8.self)
            }

            if objectType == vdir {
                if finderFlags & 0x2000 != 0 {   //kHasBundle
                    traits |= traitBundleBit
                }
            } else {
                if finderFlags & 0x8000 != 0 {   //kIsAlias
                    traits |= traitAlias
                }
                //the HFS file type
                traits |= UInt64(UInt32(bigEndian: finderInfo.loadUnaligned(as: UInt32.self))) << 32
                if ext.isEmpty && objectType == vreg {
                    wholeName = name
                    if mode & 0o111 != 0 {
                        traits |= traitExecutable
                    }
                }
            }
        }

        return FSItemKinds.ItemClass(ext: ext, name: wholeName, traits: traits)
    }
}
