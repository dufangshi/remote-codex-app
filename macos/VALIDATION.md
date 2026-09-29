# Native SwiftUI 0.4 validation

Development target: Apple Silicon, macOS 27.2, Xcode 27 beta; deployment minimum macOS 14. No claim of physical macOS 14/Intel qualification.

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
