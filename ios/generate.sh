#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
echo "Generated: DSHMobile.xcodeproj"
echo "Open: open DSHMobile.xcodeproj"

