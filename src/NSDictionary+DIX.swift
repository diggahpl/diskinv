//
//  NSDictionary+DIX.swift
//  Disk Inventory Xs
//
//  Swift port of NSDictionary+DIXExtensions (replacement for OmniFoundation
//  NSDictionary helpers). Typed accessors over a plist-style dictionary.
//
//  GPL v3
//

import Foundation

@objc extension NSDictionary {

    @objc(boolForKey:)
    func bool(forKey key: String) -> Bool {
        bool(forKey: key, defaultValue: false)
    }

    @objc(boolForKey:defaultValue:)
    func bool(forKey key: String, defaultValue: Bool) -> Bool {
        (object(forKey: key) as? NSNumber)?.boolValue ?? defaultValue
    }

    @objc(intForKey:)
    func int(forKey key: String) -> Int32 {
        int(forKey: key, defaultValue: 0)
    }

    @objc(intForKey:defaultValue:)
    func int(forKey key: String, defaultValue: Int32) -> Int32 {
        (object(forKey: key) as? NSNumber)?.int32Value ?? defaultValue
    }

    @objc(floatForKey:)
    func float(forKey key: String) -> Float {
        float(forKey: key, defaultValue: 0.0)
    }

    @objc(floatForKey:defaultValue:)
    func float(forKey key: String, defaultValue: Float) -> Float {
        (object(forKey: key) as? NSNumber)?.floatValue ?? defaultValue
    }
}

@objc extension NSMutableDictionary {

    @objc(setBoolValue:forKey:)
    func setBoolValue(_ value: Bool, forKey key: String) {
        setObject(NSNumber(value: value), forKey: key as NSString)
    }

    @objc(setIntValue:forKey:)
    func setIntValue(_ value: Int32, forKey key: String) {
        setObject(NSNumber(value: value), forKey: key as NSString)
    }

    @objc(setFloatValue:forKey:)
    func setFloatValue(_ value: Float, forKey key: String) {
        setObject(NSNumber(value: value), forKey: key as NSString)
    }
}
