#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.local/e2e-env.json"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE; run scripts/e2e-backend.sh start first" >&2
  exit 1
fi

eval "$(python3 - <<'PY'
import json
from pathlib import Path
data=json.loads(Path("/Users/mac/dev/remote-codex-app/.local/e2e-env.json").read_text())
print(f"export E2E_RELAY_URL={data['relayUrl']}")
print(f"export E2E_USERNAME={data['username']}")
print(f"export E2E_PASSWORD={data['password']}")
print(f"export E2E_TOKEN={data['token']}")
print(f"export E2E_DEVICE_ID={data['deviceId']}")
print(f"export E2E_WORKSPACE_ID={data['workspaceId']}")
print(f"export E2E_DEVICE_API={data['deviceApi']}")
PY
)"

cd "$ROOT/ios"
xcodegen generate
DEST="${IOS_DEST:-platform=iOS Simulator,name=iPhone 17 Pro}"
xcrun simctl privacy booted grant notifications com.remotecodex.app || true
xcodebuild \
  -project RemoteCodex.xcodeproj \
  -scheme RemoteCodex \
  -destination "$DEST" \
  -only-testing:RemoteCodexUITests/RemoteCodexUITests/testLoginNavigateThreadAndOpenCompletedNotification \
  test
