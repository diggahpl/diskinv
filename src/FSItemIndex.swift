//
//  FSItemIndex.swift
//  Disk Inventory Xs
//
//  Swift port of FSItemIndex (formerly FSItemIndex.{h,m}).
//
//  Lets the UI search FSItems by their display names, kinds and paths.
//  (The original was implemented with SearchKit, but that was so slow it
//  was replaced by this simple NSMutableDictionary-based index. Only that
//  live implementation is ported here; the commented-out SearchKit code was
//  dropped.)
//
//  GPL v3
//

import Foundation

@objc(FSItemIndex)
final class FSItemIndex: NSObject {

    // term (lowercased) -> items whose display name matches that term
    private var displayNameIndex: [String: [FSItem]] = [:]
    // term (lowercased) -> items whose display path matches that term
    private var displayFolderIndex: [String: [FSItem]] = [:]
    private let kindStatistics: NSDictionary

    @objc(initWithKindStatistics:)
    init(kindStatistics: NSDictionary) {
        self.kindStatistics = kindStatistics
        super.init()
    }

    // MARK: - term indexing (formerly the NSMutableDictionary(Indexing) category)

    private static func addObject(_ object: FSItem, forTerm term: String, in index: inout [String: [FSItem]]) {
        index[term, default: []].append(object)
    }

    // MARK: - public API

    @objc(addItem:)
    func add(_ item: FSItem) {
        let name = (item.displayName() ?? "").lowercased()
        let path = (item.displayPath() ?? "").lowercased()

        FSItemIndex.addObject(item, forTerm: name, in: &displayNameIndex)
        FSItemIndex.addObject(item, forTerm: path, in: &displayFolderIndex)
    }

    @objc(addItemsFromArray:)
    func addItems(from items: [FSItem]) {
        var i = items.count
        while i > 0 {
            i -= 1
            autoreleasepool {
                add(items[i])
            }
        }
    }

    // not @objc: FSItemIndexType is a Swift OptionSet (not @objc-representable),
    // and the only caller is the Swift SelectionListController.
    func searchItems(_ searchString: String?, inIndex indexesToSearch: FSItemIndexType) -> [FSItem] {
        let searchString = (searchString ?? "").lowercased()

        var items = Set<FSItem>()

        // search the display-name / display-path indexes
        let indexes: [(index: [String: [FSItem]], indexType: FSItemIndexType)] = [
            (displayNameIndex, .name),
            (displayFolderIndex, .path)
        ]

        for entry in indexes where indexesToSearch.contains(entry.indexType) {
            for (term, termItems) in entry.index {
                // An empty search string matches everything, mirroring ObjC
                // -rangeOfString: which returns location 0 (not NSNotFound).
                if searchString.isEmpty || term.range(of: searchString) != nil {
                    items.formUnion(termItems)
                }
            }
        }

        // search kinds
        if indexesToSearch.contains(.kind) {
            let kindEnum = kindStatistics.objectEnumerator()
            while let stat = kindEnum.nextObject() as? FileKindStatistic {
                if searchString.isEmpty || stat.kindName.range(of: searchString, options: .caseInsensitive) != nil {
                    if let statItems = stat.items as? Set<FSItem> {
                        items.formUnion(statItems)
                    } else {
                        for case let fsItem as FSItem in stat.items {
                            items.insert(fsItem)
                        }
                    }
                }
            }
        }

        return Array(items)
    }
}
