//
//  FileKindsPopupController.swift
//  Disk Inventory Xs
//
//  Swift port of FileKindsPopupController.{h,m}. Controller for the popup
//  button that chooses the file kind shown in the selection table. Subclass of
//  GenericArrayController; prepends a faked "(all kinds)" entry (an NSDictionary
//  rather than a FileKindStatistic) and draws a cushion swatch into each popup
//  item. Nib-wired, so the class name, outlets, and the NSDictionary(AllKinds)
//  category are pinned with @objc.
//
//  GPL v3
//

import Cocoa

// the first popup entry is a faked "all kinds" entry, represented by an
// NSDictionary; the real FileKindStatistic.isAllFileKindsItem returns NO.
extension NSDictionary {
    @objc(isAllFileKindsItem)
    func isAllFileKindsItem() -> Bool {
        !(self is FileKindStatistic)
    }
}

@objc(FileKindsPopupController)
class FileKindsPopupController: GenericArrayController {

    // plain optionals (not IUO): NSArrayController.initWithCoder: can drive
    // rearrange/selection before outlets connect, so every access nil-chains
    @IBOutlet private var _kindsPopUpButton: NSPopUpButton?
    @IBOutlet private var _windowController: AnyObject?

    override func awakeFromNib() {
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)),
                                               name: NSWindow.willCloseNotification,
                                               object: (_windowController as? NSWindowController)?.window)

        NSUserDefaultsController.shared.addObserver(self, forKeyPath: "values." + ShareKindColors,
                                                    options: [], context: &Self.shareKindColorsContext)

        let sortDesc = NSSortDescriptor(key: "kindName", ascending: true,
                                        selector: NSSelectorFromString("compareAsFilesystemName:"))
        sortDescriptors = [sortDesc]
    }

    private static var shareKindColorsContext = 0

    override func arrange(_ objects: [Any]) -> [Any] {
        var arranged = (objects as NSArray).sortedArray(using: sortDescriptors)

        let totalFileCount = arranged.reduce(into: UInt(0)) { sum, obj in
            if let stat = obj as? FileKindStatistic { sum += stat.fileCount }
        }

        let fakedItemTitle = NSLocalizedString("(all kinds)", comment: "") + "  (\(totalFileCount))"
        arranged.insert(["kindName": fakedItemTitle] as NSDictionary, at: 0)

        return arranged
    }

    override func rearrangeObjects() {
        let oldSelectionIndex = selectionIndex

        super.rearrangeObjects()

        let kindStatistics = arrangedObjects
        if NSIsControllerMarker(kindStatistics) { return }
        let count = (kindStatistics as? [Any])?.count ?? 0

        // we always want a valid selection
        if oldSelectionIndex == 0 {
            _ = setSelectionIndex(0)
        } else if selectionIndex == NSNotFound {
            _ = setSelectionIndex(count == 0 ? 0 : 1)
        }

        setFileKindsImages()
    }

    override func onSelectionChanged() {
        super.onSelectionChanged()
        // if the selection didn't change via the popup our images are gone, so reset them
        setFileKindsImages()
    }

    @objc func document() -> FileSystemDoc? {
        (_windowController as? NSWindowController)?.document as? FileSystemDoc
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        if context == &Self.shareKindColorsContext {
            setFileKindsImages()
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        NSUserDefaultsController.shared.removeObserver(self, forKeyPath: "values." + ShareKindColors)
        NotificationCenter.default.removeObserver(self)
    }

    // NSPopUpButton can't set a per-item image via bindings, so we draw the
    // cushion swatches manually.
    private func setFileKindsImages() {
        guard let popup = _kindsPopUpButton else { return }
        let imageHeight = Int((popup.cell?.font?.pointSize ?? 0))
        let imageWidth = Int(Float(imageHeight) * 1.5)

        let cushionRenderer = TMVCushionRenderer(rect: NSRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        cushionRenderer.addRidge(byHeightFactor: 0.6)

        guard let kindColors = document()?.fileTypeColors() else { return }
        guard let kindStatistics = arrangedObjects as? [Any] else { return }

        for menuItem in popup.itemArray {
            // each item's represented object is an NSNumber index into arrangedObjects
            guard let index = (menuItem.representedObject as? NSNumber)?.intValue,
                  index < kindStatistics.count,
                  let stat = kindStatistics[index] as? FileKindStatistic,
                  !stat.isAllFileKindsItem() else { continue }

            // 24-bit RGB bitmap, no alpha
            guard let bitmap = NSBitmapImageRep(rgbBitmapWithWidth: imageWidth, height: imageHeight) else { continue }
            cushionRenderer.setColor(kindColors.color(forKind: stat.kindName))
            cushionRenderer.renderCushion(inBitmap: bitmap)

            menuItem.image = bitmap.suitableImage(for: popup)
            menuItem.title = stat.kindName + "  (\(stat.fileCount))"
        }
    }
}
