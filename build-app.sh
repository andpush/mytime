#!/usr/bin/env bash
set -euo pipefail

# Build MyTime.app bundle from the Swift package.

cd "$(dirname "$0")"

echo "==> Building release binary"
swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release

BIN=".build/apple/Products/Release/MyTime"
if [ ! -f "$BIN" ]; then
    BIN=".build/release/MyTime"
fi
if [ ! -f "$BIN" ]; then
    BIN=$(find .build -type f -name MyTime -perm -u+x 2>/dev/null | grep -i release | grep -v dSYM | head -1)
fi

if [ ! -f "$BIN" ]; then
    echo "Build failed: binary not found"
    exit 1
fi

APP="build/MyTime.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/MyTime"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Generate a simple clock icon using sips if possible, else skip
if command -v iconutil >/dev/null 2>&1; then
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    # We don't have source art; omit icon — app will show a default icon.
fi

# Ad-hoc sign so the app runs locally
codesign --force --deep --sign - "$APP" || true

echo "==> Built: $APP"
echo "Run: open \"$APP\""
