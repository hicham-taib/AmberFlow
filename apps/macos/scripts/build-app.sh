#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
APP="$ROOT/build/Amberflow.app"
cd "$ROOT"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
ICON="$ROOT/Resources/AppIcon.icns"
if [[ ! -f "$ICON" ]]; then
  tmp="$(mktemp -d)"; swift "$ROOT/scripts/generate-icon.swift" "$tmp/AppIcon.iconset"; iconutil -c icns "$tmp/AppIcon.iconset" -o "$ICON"; rm -rf "$tmp"
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Amberflow" "$APP/Contents/MacOS/Amberflow"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/ACTION_AUDIT.md" "$APP/Contents/Resources/ActionAudit.md"
chmod +x "$APP/Contents/MacOS/Amberflow"
codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
