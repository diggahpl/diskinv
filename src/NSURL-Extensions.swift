//
//  NSURL-Extensions.swift
//  Disk Inventory Xs
//
//  Swift port of NSURL-Extensions.{h,m} (the NSURL(AccessExtensions)
//  category). Adds convenience accessors over NSURL resource values, plus a
//  per-URL value cache kept as a temporary resource value (Apple clears
//  non-temporary cached values after each run-loop pass).
//
//  GPL v3
//

import Cocoa

extension NSURL {

    // MARK: - functions to access NSURL resource keys (removed after each run-loop pass)

    @objc(isFile)
    func isFile() -> Bool { getBoolValue(URLResourceKey.isRegularFileKey.rawValue) }

    @objc(isDirectory)
    func isDirectory() -> Bool { getBoolValue(URLResourceKey.isDirectoryKey.rawValue) }

    // NSURLIsVolumeKey: true for the root directory of a volume.
    @objc(isVolume)
    func isVolume() -> Bool { getBoolValue(URLResourceKey.isVolumeKey.rawValue) }

    @objc(isPackage)
    func isPackage() -> Bool { getBoolValue(URLResourceKey.isPackageKey.rawValue) }

    // NSURLIsAliasFileKey: true for a Finder alias file or a symlink.
    @objc(isAliasOrSymbolicLink)
    func isAliasOrSymbolicLink() -> Bool { getBoolValue(URLResourceKey.isAliasFileKey.rawValue) }

    @objc(isFirmlink)
    func isFirmlink() -> Bool { NSURL.firmlinks.contains(self) }

    @objc(name)
    func name() -> String { getStringValue(URLResourceKey.nameKey.rawValue) ?? "" }

    @objc(displayName)
    func displayName() -> String { getStringValue(URLResourceKey.localizedNameKey.rawValue) ?? "" }

    @objc(displayPath)
    func displayPath() -> String {
        let components = FileManager.default.componentsToDisplay(forPath: self.path ?? "") ?? []
        return NSString.path(withComponents: components)
    }

    // uniform type identifier
    @objc(UTI)
    func uti() -> String? { getStringValue(URLResourceKey.typeIdentifierKey.rawValue) }

    @objc(icon)
    func icon() -> NSImage? { NSWorkspace.shared.icon(forFile: self.path ?? "") }

    @objc(logicalSize)
    func logicalSize() -> NSNumber {
        getNumberValue(URLResourceKey.totalFileSizeKey.rawValue)
            ?? getNumberValue(URLResourceKey.fileSizeKey.rawValue)
            ?? NSNumber(value: 0)
    }

    @objc(physicalSize)
    func physicalSize() -> NSNumber {
        getNumberValue(URLResourceKey.totalFileAllocatedSizeKey.rawValue)
            ?? getNumberValue(URLResourceKey.totalFileSizeKey.rawValue)
            ?? NSNumber(value: 0)
    }

    @objc(creationDate)
    func creationDate() -> NSDate {
        getDateValue(URLResourceKey.creationDateKey.rawValue) ?? NSDate(timeIntervalSince1970: 0)
    }

    @objc(modificationDate)
    func modificationDate() -> NSDate {
        getDateValue(URLResourceKey.contentModificationDateKey.rawValue) ?? NSDate(timeIntervalSince1970: 0)
    }

    // works only for file URLs
    @objc(stillExists)
    func stillExists() -> Bool { FileManager.default.fileExists(atPath: self.path ?? "") }

    @objc(residesInDirectoryURL:)
    func residesInDirectory(_ parentDir: NSURL) -> Bool {
        guard let myParent = self.deletingLastPathComponent else { return false }
        return (myParent as NSURL).isEqual(to: parentDir)
    }

    @objc(isEqualToURL:)
    func isEqual(to url: NSURL) -> Bool {
        self.scheme == url.scheme && self.resourceSpecifier == url.resourceSpecifier
    }

    // MARK: - volume attributes

    // NSURLVolumeIsLocalKey: true if the volume is stored on a local device.
    @objc(isLocalVolume)
    func isLocalVolume() -> Bool { getBoolValue(URLResourceKey.volumeIsLocalKey.rawValue) }

