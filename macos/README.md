# Remote Codex for Mac — native SwiftUI preview

Version 0.6.0 keeps conversation, composer, navigation, files and terminal native SwiftUI. Settings and sharing/export management dialogs reuse the relay web UI in a scoped WKWebView to retain configuration and permission workflows. Android/iOS are unaffected. macOS 14+, CryptoKit and Keychain; no third-party dependencies.

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
- Three-turn summary history pages, deferred inline traces with grouped commands, incremental reply refresh, Markdown tables/code/lists, bounded image previews and model/effort summaries.
- SwiftUI TextEditor composer, system image chooser, discovered model/effort settings, thread creation/fork/rename/delete and HTML export.
- Native file browser, download, remote conversation links, Markdown preview and revision-checked text editor. Direct-key terminal uses the encrypted WebSocket protocol.
- Compact anchored model/effort submenus save on selection, without Apply; slash menus use the web-shaped icon without a native popover arrow or redundant heading.
- Separate Devices/Workspaces management lists, shared access views, workspace pin/rename/path actions, setup commands and import/create forms.
- Shared web settings for appearance, device management, harnesses, upstream profiles and templates.
- One-layer Settings overlay with 12–22px text size, immediately mirrored into native conversation/composer/trace rendering and saved locally.
- macOS completion notifications while the app is running (including with its window closed), with backlog suppression and account-bound click routing. System permission, Focus and macOS delivery policy still apply; quitting the app stops monitoring.
- Command-N: new chat; Command-comma: Settings; Command-Return: send; Command-F: search loaded history; Command-Shift-E: files.
- Keychain session restoration and previous-thread restoration, including migration from the 0.3 route preference.

AppKit provides file panels, clipboard, images and quit confirmation. Only scoped management dialogs use WebKit; the main workbench does not embed a web conversation.

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

This is a native preview, not complete web feature parity. The terminal implements a VT subset, not a full emulator. Markdown covers common conversation blocks, not every CommonMark extension, math renderer or web plugin. The editor is plain text without Monaco/LSP. OAuth/passkey onboarding is not qualified. Chat polls rather than receiving WebSocket deltas. MCP/hooks editing delegates to Settings; native goal controls are incomplete. Management mutations have not all been qualified against real installed harnesses.
