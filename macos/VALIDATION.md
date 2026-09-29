# Native SwiftUI 0.6 validation

## 0.6 focused regression pass

- Timeline projection regression passes: empty reasoning omitted, consecutive commands grouped, intermediate replies retained, summary stubs cannot erase fetched detail. Notification cursor tests pass for baseline suppression, retry, deduplication and untrusted route rejection.
- Real isolated relay transport integration passed (26.356 seconds); seeded full trace/detail regression passed (1.172 seconds). Synthetic command output retains literal asterisks.
- Native screenshots/AX compared with the same seeded conversation in Chrome: inline timestamps, intermediate replies, collapsed/expanded command group and raw-output sheet. Settings state-summary preference now controls reasoning visibility.
- Native menu QA: compact slash menu has no Tools/Close header or arrow; Effort → High saved immediately and the toolbar updated without Apply. Single Settings overlay verified in light and dark, without the outer Settings/Done sheet.
- Font QA: Chrome 16→17px persisted after reload; Mac 17→21px changed native body/trace immediately and persisted in UserDefaults. Web font normalization/persistence tests, typecheck and build passed.
- Native Devices/Workspaces navigation, fixture workspace Pin/Unpin and action-menu entry points checked. Destructive/security management mutations were not exercised on production accounts.
- macOS permission UI cannot be automated by this session; user was asked to allow notifications. Actual system banner and notification-click delivery remain unverified. No APNS/quit-app delivery is claimed.

Older sections below are retained historical evidence, not new 0.6 runs.

## 0.5 regression pass

- Swift build passed. A 14-test run passed transport/integration, remote-file-link and terminal-buffer checks; its new Markdown setext case exposed a quote-classification error. After fixing that parser, the failing Markdown test passed on its targeted rerun.
- The real isolated relay integration passed (28.524 seconds), including chat, encrypted attachments, large continuations, file edits/conflicts and encrypted terminal traffic.
- An additional seeded trace integration passed (1.183 seconds): summaries defer commands, full detail retains both intermediate assistant messages and command order, and item detail preserves literal asterisks. Enable with REMOTE_CODEX_MAC_TRACE_E2E=1 after scripts/seed-native-trace.mjs; the script refuses non-loopback/non-isolated databases.
- Native QA verified trace expansion, downloaded README bytes, remote-link Markdown preview, model High selection, Devices/Workspaces navigation, shared Settings close/return, and sharing dialog entry without creating public access.
- Direct terminal printf, arrow-history replay, Ctrl-C and exit were exercised in the isolated fixture.
- Final native QA also created a fresh terminal and received NATIVE-05-RECOVERY through direct key input. The updated initial scroll showed the latest turn on reopen. Production-named 0.5 restored the existing login/conversation; its real model/effort catalog and slash commands were inspected without sending a production prompt.
- A 1.26 MB user message initially caused an accessibility text-layout hang. Native message rendering now reveals 6,000 characters at a time, and the QA app remained responsive with the remaining-character control visible.
- UI screenshots/accessibility were inspected; these checks do not establish complete web parity. See PARITY.md for specific remaining gaps.

The sections below retain baseline 0.4 evidence; their original run counts are not new 0.5 full-suite results.

Development target: Apple Silicon, macOS 27.2, Xcode 27 beta; deployment minimum macOS 14. No claim of physical macOS 14/Intel qualification.

## Explorer 0.6.1

- Native SwiftUI header now provides workspace-scoped breadcrumbs and Back to chat; AppKit code editing adds asynchronous lexical syntax highlighting without a WebView.
- Three focused Explorer tests passed, covering breadcrumb traversal boundaries, Unicode token ranges, language rules and the 500,000 UTF-16-unit plain-text fallback.
- The real isolated Rust relay integration passed (28.987 seconds), including rejection of file-tree navigation above the workspace root.
- Native QA verified TSX highlighting, editing, undo, draft retention across chat navigation, Command-S with on-disk read-back, ancestor breadcrumb navigation and a disabled parent button at the root.
- Highlighting is lexical, not semantic/LSP analysis. Large files remain editable without highlighting.

## Automated checks

The final Swift test run passed **12 tests, zero failures**, in 26.219 seconds, including the real isolated relay integration.

- HTTPS/loopback origin validation, bounded packet parsing and base64url.
- Signed descriptor verification, CryptoKit HPKE and authenticated AES-GCM response opening.
- Photo tokenization, multipart manifests, MIME/header validation and image limits.
- Native Markdown headings, fenced/unfinished code, lists, tables and escaped/code-cell pipes.
- Terminal encrypted frames: replay, tamper, channel/routing and plaintext rejection.
- Retained compatibility tests for origin-bound saved sessions and route/query validation.

## Real Rust fixture integration

Rust relay/Supervisor 0.12.47 with a synthetic agent, isolated credentials and workspace:

- Native password login, inventory, encrypted workspace/model requests, thread creation and prompt/reply.
- Multipart image upload and byte-identical encrypted image retrieval.
- 1.26 MB conversation and approximately 2.6 MB UTF-8 file continuation round trips; malformed/cross-scope continuation rejection.
- File create/read/save/read-back, stale-content conflict and duplicate-create refusal.
- History pagination and High/Auto settings round trips.
- Shared account workbench visit/favorite round trip and encrypted HTML export.
- Real encrypted WebSocket shell attach/input/output; expected marker received and test shell exited.
- Changed identity refused and logout credentials removed.

The initial socket assertion used a fixed 30-frame budget and failed when PTY startup produced more frames. It was replaced with expected-output matching and a bounded 12-second deadline; subsequent integration runs passed. No production key or chat prompt was used.

## Native interface checks

See [PARITY.md](PARITY.md). The separately signed QA app was exercised through real macOS controls: chat with partial/final reply, images, new thread, reasoning effort, file save, encrypted terminal, settings/theme and relaunch.

The production-named 0.4 package was built after normally quitting 0.3. Its Keychain login and exact previous web route migrated into the native workbench; existing ElAgente history, model/effort, favorites and recent chats loaded without the previous continuation error. Production verification did not send prompts or edit files.

## Packaging

The release-mode local build passed. Local packaging used the existing Apple Development identity; this is **not Developer ID notarized distribution**. CI defaults to an ad-hoc signature. The build script refuses to overwrite a running app. Android/iOS/runtime versions were not changed.
