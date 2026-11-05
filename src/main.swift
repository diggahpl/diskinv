//
//  main.swift
//  Disk Inventory Xs
//
//  Application entry point. NSApplicationMain reads NSPrincipalClass
//  (DIXApplication, an NSApplication that shows our own Help window) and
//  NSMainNibFile (MainMenu) from Info.plist and starts the
//  AppKit run loop — the nib-driven launch, identical to the former main.m.
//
//  GPL v3
//

import Cocoa

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
