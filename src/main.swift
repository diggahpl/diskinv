//
//  main.swift
//  Disk Inventory Xs
//
//  Application entry point. NSApplicationMain reads NSPrincipalClass
//  (NSApplication) and NSMainNibFile (MainMenu) from Info.plist and starts the
//  AppKit run loop — the nib-driven launch, identical to the former main.m.
//
//  GPL v3
//

import Cocoa

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
