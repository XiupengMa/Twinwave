#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
out="$PWD/build"
app="$out/Twinwave.app"
icons="$out/Twinwave.iconset"
mkdir -p "$icons" "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun clang -fobjc-arc -O2 Tools/Icon.m -framework AppKit -framework CoreGraphics -o "$out/make-icon"
"$out/make-icon" "$icons"
iconutil -c icns "$icons" -o "$app/Contents/Resources/Twinwave.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"
xcrun clang -arch arm64 -mmacosx-version-min=14.2 -std=gnu11 -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter \
    Sources/*.m -framework AppKit -framework CoreAudio -framework AudioUnit -framework AVFoundation \
    -framework QuartzCore -framework Accelerate -framework CoreGraphics -o "$app/Contents/MacOS/Twinwave"
codesign --force --sign "${SIGN_IDENTITY:--}" --timestamp=none "$app"
codesign --verify --strict "$app"
echo "$app"
