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

The app is dark, luminous and glassy: a deep-space canvas, one cyan accent, Liquid Glass chrome and neon cushions. Dark appearance is forced app-wide (`Theme.install()` in `AppController`).

- **Palette and tokens** live in `src/Theme.swift`: `space` (#070A12 canvas), `spaceRaised`, `accent` (cyan #00E5FF), `hairline`, `freeSpace` / `otherSpace` (dim void colors), `numericFont` (monospaced digits for sizes), `symbolImage` (SF Symbols for the toolbar). The system accent for stock controls is the `AccentColor` asset (a deeper cyan with enough contrast for white text).
- **File-kind colors**: `src/FileTypeColors.swift`, a 12-color neon palette (`paletteHex`) handed out in order of first use, then dim slate greys. It is normalized through `TMVCushionRenderer.normalize`. Keep it colorblind-safe: `python3 tools/palette_check.py` must keep reporting a CIEDE2000 distance of at least 5 for normal, protan, deutan and tritan vision.
- **Treemap frames**: `src/TreeMap/TreeMapGlow.swift` draws the selection (white-hot core, cyan bloom, dark keyline) and hover (faint veil and edge) frames, and fills the cache bitmap with the deep-space background before the cushions are shaded; `TreeMapView.draw` calls it.
- **Treemap finish**: `src/TreeMap/TreeMapPolish.swift` runs on the bitmap after the cushion shader (`TMVCushionRenderer` and its pinned pixel hashes stay untouched): color grading (saturation and tone curve), a rim light on each cell's top and left edge, a deep-space gutter on its bottom and right edge, a flattened cushion with a diagonal sheen on large cells (the shader's cushions alone look like pillows), and a luminous outline around every folder (`depth` 1 is the thickest), so the tree shows behind the cells. `TreeMapView.renderContent(into:)` chains background, cushions and finish; tune the look there, not in the shader.
- **Treemap labels**: `src/TreeMap/TreeMapLabels.swift` collects, when the cache bitmap is rendered, the names to write on it (a centered name and size on big files, a pill with the folder's name at the upper left of big folders, never two overlapping) and `TreeMapView.draw` paints them over the cached bitmap. They are not part of the bitmap, because text cannot be drawn into its 24-bit RGB format. The name comes from the delegate's tool tip text.
- **Glass**: the toolbar is a unified toolbar built in `DIXToolbarWindowController` from `MainWindowToolbar.toolbar` (SF Symbols named in the plist); the readout under the panels is `StatusBarView`, an `NSGlassEffectView` that adopts the nib's two text fields. `MainWindowController.applyChrome()` rounds and hairline-edges the panels on the space canvas.
- **Files outline**: a view-based `NSOutlineView` (the nib's cell-based one turns view-based by the delegate answering `outlineView(_:viewFor:item:)`): `FileOutlineCells.swift` has the name cell, the size cell (with a bar comparing the item with its largest sibling), the glass selection row and the flat header; `FileIcons.swift` picks SF Symbols tinted with the kind's treemap color (applications keep their own icon). The old `ImageAndTextCell` placed icons by hand and broke with the outline's indentation; it only serves the selection list now.
- **Sidebar**: the kinds and selection drawers are gone; `SidebarView` (two tabs) holds their nib views inside the window at the right edge, `MainWindowController.showSidebar/hideSidebar/toggleSidebar` drive it, and `sidebarDidChangeNotification` tells the selection list when to update.
- **Selection** in the cell-based tables (kinds, selection list) is drawn by `GlowSelection` from `highlightSelection(inClipRect:)` in `DIXTableView`; the outline's rows draw it themselves (`FileRowView`). `FlatHeaderView.install(in:)` gives every table the flat header.
- **Accessibility**: Reduce Transparency swaps the glass for a solid panel (`StatusBarView`) and drops the halo; Increase Contrast adds white outlines and thicker borders. Both are read through `Theme.reduceTransparency` / `Theme.increaseContrast` and re-evaluated on `Theme.accessibilityOptionsChanged`.
- **App icon**: generated by `python3 tools/make_app_icon.py` (numpy and Pillow) into the `AppIcon` asset set; edit the script, not the PNGs.

## Things to know

- `NSURL` purges its cached resource values after each run-loop pass, so the scanner copies the values it needs into its own cache (`NSURL-Extensions.swift`).
- The scan runs on the main thread and keeps the UI alive by pumping a modal session from `LoadingPanelController.runEventLoop()`.
- Privacy-protected folders (Documents, Desktop, Downloads, ...) are touched up front to trigger the macOS consent dialogs (`NSFileManager-Extensions.swift`).
- The nib still holds the two `NSDrawer`s, but only as carriers: `MainWindowController.installSidebar()` moves their content views into the sidebar and the drawers are never opened.
- `TMVItem` asks the data source for `isLeaf()` and `weight()` once, in `init` and `refresh(withItem:)`. A change to the tree or to sizes must therefore go through `TreeMapView.reloadData()`, which `TreeMapViewController` already calls on zoom, view option and item changes.
- `TreeMapView` is flipped, its cache image is not. `draw(_:)` mirrors the source rect when it paints only part of the view (hover frames repaint just one cell); `TreeMapViewDrawTests` pins that.
- Cushion rendering walks the tree on the main thread (the delegate picks each leaf's color there), then shades the collected leaves concurrently in `TMVCushionRenderer.render(_:inBitmap:)`. That relies on the leaf rects never overlapping.

## License

GPL v3
