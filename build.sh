#!/bin/bash
#
# Builds Wallflow.app (universal binary, ad-hoc signed).
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Wallflow.app"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
MIN_MACOS="13.0"
BUNDLE_ID="com.shizhengchen.wallflow"

echo "▸ SDK: $SDK"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/obj"

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

if compgen -G "$ROOT/Resources/Demo/*.mp4" > /dev/null; then
  cp "$ROOT"/Resources/Demo/*.mp4 "$APP/Contents/Resources/"
fi

SOURCES=("$ROOT"/Sources/*.swift)

build_arch() {
  local arch="$1"
  echo "▸ Compiling $arch"
  xcrun swiftc \
    -O -whole-module-optimization \
    -swift-version 5 \
    -sdk "$SDK" \
    -target "${arch}-apple-macos${MIN_MACOS}" \
    -framework Cocoa \
    -framework AVFoundation \
    -framework SwiftUI \
    -framework ServiceManagement \
    -framework IOKit \
    "${SOURCES[@]}" \
    -o "$BUILD/obj/Wallflow-$arch"
}

build_arch arm64
build_arch x86_64

echo "▸ Creating universal binary"
lipo -create \
  "$BUILD/obj/Wallflow-arm64" \
  "$BUILD/obj/Wallflow-x86_64" \
  -output "$APP/Contents/MacOS/Wallflow"

echo "▸ Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --verbose=1 "$APP"

echo "▸ Built: $APP"
lipo -info "$APP/Contents/MacOS/Wallflow"
