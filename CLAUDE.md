# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Platform

Disk Inventory Xs is a document-based AppKit app written in Swift that visualizes disk space usage with treemaps.

- Targets macOS 26 (Tahoe) and later, Apple Silicon (arm64) only: `MACOSX_DEPLOYMENT_TARGET = 26.0` and `ARCHS = arm64` in `src/Disk Inventory X.xcodeproj`. There is no macOS 16: Apple went from 15 straight to 26, and the SDK rejects 26-only APIs such as `NSGlassEffectView` under a 16.0 target. Do not add an x86_64 slice or fallbacks for older systems; prefer current APIs (`UTType`, Swift concurrency) over deprecated ones. APIs that exist only in macOS 27 need an `#available(macOS 27, *)` guard.
- The product is called "Disk Inventory Xs" (the "s" is for Silicon). Every user-visible string, message, help page and doc says "Disk Inventory Xs", never plain "Disk Inventory X"; the localized `MainMenu.nib` titles live in both `designable.nib` and `keyedobjects.nib`, so edit both. Only build artifacts keep the old name: the Xcode project, target, scheme, `.entitlements` file, the `Disk Inventory XTests` target and the bundle id `com.derlien.DiskInventoryX`.
- No third-party frameworks. The treemap renderer lives in `src/TreeMap/` and is compiled into the app.
- `treemap/` (the old Objective-C framework project) and `DiskInventoryX/` (an early SwiftUI prototype) are not part of the build.

## Build and test

```bash
# Release build (arm64, ad-hoc signed): src/build/Release/Disk Inventory Xs.app
src/BuildRelease.sh

# Debug build
xcodebuild -project "src/Disk Inventory X.xcodeproj" -configuration Debug

# Unit tests (kills a running "Disk Inventory Xs" first, builds ad-hoc without hardened runtime)
./run-tests.sh
```

### Downloadable build (`build/`)

`build/` at the top of the repo (tracked through the `!/build/` exception in `.gitignore`; `src/build/` stays ignored) holds `DiskInventoryXs-<version>-arm64.zip`, the release that the README offers as a download: signed with `Developer ID Application: Fundacja Zagle Zycia (8QVUBY8PDJ)`, notarized by Apple and stapled. The private key of that certificate lives, non-extractable, in the login keychain of the maintainer's Mac, and the certificate expires on 2027-12-06 (an app notarized before that date keeps launching). To refresh the zip for a new version: export the commit with `git archive HEAD | tar -x -C <empty dir>`, run `SIGN_IDENTITY="Developer ID Application: Fundacja Zagle Zycia (8QVUBY8PDJ)" src/BuildRelease.sh` there (it adds the secure timestamp the notary service requires), zip the app with `ditto -c -k --keepParent` (never plain `zip`), submit it with `xcrun notarytool submit <zip> --keychain-profile dix-notarize --wait`, run `xcrun stapler staple` on the app, zip it again to `build/DiskInventoryXs-<version>-arm64.zip`, and check it: `codesign --verify --deep --strict`, `spctl -a -vv` must say `Notarized Developer ID`, and the unzipped copy must launch. Then update the file name, size and SHA-256 in the README and delete the old zip. Replace, do not accumulate: every committed zip stays in the history for good. The keychain profile `dix-notarize` (Apple ID, team `8QVUBY8PDJ`, an app-specific password) is created by the user with `xcrun notarytool store-credentials`; never ask for the password in chat. Do not use `notarize.sh`: it, `ExportOptions.plist` and the project's `DEVELOPMENT_TEAM` still name the original maintainer's teams, and it kills every running "Disk Inventory Xs".

