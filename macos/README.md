# Remote Codex for Mac — native preview

An independent macOS 14+ SwiftUI application. Chat, history, file browsing/editing, navigation and model settings are native. An authenticated, same-origin WebKit Full workspace pane provides the advanced web UI inside the app.

## Build and run

Requires Xcode 15+ and its command-line tools (the current development machine uses Xcode-beta):

```sh
cd macos
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test
bash scripts/build-app.sh
open 'build/Remote Codex.app'
```

The build script emits a host-architecture `.app` and ZIP in `build/`. Version 0.2.0 is a native preview, independent of runtime/mobile versions. It is ad-hoc signed by default, **not notarized**. Set `MACOS_SIGNING_IDENTITY` to an available Developer ID identity for signing; notarization and Intel/universal distribution are separate release steps. Do not disable Gatekeeper globally to install the preview. `APP_NAME` and `BUNDLE_ID` allow an isolated QA bundle without replacing the running app or its Keychain session.

## Supported workflow

- Relay sign-in with password and authenticator/recovery code; persistent sessions in Keychain.
- Owned and device-wide shared devices; workspace/thread listing and creation.
- Server-discovered harnesses, models and advertised reasoning effort options; guarded permissions by default.
- Native conversation text, inline Markdown and fenced code with copy; collapsible tool/reasoning items.
- Text and image prompts, in-memory per-thread drafts, stop/steer and approval controls.
- Native light/dark appearance, search, Command-N, Command-Return, Command-R and Settings.
- Device HTTP uses signed, pinned P-256 identity + HPKE (P-256/HKDF-SHA256/AES-256-GCM), authenticated response decryption, encrypted query/body/attachments and scoped response continuations. There is no plaintext fallback. Redirects are refused.

## Preview boundaries

Updates are polled every second during a turn and every four seconds while idle (15 seconds when idle in the background). This is not yet a push/WebSocket client. History supports earlier-turn pagination and deferred tool details. Long messages have a bounded inline preview and a full-text native reader. Native file tabs preserve unsaved edits across navigation and warn before quitting. UTF-8 text up to 4 MB is editable; transport responses are capped at 64 MB. Saving checks the previous remote contents and verifies the result, but the server has no atomic compare-and-swap, so this is not protection against a simultaneous write between the check and save.

Full workspace uses an ephemeral WebKit store with the relay session cookie, not credentials injected into JavaScript. It exposes settings, terminals and advanced thread features using the existing web implementation. External links open in the system browser. Native Markdown is not a complete replacement for rich web renderers. Device-wide read-only grants remain enforced by the server; write controls may return a permission error. macOS 26+ uses Liquid Glass for controls; older systems use material backgrounds.

Device identities are trusted on first encrypted connection and pinned in Keychain per relay/device. An identity change blocks access; verify the new fingerprint using the existing web-client identity workflow, then remove only the matching `identity:<relay>:<device>` generic-password entry under `com.remotecodex.mac` in Keychain Access. A native re-trust flow is intentionally not provided yet. Relay TLS remains part of the first-use trust boundary.

## Isolated integration test

Build the Rust executable in the adjacent control-plane repo. Run the existing fixture in a retained terminal; it starts its own relay and fake-runtime Supervisor and does not modify the active host Supervisor:

```sh
bash scripts/e2e-backend.sh serve
```

In another terminal:

```sh
cd macos
REMOTE_CODEX_MAC_E2E_ENV="$PWD/../.local/e2e-env.json" swift test
```

The integration test only accepts a loopback fixture. It verifies real Rust↔CryptoKit interoperability, encrypted collection/query/write paths, thread creation and response, identity-change rejection and logout. Stop the retained fixture with Ctrl-C. Its synthetic credentials are never bundled into the application.
