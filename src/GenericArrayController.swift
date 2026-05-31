//
//  GenericArrayController.swift
//  Disk Inventory Xs
//
//  Swift port of GenericArrayController.{h,m}. An NSArrayController subclass
//  that presents an arbitrary collection (dictionary/set/array) reachable
//  through a "contentArray" binding key path, caching the arranged objects and
//  managing its own selection-index set. Base class of FileKindsPopupController
//  and SelectionListController (both Swift), so it carries @objc for the
//  members the nib bindings / subclasses use.
//
//  GPL v3
//

import Cocoa

@objc(GenericArrayController)
class GenericArrayController: NSArrayController {

    private var _cachedObjects: [Any]?
    private var _mySelectionIndexes = NSMutableIndexSet()
    private var _model: NSObject?
    private var _collectionKeyPath: String?
    private var _suspendUpdates = false
    private var _arrayIsValid = true

    private static var contentArrayContext = 0

    // The deprecated-but-still-canonical NSArrayController content/selection
    // markers, funneled through one accessor each to keep the deprecation noise
    // to a handful of lines.
    private var notApplicableMarker: Any { NSNotApplicableMarker as Any }
    private var noSelectionMarker: Any { NSNoSelectionMarker as Any }
    private var multipleValuesMarker: Any { NSMultipleValuesMarker as Any }

    // MARK: - binding support

    override func bind(_ binding: NSBindingName, to observable: Any,
                       withKeyPath keyPath: String, options: [NSBindingOption: Any]? = nil) {
        if binding == .contentArray {
            _model = observable as? NSObject
            _collectionKeyPath = keyPath
            _model?.addObserver(self, forKeyPath: keyPath,
                                options: .new, context: &Self.contentArrayContext)
        } else {
            super.bind(binding, to: observable, withKeyPath: keyPath, options: options)
        }
    }

