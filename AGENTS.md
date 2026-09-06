# Agent notes

This is the Remote Codex mobile client. It is not the control-plane repo.

- Keep the native shell aligned with `apps/supervisor-web` in remoteCodex: same route stack, back targets, labels, and theme tokens.
- Thread conversation stays in a WebView of the relay-hosted thread page. Do not reimplement timeline/composer natively.
- Relay mode only. The first screen collects the relay origin; after that, auth is `/relay/auth/*`.
- JSON field names are camelCase.
- After Android or iOS changes, run the matching simulator E2E, not a web Playwright suite.
