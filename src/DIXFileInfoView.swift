//
//  DIXFileInfoView.swift
//  Disk Inventory X
//
//  Swift port of DIXFileInfoView.{h,m}. Subclass of NTInfoView used in the
//  inspector panel; overrides infoPairs to show the "raw" file name in the
//  first row instead of the (possibly localized / extension-hidden) display
//  name shown above next to the icon.
//
//  Created by Tjark Derlien on 04.12.04.
//
//  Copyright (C) 2004 Tjark Derlien.
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or any later version.
//

import Cocoa

@objc(DIXFileInfoView)
class DIXFileInfoView: NTInfoView {

    override func infoPairs() -> [NTTitledInfoPair] {
        let url = self.url()

        var infoPairs = super.infoPairs()

        // NTInfoView shows the display name (possibly localized and with hidden extension), but we want the "raw" name
        // (the display name is shown above next to the image in the inspector panel)
        if let url = url, !infoPairs.isEmpty {
            let oldNameInfoPair = infoPairs[0]

            infoPairs[0] = NTTitledInfoPair.infoPair(oldNameInfoPair.title(), info: url.name())
        }

        return infoPairs
    }
}
