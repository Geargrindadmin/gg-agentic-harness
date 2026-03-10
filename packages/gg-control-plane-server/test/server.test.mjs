import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(__dirname, '..');

let port;
let projectRoot;
let serverProcess;

test.before(async () => {
  port = await getFreePort();
  projectRoot = await mkdtemp(path.join(os.tmpdir(), 'gg-control-plane-test-'));
  await mkdir(path.join(projectRoot, '.agent', 'control-plane'), { recursive: true });
  await writeFile(path.join(projectRoot, 'README.md'), '# control plane smoke\n');
  await writeFile(path.join(projectRoot, 'notes.md'), 'audit file\n');
  await runGit(['init']);
  await runGit(['config', 'user.name', 'GG Harness Tests']);
  await runGit(['config', 'user.email', 'tests@example.com']);
  await runGit(['add', '.']);
  await runGit(['commit', '-m', 'test fixture']);

  serverProcess = spawn('node', ['dist/index.js'], {
    cwd: packageRoot,
    env: {
      ...process.env,
      HARNESS_CONTROL_PLANE_PORT: String(port),
      HARNESS_DRY_RUN: '1',
      PROJECT_ROOT: projectRoot
    },
    stdio: ['ignore', 'pipe', 'pipe']
  });

  serverProcess.stdout.resume();
  serverProcess.stderr.resume();

  await waitForHealth();
});

test.after(async () => {
  if (serverProcess && !serverProcess.killed) {
    serverProcess.kill('SIGINT');
    await Promise.race([
      once(serverProcess, 'exit'),
      new Promise((resolve) => setTimeout(resolve, 3_000))
    ]);
  }
  if (projectRoot) {
    await rm(projectRoot, { recursive: true, force: true });
  }
});

test('core control-plane surfaces respond with expected shapes', async () => {
  const meta = await getJson('/api/meta');
  assert.equal(meta.service, 'gg-control-plane-server');
  assert.ok(Array.isArray(meta.capabilities));

  const planner = await getJson('/api/planner');
  assert.equal(planner.project.root, projectRoot);
  assert.ok(Array.isArray(planner.tasks));
  assert.ok(Array.isArray(planner.notes));

  const runtimeDiscovery = await getJson('/api/runtime-discovery');
  assert.equal(runtimeDiscovery.coordinatorSelection.requested, 'auto');
  assert.ok(Array.isArray(runtimeDiscovery.discoveries));

  const agentAnalytics = await getJson('/api/agent-analytics');
  assert.equal(typeof agentAnalytics.summary.totalRuns, 'number');

  const replays = await getJson('/api/replays/sources');
  assert.ok(Array.isArray(replays.sources));

  const modelFit = await getJson('/api/model-fit/system');
  assert.equal(typeof modelFit.available, 'boolean');

  const freeModels = await getJson('/api/free-models/catalog');
  assert.ok(Array.isArray(freeModels.providers));

  const skillStats = await getJson('/api/skill-stats');
  assert.ok(Array.isArray(skillStats.stats));
});

test('planner task CRUD and integration settings round-trip', async () => {
  const created = await requestJson('/api/planner/tasks', {
    method: 'POST',
    body: {
      title: 'smoke planner task',
      description: 'verify planner CRUD',
      status: 'todo',
      source: 'server-test'
    }
  });

  assert.equal(created.statusCode, 201);
  const taskId = created.payload.task.id;
  assert.equal(created.payload.task.title, 'smoke planner task');

  const updated = await requestJson(`/api/planner/tasks/${taskId}`, {
    method: 'PATCH',
    body: {
      status: 'in_progress',
      priority: 2,
      source: 'server-test'
    }
  });
  assert.equal(updated.statusCode, 200);
  assert.equal(updated.payload.task.status, 'in_progress');

  const removed = await requestJson(`/api/planner/tasks/${taskId}`, {
    method: 'DELETE'
  });
  assert.equal(removed.statusCode, 200);
  assert.equal(removed.payload.ok, true);

  const settings = await getJson('/api/integrations/settings');
  const roundTrip = await requestJson('/api/integrations/settings', {
    method: 'PUT',
    body: settings
  });
  assert.equal(roundTrip.statusCode, 200);
  assert.ok(roundTrip.payload.qualityTools);
  assert.ok(roundTrip.payload.mcpCatalog);

  const mcpCatalog = await getJson('/api/integrations/mcp/catalog');
  assert.ok(Array.isArray(mcpCatalog.servers));
});

