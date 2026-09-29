// Add synthetic ordered trace entries only to the isolated local fixture.
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
const fixture = JSON.parse(fs.readFileSync(new URL('../../.local/e2e-env.json', import.meta.url), 'utf8'));
if (new URL(fixture.relayUrl).hostname !== '127.0.0.1') throw Error('Loopback fixture required');
const root = path.resolve(fixture.workspacePath, '../..');
const local = path.resolve(new URL('../../.local', import.meta.url).pathname);
if (!root.startsWith(local + '/e2e.')) throw Error('Not an owned isolated fixture');
const db = new DatabaseSync(path.join(root, 'supervisor.sqlite'));
const thread = db.prepare("SELECT id FROM threads WHERE title='Mac parity checklist' ORDER BY updated_at DESC LIMIT 1").get();
if (!thread) throw Error('Run seed-parity first');
const turn = db.prepare('SELECT id, started_at FROM thread_turns WHERE thread_id=? AND status=? ORDER BY ordinal DESC LIMIT 1').get(thread.id, 'completed');
const insert = db.prepare('INSERT OR IGNORE INTO thread_history_items(id,thread_id,turn_id,item_id,item_json,created_at,updated_at) VALUES(?,?,?,?,?,?,?)');
const rows = [
  ['agentMessage', 'First intermediate checkpoint is retained.', null],
  ['reasoning', 'Inspecting the workspace files.', 'Reasoning details are retained.'],
  ['commandExecution', 'printf trace-one', 'trace-one\noutput including **literal asterisks**'],
  ['commandExecution', 'printf trace-two', 'trace-two\nsecond output'],
  ['agentMessage', 'Second intermediate checkpoint is retained.', null]
];
rows.forEach(([kind,text,detailText], i) => {
  const id = 'native-trace-' + turn.id + '-' + i;
  const time = new Date(new Date(turn.started_at).getTime() + i + 1).toISOString();
  const item = {id,kind,text,detailText,status:'completed',sequence:i+1,createdAt:time};
  insert.run(id,thread.id,turn.id,id,JSON.stringify(item),time,time);
});
db.close();
console.log('Seeded 5 synthetic trace entries in ' + thread.id);
