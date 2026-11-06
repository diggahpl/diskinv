//
//  HelpWindowController.swift
//  Disk Inventory Xs
//
//  The Help window: the help page of this very app in a web view. Help Viewer keeps
//  its books by title and version and finds an app by its bundle identifier, so with
//  several builds of the same identifier registered (every development build is one)
//  it can open the help of another build than the one asking, and an updated page does
//  not show until its cache is refreshed. DIXApplication hands showHelp: (the Help
//  menu item and its shortcut) to this window instead.
//
//  GPL v3
//

import Cocoa
import WebKit

/// The principal class (Info.plist): the same as NSApplication, but Help is ours.
@objc(DIXApplication)
final class DIXApplication: NSApplication {

    override func showHelp(_ sender: Any?) {
        HelpWindowController.shared.showHelpWindow(sender)
    }
}

final class HelpWindowController: NSWindowController, WKNavigationDelegate {

    static let shared = HelpWindowController(window: nil)

    /// Points the Help menu item, which the nib wires to the system's showHelp:, at this window
    /// (the system would also disable it, as the app has no help book for Help Viewer).
    static func install() {
        if let menu = NSApp.mainMenu {
            rewire(menu)
        }
    }

    private static func rewire(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(NSApplication.showHelp(_:)) {
                item.target = shared
                item.action = #selector(showHelpWindow(_:))
            }
            if let submenu = item.submenu {
                rewire(submenu)
            }
        }
    }

    // A controller made with init(window: nil) has no nib to load, so NSWindowController never
    // calls loadWindow() for it: the window and its web view are built here, the first time
    // Help is asked for.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.title = NSLocalizedString("Disk Inventory Xs Help", comment: "title of the Help window")
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.space
        window.minSize = NSSize(width: 520, height: 360)
        window.setFrameAutosaveName("HelpWindow")
        if !window.setFrameUsingName("HelpWindow") {
            window.center()
        }

        let webView = WKWebView(frame: window.contentLayoutRect)
        webView.autoresizingMask = [.width, .height]
        webView.underPageBackgroundColor = Theme.space
        webView.navigationDelegate = self
        window.contentView = webView

        // the page of the user's language: Bundle picks the localized Help folder
        if let page = Bundle.main.url(forResource: "index", withExtension: "htm", subdirectory: "Help") {
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        return window
    }

    @objc func showHelpWindow(_ sender: Any?) {
        if window == nil {
            window = makeWindow()
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(sender)
    }

    // The Help is a local page. A sandboxed build is allowed to open network connections only
    // so that macOS runs this web view in the sandbox, so anything that is not the local page
    // goes to the user's browser instead.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, url.scheme != "file", url.scheme != "about" else {
            decisionHandler(.allow)
            return
        }
        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
        }
        decisionHandler(.cancel)
    }
}
