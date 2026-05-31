//
//  NTInfoView.swift
//  Path Finder
//
//  Swift port of NTInfoView.{h,m}. Builds the list of NTTitledInfoPairs for a
//  file/URL (name, kind, size, dates, owner/group, permissions, version, path,
//  resolved alias, default app) and hosts an NTTitledInfoView inside a scroll
//  view to display them.
//
//  Created by Steve Gehrman on Sat Jul 12 2003.
//

import Cocoa

@objc(NTInfoView)
class NTInfoView: NSView {

    private var _titledInfoView: NTTitledInfoView!
    private var _URL: NSURL?
    private var _longFormat: Bool = false

    private var _calculatedFolderSize: String?
    private var _calculatedFolderNumItems: String?

    @objc(initWithFrame:longFormat:)
    init(frame: NSRect, longFormat: Bool) {
        _longFormat = longFormat
        super.init(frame: frame)

        autoresizingMask = [.width, .height]

        createInfoView()
    }

    @objc(initWithFrame:)
    override init(frame: NSRect) {
        // long format is NO by default
        _longFormat = false
        super.init(frame: frame)

        autoresizingMask = [.width, .height]

        createInfoView()
    }

    required init?(coder: NSCoder) {
        _longFormat = false
        super.init(coder: coder)

        autoresizingMask = [.width, .height]

        createInfoView()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc(URL)
    func url() -> NSURL? {
        _URL
    }

    @objc(setURL:)
    func setURL(_ url: NSURL?) {
        resetForNewItem()

        _URL = url

        updateInfoView()
    }

    // MARK: - Private (was NTInfoView (Private))

    private func resetForNewItem() {
        _URL = nil
        _calculatedFolderNumItems = nil
    }

    private func createInfoView() {
        let scrollView = NSScrollView(frame: bounds)

        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizesSubviews = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.scrollsDynamically = true
        scrollView.drawsBackground = true
        scrollView.contentView.copiesOnScroll = true

        // set small scrollbars
        scrollView.verticalScroller?.controlSize = .small
        scrollView.horizontalScroller?.controlSize = .small

        var contentRect = scrollView.bounds
        contentRect.size = scrollView.contentSize

        _titledInfoView = NTTitledInfoView(frame: contentRect)

        // longFormat is used in the GetInfo window, keep the extra space in that case
        if !_longFormat {
            _titledInfoView.setHorizontalOffset(0) // don't waste any horizontal space
        }

        // add the document view to the scroller
        scrollView.documentView = _titledInfoView

        addSubview(scrollView)
    }

    private func updateInfoView() {
        let array: [NTTitledInfoPair]

        if _longFormat {
            array = longInfoPairs()
        } else {
            array = infoPairs()
        }

        _titledInfoView.setWithArray(array)
    }

    // Overridable hook (DIXFileInfoView overrides this to tweak the name row).
    @objc(infoPairs)
    func infoPairs() -> [NTTitledInfoPair] {
        var infoPairs: [NTTitledInfoPair] = []

        guard let url = _URL, url.stillExists() else {
            return infoPairs
        }

        infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("Name:", comment: ""), info: url.cachedDisplayName()))

