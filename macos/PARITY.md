# Native Mac / web comparison — 0.6.1

The entire app is SwiftUI. 0.6.1 replaced the last embedded WKWebView — which had hosted Settings and the sharing/export dialogs — with native sheets that call the same backend APIs directly. Reference: Rust 0.12.47 and shared UI df80e5bc30a856a89668d3cbdf794e2343bfb854.

Native screenshots and accessibility state were inspected against the web design and behaviors. No pixel-identical or complete-feature-parity claim is made. Private production transcripts are not committed as screenshots.

| Area | Implementation / observed check |
| --- | --- |
| Navigation | Separate Devices and Workspaces pages; full rectangular thread-tab hit regions; generation guards discard stale selection responses |
| History | Three summary turns per page, deferred detail on expansion, retained prepend anchor; large user messages reveal text progressively without an accessibility layout hang |
| Trace | Inline Worked-for expansion; no empty reasoning cards; summary refresh cannot erase fetched operations; status summaries follow Settings; timestamps, ordered intermediate replies, numbered grouped commands and literal output |
| Composer | Compact two-level Model/Effort menu; clicking High immediately applies through encrypted settings API; no Apply |
| Slash | Actual capability/toolbox discovery, supported plan/fast/compact/fork/skills/MCP/hooks/goal actions; fake fixture correctly advertises only its supported subset. MCP/hooks/harness entries open the relay in a browser — they have no native editor |
| Thread tools | Secondary toolbar with pin, sharing, transcript download, actions and Explorer |
| Sharing | Native read-only link sheet (mints a device publication token, registers it with `/relay/thread-links`, lists/copies/revokes existing links) and a native permissions sheet over the relay shares/grants API |
| Export | Native HTML transcript sheet with latest-N or explicit turn selection and a token/price toggle, over `/api/threads/{id}/export-turns` and `/exports/html` |
| Files | Remote Markdown links stay in Explorer; Markdown preview/edit; hover-revealed per-row download; directories download as `.zip` through the shared `/files/download` endpoint; native download saved and byte-checked against the isolated README |
| Terminal | Direct keyboard input, arrows, Ctrl-C, resize and bracketed paste; printf, history replay and interrupted sleep verified in isolated shell |
| Settings | Native sheet for local display preferences only (appearance, 12–22px text size, auto-collapse, reasoning summaries), applied immediately to native rendering |
| Notifications | Native completion requests, baseline suppression, deduplication and same-origin/account click routing; OS banner permission verification pending user action |

## Known gaps

- **Harness, MCP, hook, upstream-profile and template configuration have no native editor.** 0.6.0 reached these through the embedded web Settings view; removing that WebView removed native access. The slash toolbox offers "Manage in browser…" and Command-Shift-O opens the current thread on the relay.
- The native Settings sheet covers local display preferences only. It is not the web Settings dialog and does not manage devices, harnesses or upstreams. Device management has its own native Devices page.
- Terminal supports a bounded VT subset, not complete full-screen TUI behavior: no SGR color rendering, complete Unicode cell-width handling or mouse protocol.
- Native Markdown lacks KaTeX/Mermaid, full nested CommonMark, syntax highlighting and web plugin renderers. Editor has no Monaco/LSP.
- Chat still polls rather than receiving WebSocket deltas; search covers loaded turns.
- Native goal history/pause/resume controls are not complete.
- The native sharing and permissions sheets are compile- and unit-verified against the documented API shapes, but their create/edit/revoke round-trips have not been exercised against a live relay with a second account.
- OAuth/passkey onboarding, every management mutation and physical macOS 14/Intel coverage remain unqualified. Native notifications require the app running and OS permission; actual system banner/click qualification is pending permission, not claimed passed.
- Drafts are in memory; quit warns before discarding them.

Prompts, file writes and terminal commands were confined to the isolated fixture. Production checks were read-only apart from normal account navigation recording. No host Supervisor was restarted.
