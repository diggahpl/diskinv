//
//  NTTitledInfoPair.swift
//  CocoaTechBase
//
//  Swift port of NTTitledInfoPair.{h,m}. A simple label/value pair model used
//  by NTTitledInfoView to lay out a titled info row; optionally carries an
//  action/target so the info cell can be clickable.
//
//  Created by Steve Gehrman on Thu Dec 11 2003.
//

import Cocoa

@objc(NTTitledInfoPair)
class NTTitledInfoPair: NSObject {

    private let _title: String?
    private let _info: String?
    private let _action: Selector?
    private weak var _target: AnyObject?

    // pass nil to edit action if you don't want it editable
    private init(title: String?, info: String?, action: Selector?, target: AnyObject?) {
        _title = title
        _info = info
        _action = action
        _target = target
        super.init()
    }

    @objc(infoPair:info:)
    class func infoPair(_ title: String?, info: String?) -> NTTitledInfoPair {
        infoPair(title, info: info, action: nil, target: nil)
    }

    @objc(infoPair:info:action:target:)
    class func infoPair(_ title: String?, info: String?, action: Selector?, target: AnyObject?) -> NTTitledInfoPair {
        NTTitledInfoPair(title: title, info: info, action: action, target: target)
    }

    @objc(title)
    func title() -> String? { _title }

    @objc(info)
    func info() -> String? { _info }

    @objc(action)
    func action() -> Selector? { _action }

    @objc(target)
    func target() -> AnyObject? { _target }
}
