#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="${CONFIGURATION:-release}"
APP="$ROOT/build/Remote Codex.app"
if pgrep -x RemoteCodexMac >/dev/null; then
  echo 'Quit Remote Codex before rebuilding its app bundle (macOS invalidates running modified code signatures).' >&2
  exit 1
fi
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/AppIcon.iconset"
cp "$BIN/RemoteCodexMac" "$APP/Contents/MacOS/RemoteCodexMac"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
ICON="$ROOT/Resources/AppIcon.png"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ICON" --out "$ROOT/build/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE="$((SIZE * 2))"
  sips -z "$DOUBLE" "$DOUBLE" "$ICON" --out "$ROOT/build/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${MACOS_SIGNING_IDENTITY:--}" --options runtime "$APP"
codesign --verify --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/Remote-Codex-macOS-0.1.0-$(uname -m).zip"
echo "Built: $APP"
echo "Default signature is ad-hoc for local testing; distribution requires Developer ID signing and notarization."
