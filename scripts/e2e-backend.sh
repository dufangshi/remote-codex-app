#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODEX="${REMOTE_CODEX_ROOT:-$HOME/dev/remoteCodex}"
BIN="${REMOTE_CODEX_BIN:-$CODEX/target/debug/remote-codex}"
WEB_DIST="${REMOTE_CODEX_RELAY_WEB_DIST_DIR:-$CODEX/apps/supervisor-web/dist}"
DATA="$ROOT/.local/e2e"
ENV_FILE="$ROOT/.local/e2e-env.json"
PID_FILE="$ROOT/.local/e2e-pids"
PORT="${E2E_RELAY_PORT:-18790}"
SUPERVISOR_PORT="${E2E_SUPERVISOR_PORT:-18791}"
RELAY="http://127.0.0.1:${PORT}"
USERNAME="${E2E_USERNAME:-mobile}"
PASSWORD="${E2E_PASSWORD:-mobile-pass-1}"

mkdir -p "$DATA"

api() {
  local method="$1" path="$2" body="${3:-}" token="${4:-}"
  local args=(-sS -X "$method" "$RELAY$path" -H "content-type: application/json")
  if [[ -n "$token" ]]; then
    args+=(-H "authorization: Bearer $token")
  fi
  if [[ -n "$body" ]]; then
    args+=(-d "$body")
  fi
  curl "${args[@]}"
}

