import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(__dirname, '..');
const cliEntry = path.join(packageRoot, 'dist', 'index.js');

function makeFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-cli-test-'));
  fs.mkdirSync(path.join(root, 'scripts'), { recursive: true });
  fs.writeFileSync(path.join(root, 'README.md'), '# cli smoke\n', 'utf8');
  fs.writeFileSync(
    path.join(root, 'scripts', 'agent-run-artifact.mjs'),
    'process.exit(0);\n',
    'utf8'
  );
  runGit(root, ['init']);
  runGit(root, ['config', 'user.name', 'GG CLI Tests']);
  runGit(root, ['config', 'user.email', 'tests@example.com']);
  runGit(root, ['add', '.']);
  runGit(root, ['commit', '-m', 'fixture']);
  return root;
}

function cleanupFixture(root) {
  fs.rmSync(root, { recursive: true, force: true });
}

function withFixture(fn) {
  const root = makeFixture();
  try {
    return fn(root);
  } finally {
    cleanupFixture(root);
  }
}

function runGit(cwd, args) {
  const result = spawnSync('git', args, {
    cwd,
    encoding: 'utf8'
  });
  assert.equal(result.status, 0, result.stderr || result.stdout || `git ${args.join(' ')} failed`);
}

function runCli(projectRoot, args) {
  const result = spawnSync('node', [cliEntry, '--json', '--project-root', projectRoot, ...args], {
    cwd: packageRoot,
    encoding: 'utf8'
  });
  const stdout = result.stdout.trim();
  const payload = stdout ? JSON.parse(stdout) : null;
  return {
    code: result.status ?? 1,
    stdout: result.stdout,
    stderr: result.stderr,
    payload
  };
}

test('run create plus worker spawn/status create a durable CLI-visible run', () => {
  withFixture((projectRoot) => {
    const created = runCli(projectRoot, [
      'run',
      'create',
      '--id',
      'run-cli-smoke',
      '--runtime',
      'codex',
      '--classification',
      'TASK',
      '--summary',
      'cli smoke'
    ]);

    assert.equal(created.code, 0, created.stderr);
    assert.equal(created.payload.ok, true);
    assert.equal(created.payload.data.runId, 'run-cli-smoke');

    const spawned = runCli(projectRoot, [
      'worker',
      'spawn',
      '--run-id',
      'run-cli-smoke',
      '--agent-id',
      'planner-1',
      '--runtime',
      'claude',
      '--role',
      'planner',
      '--task',
      'Plan the work',
      '--persona-id',
      'project-planner'
    ]);

    assert.equal(spawned.code, 0, spawned.stderr);
    assert.equal(spawned.payload.data.worker.agentId, 'planner-1');
    assert.equal(spawned.payload.data.worker.persona.personaId, 'project-planner');
    assert.match(spawned.payload.data.worker.worktree, /planner-1$/);

    const status = runCli(projectRoot, ['worker', 'status', '--run-id', 'run-cli-smoke']);
    assert.equal(status.code, 0, status.stderr);
    assert.equal(status.payload.data.workers.length, 1);
    assert.equal(status.payload.data.workers[0].agentId, 'planner-1');
  });
});

test('worker delegate and bus commands round-trip messages through the CLI', () => {
  withFixture((projectRoot) => {
    runCli(projectRoot, [
      'run',
      'create',
      '--id',
      'run-cli-bus',
      '--runtime',
      'codex',
      '--classification',
      'TASK',
      '--summary',
      'cli bus smoke'
    ]);

    runCli(projectRoot, [
      'worker',
      'spawn',
      '--run-id',
      'run-cli-bus',
      '--agent-id',
      'coordinator-1',
      '--runtime',
      'codex',
      '--role',
      'coordinator',
      '--task',
      'Coordinate this run',
      '--persona-id',
      'orchestrator',
      '--worktree',
      projectRoot
    ]);

    const rejected = runCli(projectRoot, [
      'worker',
      'delegate',
      '--run-id',
      'run-cli-bus',
      '--from-agent-id',
      'coordinator-1',
      '--agent-id',
      'builder-1',
      '--to-runtime',
      'kimi',
      '--role',
      'builder',
      '--task',
      'Implement auth workflow',
      '--persona-id',
      'backend-specialist'
    ]);

    assert.equal(rejected.code, 1, rejected.stderr);
    assert.equal(rejected.payload.data.decision.status, 'rejected');

    const approved = runCli(projectRoot, [
      'worker',
      'delegate',
      '--run-id',
      'run-cli-bus',
      '--from-agent-id',
      'coordinator-1',
      '--agent-id',
      'builder-1',
      '--to-runtime',
      'kimi',
      '--role',
      'builder',
      '--task',
      'Implement auth workflow',
      '--persona-id',
      'backend-specialist',
      '--board-approved',
      '--worktree',
      projectRoot
    ]);

    assert.equal(approved.code, 0, approved.stderr);
    assert.equal(approved.payload.data.decision.status, 'approved');
    assert.equal(approved.payload.data.worker.agentId, 'builder-1');

    const posted = runCli(projectRoot, [
      'bus',
      'post',
      '--run-id',
      'run-cli-bus',
      '--from-agent-id',
      'coordinator-1',
      '--to-agent-id',
      'builder-1',
      '--type',
      'TASK_SPEC',
      '--payload',
      '{"summary":"review cli wiring"}',
      '--requires-ack'
    ]);

    assert.equal(posted.code, 0, posted.stderr);
    const messageId = posted.payload.data.message.messageId;

    const inbox = runCli(projectRoot, [
      'bus',
      'inbox',
      '--run-id',
      'run-cli-bus',
      '--agent-id',
      'builder-1'
    ]);
    assert.equal(inbox.code, 0, inbox.stderr);
    assert.equal(inbox.payload.data.messages.length, 1);
    assert.equal(inbox.payload.data.messages[0].messageId, messageId);

    const acked = runCli(projectRoot, [
      'bus',
      'ack',
      '--run-id',
      'run-cli-bus',
      '--agent-id',
      'builder-1',
      '--message-id',
      messageId
    ]);
    assert.equal(acked.code, 0, acked.stderr);
    assert.ok(acked.payload.data.message.ackedAt);
  });
});