    override func unbind(_ binding: NSBindingName) {
        if binding == .contentArray {
            if let keyPath = _collectionKeyPath {
                _model?.removeObserver(self, forKeyPath: keyPath)
            }
            _model = nil
            _collectionKeyPath = nil
            _mySelectionIndexes = NSMutableIndexSet()
            rearrangeObjects()
        } else {
            super.unbind(binding)
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context == &Self.contentArrayContext {
            rearrangeObjects()
        }
    }

    // MARK: - data management

    @objc func suspendingArrangedObjectsUpdates() -> Bool { _suspendUpdates }

    @objc func suspendArrangedObjectsUpdates() {
        _suspendUpdates = true
        _arrayIsValid = true  // arranged objects are considered valid
    }

    @objc func resumeArrangedObjectsUpdates() {
        if _suspendUpdates {
            _suspendUpdates = false
            if !_arrayIsValid {
                rearrangeObjects()
            }
        }
    }

    @objc func collectionModel() -> Any? {
        guard let model = _model, let keyPath = _collectionKeyPath else { return nil }
        return model.value(forKeyPath: keyPath)
    }

    override var arrangedObjects: Any {
        guard _model != nil else { return notApplicableMarker }

        if _cachedObjects == nil {
            guard let collection = collectionModel() else { return notApplicableMarker }
            if NSIsControllerMarker(collection) { return collection }

            // our collection is always a dictionary (kindStatistics) or a set
            // (a kind's items); array kept for generality
            let newObjects: [Any]
            if let dict = collection as? NSDictionary {
                newObjects = dict.allValues
            } else if let set = collection as? NSSet {
                newObjects = set.allObjects
            } else if let array = collection as? [Any] {
                newObjects = array
            } else {
                newObjects = []
            }

            _cachedObjects = arrange(newObjects)
        }

        return _cachedObjects ?? notApplicableMarker
    }

    override func rearrangeObjects() {
        if _suspendUpdates {
            _arrayIsValid = false
            return
        }

        willChangeValue(forKey: "arrangedObjects")

        var selectedObjects: [Any]?
        if _cachedObjects != nil {
            selectedObjects = self.selectedObjects
        }

        _mySelectionIndexes.removeAllIndexes()
        _cachedObjects = nil
        _arrayIsValid = true

        didChangeValue(forKey: "arrangedObjects")

        if let selectedObjects = selectedObjects {
            if !NSIsControllerMarker(selectedObjects) {
                _ = setSelectedObjects(selectedObjects)
            } else {
                _ = setSelectionIndexes(IndexSet())
            }
        }
    }

    override var sortDescriptors: [NSSortDescriptor] {
        get { super.sortDescriptors }
        set {
            super.sortDescriptors = newValue
            rearrangeObjects()
        }
    }

    // MARK: - selection support

    override var selection: Any {
        switch _mySelectionIndexes.count {
        case 0:
            return noSelectionMarker
        case 1:
            let allObjects = arrangedObjects
            if NSIsControllerMarker(allObjects) { return allObjects }
            return (allObjects as! [Any])[_mySelectionIndexes.firstIndex]
        default:
            return multipleValuesMarker
        }
    }

    override func setSelectionIndex(_ index: Int) -> Bool {
        let allObjects = arrangedObjects
        if NSIsControllerMarker(allObjects) { return false }
        guard let objects = allObjects as? [Any], index < objects.count else { return false }

        if _mySelectionIndexes.count == 1 && _mySelectionIndexes.firstIndex == index {
            return true
        }

        onSelectionChanging()
        _mySelectionIndexes = NSMutableIndexSet(index: index)
        onSelectionChanged()
        return true
    }

    override var selectionIndex: Int {
        _mySelectionIndexes.count == 0 ? NSNotFound : _mySelectionIndexes.firstIndex
    }

    override var selectionIndexes: IndexSet {
        _mySelectionIndexes as IndexSet
    }

    override func setSelectionIndexes(_ indexes: IndexSet) -> Bool {
        if _mySelectionIndexes.isEqual(to: indexes) { return true }

        onSelectionChanging()
        _mySelectionIndexes = NSMutableIndexSet(indexSet: indexes)
        onSelectionChanged()
        return true
    }

    override func addSelectionIndexes(_ indexes: IndexSet) -> Bool {
        if _mySelectionIndexes.contains(indexes) { return true }

        onSelectionChanging()
        _mySelectionIndexes.add(indexes)
        onSelectionChanged()
        return true
    }

    override func removeSelectionIndexes(_ indexes: IndexSet) -> Bool {
        if indexes.isEmpty { return true }
        if !_mySelectionIndexes.contains(indexes) { return false }

        onSelectionChanging()
        _mySelectionIndexes.remove(indexes)
        onSelectionChanged()
        return true
    }

    override var selectedObjects: [Any] {
        var result: [Any] = []
        let allObjects = arrangedObjects
        if !NSIsControllerMarker(allObjects), _mySelectionIndexes.count > 0, let objects = allObjects as? [Any] {
            (_mySelectionIndexes as IndexSet).forEach { result.append(objects[$0]) }
        }
        return result
    }

    override func setSelectedObjects(_ objects: [Any]) -> Bool {
        if NSIsControllerMarker(arrangedObjects) { return false }
        return setSelectionIndexes(indexes(forObjects: objects))
    }

    override func addSelectedObjects(_ objects: [Any]) -> Bool {
        if NSIsControllerMarker(arrangedObjects) { return false }
        return addSelectionIndexes(indexes(forObjects: objects))
    }

    override func removeSelectedObjects(_ objects: [Any]) -> Bool {
        if NSIsControllerMarker(arrangedObjects) { return false }
        return removeSelectionIndexes(indexes(forObjects: objects))
    }

    @objc func onSelectionChanging() {
        willChangeValue(forKey: "selection")
        willChangeValue(forKey: "selectionIndex")
        willChangeValue(forKey: "selectionIndexes")
        willChangeValue(forKey: "selectedObjects")
    }

    @objc func onSelectionChanged() {
        didChangeValue(forKey: "selection")
        didChangeValue(forKey: "selectionIndex")
        didChangeValue(forKey: "selectionIndexes")
        didChangeValue(forKey: "selectedObjects")
    }

    @objc(indexesForObjects:)
    func indexes(forObjects objects: [Any]) -> IndexSet {
        let allObjects = arrangedObjects
        guard !NSIsControllerMarker(allObjects), let all = allObjects as? [NSObject] else { return IndexSet() }

        var indexes = IndexSet()
        for object in objects {
            // matches the ObjC indexOfObjectIdenticalTo: (identity, not equality)
            if let obj = object as? NSObject,
               let idx = all.firstIndex(where: { $0 === obj }) {
                indexes.insert(idx)
            }
        }
        return indexes
    }
}
