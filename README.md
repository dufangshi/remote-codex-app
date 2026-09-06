# Remote Codex App

Independent Android and iOS clients for [Remote Codex](https://github.com) relay mode.

The outer shell is native and follows the public web UI: the same screen stack, back targets, copy, and visual language. Thread conversation UI is the live relay web thread page inside a WebView.

## Screens

1. Relay URL
2. Relay home (`/`)
3. Setup guide (`/relay-guide`)
4. Sign in / create account (`/relay-portal`)
5. Devices (`/relay-devices`)
6. Account (`/relay-account`)
7. Workspaces (`/devices/:id/workspaces`)
8. New workspace (`/devices/:id/workspaces/new`)
9. Threads (`/devices/:id/threads?workspaceId=`)
10. New thread (`/devices/:id/threads/new`)
11. Import session (`/devices/:id/threads/import`)
12. Thread (`/devices/:id/threads/:id`) — WebView

Back navigation matches the web product header:

- Devices → Relay home
- Workspaces → Devices
- Threads → Workspaces
- Thread → Threads for that workspace
- New workspace / import → Workspaces
- New thread → Threads
- Account → previous screen
- Guide / portal → Relay home

## Login

The first native-only step is the relay URL. After that, session, register, and password sign-in match the web portal. OAuth buttons open the same relay start URLs when the relay advertises them.

## Notifications

While signed in, the app keeps a WebSocket to each selected (or last connected) device. When `thread.turn.completed` or `thread.turn.failed` arrives and that thread is not already open in the foreground, a local notification is posted. Tapping it opens `/devices/:deviceId/threads/:threadId`.

## Requirements

- JDK 21
- Android SDK 35 and an AOSP emulator (no Play Store image)
- Xcode 16+ / 26+ with iOS Simulator
- A running Remote Codex relay that serves `apps/supervisor-web/dist`

## E2E

From this repo:

```bash
export JAVA_HOME="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"

./scripts/e2e-backend.sh start
./scripts/e2e-android.sh
./scripts/e2e-ios.sh
./scripts/e2e-backend.sh stop
```

The backend helper starts a local relay + fake-runtime supervisor, writes `.local/e2e-env.json`, and the device tests drive login → devices → workspaces → thread → agent-complete notification → open thread.