Tests live in `src/Tests/` (XCTest, `@testable import Disk_Inventory_Xs`). `FSItemScanTests` scans a fixture tree that `TestFixtures` generates into the gitignored `TestFixtures/` folder; `FSItemSizePropagationTests` builds its own tree in a temporary directory. A new test file must be added to the `Disk Inventory XTests` target in the Xcode project. `TreeMapPerformanceTests` pins the treemap layout, hit-test results and every rendered pixel of a seeded synthetic tree to hashes recorded from the original single-threaded implementation, so any change to the layout or the shader that alters a pixel fails it. Its `testBenchmarkRealFolder` times tree build, layout, rendering and hit testing on a scan of `/Applications` (or `DIX_BENCH_PATH`) at 3000x1800 and only runs when asked, in a Release build: `TEST_RUNNER_DIX_TREEMAP_BENCH=1 xcodebuild test -configuration Release ...` (add `-only-testing:"Disk Inventory XTests/TreeMapPerformanceTests"`). The in-app benchmarks are `benchmarkLayoutCalculation` and `benchmarkRendering` in `TreeMapView.swift`.

## Architecture Overview

### Core Data Model

- **FSItem** (`src/FSItem.swift`): tree node and recursive folder scanner. Children are kept sorted by size, and a size change is propagated to the ancestors through `childChanged(_:oldSize:newSize:)`. Customized through the `FSItemDelegate` protocol (`fsItemEnteringFolder`, `fsItemShouldLookIntoPackages`, `fsItemShouldUsePhysicalFileSize`, ...). Its Objective-C runtime name is `DIXFSItem` because FSKit.framework already defines a class named `FSItem`.
- **FileSystemDoc** (`src/FileSystemDoc.swift`): `NSDocument` subclass holding the root `FSItem`, the zoom stack, the selection, the file kind statistics and the view options. Posts notifications for state changes.
- **FileKindStatistic** (`src/FileKindStatistic.swift`): count and total size of the files of one kind (for example all MP3 files).

### Key Notifications

Components communicate through `NotificationCenter`:
- `.GlobalSelectionChanged` - selection changed
- `.ZoomedItemChanged` - the user zoomed into or out of a folder
- `.FSItemsChanged` - items were modified, deleted or added
- `.ViewOptionChanged` - display options changed

### View Controllers

- `MainWindowController` - primary window coordination
- `TreeMapViewController` - data source and delegate of the treemap (`src/TreeMap/`)
- `FilesOutlineViewController` - left-side file browser
- `FileKindsTableController` - file kind statistics (first tab of the sidebar)
- `SelectionListTableController` - files of one kind (second tab of the sidebar)

## Key Design Patterns

- **Document-based app**: `NSDocument` lifecycle per scan
- **Notification-based**: loose coupling between UI components
- **Delegate pattern**: `FSItem` customization without subclassing
- **Value transformers**: `FileSizeTransformer`, `VolumeNameTransformer` for bindings

## Visual design ("Holo Glass")

