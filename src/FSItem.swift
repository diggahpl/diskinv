//
//  FSItem.swift
//  Disk Inventory X
//
//  Swift port of the central model class FSItem: the recursive folder
//  scanner and tree node. Ported faithfully from the original
//  Objective-C FSItem.h/.m. ARC throughout.
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

//MARK: - delegate informal protocol -> @objc protocol

@objc protocol FSItemDelegate: NSObjectProtocol {
    @objc optional func fsItemEnteringFolder(_ item: FSItem) -> Bool   //delegate may return NO to stop loading in "loadChildren"
    @objc optional func fsItemExittingFolder(_ item: FSItem) -> Bool
    @objc optional func fsItemShouldIgnoreCreatorCode(_ item: FSItem) -> Bool   //default is NO (if not implemented)
    @objc optional func fsItemShouldLookIntoPackages(_ item: FSItem) -> Bool    //default is NO (if not implemented)
    @objc optional func fsItemShouldUsePhysicalFileSize(_ item: FSItem) -> Bool
}

//global cache for kind names
private var g_kindNameDictionary = NSMutableDictionary()

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

//The ObjC runtime name must not be "FSItem": FSKit.framework (loaded into every app
//on current systems) defines a class of that name, and two classes with the same
//name make the runtime warn about "spurious casting failures and mysterious crashes".
@objc(DIXFSItem) final class FSItem: NSObject {

    private var _fileURL: NSURL?
    //only valid for non-root items (non-owning back-reference); the original
    //used __unsafe_unretained because parents own children via _childs.
    private unowned(unsafe) var _parent: FSItem?
    private var _icons: NSMutableDictionary?   //holds icons in various sizes (see iconWithSize:)
    private var _type: FSItemType = FileFolderItem
    private var _size: NSNumber?
    private var _sizeValue: UInt64 = 0
    private var _kindName: String?
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
        if url.isDirectory() {
            _childs = []
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

    // private designated initializer used by the scanner
    @objc(initWithURL:parent:setKindString:)
    init(url: NSURL, parent: FSItem?, setKindString: Bool) {
        super.init()
        _type = FileFolderItem
        _parent = parent   //no retain

        if let parent = parent {
            parent._childs?.append(self)
        }

        _fileURL = url

        let isFolder = url.isDirectory()

        if !isFolder {
            //The scan always ends with the physical sizes (see loadChildrenAndSetKindStrings), so
            //reading the logical size here would be wasted work.
            setSizeValue(url.physicalSize().uint64Value)
        } else {
            _childs = []
        }

        if setKindString {
            setKindStringIncludingChildren(false)
        }

        if isFolder {
            g_folderCount += 1
        } else {
            g_fileCount += 1
        }
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
        if !isSpecialItem() {
            return _fileURL
        } else {
            return root().fileURL()
        }
    }

    @objc(setFileURL:)
    func setFileURL(_ url: NSURL?) {
        assert(!isSpecialItem(), "free and other space items don't have a NTFileDesc object")
        _fileURL = url
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
            return _fileURL?.cachedIsDirectory() ?? false
        } else {
            return false
        }
    }

    @objc(isPackage)
    func isPackage() -> Bool {
        if !isSpecialItem() {
            return _fileURL?.cachedIsPackage() ?? false
        } else {
            return false
        }
    }

