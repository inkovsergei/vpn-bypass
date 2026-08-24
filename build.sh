#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/VPN Bypass.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"

clang \
    -fobjc-arc \
    -O2 \
    -mmacosx-version-min=14.0 \
    -framework Cocoa \
    "$PROJECT_DIR/Sources/main.m" \
    -o "$MACOS_DIR/VPNBypass"

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/Resources/vpn-bypass-runner.sh" "$RESOURCES_DIR/vpn-bypass-runner.sh"
chmod 755 "$RESOURCES_DIR/vpn-bypass-runner.sh"

clang -fobjc-arc -framework Cocoa "$PROJECT_DIR/IconMaker.m" -o "$BUILD_DIR/icon-maker"
"$BUILD_DIR/icon-maker" "$BUILD_DIR/icon-1024.png"

for entry in \
    "16 icon_16x16.png" "32 icon_16x16@2x.png" \
    "32 icon_32x32.png" "64 icon_32x32@2x.png" \
    "128 icon_128x128.png" "256 icon_128x128@2x.png" \
    "256 icon_256x256.png" "512 icon_256x256@2x.png" \
    "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
    dimension="${entry%% *}"
    filename="${entry#* }"
    sips -z "$dimension" "$dimension" "$BUILD_DIR/icon-1024.png" --out "$ICONSET_DIR/$filename" >/dev/null
done

cp "$BUILD_DIR/icon-1024.png" "$RESOURCES_DIR/AppIcon.png"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
