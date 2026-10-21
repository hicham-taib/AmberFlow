#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="$ROOT/build/Amberflow-$VERSION.dmg"
mkdir -p "$ROOT/build"
if [[ -e "$DMG" ]]; then
  print -u2 "Already exists: $DMG (move it aside before rebuilding)."
  exit 1
fi

# Build each architecture without replacing a running build/Amberflow.app.
swift build -c release --triple arm64-apple-macosx14.0
ARM_BIN="$(swift build -c release --triple arm64-apple-macosx14.0 --show-bin-path)/Amberflow"
swift build -c release --triple x86_64-apple-macosx14.0
INTEL_BIN="$(swift build -c release --triple x86_64-apple-macosx14.0 --show-bin-path)/Amberflow"

STAGING="$(mktemp -d "$ROOT/build/.amberflow-dmg.XXXXXX")"
cleanup() {
  if [[ -d "$STAGING" && "$STAGING" == "$ROOT/build/.amberflow-dmg."* ]]; then
    rm -rf -- "$STAGING"
  fi
}
trap cleanup EXIT

APP="$STAGING/Amberflow.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP/Contents/MacOS/Amberflow"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ACTION_AUDIT.md "$APP/Contents/Resources/ActionAudit.md"
chmod +x "$APP/Contents/MacOS/Amberflow"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
xcrun lipo "$APP/Contents/MacOS/Amberflow" -verify_arch arm64 x86_64

ln -s /Applications "$STAGING/Applications"
cp Resources/INSTALL.txt "$STAGING/Read Me.txt"
hdiutil create -volname "Amberflow" -srcfolder "$STAGING" \
  -format UDZO -imagekey zlib-level=9 "$DMG"
hdiutil verify "$DMG"
print "Created: $DMG"
shasum -a 256 "$DMG"
