//
//  FileKindStatistic.swift
//  Disk Inventory Xs
//
//  Swift port of FileKindStatistic (formerly embedded in FileSystemDoc.{h,m}).
//  Tracks the count and total size of all files of one kind (e.g. all MP3s).
//
//  GPL v3
//

import Foundation

@objc(FileKindStatistic)
final class FileKindStatistic: NSObject {

    private let _kindName: String
    private var _size: UInt64 = 0
    private let _items: NSMutableSet

    @objc(initWithItem:)
    init(item: FSItem) {
        _kindName = item.kindName() ?? ""
        _size = item.sizeValue()
        _items = NSMutableSet(object: item)
        super.init()
    }

    @objc(addItem:)
    func add(_ item: FSItem) {
        assert(!_items.contains(item))
        _items.add(item)
        _size += item.sizeValue()
    }

    @objc(removeItem:)
    func remove(_ item: FSItem) {
        assert(_items.contains(item))
        _size -= item.sizeValue()
        _items.remove(item)
    }

    @objc var kindName: String { _kindName }

    @objc override var description: String {
        "\(_kindName) {\(fileCount) files; \(String(format: "%.1f", Float(_size) / 1024)) kB}"
    }

    // # of files of this kind
    @objc var fileCount: UInt { UInt(_items.count) }

    // sum of sizes of files of this kind
    @objc var size: UInt64 { _size }

    @objc func recalculateSize() {
        _size = 0
        let itemEnum = _items.objectEnumerator()
        while let item = itemEnum.nextObject() as? FSItem {
            _size += item.sizeValue()
        }
    }

    @objc var items: NSSet { _items }

    @objc func itemEnumerator() -> NSEnumerator {
        _items.objectEnumerator()
    }

    // compare the size descendingly
    @objc(compareSizeDescendingly:)
    func compareSizeDescendingly(_ other: FileKindStatistic) -> ComparisonResult {
        let mySize = _size
        let otherSize = other.size

        // we want the sorting to be descending
        if mySize < otherSize { return .orderedDescending }
        if mySize > otherSize { return .orderedAscending }

        // same size: order by name
        return _kindName.compare(other.kindName, options: .numeric)
    }

    // Folded in from the former FileKindStatistic(AllKinds) category. A real
    // FileKindStatistic is never the "all kinds" item (that sentinel is a
    // faked NSDictionary with its own isAllFileKindsItem returning YES).
    @objc func isAllFileKindsItem() -> Bool {
        false
    }
}
