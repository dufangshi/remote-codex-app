# Agent notes

This repo holds the Remote Codex client apps. It is not the control-plane repo.
`android/` and `ios/` are WebView shells; `macos/` is a native SwiftUI app. The
two follow deliberately opposite rules — check which one you are editing.

Shared:

- Relay mode only. The first screen collects the relay origin; after that, auth is `/relay/auth/*`.
- JSON field names are camelCase.

Mobile (`android/`, `ios/`):

- Keep the native shell aligned with `apps/supervisor-web` in remoteCodex: same route stack, back targets, labels, and theme tokens.
- Thread conversation stays in a WebView of the relay-hosted thread page. Do not reimplement timeline/composer natively.
- After Android or iOS changes, run the matching simulator E2E, not a web Playwright suite.

macOS (`macos/`):

- The opposite: the timeline, composer, files, terminal, settings and sharing dialogs are all native SwiftUI, and no WKWebView remains. Do not reintroduce one.
- Harness/MCP/hook/upstream/template configuration has no native editor; defer to the relay in a browser via `openWeb()`.
- Build and test need `DEVELOPER_DIR` pointed at a full Xcode, and local builds want `MACOS_SIGNING_IDENTITY` set. See [macos/README.md](macos/README.md).
- Keep [macos/PARITY.md](macos/PARITY.md) honest when behaviour changes — it records real gaps, not aspirations.
