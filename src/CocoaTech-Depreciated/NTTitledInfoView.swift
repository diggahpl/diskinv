//
//  NTTitledInfoView.swift
//  Path Finder
//
//  Swift port of NTTitledInfoView.{h,m} (plus its private NTFastTextView).
//  A flipped NSView that lays out an array of NTTitledInfoPairs as right-aligned
//  titles paired with left-aligned info text, drawing the alternating
//  background lines and the title-column shadow behind them.
//
//  Created by sgehrman on Mon Aug 06 2001.
//  Copyright (c) 2001 CocoaTech. All rights reserved.
//

import Cocoa

private let kColumnDivider: CGFloat = 4

@objc(NTTitledInfoView)
class NTTitledInfoView: NSView {

    private weak var _target: AnyObject?

    private var _pairs: [NTTitledInfoPair]?
    private var _titleViews: [NTFastTextView] = []
    private var _infoViews: [NTFastTextView] = []

    private var _titleWidth: CGFloat = 0
    private var _horizontalOffset: CGFloat = 6
    private var _verticalOffset: CGFloat = 6

    private var _inFrameChanged = false

    private var _backgroundLineOffsets: [CGFloat] = []
    private var _backgroundShadowOffset: CGFloat = 72

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        autoresizesSubviews = true
        autoresizingMask = [.width, .height]

        reset()

        _horizontalOffset = 6
        _verticalOffset = 6
        _backgroundShadowOffset = 72
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        autoresizesSubviews = true
        autoresizingMask = [.width, .height]

        reset()

        _horizontalOffset = 6
        _verticalOffset = 6
        _backgroundShadowOffset = 72
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc(setTarget:)
    func setTarget(_ target: AnyObject?) {
        _target = target // don't retain
    }

    override var isFlipped: Bool { true }

    @objc(setHorizontalOffset:)
    func setHorizontalOffset(_ offset: Int) {
        _horizontalOffset = CGFloat(offset)
    }

    @objc(setVerticalOffset:)
    func setVerticalOffset(_ offset: Int) {
        _verticalOffset = CGFloat(offset)
    }

    @objc(setWithArray:)
    func setWithArray(_ pairs: [NTTitledInfoPair]?) {
        // clear out the existing views
        reset()

        if let pairs = pairs {
            _pairs = pairs

            createViews()
            positionViews()
        }

        needsDisplay = true
    }

    override func draw(_ rect: NSRect) {
        let viewWindow = self.window
        var disabledFlush = false

        // disable window flush for speed
        if let viewWindow = viewWindow, viewWindow.isFlushWindowDisabled {
            disabledFlush = true
            viewWindow.disableFlushing()
        }

        doDrawRect(rect)

        // restore
        if disabledFlush {
            viewWindow?.enableFlushing()
        }
    }

    // set to resize automatically for the width
    override func resizeSubviews(withOldSize oldBoundsSize: NSSize) {
        if !_inFrameChanged {
            _inFrameChanged = true

            let viewWindow = self.window
            var disabledFlush = false

            // disable window flush for speed
            if let viewWindow = viewWindow, viewWindow.isFlushWindowDisabled {
                disabledFlush = true
                viewWindow.disableFlushing()
            }

            // first must set a valid frame
            if let scrollView = enclosingScrollView {
                frame = scrollView.documentVisibleRect
            }

            positionViews()

            // restore
            if disabledFlush {
                viewWindow?.enableFlushing()
            }

            _inFrameChanged = false
        }
    }

    // MARK: - Private (was NTTitledInfoView (Private))

    private func doDrawRect(_ rect: NSRect) {
        drawBackgroundShadow()
        drawBackgroundLines()

        super.draw(rect)
    }

    private func resizeFrameToFit() {
        let scrollView = enclosingScrollView
        let height = totalHeight()

        if let scrollView = scrollView, height != 0 {
            var newSize = NSSize(width: scrollView.documentVisibleRect.size.width, height: height)

            // never be smaller than the current visible rect
            newSize.height = max(newSize.height, scrollView.documentVisibleRect.size.height)
            newSize.width = max(newSize.width, scrollView.documentVisibleRect.size.width)

            if newSize.height != frame.size.height || newSize.width != frame.size.width {
                setFrameSize(NSSize(width: newSize.width, height: newSize.height))
            }
        } else if let scrollView = scrollView {
            setFrameSize(scrollView.documentVisibleRect.size)
        }

        resetBackgroundShadowOffset()
        resetBackgroundLineOffsets()
    }

