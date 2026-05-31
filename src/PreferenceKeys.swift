//
//  PreferenceKeys.swift
//  Disk Inventory Xs
//
//  Swift port of PreferenceKeys.{h,m}. The user-defaults / KVO preference-key
//  constants. They were kept in ObjC while ObjC code still referenced them;
//  every consumer is now Swift and uses them purely as string values (defaults
//  keys, "values.<key>" binding paths), so they are plain Swift constants.
//  The string VALUES are preserved verbatim (they are stored defaults keys) —
//  note UseSmallFontInKindStatistic's value differs from its name.
//
//  GPL v3
//

import Foundation

let ShowPackageContents = "ShowPackageContents"
let ShowFreeSpace = "ShowFreeSpace"
let ShowOtherSpace = "ShowOtherSpace"
let IgnoreCreatorCode = "IgnoreCreatorCode"
let ShowPhysicalFileSize = "ShowPhysicalFileSize"  // logical size otherwise (like the Finder)
let UseSmallFontInKindStatistic = "UseSmallFontInKindStatisticView"
let UseSmallFontInFilesView = "UseSmallFontInFilesView"
let UseSmallFontInSelectionList = "UseSmallFontInSelectionList"
let SplitWindowHorizontally = "SplitWindowHorizontally"
let AnimatedZooming = "AnimatedZooming"
let EnableLogging = "EnableLogging"
let DontShowDonationMessage = "DontShowDonationMessage"
let DontShowPrivacyWarningMessage = "DontShowPrivacyWarningMessage"
let ShareKindColors = "ShareKindColors"