    @objc(volumeTotalCapacity)
    func volumeTotalCapacity() -> NSNumber? { getNumberValue(URLResourceKey.volumeTotalCapacityKey.rawValue) }

    @objc(volumeAvailableCapacity)
    func volumeAvailableCapacity() -> NSNumber? { getNumberValue(URLResourceKey.volumeAvailableCapacityKey.rawValue) }

    @objc(volumeFormatName)
    func volumeFormatName() -> String {
        getStringValue(URLResourceKey.volumeLocalizedFormatDescriptionKey.rawValue) ?? ""
    }

    // MARK: - resource-value helpers

    @objc(getBoolValue:)
    func getBoolValue(_ resourceName: String) -> Bool {
        (resourceValue(forKey: resourceName) as? NSNumber)?.boolValue ?? false
    }

    @objc(getStringValue:)
    func getStringValue(_ resourceName: String) -> String? {
        resourceValue(forKey: resourceName) as? String
    }

    @objc(getNumberValue:)
    func getNumberValue(_ resourceName: String) -> NSNumber? {
        resourceValue(forKey: resourceName) as? NSNumber
    }

    @objc(getDateValue:)
    func getDateValue(_ resourceName: String) -> NSDate? {
        resourceValue(forKey: resourceName) as? NSDate
    }

    private func resourceValue(forKey key: String) -> AnyObject? {
        var val: AnyObject?
        do {
            try getResourceValue(&val, forKey: URLResourceKey(rawValue: key))
        } catch {
            return nil
        }
        return val
    }

    // MARK: - cached resource values (kept in memory as a temporary resource value)

    @objc(cachedIsFile)
    func cachedIsFile() -> Bool { getCachedBoolValue(URLResourceKey.isRegularFileKey.rawValue) }

    @objc(cachedIsDirectory)
    func cachedIsDirectory() -> Bool { getCachedBoolValue(URLResourceKey.isDirectoryKey.rawValue) }

    @objc(cachedIsVolume)
    func cachedIsVolume() -> Bool { getCachedBoolValue(URLResourceKey.isVolumeKey.rawValue) }

    @objc(cachedIsPackage)
    func cachedIsPackage() -> Bool { getCachedBoolValue(URLResourceKey.isPackageKey.rawValue) }

    @objc(cachedIsAliasOrSymbolicLink)
    func cachedIsAliasOrSymbolicLink() -> Bool { getCachedBoolValue(URLResourceKey.isAliasFileKey.rawValue) }

    @objc(cachedName)
    func cachedName() -> String { getCachedStringValue(URLResourceKey.nameKey.rawValue) ?? "" }

    @objc(cachedPath)
    func cachedPath() -> String {
        // NSURL does not expose the path as a resource value, so it cannot go
        // through getCachedStringValue; cache it under a private key instead.
        let key = "URLFilePathKey"
        guard let cache = resourceValueCache() else { return self.path ?? "" }

        var cachedVal = cache.object(forKey: key) as AnyObject?
        if cachedVal == nil {
            cachedVal = (self.path as AnyObject?) ?? NSNull()
            cache.setValue(cachedVal, forKey: key)
        }
        return (cachedVal is NSNull) ? "" : (cachedVal as? String ?? "")
    }

    @objc(cachedDisplayName)
    func cachedDisplayName() -> String { getCachedStringValue(URLResourceKey.localizedNameKey.rawValue) ?? "" }

    @objc(cachedUTI)
    func cachedUTI() -> String? { getCachedStringValue(URLResourceKey.typeIdentifierKey.rawValue) }

    @objc(cachedLogicalSize)
    func cachedLogicalSize() -> NSNumber {
        getCachedNumberValue(URLResourceKey.totalFileSizeKey.rawValue)
            ?? getCachedNumberValue(URLResourceKey.fileSizeKey.rawValue)
            ?? NSNumber(value: 0)
    }

    @objc(cachedPhysicalSize)
    func cachedPhysicalSize() -> NSNumber {
        getCachedNumberValue(URLResourceKey.totalFileAllocatedSizeKey.rawValue)
            ?? getCachedNumberValue(URLResourceKey.totalFileSizeKey.rawValue)
            ?? NSNumber(value: 0)
    }