The app is dark, luminous and glassy: a deep-space canvas, one cyan accent, Liquid Glass chrome and neon cushions. Dark appearance is forced app-wide (`Theme.install()` in `MyDocumentController.applicationWillFinishLaunching`, because `MyDocumentController` is the nib's application delegate).

- **Palette and tokens** live in `src/Theme.swift`: `space` (#070A12 canvas), `spaceRaised`, `accent` (cyan #00E5FF), `hairline`, `freeSpace` / `otherSpace` (dim void colors), `numericFont` (monospaced digits for sizes), `symbolImage` (SF Symbols for the toolbar). The system accent for stock controls is the `AccentColor` asset (a deeper cyan with enough contrast for white text).
- **File-kind colors**: `src/FileTypeColors.swift`, a 12-color neon palette (`paletteHex`) handed out in order of first use, then dim slate greys. It is normalized through `TMVCushionRenderer.normalize`. Keep it colorblind-safe: `python3 tools/palette_check.py` must keep reporting a CIEDE2000 distance of at least 5 for normal, protan, deutan and tritan vision.
- **Treemap frames**: `src/TreeMap/TreeMapGlow.swift` draws the selection (white-hot core, cyan bloom, dark keyline) and hover (faint veil and edge) frames, and fills the cache bitmap with the deep-space background before the cushions are shaded; `TreeMapView.draw` calls it.
- **Treemap finish**: `src/TreeMap/TreeMapPolish.swift` runs on the bitmap after the cushion shader (`TMVCushionRenderer` and its pinned pixel hashes stay untouched): color grading (saturation and tone curve), a rim light on each cell's top and left edge, a deep-space gutter on its bottom and right edge, a flattened cushion with a diagonal sheen on large cells (the shader's cushions alone look like pillows), and a luminous outline around every folder (`depth` 1 is the thickest), so the tree shows behind the cells. `TreeMapView.renderContent(into:)` chains background, cushions and finish; tune the look there, not in the shader.
- **Treemap labels**: `src/TreeMap/TreeMapLabels.swift` collects, when the cache bitmap is rendered, the names to write on it (a centered name and size on big files, a pill with the folder's name at the upper left of big folders, never two overlapping) and `TreeMapView.draw` paints them over the cached bitmap. They are not part of the bitmap, because text cannot be drawn into its 24-bit RGB format. The name comes from the delegate's tool tip text.
- **Glass**: the toolbar is a unified toolbar built in `DIXToolbarWindowController` from `MainWindowToolbar.toolbar` (SF Symbols named in the plist); the readout under the panels is `StatusBarView`, an `NSGlassEffectView` that adopts the nib's two text fields. `MainWindowController.applyChrome()` rounds and hairline-edges the panels on the space canvas.
- **Files outline**: a view-based `NSOutlineView` (the nib's cell-based one turns view-based by the delegate answering `outlineView(_:viewFor:item:)`): `FileOutlineCells.swift` has the name cell, the size cell (with a bar comparing the item with its largest sibling), the glass selection row and the flat header; `FileIcons.swift` picks SF Symbols tinted with the kind's treemap color (applications keep their own icon). The old `ImageAndTextCell` placed icons by hand and broke with the outline's indentation; it only serves the selection list now.
- **Sidebar**: the kinds and selection drawers are gone; `SidebarView` (two tabs) holds their nib views inside the window at the right edge, `MainWindowController.showSidebar/hideSidebar/toggleSidebar` drive it (it is shown on the kinds tab on first launch and remembers the last tab, or none, in the `SidebarPane` default), and `sidebarDidChangeNotification` tells the selection list when to update. The kinds table keeps its nib bindings but draws its kind column with `ShareBarCell` (a bar for the share of the biggest kind), a chip in the kind's color for the kinds that got a palette color (`FileTypeColors.hasPaletteColor`) and a dim dot for the rest; `TableColumns.fit` sets the column widths. The information about the selected item (or the folder the map shows) is `InfoCardView` at the bottom of the sidebar, in place of the old floating panel (`showInformationPanel:` toggles it; it remembers its state in `SidebarInfoShown`). The sidebar slides in and out unless Reduce Motion is on, and `TableColumns.fit` refits the table columns whenever their visible width changes.
- **Kind focus**: picking a kind in the legend (any selection change of the kinds table that is not the table following the document, see `FileKindsTableController._followingDocument`) posts `KindFocus.changedNotification`. `TreeMapViewController` then colors every cell of another kind `Theme.dimmedKind`, drops their names (`TreeMapView.isItemDimmed`) and shows a pill over the map (`TreeMapView.focusBadge`; a click on it posts the notification without a kind, and the legend lets go of its row). The focus is by kind name, so it survives zooming and reloads.
- **Selection** in the cell-based tables (kinds, selection list) is drawn by `GlowSelection` from `drawRow` in `DIXTableView` (its `selectionHighlightStyle` is `.none`, because the system highlight paints the row's cells grey over the plate); the outline's rows draw it themselves (`FileRowView`). `FlatHeaderView.install(in:)` gives every table the flat header.
- **Accessibility**: Reduce Transparency swaps the glass for a solid panel (`StatusBarView`) and drops the halo; Increase Contrast adds white outlines and thicker borders. Both are read through `Theme.reduceTransparency` / `Theme.increaseContrast` and re-evaluated on `Theme.accessibilityOptionsChanged`.
- **App icon**: generated by `python3 tools/make_app_icon.py` (numpy and Pillow) into the `AppIcon` asset set; edit the script, not the PNGs.

## Things to know

- `NSURL` purges its cached resource values after each run-loop pass, so the scanner copies the values it needs into its own cache (`NSURL-Extensions.swift`).
- `src/PrivacyInfo.xcprivacy` (a resource of the app): no tracking, no collected data, and the required-reason APIs the code really uses (file timestamp 3B52.1 and DDA9.1, disk space 85F4.1, system boot time 35F9.1, user defaults CA92.1). Add a category there when the code starts using another listed API.
- Sandbox (`AppSandbox.swift`, `AppSandbox.isActive` reads `APP_SANDBOX_CONTAINER_ID`): the app sees only what the user hands over (open panel, Open Recent, Finder or Dock open, which the system and `NSDocumentController` turn into sandbox access). "Open Volume" (`DrivesPanelController.openVolume`) therefore shows an open panel that opens inside the volume (`AppSandbox.makeAccessPanel`, button "Scan") instead of opening the path; outside the sandbox it still opens the volume directly. A drop on the window is not supported (the window registers no drag types).
- The scan runs on the main thread and keeps the UI alive by pumping a modal session from `LoadingPanelController.runEventLoop()`.
- Privacy-protected folders (Documents, Desktop, Downloads, ...) are touched up front to trigger the macOS consent dialogs (`NSFileManager-Extensions.swift`). In the sandbox the search paths point into the app's container, so `localPrivacyProtectedFolders()` builds the list from the real home (`getpwuid`); the macOS consent prompts (TCC) still appear, the sandbox does not replace them. `NSAppleMusicUsageDescription` and the other usage strings in `Info.plist` are the prompts' texts.
- The GPL notices of this modified version live in the About panel: `Credits.rtf` (developer of this version, the original author and the Apple Silicon port; edit all four languages) and the `NSHumanReadableCopyright` and `CFBundleGetInfoString` entries of each `InfoPlist.strings`, plus the README's Credits. Keep the original authors' lines when adding names.
- The Help is one page per language, `src/<lang>.lproj/Help/index.htm` (UTF-8, `styles/help.css` follows light and dark, images in `images/`; whole folders are copied into the app, so a new file needs no project entry). `en` is the source; `de` and `es` are copies of it (they were never translated), `fr` is a French translation. When the window changes, redo `overview.jpg` (numbered callouts on a screenshot of the whole window) and `focus.jpg`, on a neutral folder rather than a private one.
- The Help opens in the app's own window (`src/HelpWindowController.swift`, a `WKWebView` on that page), not in Help Viewer: helpd keys books by title and version and finds an app by bundle id, so every registered build of the same id (each development build is one) could open another build's stale book. `Info.plist` therefore has no `CFBundleHelpBook*` keys; `DIXApplication` (the `NSPrincipalClass`) takes `showHelp(_:)`, and `HelpWindowController.install()` (called from `MyDocumentController.applicationWillFinishLaunching`) points the nib's Help menu item at the window. The window is built in `showHelpWindow(_:)`, because an `NSWindowController` made with `init(window: nil)` never calls `loadWindow()`.
- The nib still holds the two `NSDrawer`s, but only as carriers: `MainWindowController.installSidebar()` moves their content views into the sidebar and the drawers are never opened.
- `TMVItem` asks the data source for `isLeaf()` and `weight()` once, in `init` and `refresh(withItem:)`. A change to the tree or to sizes must therefore go through `TreeMapView.reloadData()`, which `TreeMapViewController` already calls on zoom, view option and item changes.
- `TreeMapView` is flipped, its cache image is not. `draw(_:)` mirrors the source rect when it paints only part of the view (hover frames repaint just one cell); `TreeMapViewDrawTests` pins that.
- Cushion rendering walks the tree on the main thread (the delegate picks each leaf's color there), then shades the collected leaves concurrently in `TMVCushionRenderer.render(_:inBitmap:)`. That relies on the leaf rects never overlapping.

## License

GPL v3
