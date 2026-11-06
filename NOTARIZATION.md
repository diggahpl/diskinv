# Notarized release recipe

`src/BuildRelease.sh` produces a working .app out of the box, signed ad-hoc.
Ad-hoc is enough to launch on the maintainer's machine and on any machine
where the downloaded .app has had its quarantine attribute removed
(`xattr -dr com.apple.quarantine "Disk Inventory Xs.app"`), but Gatekeeper
will still warn unknown users on first launch. To ship a release that
launches cleanly for everyone, sign with a Developer ID Application identity
and notarize.

## One-time setup

1. Apple Developer Program membership and a **Developer ID Application**
   certificate in the maintainer's login keychain.
2. An app-specific password from <https://appleid.apple.com> (label it
   "notarytool" or similar) and a stored credential profile:

   ```sh
   xcrun notarytool store-credentials "dix-notarize" \
       --apple-id "you@example.com" \
       --team-id "65J464P6J4" \
       --password "abcd-efgh-ijkl-mnop"
   ```

## Per-release

```sh
# 1. Build, signed with the real identity (arm64-only).
SIGN_IDENTITY="Developer ID Application: Your Name (65J464P6J4)" \
    src/BuildRelease.sh

APP="src/build/Release/Disk Inventory Xs.app"

# 2. Zip for notarytool (notarization rejects bare .app bundles).
ditto -c -k --keepParent "$APP" "DiskInventoryXs.zip"

# 3. Submit and wait.
xcrun notarytool submit "DiskInventoryXs.zip" \
    --keychain-profile "dix-notarize" \
    --wait

# 4. Staple the notarization ticket onto the .app so it works offline.
xcrun stapler staple "$APP"

# 5. Verify Gatekeeper would accept it on a clean machine.
spctl -a -vvv -t execute "$APP"
# Expected: "accepted ... source=Notarized Developer ID"
```

## Notes

- The build script always uses `--options runtime` (Hardened Runtime). The entitlements file
  `src/Disk Inventory X.entitlements` is empty: the `disable-library-validation` entitlement it once carried
  was for an embedded framework that no longer exists (the treemap is compiled into the app).
- If notarization fails with "The signature of the binary is invalid", check
  that the framework's inner Mach-O carries `flags=...,runtime`. The build
  script does this; manual re-signs sometimes forget the runtime option.
- Ship the stapled `.app` inside a `.dmg` or `.zip`. Re-running `stapler
  validate` against the staged copy is a good last sanity check before
  upload.
