//
//  NTFilePasteboardSource.swift
//  Path Finder
//
//  Swift port of NTFilePasteboardSource.{h,m}. Lazy pasteboard data provider
//  for a set of file URLs: declares the supported pasteboard types for the
//  first URL and serves the data on demand (filenames, string path, file
//  contents, TIFF/icon, RTF/RTFD/HTML/PDF).
//
//  NTFilePasteboardSource isn't included in the CocoaTech Frameworks any more
//  (and there is no replacement class either), so it was copied into the
//  Disk Inventory X project.
//
//  Created by Steve Gehrman on Sun Feb 02 2003.
//  Copyright (c) 2003 CocoaTech. All rights reserved.
//

import Cocoa
import CoreServices

// Legacy pasteboard type constants whose Swift globals are unavailable; kept as
// the same raw strings the original ObjC code used.
private let kFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
private let kFileContentsType = NSPasteboard.PasteboardType("NSFileContentsPboardType")
private let kPostScriptType = NSPasteboard.PasteboardType("NSPostScriptPboardType")

@objc(NTFilePasteboardSource)
class NTFilePasteboardSource: NSObject {

    private let _URLs: [NSURL]

    private init(urls: [NSURL]) {
        _URLs = urls
        super.init()
    }

    @objc(defaultTypes)
    class func defaultTypes() -> [NSPasteboard.PasteboardType] {
        [
            .tiff,
            .pdf,
            kPostScriptType,

            .rtf,
            .rtfd,
            .html,

            kFileContentsType,

            kFilenamesType,
            .string,
        ]
    }

    @objc(imageTypes)
    class func imageTypes() -> [NSPasteboard.PasteboardType] {
        [
            .tiff,
            .pdf,
            kPostScriptType,
        ]
    }

    @objc(file:toPasteboard:types:)
    @discardableResult
    class func file(_ url: URL?, to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> NTFilePasteboardSource {
        let urls: [NSURL] = url.map { [$0 as NSURL] } ?? []
        return files(urls, to: pboard, types: types)
    }

    @objc(files:toPasteboard:types:)
    @discardableResult
    class func files(_ urls: [NSURL], to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> NTFilePasteboardSource {
        let source = NTFilePasteboardSource(urls: urls)
        let pasteboardTypes = source.pasteboardTypes(types)

        if let pasteboardTypes = pasteboardTypes {
            // Use standard NSPasteboard for lazy data provision
            // The pasteboard retains the owner for as long as the data is valid
            pboard.declareTypes(pasteboardTypes, owner: source)
        }

        return source
    }

    // MARK: - Private (was NTFilePasteboardSource (Private))

    private func pasteboardTypes(_ types: [NSPasteboard.PasteboardType]) -> [NSPasteboard.PasteboardType]? {
        guard let url = _URLs.first else { return nil }

        // figure out what type of file the current selection is
        var pasteTypes: [NSPasteboard.PasteboardType] = []
        let uti = url.uti()

        for type in types {
            if type == kFilenamesType {
                pasteTypes.append(type)
            } else if type == .string {
                pasteTypes.append(type)
            } else if type == kFileContentsType {
                pasteTypes.append(type)
            } else if type == .tiff { // we use the icon if not an image, so don't check isImage
                pasteTypes.append(type)
            } else if type == .rtf, uti == (kUTTypeRTF as String) {
                pasteTypes.append(type)
            } else if type == .rtfd, uti == (kUTTypeFlatRTFD as String) {
                pasteTypes.append(type)
            } else if type == .html, uti == (kUTTypeHTML as String) {
                pasteTypes.append(type)
            } else if type == .pdf, uti == (kUTTypePDF as String) {
                pasteTypes.append(type)
            }
        }

        if !pasteTypes.isEmpty {
            return pasteTypes
        }

        return nil
    }

    @objc(pasteboard:provideDataForType:)
    func pasteboard(_ pboard: NSPasteboard, provideDataForType type: NSPasteboard.PasteboardType) {
        guard let url = _URLs.first else { return }

        let uti = url.uti()

        if type == kFilenamesType {
            var pathsArray: [String] = []
            for u in _URLs {
                pathsArray.append(u.path ?? "")
            }
            pboard.setPropertyList(pathsArray, forType: kFilenamesType)
        } else if type == .string {
            // set the path
            pboard.setString(url.path ?? "", forType: .string)
        } else if type == kFileContentsType {
            // write the contents
            pboard.writeFileContents(url.path ?? "")
        } else if type == .tiff {
            if uti == (kUTTypeTIFF as String) {
                if let data = NSData(contentsOfFile: url.path ?? "") as Data? {
                    pboard.setData(data, forType: .tiff)
                }
            } else if let uti = uti, UTTypeConformsTo(uti as CFString, kUTTypeImage) {
                // open the image and return TIFFRepresentation
                if let image = NSImage(contentsOfFile: url.path ?? ""),
                   let data = image.tiffRepresentation {
                    pboard.setData(data, forType: .tiff)
                }
            } else {
                // else send the icon
                // NTFilePasteBoardSource: providing file icon not implemented (matches original)
            }
        } else if type == .rtf {
            if uti == (kUTTypeRTF as String), let data = NSData(contentsOfFile: url.path ?? "") as Data? {
                pboard.setData(data, forType: .rtf)
            }
        } else if type == .rtfd {
            if uti == (kUTTypeFlatRTFD as String) {
                if let tempRTFDData = try? FileWrapper(url: url as URL, options: []) {
                    pboard.setData(tempRTFDData.serializedRepresentation ?? Data(), forType: .rtfd)
                }
            }
        } else if type == .html {
            if uti == (kUTTypeHTML as String), let data = NSData(contentsOfFile: url.path ?? "") as Data? {
                pboard.setData(data, forType: .html)
            }
        } else if type == .pdf {
            if uti == (kUTTypePDF as String), let data = NSData(contentsOfFile: url.path ?? "") as Data? {
                pboard.setData(data, forType: .pdf)
            }
        }
    }
}