    @objc(isAlias)
    func isAlias() -> Bool {
        if !isSpecialItem() {
            return _fileURL?.cachedIsAliasOrSymbolicLink() ?? false
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
            return (_childs as NSArray?)?.objectEnumerator()
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
            } else {
                //File
                if usePhysicalSize {
                    size = _fileURL?.cachedPhysicalSize().uint64Value ?? 0
                } else {
                    size = _fileURL?.cachedLogicalSize().uint64Value ?? 0
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
            if _kindName == nil {
                setKindString()
            }
            return _kindName ?? ""
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
        let uti = _fileURL?.cachedUTI()

        if let uti = uti {
            _kindName = g_kindNameDictionary.object(forKey: uti) as? String

            if _kindName == nil {
                _kindName = UTType(uti)?.localizedDescription

                //remember kind name for similar files
                if let kn = _kindName {
                    g_kindNameDictionary.setObject(kn, forKey: uti as NSString)
                }
            }
        } else {
            _kindName = nil
        }

        if _kindName == nil {
            _kindName = _fileURL?.getCachedStringValue(URLResourceKey.localizedTypeDescriptionKey.rawValue)
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
            return fileURL()?.cachedName() ?? ""
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
    private func sortChildren() {
        _childs?.sort(by: { $0.compareSizeDescendingly($1) == .orderedAscending })
    }

    //Called by the scanner when it leaves this folder: all children are complete by then, so
    //the folder's size is the sum of their sizes.
    private func finishFolder() {
        var size: UInt64 = 0
        if let childs = _childs {
            for child in childs {
                size += child.sizeValue()
            }
        }
        sortChildren()
        setSizeValue(size)
    }

    //Note: the scan always yields the physical sizes, whatever usePhysicalSize says (the final
    //pass of the original Objective-C implementation hard-coded that too).
    func loadChildrenAndSetKindStrings(_ setKindStringsParam: Bool, usePhysicalSize: Bool) throws {
        if !isFolder() {
            return
        }

        var setKindStrings = setKindStringsParam
        let delegate = delegateAsFSItemDelegate

        //should we cancel the loading?
        if let d = delegate, d.fsItemEnteringFolder?(self) == false {
            throw FSItemError.loadingCanceled
        }

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

        let urlProperties: [URLResourceKey] = [
            //.localizedNameKey,
            .nameKey,
            .isVolumeKey,
            .isPackageKey,
            .isDirectoryKey,
            //.isSymbolicLinkKey,
            .typeIdentifierKey,
            //.localizedTypeDescriptionKey,
            .totalFileAllocatedSizeKey
        ]

        // stack of directories (path to directory currently being scanned)
        var itemStack: [FSItem] = [self]

        let selfURL = fileURL()
        let dirEnum = FileManager.default.enumerator(at: selfURL! as URL,
                                                     includingPropertiesForKeys: urlProperties,
                                                     options: [],
                                                     errorHandler: { (url, error) -> Bool in
                                                         // stop if there is a problem with the directory itself
                                                         if let selfURL = selfURL, (url as NSURL).isEqual(to: selfURL as URL) {
                                                             return false
                                                         } else {
                                                             return true
                                                         }
                                                     })

        var lastEnumLevel = 1
        var lastDirItem: FSItem? = nil

        if let dirEnum = dirEnum {
            for case let current as URL in dirEnum {
                //autoreleasepool is `rethrows`, so a throwing body propagates out
                try autoreleasepool {
                    let currentUrl = current as NSURL

                    // cache all needed properties (NSURL purges all values upon next pass through the run loop)
                    currentUrl.cacheResources(in: urlProperties)

                    if dirEnum.level > lastEnumLevel {
                        // we have entered a sub directory
                        itemStack.append(lastDirItem!)

                        //should we cancel the loading?
                        if let d = delegate, d.fsItemEnteringFolder?(lastDirItem!) == false {
                            throw FSItemError.loadingCanceled
                        }
                    } else if dirEnum.level < lastEnumLevel {
                        // level can be one or more steps higher
                        let levelsWalkedUp = lastEnumLevel - dirEnum.level

                        // walk n levels up
                        for _ in 0..<levelsWalkedUp {
                            //should we cancel the loading?
                            if let d = delegate, d.fsItemExittingFolder?(itemStack.last!) == false {
                                throw FSItemError.loadingCanceled
                            }
                            itemStack.removeLast().finishFolder()
                        }
                    }

                    let currentItem = FSItem(url: currentUrl,
                                             parent: itemStack.last,
                                             setKindString: setKindStrings)

                    //files can't be firmlinks or volumes, so don't even ask them (the firmlink test hashes the URL)
                    let isDir = currentUrl.isDirectory()
                    if isDir {
                        if currentUrl.isFirmlink() {
                            // firmlinks are not followed by NSDirectoryEnumerator, but Apple may
                            // change that, so we tell the enumerator to not enter the directory
                            dirEnum.skipDescendants()
                            try currentItem.loadChildrenAndSetKindStrings(setKindStrings, usePhysicalSize: usePhysicalSize)
                        } else if currentUrl.isVolume() {
                            // on 10.15 Beta 7 the mount point /System/Volume/data is followed,
                            // although this should not be the case according to the docs
                            dirEnum.skipDescendants()
                        }
                    }

                    lastDirItem = isDir ? currentItem : nil
                    lastEnumLevel = dirEnum.level
                }
            }
        }

        // signal exiting of remaining folders
        for stackItem in itemStack.reversed() {
            //should we cancel the loading?
            if let d = delegate, d.fsItemExittingFolder?(stackItem) == false {
                throw FSItemError.loadingCanceled
            }
            stackItem.finishFolder()
        }
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