    @objc(cachedCreationDate)
    func cachedCreationDate() -> NSDate {
        getCachedDateValue(URLResourceKey.creationDateKey.rawValue) ?? NSDate(timeIntervalSince1970: 0)
    }

    @objc(cachedModificationDate)
    func cachedModificationDate() -> NSDate {
        getCachedDateValue(URLResourceKey.contentModificationDateKey.rawValue) ?? NSDate(timeIntervalSince1970: 0)
    }

    @objc(cachedIsLocalVolume)
    func cachedIsLocalVolume() -> Bool { getCachedBoolValue(URLResourceKey.volumeIsLocalKey.rawValue) }

    @objc(cachedVolumeTotalCapacity)
    func cachedVolumeTotalCapacity() -> NSNumber? { getCachedNumberValue(URLResourceKey.volumeTotalCapacityKey.rawValue) }

    @objc(cachedVolumeAvailableCapacity)
    func cachedVolumeAvailableCapacity() -> NSNumber? { getCachedNumberValue(URLResourceKey.volumeAvailableCapacityKey.rawValue) }

    @objc(cachedVolumeFormatName)
    func cachedVolumeFormatName() -> String {
        getCachedStringValue(URLResourceKey.volumeLocalizedFormatDescriptionKey.rawValue) ?? ""
    }

    @objc(cacheResourcesInArray:)
    func cacheResources(in resourceKeys: [URLResourceKey]) {
        guard let cache = resourceValueCache() else { return }
        for key in resourceKeys {
            var val: AnyObject?
            try? getResourceValue(&val, forKey: key)
            cache.setValue(val ?? NSNull(), forKey: key.rawValue) // mark missing resources with NSNull
        }
    }

    @objc(getCachedBoolValue:)
    func getCachedBoolValue(_ resourceName: String) -> Bool {
        (getCachedResourceValue(forKey: resourceName) as? NSNumber)?.boolValue ?? false
    }

    @objc(getCachedStringValue:)
    func getCachedStringValue(_ resourceName: String) -> String? {
        getCachedResourceValue(forKey: resourceName) as? String
    }

    @objc(getCachedNumberValue:)
    func getCachedNumberValue(_ resourceName: String) -> NSNumber? {
        getCachedResourceValue(forKey: resourceName) as? NSNumber
    }

    @objc(getCachedDateValue:)
    func getCachedDateValue(_ resourceName: String) -> NSDate? {
        getCachedResourceValue(forKey: resourceName) as? NSDate
    }

    // MARK: - private cache plumbing

    // The cached values live in a single NSMutableDictionary kept as the URL's
    // sole temporary resource value; storing each one as its own temporary
    // resource value costs ~50% more memory.
    private func resourceValueCache() -> NSMutableDictionary? {
        let cacheKey = URLResourceKey(rawValue: "com.derlien.URLResourceValueCacheKey")

        var cache: AnyObject?
        // A thrown error (not a missing value) means we cannot use a cache.
        do {
            try getResourceValue(&cache, forKey: cacheKey)
        } catch {
            return nil
        }

        if let dict = cache as? NSMutableDictionary {
            return dict
        }

        let newCache = NSMutableDictionary()
        setTemporaryResourceValue(newCache, forKey: cacheKey)
        return newCache
    }

    private func getCachedResourceValue(forKey key: String) -> AnyObject? {
        guard let cache = resourceValueCache() else { return nil }

        var cachedVal = cache.object(forKey: key) as AnyObject?
        if cachedVal == nil {
            var loaded: AnyObject?
            do {
                try getResourceValue(&loaded, forKey: URLResourceKey(rawValue: key))
            } catch {
                return nil
            }
            cachedVal = loaded ?? NSNull() // mark missing resource so we don't reload it
            cache.setValue(cachedVal, forKey: key)
        }
        return (cachedVal is NSNull) ? nil : cachedVal
    }

    // MARK: - firmlinks

    private static let firmlinks: Set<NSURL> = {
        var set = Set<NSURL>()
        guard let contents = try? String(contentsOfFile: "/usr/share/firmlinks", encoding: .ascii) else {
            return set
        }
        for line in contents.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let url = NSURL(fileURLWithPath: parts[0])
            if url.stillExists() { set.insert(url) }
        }
        return set
    }()
}
