# macOS native client

The macOS client is explicitly authorized to use native SwiftUI conversation and composer views. The repository's WebView-only constraint continues to apply to Android/iOS, not this directory.

- macOS 14+, SwiftUI, CryptoKit, Keychain. No third-party dependencies.
- Relay origin first; authenticate with `/relay/auth/*`. Device requests must be encrypted, including attachments. Never fall back to plaintext.
- Keep tokens and pinned device identity keys in Keychain; never in UserDefaults, logs, or bundled files.
- Run `swift test`, build the app, and test native UI plus the isolated real relay transport after relevant changes.
- No runtime or mobile version bump for macOS-only changes. Local ad-hoc signatures are not notarized releases.
