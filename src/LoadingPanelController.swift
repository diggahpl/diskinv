//
//  LoadingPanelController.swift
//  Disk Inventory Xs
//
//  Swift port of LoadingPanelController.{h,m}. Owns LoadingPanel.nib and drives
//  the scan progress panel (either modal or as a sheet), throttling event-loop
//  pumping to ~5 Hz so it doesn't dominate scan time. Nib owner, so the class
//  name, IBOutlets, and the cancel: action are pinned with @objc.
//
//  GPL v3
//

import Cocoa

@objc(LoadingPanelController)
class LoadingPanelController: NSObject {

    @IBOutlet private var _loadingTextField: NSTextField!
    @IBOutlet private var _loadingPanel: NSPanel!
    @IBOutlet private var _loadingProgressIndicator: NSProgressIndicator!
    @IBOutlet private var _loadingCancelButton: NSButton!

    private var _loadingPanelModalSession: NSApplication.ModalSession?
    private var _lastEventLoopRun: UInt64 = 0
    private var _cancelPressed = false
    private var _message: String?
    private var _nibTopLevelObjects: [Any]?

    // starts a modal session immediately
    @objc override init() {
        super.init()
        loadPanelNib()

        // the nib has "release when closed = YES"; turn it off so the panel's
        // lifetime is governed by _nibTopLevelObjects only. Otherwise closing it
        // frees the panel while the array still holds a stale pointer, producing
        // a zombie crash when the controller is later released.
        _loadingPanel.isReleasedWhenClosed = false

        _loadingProgressIndicator.usesThreadedAnimation = false
        _loadingProgressIndicator.startAnimation(self)
        _loadingPanel.display()

        _loadingPanelModalSession = NSApplication.shared.beginModalSession(for: _loadingPanel)
        _lastEventLoopRun = 0
        _cancelPressed = false
    }

    // starts the panel as a sheet immediately
    @objc(initAsSheetForWindow:) init(asSheetFor window: NSWindow) {
        super.init()
        loadPanelNib()

        _loadingPanel.isReleasedWhenClosed = false  // see init() for the reason

        window.beginSheet(_loadingPanel, completionHandler: nil)
        _loadingPanel.worksWhenModal = true

        _loadingProgressIndicator.usesThreadedAnimation = false
        _loadingProgressIndicator.startAnimation(self)

        // no modal session when shown as a sheet
        _loadingPanelModalSession = nil
        _lastEventLoopRun = 0
        _cancelPressed = false
    }

    private func loadPanelNib() {
        var topLevelObjects: NSArray?
        if !Bundle.main.loadNibNamed("LoadingPanel", owner: self, topLevelObjects: &topLevelObjects) {
            assertionFailure("couldn't load LoadingPanel.nib")
        }
        _nibTopLevelObjects = topLevelObjects as? [Any]
    }

    deinit {
        if _loadingPanel != nil {
            close()
        }
    }

    @objc func close() {
        if _loadingPanel.isSheet {
            _loadingPanel.sheetParent?.endSheet(_loadingPanel)
            _loadingPanel.close()  // just hides; ownership stays with _nibTopLevelObjects
        } else {
            if let session = _loadingPanelModalSession {
                NSApplication.shared.endModalSession(session)
            }
            _loadingPanelModalSession = nil
            closeNoModalEnd()
            return
        }
        _loadingPanel = nil
        _loadingProgressIndicator = nil
        _loadingTextField = nil
        _loadingCancelButton = nil
    }

    @objc func closeNoModalEnd() {
        // the sender asked us not to end the modal session (e.g. it hit an exception)
        _loadingPanelModalSession = nil
        _loadingPanel?.close()
        _loadingPanel = nil
        _loadingProgressIndicator = nil
        _loadingTextField = nil
        _loadingCancelButton = nil
    }

    @objc(enableCancelButton:) func enableCancelButton(_ enable: Bool) {
        _loadingCancelButton.isEnabled = enable
    }

    @objc func cancelPressed() -> Bool { _cancelPressed }

    @objc func startAnimation() { _loadingProgressIndicator.startAnimation(nil) }
    @objc func stopAnimation() { _loadingProgressIndicator.stopAnimation(nil) }

    // message will be shown next time runEventLoop is called
    @objc(setMessageText:) func setMessageText(_ msg: String?) { _message = msg }

    @objc func runEventLoop() {
        // only refresh the UI every 0.2s; pumping the event loop more often eats
        // over half the total scan time
        let currentTime = getTime()
        let pumpEventLoop = _lastEventLoopRun == 0 || subtractTime(currentTime, _lastEventLoopRun) > 0.2

        if let message = _message {
            _loadingTextField.stringValue = message
            setMessageText(nil)  // so it isn't reapplied next time
            if !pumpEventLoop {
                _loadingTextField.displayIfNeeded()
            }
        }

        if pumpEventLoop {
            _lastEventLoopRun = currentTime
            if let session = _loadingPanelModalSession {
                if NSApplication.shared.runModalSession(session) != .continue {
                    assertionFailure("run loop stopped by unknown party")
                }
            } else {
                RunLoop.current.run(until: Date())
            }
        }
    }

    @IBAction func cancel(_ sender: Any?) {
        _cancelPressed = true
        _loadingCancelButton.isEnabled = false
    }
}
