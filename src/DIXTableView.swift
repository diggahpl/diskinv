//
//  DIXTableView.swift
//  Disk Inventory Xs
//
//  Swift port of DIXTableView.{h,m}. An NSTableView subclass adding
//  context-menu and drag-source support, forwarded to the delegate. Nib-wired,
//  so the class name is pinned with @objc(DIXTableView).
//
//  GPL v3
//

import Cocoa

@objc(DIXTableView)
class DIXTableView: NSTableView {

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let columnIndex = column(at: point)
        let rowIndex = row(at: point)

        if rowIndex >= 0 && numberOfSelectedRows <= 1 {
            selectRowIndexes(IndexSet(integer: rowIndex), byExtendingSelection: false)
        }

        guard columnIndex >= 0, rowIndex >= 0 else { return nil }

        let contextMenu: NSMenu?
        // Preserves the original's selector check verbatim: it tests for
        // tableView:menuForTableColumn:item: yet invokes the ...:row: variant.
        // No table delegate implements either, so this consistently falls back
        // to the view's own menu.
        if let delegate = self.delegate,
           delegate.responds(to: NSSelectorFromString("tableView:menuForTableColumn:item:")) {
            let column = tableColumns[columnIndex]
            contextMenu = (delegate as AnyObject).tableView?(self, menuForTableColumn: column, row: rowIndex)
        } else {
            contextMenu = self.menu
        }

        // make ourselves first responder when a context menu is about to appear
        if contextMenu != nil, acceptsFirstResponder, window?.firstResponder != self {
            window?.makeFirstResponder(self)
        }

        return contextMenu
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

@objc protocol DIXTableViewDelegate: NSObjectProtocol {
    // delegate is asked which menu to show (else the view's own menu is used)
    @objc optional func tableView(_ tableView: NSTableView, menuForTableColumn column: NSTableColumn, row: Int) -> NSMenu?
    @objc(dixDraggingSourceMaskForLocal:) optional func dixDraggingSourceMask(forLocal isLocal: Bool) -> NSDragOperation
}