    private func reset() {
        for view in _titleViews {
            view.removeFromSuperview()
        }

        for view in _infoViews {
            view.removeFromSuperview()
        }

        _titleViews = []
        _infoViews = []
        _pairs = nil
        _titleWidth = 0

        resizeFrameToFit()
    }

    private func createViews() {
        guard let pairs = _pairs else { return }

        for pair in pairs {
            // init the text views
            let titleView = NTFastTextView.fastTextView(pair.title(), action: nil, target: nil, attributes: titleAttributes())
            _titleViews.append(titleView)
            addSubview(titleView)

            let infoView = NTFastTextView.fastTextView(pair.info(), action: pair.action(), target: pair.target(), attributes: infoAttributes())
            _infoViews.append(infoView)
            addSubview(infoView)

            // calc the widest title
            let titleSize = titleView.sizeForBounds(NSRect(x: 0, y: 0, width: 1000, height: 10000))
            if titleSize.width > _titleWidth {
                _titleWidth = titleSize.width
            }
        }
    }

    private func positionViews() {
        let cnt = _titleViews.count

        if cnt > 0 {
            var rect = bounds.insetBy(dx: _horizontalOffset, dy: _verticalOffset)

            rect.size.width = max(_titleWidth + 100, rect.size.width) // enforce a minimum width
            rect.size.height = 10000 // give enough vertical room to work with

            var titleRect = NSRect.zero
            var infoRect = NSRect.zero
            var rectBetween = NSRect.zero
            NSDivideRect(rect, &titleRect, &infoRect, _titleWidth + kColumnDivider, .minX)
            NSDivideRect(infoRect, &rectBetween, &infoRect, kColumnDivider, .minX)

            for i in 0..<cnt {
                let titleView = _titleViews[i]
                let infoView = _infoViews[i]

                let titleSize = titleView.sizeForBounds(titleRect)
                let infoSize = infoView.sizeForBounds(infoRect)

                var itemRect = NSRect.zero
                NSDivideRect(titleRect, &itemRect, &titleRect, max(titleSize.height, infoSize.height), .minY)
                itemRect.size.height = titleSize.height
                titleView.frame = itemRect

                NSDivideRect(infoRect, &itemRect, &infoRect, max(titleSize.height, infoSize.height), .minY)
                itemRect.size.height = infoSize.height
                infoView.frame = itemRect
            }
        }

        resizeFrameToFit()
    }

    private func totalHeight() -> CGFloat {
        var height: CGFloat = 0

        // just look at the last infoView
        if let lastView = _infoViews.last {
            height = _verticalOffset * 2
            height = lastView.frame.maxY + _verticalOffset
        }

        return height
    }

    // =========================================================================

    private func resetBackgroundLineOffsets() {
        _backgroundLineOffsets = []

        if !_infoViews.isEmpty {
            let bounds = self.bounds

            // draw lines
            for infoView in _infoViews {
                var viewRect = infoView.frame

                viewRect.size.width = bounds.size.width
                viewRect.origin.y += viewRect.size.height - 1

                _backgroundLineOffsets.append(viewRect.origin.y)
            }
        }
    }

    private func resetBackgroundShadowOffset() {
        if let firstTitle = _titleViews.first {
            let bounds = self.bounds
            var viewRect = firstTitle.frame

            viewRect.size.height = bounds.size.height
            viewRect.size.width += (kColumnDivider / 2) + (viewRect.origin.x - bounds.origin.x)

            _backgroundShadowOffset = viewRect.size.width
        }
    }

    private func titleShadowColor() -> NSColor {
        NTTitledInfoView._titleShadowColor
    }

    private static let _titleShadowColor: NSColor =
        NSColor(calibratedRed: 0.6, green: 0.6, blue: 0.9, alpha: 0.1).withAlphaComponent(0.1)

