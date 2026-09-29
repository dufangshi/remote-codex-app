# Remote Codex for Mac — native SwiftUI preview

Version 0.6.1 is fully native SwiftUI: conversation, composer, navigation, files, terminal, settings and the sharing/export dialogs. No WKWebView remains in the app. Android/iOS are unaffected. macOS 14+, CryptoKit and Keychain; no third-party dependencies.

## Build

```sh
cd macos
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test
MACOS_SIGNING_IDENTITY="<your Apple Development identity>" bash scripts/build-app.sh
open 'build/Remote Codex.app'
```

`DEVELOPER_DIR` must point at a full Xcode install; the bare Command Line Tools SDK has no SwiftUI macro plugin and the build fails on every `@State`.

Pass `MACOS_SIGNING_IDENTITY` for local development. The default is ad-hoc signing, and an ad-hoc signature is derived from the binary's contents, so it changes on every rebuild — macOS Keychain then treats each build as a different application and re-prompts for the `com.remotecodex.mac` item even after "Always Allow". A stable Developer identity avoids that. Run `security find-identity -v -p codesigning` to list available identities. Builds are **not notarized**; Developer ID signing, notarization and universal distribution are separate work.

`build-app.sh` refuses to run while the app is open, because macOS invalidates the signature of running modified code. Quit it first. `APP_NAME` and `BUNDLE_ID` create an isolated QA app that can run alongside the production-named one without sharing its Keychain session.

The host-architecture app and ZIP are written to `build/`, which is gitignored and disposable.

## Native workspace

- Web-aligned activity rail, sidebar, workspace tabs, shared account recents/favorites, latest ten notifications, green accent and light/dark/system palettes.
- Three-turn summary history pages, deferred inline traces with grouped commands, incremental reply refresh, Markdown tables/code/lists, bounded image previews and model/effort summaries.
- SwiftUI TextEditor composer, system image chooser, discovered model/effort settings, thread creation/fork/rename/delete.
- Native file browser with hover-revealed per-row download, directory download as a `.zip` archive, remote conversation links, Markdown preview and a revision-checked text editor. Direct-key terminal over the encrypted WebSocket protocol.
- Compact anchored model/effort submenus save on selection, without Apply; slash menus use the web-shaped icon without a native popover arrow or redundant heading.
- Separate Devices/Workspaces management lists, shared access views, workspace pin/rename/path actions, setup commands and import/create forms.
- Native thread sharing: read-only public links (minting a device publication token and registering it with the relay), per-thread sharing permissions over the relay shares/grants API, and HTML transcript export with turn selection.
- Native Settings sheet for local display preferences: appearance, 12–22px text size, auto-collapse completed turns and reasoning summaries. These apply immediately to conversation/composer/trace rendering and are saved locally.
- macOS completion notifications while the app is running (including with its window closed), with backlog suppression and account-bound click routing. System permission, Focus and macOS delivery policy still apply; quitting the app stops monitoring.
- Command-N: new chat; Command-comma: Settings; Command-Return: send; Command-F: search loaded history; Command-Control-S: toggle sidebar; Command-Shift-E: files; Command-Shift-T: terminal; Command-R: refresh; Command-Shift-O: open the current thread in a browser.
- Keychain session restoration and previous-thread restoration, including migration from the 0.3 route preference.

AppKit provides file panels, clipboard, images and quit confirmation.

## Security and persistence

Only HTTPS relay origins are accepted, except loopback HTTP for tests. Native signed and pinned HPKE transport protects device HTTP traffic, attachments, continuations and terminal key exchange. Terminal frames use authenticated AES-GCM with sequence/routing validation. No plaintext fallback or certificate bypass exists.

Credentials and device identity pins stay in Keychain. UserDefaults holds non-secret UI preferences and validated device/thread identifiers. Unsaved drafts are held in memory; quitting warns about drafts/modified files, but does not persist their content.

## Verification and boundaries

```sh
# Repository root, isolated fixture only:
bash scripts/e2e-backend.sh serve
node macos/scripts/seed-parity.mjs
cd macos
REMOTE_CODEX_MAC_E2E_ENV="$PWD/../.local/e2e-env.json" swift test
```

See [PARITY.md](PARITY.md) for interface comparisons and remaining differences, and [VALIDATION.md](VALIDATION.md) for protocol/native UI checks.

This is a native preview, not complete web feature parity. The terminal implements a VT subset, not a full emulator. Markdown covers common conversation blocks, not every CommonMark extension, math renderer or web plugin. The editor is plain text without Monaco/LSP. OAuth/passkey onboarding is not qualified. Chat polls rather than receiving WebSocket deltas. Native goal controls are incomplete.

Harness selection, MCP server and hook configuration, upstream profiles and prompt templates have **no native editor**. They were previously reachable through an embedded web Settings view, which 0.6.1 removed; the slash toolbox now offers "Manage in browser…" and Command-Shift-O opens the current thread on the relay for that work. Management mutations have not all been qualified against real installed harnesses.
