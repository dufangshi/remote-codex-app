#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.local/e2e-env.json"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE; run scripts/e2e-backend.sh start first" >&2
  exit 1
fi

eval "$(python3 - "$ENV_FILE" <<'PY'
import json, sys, shlex
from pathlib import Path
data=json.loads(Path(sys.argv[1]).read_text())
for key, field in {'RELAY_URL':'relayUrl','TOKEN':'token','DEVICE_ID':'deviceId','WORKSPACE_ID':'workspaceId','DEVICE_API':'deviceApi'}.items():
    print('export TEST_RUNNER_E2E_' + key + '=' + shlex.quote(str(data[field])))
PY
)"

cd "$ROOT/ios"
xcodegen generate
DEST="${IOS_DEST:-platform=iOS Simulator,name=iPhone 17 Pro}"
xcodebuild \
  -project RemoteCodex.xcodeproj \
  -scheme RemoteCodex \
  -destination "$DEST" \
  -only-testing:RemoteCodexUITests/RemoteCodexUITests/testLoginNavigateThreadAndOpenCompletedNotification \
  -resultBundlePath "$ROOT/.local/ios-results-$(date +%s).xcresult" \
  CODE_SIGNING_ALLOWED=NO \
  test
