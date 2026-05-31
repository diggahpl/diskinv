#!/bin/sh
#
# Build a release of Disk Inventory Xs with a consistent code signature.
#
# The treemap rendering code (formerly TreeMapView.framework) is now compiled
# directly into the app target, so there is no embedded framework to build,
# stage, or re-sign separately. This script just builds the app and signs it
# with Hardened Runtime.
#
# Override the signing identity by exporting SIGN_IDENTITY before running:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./BuildRelease.sh
# The default is "-" (ad-hoc), which is enough for local builds but is not
# suitable for distribution. See NOTARIZATION.md for the distribution recipe.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PROJECT="$SCRIPT_DIR/Disk Inventory X.xcodeproj"
ENTITLEMENTS="$SCRIPT_DIR/Disk Inventory X.entitlements"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

# Build with ad-hoc signing regardless of project settings; we re-sign with
# the real identity at the end. This means BuildRelease.sh works on machines
# that don't have the project's hard-coded development team certificate.
XCODEBUILD_SIGN_FLAGS="CODE_SIGN_IDENTITY= CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"

# Build arm64-only. The "s" in "Disk Inventory Xs" is for Silicon.
XCODEBUILD_ARCH_FLAGS="ARCHS=arm64 VALID_ARCHS=arm64 ONLY_ACTIVE_ARCH=NO"

echo "==> Building app"
rm -rf "$SCRIPT_DIR/build"
# shellcheck disable=SC2086
xcodebuild \
    -project "$APP_PROJECT" \
    -configuration Release \
    $XCODEBUILD_SIGN_FLAGS \
    $XCODEBUILD_ARCH_FLAGS \
    build

APP_BUILT_DIR="$(xcodebuild -project "$APP_PROJECT" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR =/ {print $2; exit}')"
APP_WRAPPER_NAME="$(xcodebuild -project "$APP_PROJECT" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^ *WRAPPER_NAME =/ {print $2; exit}')"
APP_BUILT="$APP_BUILT_DIR/$APP_WRAPPER_NAME"

if [ ! -d "$APP_BUILT" ]; then
    echo "error: app not found at $APP_BUILT" >&2
    exit 1
fi

echo "==> Re-signing with identity: $SIGN_IDENTITY"
# The explicit main Mach-O sign is required because we pass CODE_SIGNING_ALLOWED=NO
# to xcodebuild, so the linker leaves the binary unsigned and `codesign <bundle>`
# won't propagate a signature to an unsigned inner Mach-O.
EXE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_BUILT/Contents/Info.plist")"
codesign --force --options runtime \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUILT/Contents/MacOS/$EXE_NAME"

codesign --force --options runtime \
    --sign "$SIGN_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUILT"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_BUILT"

echo "==> Done"
echo "    $APP_BUILT"
echo
echo "App Team ID:"
codesign -dvv "$APP_BUILT" 2>&1 | grep -E "TeamIdentifier|Authority|Signature" || true
