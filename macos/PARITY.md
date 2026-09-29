# Native Mac / web comparison — 0.4.0

The 0.3 embedded web workspace has been removed. The 0.4 workspace, timeline, composer, editor and settings are SwiftUI views. A real loopback Rust 0.12.47 relay and the pinned web UI df80e5bc30a856a89668d3cbdf794e2343bfb854 provided the comparison fixture.

Screenshots were visually inspected through native UI automation. They were not asserted pixel-identical: viewport sizes, window chrome, font metrics and native controls differ. No similarity percentage is claimed, and private production transcripts are not committed as screenshots.

| Area | Native implementation and observed verification |
| --- | --- |
| Navigation | Web-shaped activity rail, compact sidebar and thread tabs; account recents and favorites read from the shared relay workbench |
| Appearance | Web-aligned dark/light colors and green accent; no visible gray scrolling gutters; native Light preference survives relaunch |
| Conversation | User bubbles on the right; assistant Markdown on the left; turn duration/model/effort below the reply |
| Markdown | Same synthetic heading, inline formatting, code, list and table inspected in Chrome and the native app |
| Activity | Tool details open in a popover instead of expanding the conversation layout |
| Composer | Command-Return sent a synthetic prompt; partial and completed replies appeared; native model dialog applied High effort |
| Images | System picker added the icon, composer showed the attachment, sending produced a bounded history image |
| New chat | Command-N opened native creation controls and created an empty ready conversation |
| Files | Native README edit/save showed Saved on device; protocol checks independently verify saved bytes and stale-write refusal |
| Terminal | Native encrypted socket attached; printf output appeared; owned test shell exited |
| Settings | Command-comma opened native tabs; Light theme, device inventory and harness inventory inspected; dismiss returned to conversation |
| Export and navigation | Real encrypted HTML export and shared favorite/navigation round trip covered by integration test |
| Restoration | Separate QA build restored login, theme and exact thread; production-named 0.4 restored the previous 0.3 ElAgente conversation with readable completed history |

## Remaining differences

- Command terminal output is bounded plain text with ANSI control removal, not a full terminal emulator. Full-screen TUI programs are explicitly marked unsupported.
- Markdown is a native block parser with inline attributed text. Complex nested syntax, KaTeX/Mermaid, syntax highlighting and web-rendered scientific/plugins are not equivalent.
- The plain-text editor has native selection/undo but not Monaco language services, rich document editing or a full web explorer layout.
- Chat uses foreground polling (one second while running), not WebSocket event streaming. History search searches loaded turns.
- Native prompt shortcuts are a small subset of the web command catalog. Advanced sharing, public-link administration, plugin management and some upstream configuration workflows are not present.
- Password/MFA sign-in is supported; OAuth/passkey onboarding and OS notification delivery have not been qualified.
- Settings mutations (runtime/harness installs, updates and real upstream changes) were not executed against the host as parity tests. Their presence is not evidence of end-to-end qualification for every harness.
- Drafts are not durable across application quit; a warning protects in-memory work.
- Apple Silicon/macOS 27.2 was tested; macOS 14 and Intel physical-device coverage remains outstanding.

Production checks were read-only except normal account navigation recording. Prompts, file writes and terminal commands were confined to the isolated fixture. No active host Supervisor was restarted.
