#!/usr/bin/env node
import { spawnSync } from 'node:child_process';

function usage() {
  console.log(`Usage:
  node scripts/gws-task.mjs list-lists
  node scripts/gws-task.mjs ensure-list --title "<name>"
  node scripts/gws-task.mjs list --tasklist <id>
  node scripts/gws-task.mjs add --tasklist <id> --title "<title>" [--notes "<notes>"] [--due YYYY-MM-DD]
  node scripts/gws-task.mjs complete --tasklist <id> --task <id>
  node scripts/gws-task.mjs sync-run --tasklist <id> --run-id <id> --title "<title>" [--status open|completed] [--notes "<notes>"]

Environment:
  GOOGLE_WORKSPACE_CLI_TOKEN or OAuth login for gws must be configured.
`);
}

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) {
      args._.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
      continue;
    }
    args[key] = next;
    i += 1;
  }
  return args;
}

function runGws(args) {
  const result = spawnSync('npx', ['-y', '@googleworkspace/cli', ...args], {
    encoding: 'utf8',
    env: process.env
  });

  if (result.status !== 0) {
    const err = result.stderr || result.stdout || `gws command failed (${result.status})`;
    throw new Error(err.trim());
  }

  return result.stdout;
}

function parseJsonOutput(raw) {
  const text = raw.trim();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`Expected JSON output but got: ${text.slice(0, 240)}`);
  }
}

function toDueTimestamp(dateYmd) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateYmd)) {
    throw new Error(`Invalid --due value "${dateYmd}". Expected YYYY-MM-DD.`);
  }
  return `${dateYmd}T00:00:00.000Z`;
}

function toCompletedTimestamp() {
  return new Date().toISOString();
}

function req(name, value) {
  if (!value || value === true) {
    throw new Error(`Missing required --${name}`);
  }
  return String(value);
}

function getItems(obj) {
  if (Array.isArray(obj?.items)) return obj.items;
  if (Array.isArray(obj)) return obj;
  return [];
}

function listTasklists() {
  const raw = runGws(['tasks', 'tasklists', 'list', '--format', 'json']);
  const json = parseJsonOutput(raw);
  const items = getItems(json);
  console.log(JSON.stringify({ count: items.length, items }, null, 2));
}

function ensureTasklist(title) {
  const raw = runGws(['tasks', 'tasklists', 'list', '--format', 'json']);
  const json = parseJsonOutput(raw);
  const items = getItems(json);
  const existing = items.find(i => i?.title === title);
  if (existing?.id) {
    console.log(JSON.stringify({ created: false, tasklist: existing }, null, 2));
    return;
  }

  const createdRaw = runGws([
    'tasks',
    'tasklists',
    'insert',
    '--json',
    JSON.stringify({ title }),
    '--format',
    'json'
  ]);
  const created = parseJsonOutput(createdRaw);
  console.log(JSON.stringify({ created: true, tasklist: created }, null, 2));
}

function listTasks(tasklist) {
  const raw = runGws([
    'tasks',
    'tasks',
    'list',
    '--params',
    JSON.stringify({
      tasklist,
      showCompleted: true,
      showHidden: false
    }),
    '--format',
    'json'
  ]);
  const json = parseJsonOutput(raw);
  const items = getItems(json);
  console.log(JSON.stringify({ tasklist, count: items.length, items }, null, 2));
}

function addTask(tasklist, title, notes, dueYmd) {
  const body = { title };
  if (notes) body.notes = notes;
  if (dueYmd) body.due = toDueTimestamp(dueYmd);

  const raw = runGws([
    'tasks',
    'tasks',
    'insert',
    '--params',
    JSON.stringify({ tasklist }),
    '--json',
    JSON.stringify(body),
    '--format',
    'json'
  ]);
  console.log(raw.trim());
}

function completeTask(tasklist, task) {
  const raw = runGws([
    'tasks',
    'tasks',
    'patch',
    '--params',
    JSON.stringify({ tasklist, task }),
    '--json',
    JSON.stringify({
      status: 'completed',
      completed: toCompletedTimestamp()
    }),
    '--format',
    'json'
  ]);
  console.log(raw.trim());
}

function syncRun(tasklist, runId, title, status, notes) {
  const listRaw = runGws([
    'tasks',
    'tasks',
    'list',
    '--params',
    JSON.stringify({
      tasklist,
      showCompleted: true,
      showHidden: false
    }),
    '--format',
    'json'
  ]);
  const existingItems = getItems(parseJsonOutput(listRaw));
  const runTag = `run-id:${runId}`;
  const existing = existingItems.find(i => {
    if (i?.title !== title) return false;
    return typeof i?.notes === 'string' ? i.notes.includes(runTag) : false;
  });

  const mergedNotes = [runTag, notes].filter(Boolean).join('\n');
  if (!existing?.id) {
    const payload = {
      title,
      notes: mergedNotes,
      status: status === 'completed' ? 'completed' : 'needsAction'
    };
    if (payload.status === 'completed') payload.completed = toCompletedTimestamp();

    const createdRaw = runGws([
      'tasks',
      'tasks',
      'insert',
      '--params',
      JSON.stringify({ tasklist }),
      '--json',
      JSON.stringify(payload),
      '--format',
      'json'
    ]);
    const created = parseJsonOutput(createdRaw);
    console.log(JSON.stringify({ created: true, task: created }, null, 2));
    return;
  }

  const patchBody = {
    notes: mergedNotes,
    status: status === 'completed' ? 'completed' : 'needsAction'
  };
  if (patchBody.status === 'completed') patchBody.completed = toCompletedTimestamp();

  const patchRaw = runGws([
    'tasks',
    'tasks',
    'patch',
    '--params',
    JSON.stringify({ tasklist, task: existing.id }),
    '--json',
    JSON.stringify(patchBody),
    '--format',
    'json'
  ]);
  const patched = parseJsonOutput(patchRaw);
  console.log(JSON.stringify({ created: false, task: patched }, null, 2));
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const [command] = args._;

  if (!command || command === 'help' || command === '--help') {
    usage();
    return;
  }

  switch (command) {
    case 'list-lists':
      listTasklists();
      return;
    case 'ensure-list':
      ensureTasklist(req('title', args.title));
      return;
    case 'list':
      listTasks(req('tasklist', args.tasklist));
      return;
    case 'add':
      addTask(
        req('tasklist', args.tasklist),
        req('title', args.title),
        args.notes ? String(args.notes) : '',
        args.due ? String(args.due) : ''
      );
      return;
    case 'complete':
      completeTask(req('tasklist', args.tasklist), req('task', args.task));
      return;
    case 'sync-run':
      syncRun(
        req('tasklist', args.tasklist),
        req('run-id', args['run-id']),
        req('title', args.title),
        args.status ? String(args.status) : 'open',
        args.notes ? String(args.notes) : ''
      );
      return;
    default:
      throw new Error(`Unknown command: ${command}`);
  }
}

try {
  main();
} catch (err) {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
}