    private func infoLineColor() -> NSColor {
        NTTitledInfoView._infoLineColor
    }

    private static let _infoLineColor: NSColor =
        NSColor(calibratedRed: 0.6, green: 0.6, blue: 0.9, alpha: 0.1)

    private func drawBackgroundShadow() {
        var viewRect = bounds

        viewRect.size.width = _backgroundShadowOffset

        titleShadowColor().set()
        NSBezierPath.fill(viewRect)
    }

    private func drawBackgroundLines() {
        let bounds = self.bounds
        var viewRect = bounds

        var whiteLineColor = NSColor.white.withAlphaComponent(0.7)
        if #available(macOS 10.14, *) {
            whiteLineColor = NSColor.separatorColor
        }

        // draw lines
        for offset in _backgroundLineOffsets {
            viewRect = bounds

            viewRect.origin.y = offset
            viewRect.size.height = 1

            viewRect.size.width += _backgroundShadowOffset

            whiteLineColor.set()
            NSBezierPath.fill(viewRect)

            viewRect.origin.x += _backgroundShadowOffset
            viewRect.size.width = bounds.size.width

            infoLineColor().set()
            NSBezierPath.fill(viewRect)
        }

        var lastLineHeight: CGFloat = 12.0
        if _backgroundLineOffsets.count > 2 {
            lastLineHeight = _backgroundLineOffsets[_backgroundLineOffsets.count - 1]
                - _backgroundLineOffsets[_backgroundLineOffsets.count - 2]
        }

        let maxBounds = min(bounds.maxY, 10000.0) // had a strange bug where bounds was like 10e23 and looped forever, bounds was not set or negative or something
        while viewRect.origin.y < maxBounds {
            viewRect.origin.y += lastLineHeight
            viewRect.size.height = 1.0

            viewRect.origin.x = bounds.origin.x
            viewRect.size.width += _backgroundShadowOffset

            whiteLineColor.set()
            NSBezierPath.fill(viewRect)

            viewRect.origin.x = bounds.origin.x + _backgroundShadowOffset
            viewRect.size.width = bounds.size.width

            infoLineColor().set()
            NSBezierPath.fill(viewRect)
        }
    }

    private func titleAttributes() -> [NSAttributedString.Key: Any] {
        NTTitledInfoView._titleAttributes
    }

    private static let _titleAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .right
        paragraphStyle.lineBreakMode = .byWordWrapping

        return [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.boldSystemFont(ofSize: 10),
            .foregroundColor: NSColor.controlTextColor,
        ]
    }()

    private func infoAttributes() -> [NSAttributedString.Key: Any] {
        NTTitledInfoView._infoAttributes
    }

    private static let _infoAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byWordWrapping

        return [
            .paragraphStyle: paragraphStyle,
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.controlTextColor,
        ]
    }()
}

// =====================================================================================================

private class NTFastTextView: NSView {

    private let _textString: String
    private let _attributes: [NSAttributedString.Key: Any]
    private let _action: Selector?
    private weak var _target: AnyObject?

    private init(string title: String?, action: Selector?, target: AnyObject?, attributes: [NSAttributedString.Key: Any]) {
        _textString = title ?? ""
        _attributes = attributes
        _action = action
        _target = target
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    class func fastTextView(_ title: String?, action: Selector?, target: AnyObject?, attributes: [NSAttributedString.Key: Any]) -> NTFastTextView {
        NTFastTextView(string: title, action: action, target: target, attributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        if let target = _target, let action = _action {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    override var isFlipped: Bool { true }

    func sizeForBounds(_ bounds: NSRect) -> NSSize {
        let stringBounds = (_textString as NSString).boundingRect(
            with: bounds.size,
            options: .usesLineFragmentOrigin,
            attributes: _attributes)

        return NSSize(width: min(bounds.size.width, stringBounds.size.width), height: stringBounds.size.height)
    }

    override func draw(_ rect: NSRect) {
        let bounds = self.bounds

        (_textString as NSString).draw(in: bounds, withAttributes: _attributes)
    }
}
