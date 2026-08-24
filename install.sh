#!/bin/bash
# Install the latest community build, verify its checksum, and remove quarantine
# only from the installed DSH Desktop bundle.
set -euo pipefail

REPOSITORY="frankfika/dsh-desktop-macos"
ASSET="DSH-Desktop-latest.zip"
BASE_URL="https://github.com/${REPOSITORY}/releases/latest/download"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dsh-desktop-install.XXXXXX")"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

if ! command -v curl >/dev/null || ! command -v shasum >/dev/null || ! command -v ditto >/dev/null; then
    echo "This installer requires the standard macOS curl, shasum, and ditto tools." >&2
    exit 1
fi

echo "==> Downloading the latest DSH Desktop release"
curl --fail --location --retry 3 --output "$WORK_DIR/$ASSET" "$BASE_URL/$ASSET"
curl --fail --location --retry 3 --output "$WORK_DIR/$ASSET.sha256" "$BASE_URL/$ASSET.sha256"

echo "==> Verifying SHA-256 checksum"
(
    cd "$WORK_DIR"
    shasum -a 256 -c "$ASSET.sha256"
)

echo "==> Extracting the application"
ditto -x -k "$WORK_DIR/$ASSET" "$WORK_DIR/unpacked"
SOURCE_APP="$WORK_DIR/unpacked/DSH Desktop.app"
if [ ! -d "$SOURCE_APP" ]; then
    echo "The verified archive does not contain DSH Desktop.app." >&2
    exit 1
fi

if [ -w /Applications ]; then
    INSTALL_DIR="/Applications"
else
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
fi
TARGET_APP="$INSTALL_DIR/DSH Desktop.app"

osascript -e 'tell application id "com.fangchen.dsh-launcher" to quit' >/dev/null 2>&1 || true
echo "==> Installing to $TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"

if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
    echo
    echo "DSH Desktop is installed, but Node.js 22.19+ or 24+ is required."
    echo "Install Node.js from https://nodejs.org/ and run this installer again."
    exit 2
fi

echo "==> Installing the official @deepseek-ai/dsh runtime"
mkdir -p "$HOME/.dsh/app"
npm install --prefix "$HOME/.dsh/app" @deepseek-ai/dsh@latest

echo "==> Launching DSH Desktop"
open "$TARGET_APP"
echo "Installed successfully."
