#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

android_jdk="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}"
android_sdk="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"

JAVA_HOME="$android_jdk" ANDROID_HOME="$android_sdk" \
    ./gradlew --no-daemon testDebugUnitTest assembleDebug lintDebug

echo "Verified APK: app/build/outputs/apk/debug/app-debug.apk"

