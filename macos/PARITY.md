# Native Mac / web comparison — 0.5.0

The workbench, conversation, composer, files and terminal remain SwiftUI. Settings and sharing/export dialogs reuse the relay web implementation; they are not a replacement web conversation. Reference: Rust 0.12.47 and shared UI df80e5bc30a856a89668d3cbdf794e2343bfb854.

Native screenshots and accessibility state were inspected against the web design and behaviors. No pixel-identical or complete-feature-parity claim is made. Private production transcripts are not committed as screenshots.

| Area | Implementation / observed check |
| --- | --- |
| Navigation | Separate Devices and Workspaces pages; full rectangular thread-tab hit regions; generation guards discard stale selection responses |
| History | Three summary turns per page, deferred detail on expansion, retained prepend anchor; large user messages reveal text progressively without an accessibility layout hang |
| Trace | Inline Worked-for expansion before final reply; ordered intermediate replies, reasoning and grouped commands; literal command output preserved |
| Composer | Anchored model/reasoning popover; High applied through real encrypted settings API |
| Slash | Actual capability/toolbox discovery, supported plan/fast/compact/fork/skills/MCP/hooks/goal actions; fake fixture correctly advertises only its supported subset |
| Thread tools | Secondary toolbar with pin, sharing, transcript download, actions and Explorer; actual shared-link dialog opened without publishing a link |
| Files | Remote Markdown links stay in Explorer; Markdown preview/edit; native download saved and byte-checked against the isolated README |
| Terminal | Direct keyboard input, arrows, Ctrl-C, resize and bracketed paste; printf, history replay and interrupted sleep verified in isolated shell |
| Settings | Actual web Preferences/Session/Harnesses/Device/Workspace/Plugins/Advanced tabs; closing returns to native conversation |

## Known gaps

- Terminal supports a bounded VT subset, not complete full-screen TUI behavior: no SGR color rendering, complete Unicode cell-width handling or mouse protocol.
- Native Markdown lacks KaTeX/Mermaid, full nested CommonMark, syntax highlighting and web plugin renderers. Editor has no Monaco/LSP.
- Chat still polls rather than receiving WebSocket deltas; search covers loaded turns.
- MCP/hooks editing delegates to shared Settings. Native goal history/pause/resume controls are not complete.
- OAuth/passkey onboarding, OS notification delivery, every management mutation and physical macOS 14/Intel coverage remain unqualified.
- Drafts are in memory; quit warns before discarding them.

Prompts, file writes and terminal commands were confined to the isolated fixture. Production checks were read-only apart from normal account navigation recording. No host Supervisor was restarted.
