# Remote Codex for Mac — native SwiftUI preview

Version 0.4.0 replaces the 0.3 web workspace with a native SwiftUI view tree. There is no WKWebView, HTML renderer, JavaScript bridge, or embedded React UI in the Mac app. Android/iOS are unaffected. macOS 14+, CryptoKit and Keychain; no third-party dependencies.

## Build

```sh
cd macos
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test
bash scripts/build-app.sh
open 'build/Remote Codex.app'
```

The host-architecture app and ZIP are under build/. Set MACOS_SIGNING_IDENTITY to sign; default builds are ad-hoc and **not notarized**. APP_NAME and BUNDLE_ID create an isolated QA app. Public Developer ID signing, notarization and universal distribution are separate work.

## Native workspace

- Web-aligned activity rail, sidebar, workspace tabs, shared account recents/favorites, latest ten notifications, green accent and light/dark/system palettes.
- Native conversation history, incremental reply refresh, Markdown tables/code/lists, bounded image previews, tool-detail popovers, model/effort and usage summaries.
- SwiftUI TextEditor composer, system image chooser, discovered model/effort settings, thread creation/fork/rename/delete and HTML export.
- Native file browser and revision-checked text editor. Command terminal uses the encrypted WebSocket protocol.
- Native settings for appearance, device management, harnesses, upstream profiles and templates.
- Command-N: new chat; Command-comma: Settings; Command-Return: send; Command-F: search loaded history; Command-Shift-E: files.
- Keychain session restoration and previous-thread restoration, including migration from the 0.3 route preference.

AppKit is used for operating-system integration (file panels, clipboard, images and quit confirmation), not to embed a web interface.

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

This is a native preview, not complete web feature parity. The command terminal is not a full-screen VT/TUI emulator. Markdown covers common conversation blocks, not every CommonMark extension, math renderer or web plugin. The editor is plain text without Monaco/LSP. Advanced sharing/admin/plugin workflows and OAuth/passkeys are not implemented. Chat currently polls while active rather than receiving WebSocket deltas. Management mutations have controls and confirmations but have not all been qualified against real installed harnesses.
