//
//  NSFileManager-Extensions.swift
//  Disk Inventory Xs
//
//  Swift port of NSFileManager-Extensions.{h,m} (the
//  NSFileManager(PrivacyProtectedFolders) category). Enumerates the folders
//  macOS guards behind privacy consent, and pokes them so the consent dialogs
//  appear up front. Only the Swift FileSystemDoc uses these, so this is a
//  plain Swift extension (no ObjC exposure needed).
//
//  GPL v3
//

import Foundation

extension FileManager {

    // Folders/files on the local volume under macOS privacy protection. See
    // https://developer.apple.com/documentation/bundleresources/information_property_list/protected_resources
    func localPrivacyProtectedFolders() -> [URL] {
        var protectedURLs: [URL] = []

        let mojave = OperatingSystemVersion(majorVersion: 10, minorVersion: 14, patchVersion: 0)
        let catalina = OperatingSystemVersion(majorVersion: 10, minorVersion: 15, patchVersion: 0)

        // protection of these folders arrived in 10.14 Mojave
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(mojave) else {
            return protectedURLs
        }

        // folders identified directly by a search-path constant
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(catalina) {
            let searchDirs: [SearchPathDirectory] = [.documentDirectory, .desktopDirectory, .downloadsDirectory]
            for dir in searchDirs {
                if let dirURL = try? url(for: dir, in: .userDomainMask, appropriateFor: nil, create: false) {
                    protectedURLs.append(dirURL)
                }
            }
        }

        // photo libraries: all .photoslibrary folders in ~/Pictures
        if let picturesURL = try? url(for: .picturesDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            let dirEnum = enumerator(at: picturesURL,
                                     includingPropertiesForKeys: [.typeIdentifierKey],
                                     options: .skipsSubdirectoryDescendants,
                                     errorHandler: { _, error in
                                         NSLog("error: %@", error as NSError)
                                         return true
                                     })
            while let entry = dirEnum?.nextObject() as? URL {
                let uti = try? entry.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier
                if uti == "com.apple.photos.library" {
                    protectedURLs.append(entry)
                }
            }
        }

        // calendars and reminders: ~/Library/Calendars and ~/Library/Reminders (10.15+)
        if let libURL = try? url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            protectedURLs.append(libURL.appendingPathComponent("Calendars"))
            if ProcessInfo.processInfo.isOperatingSystemAtLeast(catalina) {
                protectedURLs.append(libURL.appendingPathComponent("Reminders"))
            }
        }

        // address book: ~/Library/Application Support/AddressBook
        if let appSupportURL = try? url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            protectedURLs.append(appSupportURL.appendingPathComponent("AddressBook"))
        }

        return protectedURLs
    }

    // Protected folders/files at or below the given URL.
    func privacyProtectedFolders(in url: URL) -> [URL] {
        localPrivacyProtectedFolders().filter { protectedURL in
            var relationship: URLRelationship = .other
            guard (try? getRelationship(&relationship, ofDirectoryAt: url, toItemAt: protectedURL)) != nil else {
                return false
            }
            return relationship == .same || relationship == .contains
        }
    }

    // Touch the protected URLs to trigger macOS' consent dialogs.
    func triggerConsentDialog(forPrivacyProtectedFolders urls: [URL]) {
        for protectedURL in urls {
            do {
                _ = try attributesOfItem(atPath: protectedURL.path)
            } catch {
                NSLog("cannot access '%@': %@", protectedURL.path, error as NSError)
                continue
            }

            // the dialog sometimes appears only when listing the folder's
            // contents rather than reading its attributes, so do both
            let isDir = (try? protectedURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                _ = contents(atPath: protectedURL.path)
            }
        }
    }

    // Touch the protected URLs at or below "url" to trigger the consent dialogs.
    func triggerConsentDialog(forPrivacyProtectedFoldersIn url: URL) {
        triggerConsentDialog(forPrivacyProtectedFolders: privacyProtectedFolders(in: url))
    }
}