test('harness settings and dynamic diagram endpoints round-trip', async () => {
  const settings = await getJson('/api/harness/settings');
  assert.equal(settings.execution.loopBudget, 50);
  assert.equal(settings.execution.retryLimit, 3);

  const updated = await requestJson('/api/harness/settings', {
    method: 'PUT',
    body: {
      ...settings,
      execution: {
        ...settings.execution,
        loopBudget: 18,
        retryLimit: 2,
        promptImproverMode: 'force',
        hydraMode: 'shadow'
      },
      governor: {
        ...settings.governor,
        cpuHighPct: 91
      }
    }
  });
  assert.equal(updated.statusCode, 200);
  assert.equal(updated.payload.execution.loopBudget, 18);
  assert.equal(updated.payload.governor.cpuHighPct, 91);

  const diagram = await getJson('/api/harness/diagram');
  assert.equal(diagram.settings.execution.loopBudget, 18);
  assert.equal(typeof diagram.live.activity.totalRuns, 'number');
  assert.match(diagram.diagram.artifactRelativePath, /agentic-harness-dynamic-user-diagram\.html$/);

  const reset = await requestJson('/api/harness/settings/reset', {
    method: 'POST'
  });
  assert.equal(reset.statusCode, 200);
  assert.equal(reset.payload.execution.loopBudget, 50);
});

test('dry-run task dispatch creates run, bus state, and worktree browsing surface', async () => {
  const dispatch = await requestJson('/api/task', {
    method: 'POST',
    body: {
      task: 'dry-run server smoke',
      mode: 'minion',
      coordinator: 'codex',
      workerBackend: 'codex'
    }
  });

  assert.equal(dispatch.statusCode, 202);
  const runId = dispatch.payload.runId;
  assert.ok(runId.startsWith('run-'));

  const runs = await getJson('/api/runs');
  assert.ok(runs.runs.some((entry) => entry.runId === runId));

  const busRuns = await getJson('/api/bus');
  assert.ok(busRuns.runs.some((entry) => entry.runId === runId));

  const busStatus = await getJson(`/api/bus/${runId}/status`);
  assert.equal(busStatus.runId, runId);
  assert.ok(Object.keys(busStatus.workers).length >= 1);

  const worktree = await getJson(`/api/worktree?path=${encodeURIComponent(projectRoot)}`);
  assert.equal(worktree.path, projectRoot);
  assert.ok(worktree.totalFiles >= 1);
  assert.ok(Array.isArray(worktree.files));
});

async function waitForHealth() {
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`http://127.0.0.1:${port}/health`);
      if (response.ok) {
        return;
      }
    } catch {
      // ignore until deadline
    }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error(`control plane failed to become healthy on port ${port}`);
}

async function getJson(pathname) {
  const response = await fetch(`http://127.0.0.1:${port}${pathname}`);
  assert.equal(response.status, 200, `Expected 200 for ${pathname}`);
  return response.json();
}

async function requestJson(pathname, { method, body }) {
  const response = await fetch(`http://127.0.0.1:${port}${pathname}`, {
    method,
    headers: body ? { 'content-type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined
  });
  const payload = await response.json();
  return { statusCode: response.status, payload };
}

async function getFreePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.unref();
    server.on('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (!address || typeof address === 'string') {
        server.close();
        reject(new Error('failed to allocate test port'));
        return;
      }
      server.close(() => resolve(address.port));
    });
  });
}

async function runGit(args) {
  await new Promise((resolve, reject) => {
    const child = spawn('git', args, {
      cwd: projectRoot,
      stdio: ['ignore', 'ignore', 'pipe']
    });
    let stderr = '';
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(stderr || `git ${args.join(' ')} failed with code ${code}`));
    });
  });
}
