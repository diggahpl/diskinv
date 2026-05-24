# Disk Inventory Xs

A macOS app that visualizes disk space usage with treemaps. This is Tjark Derlien's original Objective-C **Disk Inventory X** (1.4b2, 2022) brought forward to run natively on Apple Silicon and clean on modern Xcode / macOS.

The "s" is for Silicon.

## Install

Grab the latest [release](https://github.com/diskinv/diskinv/releases/latest) — `DiskInventoryXs-<version>-arm64.zip`. Unzip, drag `Disk Inventory Xs.app` to `/Applications`, double-click. Releases are notarized and stapled, so no `xattr` workaround or right-click → Open.

Requirements: Apple Silicon Mac, macOS 10.13+.

## Build from source

```sh
src/BuildRelease.sh
```

That builds `TreeMapView.framework` from `treemap/`, builds the app, and produces a self-consistent ad-hoc-signed `.app` at `src/build/Release/Disk Inventory Xs.app` that launches locally without further setup.

To produce a signed/notarizable build, point it at a Developer ID identity in your keychain:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" src/BuildRelease.sh
```

See [`NOTARIZATION.md`](NOTARIZATION.md) for the notarytool + stapler recipe used to cut official releases.

## Layout

- `src/` — the Objective-C app (NSDocument-based, AppKit)
- `treemap/` — the embedded `TreeMapView.framework`
- `src/BuildRelease.sh` — single canonical build entry point (re-signs deeply, arm64-only)

Architectural notes live in [`CLAUDE.md`](CLAUDE.md).

## Disk Inventory Y (Swift rewrite)

A from-scratch SwiftUI rewrite lives in a sibling repository as **Disk Inventory Y**. Same idea, modern stack: `@Observable`, actor-isolated parallel scanning, Canvas-rendered treemap, structured concurrency. Targets macOS 14+. If you want the modern codebase, look there; this repo exists to keep the original Objective-C app alive and shipping.

## Credits

- **Tjark Derlien** — original author of Disk Inventory X (2003–2022)
- **Mahmoud Lababidi** — Apple Silicon port, Xcode 26 warning cleanup, Hardened Runtime fix, notarized release pipeline (2026)

## License

GPL v3 — see source headers. Same license as the original.
