// Synthetic content only; refuses non-loopback backends. Run after e2e-backend.sh.
import fs from 'node:fs';
const fixture = JSON.parse(fs.readFileSync(new URL('../../.local/e2e-env.json', import.meta.url), 'utf8'));
if (new URL(fixture.relayUrl).hostname !== '127.0.0.1') throw Error('Loopback fixture required');
const base = `http://127.0.0.1:${process.env.E2E_SUPERVISOR_PORT || 18791}`;
const login = await fetch(base + '/api/auth/login', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({username: 'admin', password: 'admin-pass-1'})});
if (!login.ok) throw Error(`Fixture login failed: ${login.status}`);
const headers = {'Content-Type': 'application/json', Cookie: login.headers.getSetCookie().map(x => x.split(';')[0]).join('; ')};
const response = await fetch(base + '/api/threads/start', {method: 'POST', headers, body: JSON.stringify({workspaceId: fixture.workspaceId, title: 'Mac parity checklist', provider: 'acp', agentId: 'codex', model: 'ios-e2e-stream', approvalMode: 'yolo'})});
if (!response.ok) throw Error(`${response.status}: ${await response.text()}`);
const thread = await response.json();
const prompt = 'Reply with exactly ## Workspace parity\n\nThis is **bold**, *italic* and `inline code`.\n\n| Feature | Status |\n| --- | --- |\n| Chat | Ready |\n| Files | Ready |\n\n```swift\nlet message = "Native shell, shared workspace"\nprint(message)\n```\n\n- Rich Markdown\n- Encrypted files\n- Shared settings';
const sent = await fetch(base + `/api/threads/${thread.id}/prompt`, {method: 'POST', headers, body: JSON.stringify({prompt, clientRequestId: crypto.randomUUID()})});
if (!sent.ok) throw Error(`${sent.status}: ${await sent.text()}`);
console.log(`${fixture.relayUrl}/devices/${fixture.deviceId}/threads/${thread.id}`);