start() {
  if [[ ! -x "$BIN" ]]; then
    echo "missing remote-codex binary at $BIN" >&2
    exit 1
  fi
  if [[ ! -f "$WEB_DIST/index.html" ]]; then
    echo "missing supervisor-web dist at $WEB_DIST" >&2
    exit 1
  fi
  stop >/dev/null 2>&1 || true
  rm -rf "$DATA"
  mkdir -p "$DATA/workspaces/mobile-ws"
  echo "# mobile e2e workspace" > "$DATA/workspaces/mobile-ws/README.md"

  HOST=127.0.0.1 PORT="$PORT" \
    REMOTE_CODEX_ADMIN_USERNAME=admin \
    REMOTE_CODEX_ADMIN_PASSWORD=admin-pass-1 \
    REMOTE_CODEX_RELAY_DATA_DIR="$DATA/relay" \
    REMOTE_CODEX_RELAY_WEB_DIST_DIR="$WEB_DIST" \
    REMOTE_CODEX_RELAY_REGISTRATION_ENABLED=true \
    "$BIN" relay >"$DATA/relay.log" 2>&1 &
  echo $! >> "$PID_FILE"
  for _ in $(seq 1 80); do
    if curl -sf "$RELAY/healthz" >/dev/null; then
      break
    fi
    sleep 0.25
  done
  curl -sf "$RELAY/healthz" >/dev/null

  python3 - "$RELAY" "$USERNAME" "$PASSWORD" "$DATA" "$ENV_FILE" "$PORT" <<'PY'
import json, sys, urllib.request, pathlib, time
relay, username, password, data_dir, env_file, port = sys.argv[1:7]

def req(method, path, body=None, token=None):
    headers = {"content-type": "application/json"}
    if token:
        headers["authorization"] = f"Bearer {token}"
    payload = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(relay + path, data=payload, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            raw = response.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raw = error.read().decode()
        try:
            return json.loads(raw)
        except Exception:
            raise SystemExit(f"{method} {path}: {error.code} {raw}") from error

reg = req("POST", "/relay/auth/register", {
    "email": "mobile@example.com",
    "username": username,
    "password": password,
})
token = reg.get("token") or ""
if not token:
    login = req("POST", "/relay/auth/login", {"identifier": username, "password": password})
    token = login.get("token") or ""
if not token:
    raise SystemExit(f"unable to obtain relay user token: {reg}")
created = req("POST", "/relay/devices", {"name": "e2e-phone"}, token)
device = created.get("device") or {}
device_id = device.get("id")
device_token = created.get("token") or device.get("token")
if not device_id or not device_token:
    raise SystemExit(f"unable to create device: {created}")
pathlib.Path(data_dir, "provision.json").write_text(json.dumps({
    "token": token,
    "deviceId": device_id,
    "deviceToken": device_token,
}))
print(json.dumps({"token": token, "deviceId": device_id, "deviceToken": device_token}))
PY
  eval "$(python3 - <<PY
import json
from pathlib import Path
p=Path("$DATA/provision.json")
data=json.loads(p.read_text())
print(f"TOKEN={data['token']}")
print(f"DEVICE_ID={data['deviceId']}")
print(f"DEVICE_TOKEN={data['deviceToken']}")
PY
)"

  env -u REMOTE_CODEX_RELAY_AGENT_TOKEN -u REMOTE_CODEX_RELAY_SERVER_URL \
    HOST=127.0.0.1 PORT="$SUPERVISOR_PORT" \
    REMOTE_CODEX_MODE=relay \
    REMOTE_CODEX_E2E_FAKE_RUNTIME=1 \
    REMOTE_CODEX_RELAY_SERVER_URL="$RELAY" \
    REMOTE_CODEX_RELAY_AGENT_TOKEN="$DEVICE_TOKEN" \
    REMOTE_CODEX_RELAY_SUPERVISOR_PORT="$SUPERVISOR_PORT" \
    REMOTE_CODEX_RELAY_SUPERVISOR_HOST=127.0.0.1 \
    DATABASE_URL="$DATA/supervisor.sqlite" \
    WORKSPACE_ROOT="$DATA/workspaces" \
    "$BIN" relay-supervisor >"$DATA/supervisor.log" 2>&1 &
  echo $! >> "$PID_FILE"

  for _ in $(seq 1 80); do
    HEALTH="$(curl -sf "$RELAY/healthz" || true)"
    if python3 -c 'import json,sys; raise SystemExit(0 if json.loads(sys.argv[1] or "{}").get("connectedSupervisors",0)>=1 else 1)' "$HEALTH" 2>/dev/null; then
      break
    fi
    sleep 0.25
  done

  DEVICE_API="$RELAY/relay/devices/$DEVICE_ID/api"
  python3 - "$RELAY" "$TOKEN" "$DEVICE_ID" "$DATA" "$ENV_FILE" "$PORT" "$USERNAME" "$PASSWORD" "$DEVICE_TOKEN" <<'PY'
import json, sys, urllib.request, pathlib
relay, token, device_id, data_dir, env_file, port, username, password, device_token = sys.argv[1:10]
workspace_path = str(pathlib.Path(data_dir) / "workspaces" / "mobile-ws")
headers = {"content-type": "application/json", "authorization": f"Bearer {token}"}
body = json.dumps({"absPath": workspace_path, "label": "mobile-ws"}).encode()
url = f"{relay}/relay/devices/{device_id}/api/workspaces"
request = urllib.request.Request(url, data=body, headers=headers, method="POST")
with urllib.request.urlopen(request) as response:
    workspace = json.loads(response.read().decode())
env = {
    "relayUrl": relay,
    "relayPort": int(port),
    "username": username,
    "password": password,
    "token": token,
    "deviceId": device_id,
    "deviceToken": device_token,
    "workspaceId": workspace["id"],
    "deviceApi": f"{relay}/relay/devices/{device_id}/api",
    "workspacePath": workspace_path,
}
pathlib.Path(env_file).write_text(json.dumps(env, indent=2) + "\n")
print(json.dumps(env, indent=2))
PY
}

stop() {
  if [[ -f "$PID_FILE" ]]; then
    while read -r pid; do
      kill "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi
}

case "${1:-start}" in
  start) start ;;
  stop) stop ;;
  *) echo "usage: $0 start|stop" >&2; exit 1 ;;
esac