        let kindName = url.getCachedStringValue(URLResourceKey.localizedTypeDescriptionKey.rawValue)
        infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("Kind:", comment: ""), info: kindName))

        if url.isVolume() && !url.isLocalVolume() {
            var networkURL: AnyObject?
            try? url.getResourceValue(&networkURL, forKey: .volumeURLForRemountingKey)
            if let networkURL = networkURL as? NSURL {
                infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("URL:", comment: ""), info: networkURL.absoluteString))
            }
        }

        infoPairs.append(contentsOf: sizePairs())

        do {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .medium
            dateFormatter.locale = Locale.current

            infoPairs.append(NTTitledInfoPair.infoPair(
                NSLocalizedString("Modified:", comment: ""),
                info: dateFormatter.string(from: url.cachedModificationDate() as Date)))
            infoPairs.append(NTTitledInfoPair.infoPair(
                NSLocalizedString("Created:", comment: ""),
                info: dateFormatter.string(from: url.cachedCreationDate() as Date)))
        }

        if let attribs = try? FileManager.default.attributesOfItem(atPath: url.path ?? "") {
            infoPairs.append(NTTitledInfoPair.infoPair(
                NSLocalizedString("Owner:", comment: ""),
                info: (attribs as NSDictionary).fileOwnerAccountName()))
            infoPairs.append(NTTitledInfoPair.infoPair(
                NSLocalizedString("Group:", comment: ""),
                info: (attribs as NSDictionary).fileGroupOwnerAccountName()))
        }

        infoPairs.append(NTTitledInfoPair.infoPair(
            NSLocalizedString("Permission:", comment: ""),
            info: NTInfoView.permissionString(for: url)))

        if let bundle = Bundle(url: url as URL) {
            var version: String?

            let bundleVersionInfos: [(dict: [String: Any]?, key: String)] = [
                (bundle.localizedInfoDictionary, "CFBundleGetInfoString"),
                (bundle.infoDictionary, "CFBundleGetInfoString"),
                (bundle.localizedInfoDictionary, "CFBundleShortVersionString"),
                (bundle.infoDictionary, "CFBundleShortVersionString"),
            ]

            for info in bundleVersionInfos {
                if version == nil || version?.isEmpty == true {
                    version = info.dict?[info.key] as? String
                }
            }

            if let version = version, !version.isEmpty {
                infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("Version:", comment: ""), info: version))
            }
        }

        infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("Path:", comment: ""), info: url.path))

        // if alias or symbolic link - resolved:
        var resolvedURL: NSURL? // needed below
        if url.cachedIsAliasOrSymbolicLink() {
            let resolvedPath = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path ?? "")

            if let resolvedPath = resolvedPath {
                resolvedURL = NSURL(fileURLWithPath: resolvedPath)

                infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("Resolved:", comment: ""), info: resolvedPath))
            }
        }

        // application to open the file
        do {
            let lookupURL: NSURL = resolvedURL ?? url

            let appURL = AppsForItem.appsForItem(lookupURL).defaultAppURL

            // if _URL is an application, LSCopyDefaultApplicationURLForURL(..) returns the app URL, so sort that out
            if let appURL = appURL, !appURL.isEqual(to: url as URL) {
                infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("Application:", comment: ""), info: appURL.displayName()))
            }
        }

        return infoPairs
    }

    @objc(longInfoPairs)
    func longInfoPairs() -> [NTTitledInfoPair] {
        var infoPairs: [NTTitledInfoPair] = []

        guard let url = _URL, url.stillExists() else {
            return infoPairs
        }

        infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("Name:", comment: ""), info: url.cachedDisplayName()))

        let kindName = url.getCachedStringValue(URLResourceKey.localizedTypeDescriptionKey.rawValue)
        infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("Kind:", comment: ""), info: kindName))

        if url.isVolume() && !url.isLocalVolume() {
            var networkURL: AnyObject?
            try? url.getResourceValue(&networkURL, forKey: .volumeURLForRemountingKey)
            if let networkURL = networkURL as? NSURL {
                infoPairs.append(NTTitledInfoPair.infoPair(NSLocalizedString("URL:", comment: ""), info: networkURL.absoluteString))
            }
        }

        infoPairs.append(contentsOf: sizePairs())

        return infoPairs
    }

    private func sizePairs() -> [NTTitledInfoPair] {
        let infoPairs: [NTTitledInfoPair] = []

        // (original NTFileDesc-based size/capacity/folder logic is disabled;
        //  to be reimplemented using NSURL & co — see original NTInfoView.m)

        return infoPairs
    }

    @objc(setFolderSizeInfo:totalValence:)
    func setFolderSizeInfo(_ size: NSNumber?, totalValence: NSNumber?) {
        // this is nil for volumes
        if let totalValence = totalValence {
            let formatter = NumberFormatter()

            formatter.positiveFormat = "#,###"
            formatter.allowsFloats = false
            formatter.attributedStringForZero = NSAttributedString(string: "0")

            let numberString = formatter.string(for: totalValence) ?? ""
            _calculatedFolderNumItems = numberString + NSLocalizedString(" items", comment: "")
        }
    }

    // MARK: - permissions (adopted from CocoaTechFile, NTFileDesc-NTUtilities.m)

    @objc(permissionStringForURL:)
    class func permissionString(for url: NSURL) -> String {
        var perm = ""

        // get mode bits via lstat (replaces deprecated FSPathMakeRef/FSGetCatalogInfo);
        // attributesOfItemAtPath:error: strips the type bits we need below.
        var statBuf = stat()
        guard let fsRep = (url as URL).withUnsafeFileSystemRepresentation({ ptr -> String? in
            guard let ptr = ptr else { return nil }
            return String(cString: ptr)
        }) else {
            return perm
        }

        if lstat(fsRep, &statBuf) != 0 {
            return perm
        }

        let modeBits = UInt32(statBuf.st_mode)
        let accessPerms = UInt32(S_IRWXU) | UInt32(S_IRWXG) | UInt32(S_IRWXO)
        let permBits = modeBits & accessPerms

        let fmt = modeBits & UInt32(S_IFMT)
        if fmt == UInt32(S_IFDIR) {
            perm += "d"
        } else if fmt == UInt32(S_IFCHR) {
            perm += "c"
        } else if fmt == UInt32(S_IFBLK) {
            perm += "b"
        } else if fmt == UInt32(S_IFLNK) {
            perm += "l"
        } else if fmt == UInt32(S_IFSOCK) {
            perm += "s"
        } else if fmt == UInt32(S_IFWHT) {
            perm += "w"
        } else if fmt == UInt32(S_IFREG) {
            perm += "-"
        } else {
            perm += " " // what is it?
        }

        let hasSuidOrSgid = ((UInt32(S_ISUID) & modeBits) != 0) || ((UInt32(S_ISGID) & modeBits) != 0)

        // Owner
        perm += (permBits & UInt32(S_IRUSR)) != 0 ? "r" : "-"
        perm += (permBits & UInt32(S_IWUSR)) != 0 ? "w" : "-"

        if (permBits & UInt32(S_IXUSR)) != 0 {
            perm += hasSuidOrSgid ? "s" : "x"
        } else {
            perm += hasSuidOrSgid ? "S" : "-"
        }

        // Group
        perm += (permBits & UInt32(S_IRGRP)) != 0 ? "r" : "-"
        perm += (permBits & UInt32(S_IWGRP)) != 0 ? "w" : "-"

        if (permBits & UInt32(S_IXGRP)) != 0 {
            perm += hasSuidOrSgid ? "s" : "x"
        } else {
            perm += hasSuidOrSgid ? "S" : "-"
        }

        // Others
        let hasSticky = (UInt32(S_ISVTX) & modeBits) != 0

        perm += (permBits & UInt32(S_IROTH)) != 0 ? "r" : "-"
        perm += (permBits & UInt32(S_IWOTH)) != 0 ? "w" : "-"

        if (permBits & UInt32(S_IXOTH)) != 0 {
            if hasSuidOrSgid {
                perm += "s"
            } else {
                // check sticky bit
                perm += hasSticky ? "t" : "x"
            }
        } else {
            if hasSuidOrSgid {
                perm += "S"
            } else {
                // check sticky bit
                perm += hasSticky ? "T" : "-"
            }
        }

        // includeOctal
        perm += " ("
        perm += permissionOctalString(forModeBits: statBuf.st_mode)
        perm += ")"

        return perm
    }

    @objc(permissionOctalStringForModeBits:)
    class func permissionOctalString(forModeBits modeBits: UInt16) -> String {
        let accessPerms = UInt32(S_IRWXU) | UInt32(S_IRWXG) | UInt32(S_IRWXO)
        let permBits = UInt32(modeBits) & accessPerms

        // add - chmod 755
        var chmodNum = 100 * Int((permBits & UInt32(S_IRWXU)) >> 6) // octets
        chmodNum += 10 * Int((permBits & UInt32(S_IRWXG)) >> 3)
        chmodNum += 1 * Int(permBits & UInt32(S_IRWXO))

        return String(format: "%03d", chmodNum)
    }
}
