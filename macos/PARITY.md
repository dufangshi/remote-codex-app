# Mac / web parity audit — 0.3.0

Compared the same production wsl → remoteCodex → 1 conversation in Chrome and the 0.2.0 app, then tested 0.3.0 against a loopback Rust 0.12.47 relay with the shared UI at `df80e5bc30a856a89668d3cbdf794e2343bfb854`. Screenshots were inspected through native UI automation; production transcripts were not checked into the repository.

| Area | 0.2.0 gap | 0.3.0 action / observed result |
| --- | --- | --- |
| Navigation | Extra device and thread columns consume the workspace | Uses web activity rail, shortcuts, recent chats and workspace tabs directly |
| Theme and spacing | Gray native panels, blue controls, oversized composer | Uses the website's actual CSS and layout; window title bar follows theme |
| Markdown | Tables rendered as plain pipe-delimited text | Same synthetic table, heading, bold/italic, inline code, Swift code block and list visible in both clients |
| Timeline | Separate native item rendering and limited turn summaries | Uses shared timeline, tool grouping, usage and history implementation |
| Composer | Missing slash/model/sandbox/attachment menus | High effort selected; Command-Return sent `mac-shared-chat-ok` and its reply appeared |
| Attachments | Independent image pipeline | System picker selected AppIcon.png; composer attachment appeared, sent successfully, bounded conversation preview loaded |
| Explorer/editor | Separate file screen and editor | In-app shared editor saved README.md; Chrome read back the same edited content |
| Terminal | Advanced feature relegated to nested web fallback | Main workspace terminal attached; `printf` returned `mac-terminal-ok`; test shell exited |
| Settings | Separate native settings and web settings | Command-comma opened the same tabbed Preferences UI; light screenshots compared; close returned to unobscured conversation |
| New thread | Different native creation sheet | Command-N opened shared dialog and created `Mac UI created` |
| Export | Incomplete native conversation export | Shared export generated HTML through native Save panel; output contained the expected test conversation |
| Restart | Ephemeral web pins/preferences lost with the pane | Restart restored session, exact last thread and Light preference; no second login or changed-identity error |
| Sign-out | Native and web sessions could diverge | Web Log out followed by app relaunch returned to native sign-in, without silently restoring the revoked session |

## Scope and caveats

- Screenshots were visually compared, not asserted pixel-identical: viewport sizes, browser chrome, WebKit native checkboxes and font rasterization differ. No numeric similarity score is claimed.
- Runtime/harness install, billing, sharing changes, destructive deletion and paid real-model inference were not executed as UI-parity tests. Their existing web controls are reused, not independently reimplemented.
- Protocol tests cover encrypted history/file continuations, identity-change rejection, query boundaries and session persistence. Manual interface tests use a fake agent but a real relay, real encryption and real file/terminal services.
- Production verification is read-only. Test edits/prompts/export are confined to the isolated fixture.
- The app is an explicit native-shell/shared-web architecture, not a claim that React views have become native SwiftUI views.
