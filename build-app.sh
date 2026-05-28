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

# Generate the hourglass app icon (drawn in code) into the bundle.
echo "==> Generating app icon"
swift scripts/make-icon.swift "$APP/Contents/Resources" >/dev/null
rm -f "$APP/Contents/Resources/AppIcon-preview.png"

# Ad-hoc sign so the app runs locally
codesign --force --deep --sign - "$APP" || true

echo "==> Built: $APP"

# Install to ~/Applications and run from there. macOS only delivers
# notifications to a recognized bundle path, and running straight from
# build/ creates a duplicate Launch Services registration that breaks
# notification routing. Always run the installed copy.
INSTALLED="$HOME/Applications/MyTime.app"
echo "==> Installing to $INSTALLED"
mkdir -p "$HOME/Applications"

# Stop any running instance (orphaned build/ copies included).
pkill -x MyTime 2>/dev/null || true
sleep 1

rm -rf "$INSTALLED"
cp -R "$APP" "$INSTALLED"

# Drop stale build/ registrations so only the installed copy is known.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
    "$LSREGISTER" -f "$INSTALLED" 2>/dev/null || true
fi

echo "==> Installed. Run: open \"$INSTALLED\""
