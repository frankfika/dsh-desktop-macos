#!/bin/bash
# Package an existing app bundle as ZIP and DMG release artifacts.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="DSH Desktop"
APP=".build/${APP_NAME}.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)}"

if [ ! -d "$APP" ]; then
    echo "Missing $APP. Run ./build.sh first." >&2
    exit 1
fi
if [ -z "$VERSION" ]; then
    echo "Could not determine app version." >&2
    exit 1
fi

DIST=".build/dist"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/dsh-desktop-release.XXXXXX")"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

mkdir -p "$DIST" "$STAGING/DSH Desktop"
rm -f "$DIST/DSH-Desktop-${VERSION}.zip" "$DIST/DSH-Desktop-${VERSION}.dmg"

ditto "$APP" "$STAGING/DSH Desktop/$APP_NAME.app"
ln -s /Applications "$STAGING/DSH Desktop/Applications"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/DSH-Desktop-${VERSION}.zip"
hdiutil create -quiet -volname "DSH Desktop" -srcfolder "$STAGING/DSH Desktop" \
    -ov -format UDZO "$DIST/DSH-Desktop-${VERSION}.dmg"

shasum -a 256 "$DIST/DSH-Desktop-${VERSION}.zip" "$DIST/DSH-Desktop-${VERSION}.dmg" \
    > "$DIST/SHA256SUMS.txt"

echo "Release artifacts:"
ls -lh "$DIST"
