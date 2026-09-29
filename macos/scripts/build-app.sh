#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="${APP_NAME:-Remote Codex}"
case "$APP_NAME" in *[!a-zA-Z0-9\ -]*) echo 'Invalid APP_NAME' >&2; exit 1 ;; esac
APP="$ROOT/build/$APP_NAME.app"
if ps -axo comm= | grep -Fxq "$APP/Contents/MacOS/RemoteCodexMac"; then
  echo 'Quit Remote Codex before rebuilding its app bundle (macOS invalidates running modified code signatures).' >&2
  exit 1
fi
swift build -c "$CONFIGURATION"
BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/build/AppIcon.iconset"
cp "$BIN/RemoteCodexMac" "$APP/Contents/MacOS/RemoteCodexMac"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ -n "${BUNDLE_ID:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$APP/Contents/Info.plist"
fi
ICON="$ROOT/Resources/AppIcon.png"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ICON" --out "$ROOT/build/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE="$((SIZE * 2))"
  sips -z "$DOUBLE" "$DOUBLE" "$ICON" --out "$ROOT/build/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${MACOS_SIGNING_IDENTITY:--}" --options runtime "$APP"
codesign --verify --strict "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/${APP_NAME// /-}-macOS-$VERSION-$(uname -m).zip"
echo "Built: $APP"
echo "Default signature is ad-hoc for local testing; distribution requires Developer ID signing and notarization."
