#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.local/e2e-env.json"
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE; run scripts/e2e-backend.sh start first" >&2
  exit 1
fi

eval "$(python3 - "$ENV_FILE" <<'PY'
import json, sys
from pathlib import Path
data=json.loads(Path(sys.argv[1]).read_text())
print(f"RELAY_PORT={data['relayPort']}")
print(f"USERNAME={data['username']}")
print(f"PASSWORD={data['password']}")
print(f"TOKEN={data['token']}")
print(f"DEVICE_ID={data['deviceId']}")
print(f"WORKSPACE_ID={data['workspaceId']}")
print(f"DEVICE_API={data['deviceApi']}")
print(f"RELAY_URL={data['relayUrl']}")
PY
)"

AVD="${ANDROID_AVD:-cardverify_aosp35_root}"
if ! adb devices | awk 'NR>1 && $2=="device"{found=1} END{exit found?0:1}'; then
  echo "starting AVD $AVD"
  "$ANDROID_HOME/emulator/emulator" -avd "$AVD" -no-snapshot-save -no-boot-anim -netdelay none -netspeed full >/tmp/remote-codex-emulator.log 2>&1 &
  echo $! > "$ROOT/.local/emulator.pid"
  adb wait-for-device
  for _ in $(seq 1 90); do
    boot="$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [[ "$boot" == "1" ]]; then
      break
    fi
    sleep 2
  done
fi

adb reverse "tcp:${RELAY_PORT}" "tcp:${RELAY_PORT}"
adb reverse tcp:18790 tcp:18790 || true

cd "$ROOT/android"
./gradlew :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.relayUrl="http://127.0.0.1:${RELAY_PORT}" \
  -Pandroid.testInstrumentationRunnerArguments.hostRelayUrl="http://127.0.0.1:${RELAY_PORT}" \
  -Pandroid.testInstrumentationRunnerArguments.username="$USERNAME" \
  -Pandroid.testInstrumentationRunnerArguments.password="$PASSWORD" \
  -Pandroid.testInstrumentationRunnerArguments.token="$TOKEN" \
  -Pandroid.testInstrumentationRunnerArguments.deviceId="$DEVICE_ID" \
  -Pandroid.testInstrumentationRunnerArguments.workspaceId="$WORKSPACE_ID" \
  -Pandroid.testInstrumentationRunnerArguments.deviceApi="http://127.0.0.1:${RELAY_PORT}/relay/devices/${DEVICE_ID}/api"
