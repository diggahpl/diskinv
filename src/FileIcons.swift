//
//  FileIcons.swift
//  Disk Inventory Xs
//
//  The icons of the files outline: SF Symbols tinted with the color the treemap
//  gives the item's kind, so a row and its cell on the map share a color. Folders
//  are glassy ice blue, applications keep their own icon (it is what the user
//  knows them by), everything else is a symbol picked by the file's type.
//
//  GPL v3
//

import Cocoa
import UniformTypeIdentifiers

enum FileIcons {

    /// Folders carry no kind color, so they get the quiet blue of glass.
    static let folderColor = NSColor(srgbRed: 0.55, green: 0.80, blue: 1.0, alpha: 1)
    /// Free and other space are voids, not files.
    static let voidColor = NSColor(white: 1, alpha: 0.35)

    private static var symbols: [String: NSImage] = [:]
    private static var symbolNames: [String: String] = [:]

    /// The icon for `item`; `kindColor` is the treemap color of its kind (nil for
    /// folders and special items). `size` is the edge of the square in points.
    static func icon(for item: FSItem, kindColor: NSColor?, size: CGFloat) -> NSImage? {
        if item.isSpecialItem() {
            return symbol("circle.dotted", color: voidColor, size: size)
        }
        if item.isPackage(), isApplication(item) {
            return item.icon(withSize: UInt32(size.rounded()))
        }
        if item.isPackage() {
            return symbol("shippingbox.fill", color: tint(kindColor), size: size)
        }
        if item.isFolder() {
            return symbol("folder.fill", color: folderColor, size: size)
        }
        if item.isAlias() {
            return symbol("arrow.turn.up.right", color: tint(kindColor), size: size)
        }
        return symbol(symbolName(for: item), color: tint(kindColor), size: size)
    }

    /// What a cushion of this color looks like on average, so the icon matches the map.
    private static func tint(_ kindColor: NSColor?) -> NSColor {
        guard let kindColor = kindColor else { return NSColor(white: 1, alpha: 0.6) }
        return Theme.cushionDisplayColor(kindColor)
    }

    private static func isApplication(_ item: FSItem) -> Bool {
        item.fileURL()?.pathExtension?.lowercased() == "app"
    }

    private static func symbolName(for item: FSItem) -> String {
        let ext = item.fileURL()?.pathExtension?.lowercased() ?? ""
        if let known = symbolNames[ext] {
            return known
        }
        let name = symbolName(forExtension: ext)
        symbolNames[ext] = name
        return name
    }

    // the type hierarchy decides, so "heic", "png" and "tiff" are all photos
    static func symbolName(forExtension ext: String) -> String {
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return "doc" }

        let table: [(UTType, String)] = [
            (.image, "photo"),
            (.movie, "film"),
            (.audio, "waveform"),
            (.diskImage, "opticaldiscdrive"),
            (.archive, "archivebox"),
            (.pdf, "doc.richtext"),
            (.sourceCode, "chevron.left.forwardslash.chevron.right"),
            (.executable, "terminal"),
            (.spreadsheet, "tablecells"),
            (.presentation, "rectangle.on.rectangle"),
            (.font, "textformat"),
            (.database, "cylinder"),
            (.text, "doc.text")
        ]
        return table.first { type.conforms(to: $0.0) }?.1 ?? "doc"
    }

    private static func symbol(_ name: String, color: NSColor, size: CGFloat) -> NSImage? {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let key = String(format: "%@|%.2f|%.2f|%.2f|%.2f|%.0f", name, rgb.redComponent, rgb.greenComponent,
                         rgb.blueComponent, rgb.alphaComponent, size)
        if let cached = symbols[key] {
            return cached
        }

        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.92, weight: .regular, scale: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        symbols[key] = image
        return image
    }
}
