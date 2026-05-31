//
//  DIXOutlineView.swift
//  Disk Inventory Xs
//
//  Swift port of DIXOutlineView.{h,m}. An NSOutlineView subclass adding
//  context-menu and drag-source support, forwarded to the delegate when it
//  implements the matching (informal) protocol method. Nib-wired, so the
//  class name is pinned with @objc(DIXOutlineView).
//
//  GPL v3
//

import Cocoa

@objc(DIXOutlineView)
class DIXOutlineView: NSOutlineView {

    @objc func selectedItem() -> Any? {
        let row = selectedRow
        return row >= 0 ? item(atRow: row) : nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let columnIndex = column(at: point)
        let rowIndex = row(at: point)

        if rowIndex >= 0 && numberOfSelectedRows <= 1 {
            selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        }

        guard columnIndex >= 0, rowIndex >= 0,
              let delegate = self.delegate,
              delegate.responds(to: #selector(DIXOutlineViewDelegate.outlineView(_:menuForTableColumn:item:)))
        else {
            return nil
        }

        let column = tableColumns[columnIndex]
        let contextMenu = (delegate as AnyObject).outlineView?(self, menuForTableColumn: column, item: item(atRow: rowIndex))

        // make ourselves first responder when a context menu is about to appear
        if contextMenu != nil, acceptsFirstResponder, window?.firstResponder != self {
            window?.makeFirstResponder(self)
        }

        return contextMenu ?? nil
    }

    // forward to the delegate if it supplies a drag-source mask, else fall back.
    // The original overrode the now-unavailable -draggingSourceOperationMaskForLocal:;
    // .withinApplication maps to that method's isLocal == YES.
    override func draggingSession(_ session: NSDraggingSession,
                                  sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        let isLocal = (context == .withinApplication)
        if let mask = (delegate as AnyObject?)?.dixDraggingSourceMask?(forLocal: isLocal) {
            return mask
        }
        return super.draggingSession(session, sourceOperationMaskFor: context)
    }
}

@objc protocol DIXOutlineViewDelegate: NSObjectProtocol {
    // delegate is asked which menu to show (else the view's own menu is used)
    @objc optional func outlineView(_ outlineView: NSOutlineView, menuForTableColumn column: NSTableColumn, item: Any) -> NSMenu?
    @objc(dixDraggingSourceMaskForLocal:) optional func dixDraggingSourceMask(forLocal isLocal: Bool) -> NSDragOperation
}
