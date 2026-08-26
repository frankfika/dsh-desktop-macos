#!/bin/bash
# Build and ad-hoc sign a universal DSH Desktop app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="DSH Desktop"
APP=".build/${APP_NAME}.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)}"
ARCHS="${ARCHS:-arm64 x86_64}"
MACOS_MIN="${MACOS_MIN:-13.0}"

RESDIR_FLAGS=()
PATCHED_RESOURCE_DIR=""
CLT_SWIFT_INC="/Library/Developer/CommandLineTools/usr/include/swift"

cleanup() {
    if [ -n "$PATCHED_RESOURCE_DIR" ] && [ -d "$PATCHED_RESOURCE_DIR" ]; then
        rm -rf "$PATCHED_RESOURCE_DIR"
    fi
}
trap cleanup EXIT

# Some Command Line Tools releases contain two SwiftBridging module maps.
# Use a temporary resource directory without modifying the system installation.
if [ -f "$CLT_SWIFT_INC/module.modulemap" ] && [ -f "$CLT_SWIFT_INC/bridging.modulemap" ]; then
    echo "==> Applying Command Line Tools SwiftBridging workaround"
    PATCHED_RESOURCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dsh-desktop-crt.XXXXXX")"
    mkdir -p "$PATCHED_RESOURCE_DIR/usr/lib" "$PATCHED_RESOURCE_DIR/usr/include"
    ln -s /Library/Developer/CommandLineTools/usr/lib/swift "$PATCHED_RESOURCE_DIR/usr/lib/swift"
    cp -R "$CLT_SWIFT_INC" "$PATCHED_RESOURCE_DIR/usr/include/swift"
    rm -f "$PATCHED_RESOURCE_DIR/usr/include/swift/module.modulemap"
    RESDIR_FLAGS=(-resource-dir "$PATCHED_RESOURCE_DIR/usr/lib/swift")
fi

echo "==> Cleaning build directory"
rm -rf .build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/bin

echo "==> Generating app icon"
swiftc -parse-as-library -O ${RESDIR_FLAGS[@]+"${RESDIR_FLAGS[@]}"} \
    -o .build/icon-gen tools/IconGen.swift
./.build/icon-gen
mkdir -p .build/AppIcon.iconset
sips -z 16 16 .build/icon-1024.png --out .build/AppIcon.iconset/icon_16x16.png >/dev/null
sips -z 32 32 .build/icon-1024.png --out .build/AppIcon.iconset/icon_16x16@2x.png >/dev/null
sips -z 32 32 .build/icon-1024.png --out .build/AppIcon.iconset/icon_32x32.png >/dev/null
sips -z 64 64 .build/icon-1024.png --out .build/AppIcon.iconset/icon_32x32@2x.png >/dev/null
sips -z 128 128 .build/icon-1024.png --out .build/AppIcon.iconset/icon_128x128.png >/dev/null
sips -z 256 256 .build/icon-1024.png --out .build/AppIcon.iconset/icon_128x128@2x.png >/dev/null
sips -z 256 256 .build/icon-1024.png --out .build/AppIcon.iconset/icon_256x256.png >/dev/null
sips -z 512 512 .build/icon-1024.png --out .build/AppIcon.iconset/icon_256x256@2x.png >/dev/null
sips -z 512 512 .build/icon-1024.png --out .build/AppIcon.iconset/icon_512x512.png >/dev/null
cp .build/icon-1024.png .build/AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Compiling for: $ARCHS"
BINARIES=()
for arch in $ARCHS; do
    binary=".build/bin/DSHLauncher-${arch}"
    swiftc -parse-as-library -O -swift-version 5 \
        ${RESDIR_FLAGS[@]+"${RESDIR_FLAGS[@]}"} \
        -target "${arch}-apple-macosx${MACOS_MIN}" \
        -framework SwiftUI -framework AppKit -framework WebKit -framework CoreImage \
        -o "$binary" Sources/DSHLauncher.swift
    BINARIES+=("$binary")
done

if [ "${#BINARIES[@]}" -eq 1 ]; then
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/DSHLauncher"
else
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/DSHLauncher"
fi

echo "==> Assembling app bundle"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/remote-bridge.js "$APP/Contents/Resources/remote-bridge.js"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

echo "==> Verifying bundle"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -archs "$APP/Contents/MacOS/DSHLauncher"

echo
echo "Built: $APP"
echo "Open:  open \"$APP\""
