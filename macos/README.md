# Remote Codex for Mac — shared workspace preview

macOS 14+, SwiftUI/AppKit shell and a full-window WebKit workspace. Version 0.3.0 makes the relay's actual web UI the primary interface: the same navigation, timeline, Markdown, composer, explorer, editor, terminal and settings. It no longer nests a second workspace inside native device/thread columns. The earlier native-renderer sources remain for development but are not the default user surface.

## Build

```sh
cd macos
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test
bash scripts/build-app.sh
open 'build/Remote Codex.app'
```

The host-architecture app and ZIP are under `build/`. Set `MACOS_SIGNING_IDENTITY` to sign; default builds are ad-hoc and **not notarized**. Developer ID/notarization and universal distribution remain separate release steps. `APP_NAME` and `BUNDLE_ID` create a separately signed QA app without replacing a running bundle or sharing its credentials.

## Native integration

- Native relay sign-in, password/MFA and Keychain session restoration.
- Full-window web workspace; no custom CSS reskin or duplicate navigation. Web UI deployments apply to the Mac app as well.
- Command-N opens the web new-chat dialog; Command-comma opens web Settings. Command-Return sends through the existing composer.
- Back/forward, devices, guarded reload, zoom and open-in-browser commands.
- System attachment chooser and download destination picker, JavaScript confirmation dialogs and external links.
- Window appearance follows the workspace's light/dark/system setting.
- Quit/reload/sign-out reminders protect against inadvertently discarding unsaved files. They are reminders, not automatic draft saving.

## Security and persistence

The configured HTTPS relay is the navigation boundary (loopback HTTP is allowed for tests). Device requests use the web client's existing signed, pinned HPKE transport; there is no plaintext fallback. External clicked HTTP(S) links open in the default browser. TLS warnings are never bypassed.

WebKit uses a non-persistent store. The session is copied into an origin-bound HttpOnly cookie; it is not injected into JavaScript. Cookie changes synchronize to Keychain, including web sign-out. Public device identity pins and an allowlist of UI preferences are checkpointed in Keychain per relay. Existing native identity pins are restored into IndexedDB before loading the workspace; conflicting native/web pins block startup. Route restoration saves only device paths and valid workspace IDs, never arbitrary query parameters. Other web storage (including unsaved composer/editor content) is ephemeral.

Only one workspace renderer exists throughout in-app navigation. There is no parallel native polling loop. Updates, reconnection, history pagination, models, approvals and tools use the website implementation.

## Verification

Start the isolated relay/fake supervisor from the repository root; never point fixtures at a production supervisor:

```sh
bash scripts/e2e-backend.sh serve
# In another terminal, from the repository root:
node macos/scripts/seed-parity.mjs
cd macos
REMOTE_CODEX_MAC_E2E_ENV="$PWD/../.local/e2e-env.json" swift test
```

The fixture must serve freshly built web assets from the control-plane's pinned shared UI commit. See [PARITY.md](PARITY.md) for the point-by-point UI comparison and [VALIDATION.md](VALIDATION.md) for protocol regressions.

This is a preview, not a guarantee of every harness/browser capability. WebKit and Chromium have small native-control/font rasterization differences; passkey/OAuth, platform notification delivery and all third-party agent workflows have not been comprehensively qualified on macOS 14/Intel. The first native sign-in still requires password/MFA. No extra glass effects are layered over the website's content.
