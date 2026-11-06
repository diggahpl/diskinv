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

    // The user's real home folder. In the App Sandbox the search paths below point into the
    // app's container, but the folders macOS guards are the real ones, which the user hands
    // over by choosing a folder or a disk in an open panel.
    private func realUserFolder(_ dir: SearchPathDirectory, named name: String) -> URL? {
        if AppSandbox.isActive, let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
                .appendingPathComponent(name, isDirectory: true)
        }
        return try? url(for: dir, in: .userDomainMask, appropriateFor: nil, create: false)
    }

    // Folders/files on the local volume under macOS privacy protection. See
    // https://developer.apple.com/documentation/bundleresources/information_property_list/protected_resources
    func localPrivacyProtectedFolders() -> [URL] {
        var protectedURLs: [URL] = []

        // folders identified directly by a search-path constant
        let searchDirs: [(SearchPathDirectory, String)] = [(.documentDirectory, "Documents"),
                                                           (.desktopDirectory, "Desktop"),
                                                           (.downloadsDirectory, "Downloads")]
        for (dir, name) in searchDirs {
            if let dirURL = realUserFolder(dir, named: name) {
                protectedURLs.append(dirURL)
            }
        }

        // photo libraries: all .photoslibrary folders in ~/Pictures
        if let picturesURL = realUserFolder(.picturesDirectory, named: "Pictures") {
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

        // calendars and reminders: ~/Library/Calendars and ~/Library/Reminders
        if let libURL = realUserFolder(.libraryDirectory, named: "Library") {
            protectedURLs.append(libURL.appendingPathComponent("Calendars"))
            protectedURLs.append(libURL.appendingPathComponent("Reminders"))
            // address book: ~/Library/Application Support/AddressBook
            protectedURLs.append(libURL.appendingPathComponent("Application Support").appendingPathComponent("AddressBook"))
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
