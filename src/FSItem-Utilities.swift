//
//  FSItem-Utilities.swift
//  Disk Inventory Xs
//
//  Swift port of the FSItem(Utilities) category: tree-traversal helpers
//  (deep file count, path lookups, ancestor/descendant queries).
//
//  GPL v3
//

import Foundation

@objc extension FSItem {

    // count of files in all subdirectories
    @objc(deepFileCountIncludingPackages:)
    func deepFileCount(includingPackages lookInPackages: Bool) -> UInt {
        if isSpecialItem() { return 0 }

        var deepChildCount: UInt = 0
        var i: UInt = 0
        while i < childCount() {
            if let child = self.child(at: i) {
                if child.isFolder() {
                    if lookInPackages || !isPackage() {
                        deepChildCount += child.deepFileCount(includingPackages: lookInPackages)
                    }
                } else {
                    deepChildCount += 1
                }
            }
            i += 1
        }
        return deepChildCount
    }

    // path e.g. /Applications/Utilities/Terminal.app
    @objc(findItemByAbsolutePath:allowAncestors:)
    func findItem(byAbsolutePath path: String, allowAncestors: Bool) -> FSItem? {
        let myPath = self.path()

        if path == myPath {
            return self
        }
        if !path.hasPrefix(myPath) {
            return nil // path defines no child
        }

        // relative child path (relative to self)
        var childPathStartIndex = (myPath as NSString).length
        if myPath != NSOpenStepRootDirectory() { // should just be "/"
            childPathStartIndex += 1
        }
        let childPath = (path as NSString).substring(from: childPathStartIndex)

        return findItem(byRelativePath: childPath, allowAncestors: allowAncestors)
    }

    // path e.g. Utilities/Terminal.app
    @objc(findItemByRelativePath:allowAncestors:)
    func findItem(byRelativePath path: String, allowAncestors: Bool) -> FSItem? {
        if path.isEmpty {
            return self
        }
        return findChild(byRelativePathComponents: (path as NSString).pathComponents, allowAncestors: allowAncestors)
    }

    @objc(findChildByRelativePathComponents:allowAncestors:)
    func findChild(byRelativePathComponents pathComponents: [String], allowAncestors: Bool) -> FSItem? {
        assert(!pathComponents.isEmpty, "path must contain at least 1 component")

        var parent: FSItem = self
        var child: FSItem? = nil

        for name in pathComponents {
            let childEnum = parent.childEnumerator()
            child = nil
            while let candidate = childEnum?.nextObject() as? FSItem {
                if candidate.name() == name {
                    child = candidate
                    break
                }
            }

            guard let found = child else {
                return allowAncestors ? parent : nil
            }
            parent = found
        }

        return child
    }

    // path from root to self as FSItems: <root><child1><child2><self>
    @objc func fsItemPath() -> [FSItem] {
        fsItemPath(fromAncestor: nil)
    }

    // path from a specific ancestor to self: <ancestor><child1><child2><self>
    @objc(fsItemPathFromAncestor:)
    func fsItemPath(fromAncestor ancestor: FSItem?) -> [FSItem] {
        var pathToSelf: [FSItem] = []

        var item: FSItem? = self
        repeat {
            pathToSelf.insert(item!, at: 0)
            item = item!.parent()
        } while item != nil && item !== ancestor

        assert(item === ancestor, "the given item is no ancestor of self")

        if let item = item {
            pathToSelf.insert(item, at: 0)
        }

        return pathToSelf
    }

    // YES if receiver is a descendant of ancestor
    @objc(isDescendantOf:)
    func isDescendant(of ancestor: FSItem) -> Bool {
        var aParent: FSItem? = self
        repeat {
            aParent = aParent?.parent()
        } while aParent != nil && aParent !== ancestor

        return aParent != nil
    }
}
