# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Platform

Disk Inventory X is a document-based AppKit app written in Swift that visualizes disk space usage with treemaps.

- Targets macOS 27 and later, Apple Silicon (arm64) only: `MACOSX_DEPLOYMENT_TARGET = 27.0` and `ARCHS = arm64` in `src/Disk Inventory X.xcodeproj`. Do not add an x86_64 slice or fallbacks for older systems; prefer current APIs (`UTType`, Swift concurrency) over deprecated ones.
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

Tests live in `src/Tests/` (XCTest, `@testable import Disk_Inventory_Xs`). `FSItemScanTests` scans a fixture tree that `TestFixtures` generates into the gitignored `TestFixtures/` folder; `FSItemSizePropagationTests` builds its own tree in a temporary directory. A new test file must be added to the `Disk Inventory XTests` target in the Xcode project. Benchmarks: `benchmarkLayoutCalculation` and `benchmarkRendering` in `TreeMapView.swift`.

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
- `FileKindsTableController` - file kind statistics drawer
- `SelectionListController` - selection list drawer

## Key Design Patterns

- **Document-based app**: `NSDocument` lifecycle per scan
- **Notification-based**: loose coupling between UI components
- **Delegate pattern**: `FSItem` customization without subclassing
- **Value transformers**: `FileSizeTransformer`, `VolumeNameTransformer` for bindings

## Things to know

- `NSURL` purges its cached resource values after each run-loop pass, so the scanner copies the values it needs into its own cache (`NSURL-Extensions.swift`).
- The scan runs on the main thread and keeps the UI alive by pumping a modal session from `LoadingPanelController.runEventLoop()`.
- Privacy-protected folders (Documents, Desktop, Downloads, ...) are touched up front to trigger the macOS consent dialogs (`NSFileManager-Extensions.swift`).
- `NSDrawer` (kinds and selection drawers) is deprecated but still used.

## License

GPL v3
