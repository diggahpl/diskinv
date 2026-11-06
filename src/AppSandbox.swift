//
//  AppSandbox.swift
//  Disk Inventory Xs
//
//  Tells whether the process runs inside the App Sandbox. In the sandbox the
//  app can only read folders the user handed over through an open panel, a drag
//  or an "Open Recent" entry, so the places that used to open a path straight
//  away (the volumes panel) go through an open panel instead. Builds made by
//  BuildRelease.sh are not sandboxed and keep opening volumes directly.
//
//  GPL v3
//

import Cocoa

enum AppSandbox {

    // The sandbox sets this variable in every sandboxed process; Apple documents
    // it as the way to detect the sandbox at run time.
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    // The open panel that hands a whole volume (or any folder) over to the app.
    // The panel opens inside the volume, so "Scan" with nothing selected chooses
    // the volume itself. It is the only way into a volume in the sandbox.
    static func makeAccessPanel(for volumeURL: URL, name: String) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = volumeURL
        panel.prompt = NSLocalizedString("Scan", comment: "default button of the open panel that gives the app access to a disk")
        panel.message = String(format: NSLocalizedString("To scan \"%@\", click Scan.\nmacOS lets Disk Inventory Xs look only into what you hand over.\nThe app reads names and sizes, never the contents of your files.", comment: "message of the open panel that gives the app access to a disk"), name)
        return panel
    }
}
