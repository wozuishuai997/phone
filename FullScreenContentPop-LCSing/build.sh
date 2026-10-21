#!/bin/bash
set -euo pipefail

# Run on macOS with Xcode Command Line Tools installed.
# The resulting dylib is unsigned; inject it into the IPA and sign the app with LCSing.

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
mkdir -p "$OUT"

xcrun --sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min=15.0 \
  -fobjc-arc \
  -fvisibility=hidden \
  -dynamiclib "$ROOT/FullScreenContentPop.m" \
  -framework Foundation \
  -framework UIKit \
  -install_name '@rpath/FullScreenContentPop.dylib' \
  -o "$OUT/FullScreenContentPop.dylib"

echo "Built: $OUT/FullScreenContentPop.dylib"
echo "Next: inject into a test IPA with LCSing, then re-sign the entire app."
