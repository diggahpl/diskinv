#!/bin/bash
#
# Runs the unit-test suite (Disk Inventory XTests).
#
# The tests @testable-import the app module and inject into the app as the test
# host, so the host app and test bundle are built ad-hoc with the hardened
# runtime disabled (otherwise library validation refuses to load the test
# bundle). These overrides are passed on the command line only — they do NOT
# change the project's normal Debug/Release signing.
#
# The fixture tree (files 2 MB down, nested in folders) is generated on first
# run under <repo>/TestFixtures (gitignored); see Tests/TestFixtures.swift.
#
# Usage:  ./run-tests.sh            # run all tests
#         ./run-tests.sh -only-testing:...   # extra xcodebuild args are forwarded
#
set -euo pipefail
cd "$(dirname "$0")/src"

pkill -9 -f "Disk Inventory Xs" 2>/dev/null || true

exec xcodebuild test \
  -project "Disk Inventory X.xcodeproj" \
  -scheme "Disk Inventory X" \
  -configuration Debug \
  -destination 'platform=macOS' \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  ENABLE_HARDENED_RUNTIME=NO \
  "$@"
