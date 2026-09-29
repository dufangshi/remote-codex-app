# Native preview validation

Development target: Apple Silicon, macOS 27.2, Xcode 27 beta; deployment minimum macOS 14. This is not a claim of physical-device testing on macOS 14 or Intel.

## Automated checks

- Swift package compilation and ten XCTest cases (nine-test run including real transport plus the added targeted browser-session regression).
- Origin validation (HTTPS or loopback HTTP; no embedded credentials, paths or query).
- Base64url, bounded binary packet parsing, truncated/malformed metadata rejection.
- Signed descriptor challenge verification and tamper rejection.
- CryptoKit HPKE request opening and exported AES-GCM response authentication.
- Photo tokenization, multipart manifest, MIME/header-injection rejection and attachment limits.
- A fresh isolated real Rust 0.12.47 relay and fake-runtime Supervisor: native password login, device inventory, encrypted workspaces, encrypted model query, thread creation, prompt/reply, multipart photo upload and byte-identical encrypted image retrieval, changed-identity rejection, logout credential removal. Synthetic loopback fixture only; no production inference or host Supervisor restart.

## Historical native UI checks (0.1 / 0.2)

- Launched the packaged `.app` and signed in to the isolated relay through the actual native controls.
- Opened the three-column device/workspace/thread layout.
- Created a thread from discovered models and selected High reasoning from advertised Auto/Low/Medium/High options.
- Sent a text prompt; inspected native user/agent transcript and completion status.
- Opened the system image picker, selected the repository's icon, observed a thumbnail in the composer, sent it, and inspected the bounded image in the conversation.
- Relaunched the Development-signed build and restored the session from Keychain without signing in again.
- Filtered threads with native search and sent a message using Command-Return in the AppKit composer.
- Inspected both dark and light settings/chat appearance, then restored System appearance and signed out of the synthetic account.

## Current 0.3 UI checks

See [PARITY.md](PARITY.md). The shared workbench replaces the native three-column layout as the default. Browser route confinement, sensitive-query exclusion, HttpOnly session synchronization and native identity migration have targeted tests. The protocol fixture run passed in 26 seconds; the new browser-session test passed separately after it was added.

## 0.2.0 regression checks

- Real Rust encrypted continuations: 1.26 MB conversation and approximately 2.6 MB UTF-8 file round trips; sequential scoped chunk validation rejects cross-scope, changed-stream and malformed URLs.
- File create/read/save/read-back, stale-content conflict refusal, duplicate-create refusal, history pagination, High/Auto settings round trips.
- Native QA UI opened the large conversation, edited README.md with Command-S, reloaded saved content, and loaded the embedded authenticated thread and Settings without a second login.
- Initial UI testing exposed concurrent first-use Keychain writes; device key fetches now coalesce and Keychain insert races retry an update. The final eight-test integration run passed after this fix.
- QA uses a separate bundle ID and Keychain service. No production chat prompt or production file edit is part of the fixture tests.
- Rebuilt the production-named 0.2.0 app after normally quitting 0.1.0. Existing Keychain login restored; the exact reported wsl → remoteCodex → 1 conversation opened with its completed history and model/effort visible, without the continuation error. Read-only production verification only.

## Signing and deployment

Rebuilding a signed executable in-place while it was running caused macOS to terminate the **old test process** with `Code Signature Invalid`. The build script now refuses to overwrite a running app. Keychain operations were moved off the main actor so OS access prompts cannot freeze the application UI. Only the synthetic loopback session and identity entries were removed during this test reset; no production Keychain entries were touched.

Local packaging can use the existing Apple Development identity. This is not Developer ID distribution/notarization. The ordinary build and CI artifact default to an ad-hoc signature. A public stable distribution needs Developer ID, notarization and a versioned update channel.
