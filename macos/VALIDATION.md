# Native preview validation

Development target: Apple Silicon, macOS 27.2, Xcode 27 beta; deployment minimum macOS 14. This is not a claim of physical-device testing on macOS 14 or Intel.

## Automated checks

- Swift package compilation and seven XCTest cases.
- Origin validation (HTTPS or loopback HTTP; no embedded credentials, paths or query).
- Base64url, bounded binary packet parsing, truncated/malformed metadata rejection.
- Signed descriptor challenge verification and tamper rejection.
- CryptoKit HPKE request opening and exported AES-GCM response authentication.
- Photo tokenization, multipart manifest, MIME/header-injection rejection and attachment limits.
- A fresh isolated real Rust 0.12.47 relay and fake-runtime Supervisor: native password login, device inventory, encrypted workspaces, encrypted model query, thread creation, prompt/reply, multipart photo upload and byte-identical encrypted image retrieval, changed-identity rejection, logout credential removal. Synthetic loopback fixture only; no production inference or host Supervisor restart.

## Native UI checks

- Launched the packaged `.app` and signed in to the isolated relay through the actual native controls.
- Opened the three-column device/workspace/thread layout.
- Created a thread from discovered models and selected High reasoning from advertised Auto/Low/Medium/High options.
- Sent a text prompt; inspected native user/agent transcript and completion status.
- Opened the system image picker, selected the repository's icon, observed a thumbnail in the composer, sent it, and inspected the bounded image in the conversation.
- Relaunched the Development-signed build and restored the session from Keychain without signing in again.
- Filtered threads with native search and sent a message using Command-Return in the AppKit composer.
- Inspected both dark and light settings/chat appearance, then restored System appearance and signed out of the synthetic account.

## Packaging observations

Rebuilding a signed executable in-place while it was running caused macOS to terminate the **old test process** with `Code Signature Invalid`. The build script now refuses to overwrite a running app. Keychain operations were moved off the main actor so OS access prompts cannot freeze the application UI. Only the synthetic loopback session and identity entries were removed during this test reset; no production Keychain entries were touched.

Local packaging can use the existing Apple Development identity. This is not Developer ID distribution/notarization. The ordinary build and CI artifact default to an ad-hoc signature. A public stable distribution needs Developer ID, notarization and a versioned update channel.
