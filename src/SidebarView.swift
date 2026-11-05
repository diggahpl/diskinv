//
//  SidebarView.swift
//  Disk Inventory Xs
//
//  The panel at the right edge of the window that replaced the kinds and the
//  selection drawers (NSDrawer is deprecated, and its chrome belongs to another
//  era): two tabs over the two former drawer contents, which keep their nib
//  wiring. MainWindowController owns it and decides when it is shown.
//
//  GPL v3
//

import Cocoa

final class SidebarView: NSView {

    enum Pane: Int, CaseIterable {
        case kinds, selection

        var title: String {
            switch self {
            case .kinds: return NSLocalizedString("Kinds", comment: "sidebar tab: file kind statistics")
            case .selection: return NSLocalizedString("Selection", comment: "sidebar tab: list of the selected kind's files")
            }
        }
    }

    /// 360 points, less in a narrow window so the outline and the map keep their room.
    static func width(forContentWidth contentWidth: CGFloat) -> CGFloat {
        min(360, max(220, (contentWidth * 0.28).rounded()))
    }

    private let tabs = NSSegmentedControl()
    /// The details of the selected item, under the tabs.
    let infoCard = InfoCardView(frame: .zero)
    private var contents: [Pane: NSView] = [:]
    private(set) var selectedPane: Pane = .kinds

    /// Called when the user switches the tab.
    var onPaneChange: ((Pane) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        tabs.segmentCount = Pane.allCases.count
        for pane in Pane.allCases {
            tabs.setLabel(pane.title, forSegment: pane.rawValue)
        }
        tabs.segmentDistribution = .fillEqually
        tabs.controlSize = .regular
        tabs.trackingMode = .selectOne
        tabs.selectedSegment = selectedPane.rawValue
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        addSubview(tabs)
        addSubview(infoCard)
    }

    /// Whether the card is shown under the tabs.
    var infoShown = true {
        didSet {
            infoCard.isHidden = !infoShown
            needsLayout = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("SidebarView is created in code")
    }

    func install(kinds: NSView, selection: NSView) {
        for (pane, view) in [(Pane.kinds, kinds), (Pane.selection, selection)] {
            contents[pane] = view
            view.removeFromSuperview()
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        select(selectedPane)
        needsLayout = true
    }

    func select(_ pane: Pane) {
        selectedPane = pane
        tabs.selectedSegment = pane.rawValue
        for (candidate, view) in contents {
            view.isHidden = candidate != pane
        }
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        guard let pane = Pane(rawValue: sender.selectedSegment) else { return }
        select(pane)
        onPaneChange?(pane)
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        let tabsHeight: CGFloat = 28
        tabs.frame = NSRect(x: inset, y: bounds.height - inset - tabsHeight,
                            width: bounds.width - 2 * inset, height: tabsHeight)

        // the card takes about two fifths of the height, never less than its list needs
        let infoHeight: CGFloat = infoShown ? min(max((bounds.height * 0.42).rounded(), 240), 380) : 0
        infoCard.frame = NSRect(x: 0, y: 0, width: bounds.width, height: infoHeight)

        let area = NSRect(x: 0, y: infoHeight, width: bounds.width, height: max(tabs.frame.minY - 8 - infoHeight, 0))
        for view in contents.values {
            view.frame = area
            fitColumns(in: view)
        }
    }

    // the nib's column widths were made for a drawer of another width
    private func fitColumns(in view: NSView) {
        if let table = view as? NSTableView {
            TableColumns.fit(table)
            watchWidth(of: table)
        } else {
            view.subviews.forEach(fitColumns)
        }
    }

    // a scroller that shows up after the layout narrows what the columns have
    private var watched: [ObjectIdentifier] = []

    private func watchWidth(of table: NSTableView) {
        guard let clip = table.enclosingScrollView?.contentView, !watched.contains(ObjectIdentifier(table)) else { return }
        watched.append(ObjectIdentifier(table))
        clip.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip,
                                               queue: .main) { [weak table] _ in
            if let table = table { TableColumns.fit(table) }
        }
    }
}
