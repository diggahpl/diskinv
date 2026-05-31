//
//  Preferences.swift
//  Disk Inventory Xs
//
//  Swift port of the Preferences module's two ObjC categories:
//   - NSUserDefaults(VersionDepedantValues): version-suffixed bool storage.
//   - NSMutableDictionary(DocumentPreferences): typed view-option accessors
//     plus a factory that seeds a fresh dictionary from the shared defaults.
//
//  The bare `extern NSString*` preference-key constants remain in ObjC
//  (PreferenceKeys.h/.m); they are visible here via the bridging header.
//
//  GPL v3
//

import Foundation

@objc extension UserDefaults {

    private var mainBundleVersion: String {
        let bundle = Bundle.main
        let dict = bundle.infoDictionary
        for key in ["CFBundleShortVersionString", "CFBundleGetInfoString"] {
            if let value = dict?[key] as? String, !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func versionDependantKey(forKey key: String) -> String {
        let version = mainBundleVersion
        return version.isEmpty ? key : key + " v\(version)"
    }

    @objc(boolForVersionDependantKey:)
    func boolForVersionDependantKey(_ key: String) -> Bool {
        bool(forKey: versionDependantKey(forKey: key))
    }

    @objc(setBool:forVersionDependantKey:)
    func setBool(_ value: Bool, forVersionDependantKey key: String) {
        set(value, forKey: versionDependantKey(forKey: key))
    }
}

@objc extension NSMutableDictionary {

    @objc(dictionaryWithDefaults)
    class func dictionaryWithDefaults() -> NSMutableDictionary {
        let dict = NSMutableDictionary()
        let defaults = UserDefaults.standard

        for key in [ShowPackageContents,
                    ShowFreeSpace,
                    ShowOtherSpace,
                    IgnoreCreatorCode,
                    ShowPhysicalFileSize] {
            dict.setBoolValue(defaults.bool(forKey: key), forKey: key)
        }

        return dict
    }

    @objc var showPackageContents: Bool {
        get { bool(forKey: ShowPackageContents) }
        set { setBoolValue(newValue, forKey: ShowPackageContents) }
    }

    @objc var showFreeSpace: Bool {
        get { bool(forKey: ShowFreeSpace) }
        set { setBoolValue(newValue, forKey: ShowFreeSpace) }
    }

    @objc var showOtherSpace: Bool {
        get { bool(forKey: ShowOtherSpace) }
        set { setBoolValue(newValue, forKey: ShowOtherSpace) }
    }

    @objc var ignoreCreatorCode: Bool {
        get { bool(forKey: IgnoreCreatorCode) }
        set { setBoolValue(newValue, forKey: IgnoreCreatorCode) }
    }

    @objc var showPhysicalFileSize: Bool {
        get { bool(forKey: ShowPhysicalFileSize) }
        set { setBoolValue(newValue, forKey: ShowPhysicalFileSize) }
    }
}
