import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import { spawn, spawnSync } from 'node:child_process';
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

function seedHarnessFixture(root, options = {}) {
  const {
    contextExitCode = 0,
    parityOk = true
  } = options;

  fs.mkdirSync(path.join(root, '.agent', 'skills', 'example-skill'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'workflows'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'agents'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'runs'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'packs'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'product-lanes'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'schemas'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'control-plane', 'runs'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'control-plane', 'worktrees'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'control-plane', 'executions'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'control-plane', 'server'), { recursive: true });

  fs.writeFileSync(
    path.join(root, '.agent', 'skills', 'example-skill', 'SKILL.md'),
    '---\nname: example-skill\ndescription: Example skill\n---\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'workflows', 'agentic-status.md'),
    '---\nname: agentic-status\ndescription: Status surface\n---\n',
    'utf8'
  );
  fs.writeFileSync(path.join(root, '.agent', 'agents', 'coordinator.md'), '# coordinator\n', 'utf8');
  fs.writeFileSync(path.join(root, '.agent', 'packs', 'design-system.json'), '{"slug":"design-system"}\n', 'utf8');
  fs.writeFileSync(path.join(root, '.agent', 'product-lanes', 'marketing-site.json'), '{"slug":"marketing-site"}\n', 'utf8');
  fs.writeFileSync(
    path.join(root, '.agent', 'schemas', 'canonical-product-spec.schema.json'),
    '{"$schema":"https://json-schema.org/draft/2020-12/schema"}\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'runs', 'seed-run.json'),
    `${JSON.stringify({
      runId: 'seed-run',
      workflow: 'go',
      status: 'HANDOFF_READY',
      createdAt: '2026-03-09T00:00:00.000Z'
    }, null, 2)}\n`,
    'utf8'
  );
  fs.writeFileSync(path.join(root, '.agent', 'control-plane', 'runs', 'state.json'), '{}\n', 'utf8');
  fs.writeFileSync(path.join(root, '.agent', 'control-plane', 'server', 'socket.json'), '{}\n', 'utf8');
  fs.writeFileSync(path.join(root, '.mcp.json'), '{"mcpServers":{"gg-skills":{"args":["mcp-servers/gg-skills/dist/index.js"]}}}\n', 'utf8');

  fs.writeFileSync(
    path.join(root, 'scripts', 'runtime-project-sync.mjs'),
    `const payload = {
  active: true,
  activationType: 'host-config',
  checks: [
    { id: 'config_toml_exists', ok: true, detail: 'config.toml' },
    { id: 'gg_skills_json', ok: true, detail: 'mcp.json' }
  ]
};
console.log(JSON.stringify(payload));
`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, 'scripts', 'runtime-parity-smoke.mjs'),
    `const payload = {
  ok: ${parityOk ? 'true' : 'false'},
  strict: true,
  results: [
    {
      status: ${parityOk ? "'pass'" : "'fail'"},
      id: 'runtime_registry',
      summary: ${parityOk ? "'Runtime registry is aligned'" : "'Runtime registry is stale'"},
      detail: 'fixture'
    }
  ]
};
console.log(JSON.stringify(payload));
process.exit(${parityOk ? '0' : '1'});
`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, 'scripts', 'generate-project-context.mjs'),
    `console.log(${JSON.stringify(contextExitCode === 0 ? 'Project context up to date' : 'Project context is stale')});
process.exit(${String(contextExitCode)});
`,
    'utf8'
  );

  runGit(root, ['add', '.']);
  runGit(root, ['commit', '-m', 'seed harness fixture']);
}

function seedGoFixture(root, options = {}) {
  const {
    activationActive = true,
    parityOk = true,
    contextExitCode = 0
  } = options;

  fs.mkdirSync(path.join(root, '.agent', 'skills', 'example-skill'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'workflows'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'product-lanes'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'packs'), { recursive: true });
  fs.mkdirSync(path.join(root, 'docs'), { recursive: true });

  fs.writeFileSync(
    path.join(root, '.agent', 'skills', 'example-skill', 'SKILL.md'),
    '---\nname: example-skill\ndescription: Example skill\n---\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'workflows', 'go.md'),
    '---\nname: go\ndescription: Goal intake\n---\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'workflows', 'create.md'),
    '---\nname: create\ndescription: Headless product bundle generation\n---\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'workflows', 'minion.md'),
    '---\nname: minion\ndescription: Autonomous execution\n---\n',
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'product-lanes', 'marketing-site.json'),
    `${JSON.stringify({
      id: 'marketing-site',
      name: 'Marketing Site',
      description: 'Public-facing marketing site',
      v1Mandatory: true,
      category: 'web',
      allowedStacks: ['nextjs-app-router', 'vite-react'],
      defaultStack: 'nextjs-app-router',
      requiredCapabilities: ['responsive-layout', 'seo-metadata'],
      defaultPacks: ['design-system', 'observability'],
      allowedPacks: ['design-system', 'observability', 'notifications'],
      requiredGates: ['typecheck', 'lint', 'ui-smoke']
    }, null, 2)}\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'product-lanes', 'saas-dashboard.json'),
    `${JSON.stringify({
      id: 'saas-dashboard',
      name: 'SaaS Dashboard',
      description: 'Authenticated enterprise dashboard with settings and analytics',
      v1Mandatory: true,
      category: 'web-app',
      allowedStacks: ['nextjs-app-router', 'vite-react-node'],
      defaultStack: 'nextjs-app-router',
      requiredCapabilities: ['authenticated-shell', 'typed-api-layer', 'loading-empty-error-states'],
      defaultPacks: ['design-system', 'observability', 'auth-rbac'],
      allowedPacks: ['design-system', 'observability', 'auth-rbac', 'billing-stripe'],
      requiredGates: ['typecheck', 'lint', 'targeted-tests']
    }, null, 2)}\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'product-lanes', 'admin-panel.json'),
    `${JSON.stringify({
      id: 'admin-panel',
      name: 'Admin Panel',
      description: 'Internal admin and operations interface',
      v1Mandatory: true,
      category: 'internal-web-app',
      allowedStacks: ['nextjs-app-router', 'vite-react-node'],
      defaultStack: 'nextjs-app-router',
      requiredCapabilities: ['rbac-ready-shell', 'operational-controls'],
      defaultPacks: ['design-system', 'observability', 'auth-rbac'],
      allowedPacks: ['design-system', 'observability', 'auth-rbac', 'admin-ops'],
      requiredGates: ['typecheck', 'lint', 'operational-smoke']
    }, null, 2)}\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'packs', 'design-system.json'),
    `${JSON.stringify({
      id: 'design-system',
      name: 'Design System',
      description: 'Shared UI patterns',
      v1Unattended: true,
      riskTier: 'low',
      compatibleLanes: ['marketing-site', 'saas-dashboard', 'admin-panel'],
      requiredConfig: [],
      addsCapabilities: ['ui-tokens'],
      requiredGates: ['ui-smoke'],
      reviewRequired: false
    }, null, 2)}\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'packs', 'observability.json'),
    `${JSON.stringify({
      id: 'observability',
      name: 'Observability',
      description: 'Telemetry hooks',
      v1Unattended: true,
      riskTier: 'low',
      compatibleLanes: ['marketing-site', 'saas-dashboard', 'admin-panel'],
      requiredConfig: [],
      addsCapabilities: ['logging-hooks'],
      requiredGates: ['docs-bundle'],
      reviewRequired: false
    }, null, 2)}\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'packs', 'auth-rbac.json'),
    `${JSON.stringify({
      id: 'auth-rbac',
      name: 'Auth and RBAC',
      description: 'Authenticated shell and permissions',
      v1Unattended: true,
      riskTier: 'medium',
      compatibleLanes: ['saas-dashboard', 'admin-panel'],
      requiredConfig: ['auth-provider', 'session-strategy'],
      addsCapabilities: ['authenticated-shell'],
      requiredGates: ['targeted-tests'],
      reviewRequired: true
    }, null, 2)}\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'packs', 'billing-stripe.json'),
    `${JSON.stringify({
      id: 'billing-stripe',
      name: 'Billing via Stripe',
      description: 'Stripe billing surfaces',
      v1Unattended: false,
      riskTier: 'high',
      compatibleLanes: ['saas-dashboard'],
      requiredConfig: ['stripe-secret-key', 'stripe-publishable-key'],
      addsCapabilities: ['billing-settings'],
      requiredGates: ['security-review'],
      reviewRequired: true
    }, null, 2)}\n`,
    'utf8'
  );
  fs.writeFileSync(path.join(root, 'docs', 'project-context.md'), '# Project Context\n', 'utf8');
  fs.writeFileSync(
    path.join(root, 'scripts', 'runtime-project-sync.mjs'),
    `console.log(JSON.stringify({
  active: ${activationActive ? 'true' : 'false'},
  activationType: ${activationActive ? "'host-config'" : 'null'},
  checks: [
    { id: 'config_toml_exists', ok: ${activationActive ? 'true' : 'false'}, detail: 'config.toml' },
    { id: 'gg_skills_json', ok: ${activationActive ? 'true' : 'false'}, detail: 'mcp.json' }
  ]
}));\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, 'scripts', 'runtime-parity-smoke.mjs'),
    `console.log(JSON.stringify({
  ok: ${parityOk ? 'true' : 'false'},
  strict: true,
  results: [
    {
      status: ${parityOk ? "'pass'" : "'fail'"},
      id: 'runtime_registry',
      summary: ${parityOk ? "'Runtime registry is aligned'" : "'Runtime registry is stale'"},
      detail: 'fixture'
    }
  ]
}));
process.exit(${parityOk ? '0' : '1'});\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, 'scripts', 'generate-project-context.mjs'),
    `console.log(${JSON.stringify(contextExitCode === 0 ? 'Project context is up to date.' : 'Project context is stale.')});
process.exit(${String(contextExitCode)});\n`,
    'utf8'
  );

  runGit(root, ['add', '.']);
  runGit(root, ['commit', '-m', 'seed go fixture']);
}

function withFixture(fn) {
  const root = makeFixture();
  try {
    const result = fn(root);
    if (result && typeof result.then === 'function') {
      return result.finally(() => {
        cleanupFixture(root);
      });
    }
    cleanupFixture(root);
    return result;
  } finally {
    if (fs.existsSync(root)) {
      cleanupFixture(root);
    }
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

function runCliAsync(projectRoot, args) {
  return new Promise((resolve, reject) => {
    const child = spawn('node', [cliEntry, '--json', '--project-root', projectRoot, ...args], {
      cwd: packageRoot,
      stdio: ['ignore', 'pipe', 'pipe']
    });
    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
    });
    child.on('error', reject);
    child.on('close', (code) => {
      const trimmed = stdout.trim();
      resolve({
        code: code ?? 1,
        stdout,
        stderr,
        payload: trimmed ? JSON.parse(trimmed) : null
      });
    });
  });
}

async function withRpcServer(responses, fn) {
  const requests = [];
  let index = 0;
  const server = net.createServer((socket) => {
    const chunks = [];
    socket.on('data', (chunk) => {
      chunks.push(chunk);
    });
    socket.on('end', () => {
      const payload = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      requests.push(payload);
      const response = responses[Math.min(index, responses.length - 1)];
      index += 1;
      socket.end(`${JSON.stringify(response)}\n`);
    });
  });

  await new Promise((resolve, reject) => {
    server.listen(0, '127.0.0.1', () => resolve());
    server.once('error', reject);
  });

  const address = server.address();
  assert.equal(typeof address, 'object');
  assert.ok(address && typeof address.port === 'number');

  try {
    return await fn({ port: address.port, requests });
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
  }
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

test('harness settings and diagram commands work without the macOS app', () => {
  withFixture((projectRoot) => {
    fs.mkdirSync(path.join(projectRoot, 'docs', 'architecture'), { recursive: true });
    fs.writeFileSync(
      path.join(projectRoot, 'docs', 'architecture', 'agentic-harness-dynamic-user-diagram.html'),
      '<!doctype html><title>fixture</title>',
      'utf8'
    );

    const initial = runCli(projectRoot, ['harness', 'settings', 'get']);
    assert.equal(initial.code, 0, initial.stderr);
    assert.equal(initial.payload.data.settings.execution.loopBudget, 50);

    const updated = runCli(projectRoot, [
      'harness',
      'settings',
      'set',
      '--key',
      'execution.loopBudget',
      '--value',
      '32'
    ]);
    assert.equal(updated.code, 0, updated.stderr);
    assert.equal(updated.payload.data.settings.execution.loopBudget, 32);

    const diagram = runCli(projectRoot, ['harness', 'diagram', '--format', 'json']);
    assert.equal(diagram.code, 0, diagram.stderr);
    assert.match(diagram.payload.data.artifactPath, /agentic-harness-dynamic-user-diagram\.html$/);

    const reset = runCli(projectRoot, ['harness', 'settings', 'reset']);
    assert.equal(reset.code, 0, reset.stderr);
    assert.equal(reset.payload.data.settings.execution.loopBudget, 50);
  });
});

test('workflow run agentic-status executes a real headless status check and writes an artifact', () => {
  withFixture((projectRoot) => {
    seedHarnessFixture(projectRoot);

    const result = runCli(projectRoot, ['workflow', 'run', 'agentic-status', '--limit', '2']);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.payload.ok, true);
    assert.equal(result.payload.data.overall, 'healthy');
    assert.equal(result.payload.data.runtime.activation.active, true);
    assert.equal(result.payload.data.runtime.context.status, 'current');
    assert.equal(result.payload.data.catalogs.productLanesCount, 1);
    assert.equal(result.payload.data.catalogs.packsCount, 1);
    assert.equal(result.payload.data.recentRuns.length, 1);
    assert.match(result.payload.data.runArtifact, /agentic-status-[a-z0-9]+-[a-z0-9]+\.json$/);

    const artifact = JSON.parse(fs.readFileSync(result.payload.data.runArtifact, 'utf8'));
    assert.equal(artifact.runId, result.payload.data.runId);
    assert.equal(artifact.summary.failingChecks, 0);
    assert.equal(Array.isArray(artifact.checks), true);
    assert.equal(artifact.checks.some((check) => check.id === 'project_context_check'), true);
  });
});

test('workflow run go normalizes a supported product prompt and routes it into create', () => {
  withFixture((projectRoot) => {
    seedGoFixture(projectRoot);

    const result = runCli(projectRoot, [
      'workflow',
      'run',
      'go',
      'Build a SaaS dashboard for vendor analytics with RBAC, settings, alerting, and admin views.'
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.payload.ok, true);
    assert.equal(result.payload.data.sourceType, 'prompt');
    assert.equal(result.payload.data.canonicalSpec.lane, 'saas-dashboard');
    assert.equal(result.payload.data.canonicalSpec.targetStack, 'nextjs-app-router');
    assert.deepEqual(
      result.payload.data.canonicalSpec.enterprisePacks,
      ['design-system', 'observability', 'auth-rbac']
    );
    assert.equal(result.payload.data.canonicalSpec.validationProfile, 'saas-dashboard');
    assert.equal(result.payload.data.canonicalSpec.requiresHumanReview, true);
    assert.equal(result.payload.data.laneSelection.laneId, 'saas-dashboard');
    assert.equal(result.payload.data.routedWorkflow, 'create');
    assert.equal(result.payload.data.resolvedExecutionPath, 'builder');
    assert.equal(result.payload.data.builderInvoked, true);
    assert.match(result.payload.data.downstreamRunArtifact, /create-[a-z0-9]+-[a-z0-9]+\.json$/);
    assert.match(result.payload.data.bundleDir, /product-bundles\/go-[a-z0-9]+-[a-z0-9]+$/);
    assert.match(result.payload.data.bundleManifest, /product-bundles\/go-[a-z0-9]+-[a-z0-9]+\/gg-product-bundle\.json$/);
    assert.equal(Array.isArray(result.payload.data.generatedFiles), true);
    assert.match(result.payload.data.specArtifact, /go-[a-z0-9]+-[a-z0-9]+\.spec\.json$/);

    const spec = JSON.parse(fs.readFileSync(result.payload.data.specArtifact, 'utf8'));
    assert.equal(spec.lane, 'saas-dashboard');
    assert.equal(spec.sourceType, 'prompt');

    const bundleManifest = JSON.parse(fs.readFileSync(result.payload.data.bundleManifest, 'utf8'));
    assert.equal(bundleManifest.lane, 'saas-dashboard');

    const artifact = JSON.parse(fs.readFileSync(result.payload.data.runArtifact, 'utf8'));
    assert.equal(artifact.routedWorkflow, 'create');
    assert.equal(artifact.resolvedExecutionPath, 'builder');
    assert.equal(artifact.builderInvoked, true);
  });
});

test('workflow run go accepts a PRD file and resolves downstream install targets', () => {
  withFixture((projectRoot) => {
    seedGoFixture(projectRoot);
    fs.mkdirSync(path.join(projectRoot, 'docs', 'prd'), { recursive: true });
    fs.writeFileSync(
      path.join(projectRoot, 'docs', 'prd', 'downstream-proof.md'),
      [
        '# Downstream Proof',
        '',
        'Install the finished harness into GGV3 and prove one downstream supported build path.',
        'Use a SaaS dashboard shell with RBAC, settings, and observability.'
      ].join('\n'),
      'utf8'
    );

    const result = runCli(projectRoot, [
      'workflow',
      'run',
      'go',
      'docs/prd/downstream-proof.md'
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.payload.ok, true);
    assert.equal(result.payload.data.sourceType, 'prd');
    assert.equal(result.payload.data.sourcePath, 'docs/prd/downstream-proof.md');
    assert.equal(result.payload.data.canonicalSpec.sourceType, 'prd');
    assert.equal(result.payload.data.canonicalSpec.deliveryTarget, 'downstream-install');
    assert.equal(result.payload.data.canonicalSpec.downstreamTarget, 'GGV3');
    assert.equal(result.payload.data.canonicalSpec.lane, 'saas-dashboard');
  });
});

test('workflow run go keeps informational pricing marketing PRDs on the builder path', () => {
  withFixture((projectRoot) => {
    seedGoFixture(projectRoot);
    fs.mkdirSync(path.join(projectRoot, 'docs', 'prd'), { recursive: true });
    fs.writeFileSync(
      path.join(projectRoot, 'docs', 'prd', 'signalforge.md'),
      [
        '# SignalForge Launch PRD',
        '',
        'Build a launch-ready marketing site for SignalForge.',
        'SignalForge helps operations teams automate work across CRM, billing, support, and approvals.',
        'Include an informational pricing section only.',
        'Do not add checkout, subscriptions, payments, billing APIs, or Stripe integration.'
      ].join('\n'),
      'utf8'
    );

    const result = runCli(projectRoot, [
      'workflow',
      'run',
      'go',
      'docs/prd/signalforge.md'
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.payload.ok, true);
    assert.equal(result.payload.data.sourceType, 'prd');
    assert.equal(result.payload.data.canonicalSpec.lane, 'marketing-site');
    assert.equal(result.payload.data.resolvedExecutionPath, 'builder');
    assert.equal(result.payload.data.builderInvoked, true);
    assert.deepEqual(result.payload.data.packSelection.requestedPackIds, []);
    assert.deepEqual(result.payload.data.packSelection.unsupportedRequestedPackIds, []);
  });
});

test('workflow run go fails fast when project context is stale', () => {
  withFixture((projectRoot) => {
    seedGoFixture(projectRoot, { contextExitCode: 1 });

    const result = runCli(projectRoot, [
      'workflow',
      'run',
      'go',
      'Build a SaaS dashboard for vendor analytics with RBAC and settings.'
    ]);

    assert.equal(result.code, 1, result.stderr);
    assert.equal(result.payload.ok, false);
    assert.equal(result.payload.data.outcome, 'BLOCKED');
    assert.equal(result.payload.data.preflight.context.status, 'stale');
    assert.match(result.payload.data.blockingIssues[0], /Project context is stale/i);
    assert.equal(typeof result.payload.data.downstreamRunArtifact, 'undefined');

    const artifact = JSON.parse(fs.readFileSync(result.payload.data.runArtifact, 'utf8'));
    assert.equal(artifact.status, 'BLOCKED');
    assert.equal(artifact.preflight.context.status, 'stale');
  });
});

test('workflow run create generates a portable product bundle from a prompt', () => {
  withFixture((projectRoot) => {
    seedGoFixture(projectRoot);

    const result = runCli(projectRoot, [
      'workflow',
      'run',
      'create',
      'Build a marketing site for an AI automation platform with pricing, case studies, and a contact funnel.',
      '--output-dir',
      'generated-bundles/marketing-smoke'
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.payload.ok, true);
    assert.equal(result.payload.data.outcome, 'HANDOFF_READY');
    assert.equal(result.payload.data.sourceType, 'prompt');
    assert.equal(result.payload.data.canonicalSpec.lane, 'marketing-site');
    assert.match(result.payload.data.bundleDir, /generated-bundles\/marketing-smoke$/);
    assert.match(result.payload.data.bundleManifest, /generated-bundles\/marketing-smoke\/gg-product-bundle\.json$/);
    assert.equal(Array.isArray(result.payload.data.generatedFiles), true);

    const manifest = JSON.parse(fs.readFileSync(result.payload.data.bundleManifest, 'utf8'));
    assert.equal(manifest.lane, 'marketing-site');
    assert.equal(fs.existsSync(path.join(result.payload.data.bundleDir, 'src', 'app', 'contact', 'page.tsx')), true);

    const artifact = JSON.parse(fs.readFileSync(result.payload.data.runArtifact, 'utf8'));
    assert.equal(artifact.workflow, 'create');
    assert.equal(artifact.status, 'HANDOFF_READY');
  });
});

test('workflow run create records preflight warnings but still builds deterministic bundles', () => {
  withFixture((projectRoot) => {
    seedGoFixture(projectRoot, { activationActive: false });

    const result = runCli(projectRoot, [
      'workflow',
      'run',
      'create',
      'Build a SaaS dashboard for vendor analytics with RBAC, settings, and admin views.',
      '--output-dir',
      'generated-bundles/dashboard-smoke'
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.payload.ok, true);
    assert.equal(result.payload.data.outcome, 'HANDOFF_READY');
    assert.equal(result.payload.data.preflight.activation.active, false);
    assert.equal(result.payload.data.preflightWarnings.length > 0, true);
    assert.equal(fs.existsSync(path.join(result.payload.data.bundleDir, 'src', 'app', 'dashboard', 'page.tsx')), true);
  });
});

test('workflow run minion normalizes a supported product prompt and routes it into create', () => {
  withFixture((projectRoot) => {
    seedGoFixture(projectRoot);

    const result = runCli(projectRoot, [
      'workflow',
      'run',
      'minion',
      'Build a SaaS dashboard for vendor analytics with RBAC, settings, and admin views.',
      '--validate',
      'none',
      '--doc-sync',
      'off'
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.payload.ok, true);
    assert.equal(result.payload.data.sourceType, 'prompt');
    assert.equal(result.payload.data.canonicalSpec.lane, 'saas-dashboard');
    assert.equal(result.payload.data.executionPlan.delegatedWorkflow, 'create');
    assert.equal(result.payload.data.executionPlan.validateMode, 'none');
    assert.equal(result.payload.data.resolvedExecutionPath, 'builder');
    assert.equal(result.payload.data.builderInvoked, true);
    assert.equal(result.payload.data.outcome, 'HANDOFF_READY');
    assert.match(result.payload.data.specArtifact, /minion-[a-z0-9]+-[a-z0-9]+\.spec\.json$/);
    assert.match(result.payload.data.downstreamRunArtifact, /create-[a-z0-9]+-[a-z0-9]+\.json$/);
    assert.match(result.payload.data.bundleDir, /product-bundles\/minion-[a-z0-9]+-[a-z0-9]+$/);
    assert.match(result.payload.data.bundleManifest, /product-bundles\/minion-[a-z0-9]+-[a-z0-9]+\/gg-product-bundle\.json$/);
    assert.equal(Array.isArray(result.payload.data.generatedFiles), true);

    const artifact = JSON.parse(fs.readFileSync(result.payload.data.runArtifact, 'utf8'));
    assert.equal(artifact.workflow, 'minion');
    assert.equal(artifact.status, 'HANDOFF_READY');
    assert.equal(artifact.executionPlan.delegatedWorkflow, 'create');
    assert.equal(artifact.resolvedExecutionPath, 'builder');
    assert.equal(artifact.builderInvoked, true);
  });
});

test('workflow run minion accepts a canonical spec path and preserves normalized source type', () => {
  withFixture((projectRoot) => {
    seedGoFixture(projectRoot);
    const specPath = path.join(projectRoot, 'docs', 'prd', 'admin-panel.spec.json');
    fs.mkdirSync(path.dirname(specPath), { recursive: true });
    fs.writeFileSync(
      specPath,
      `${JSON.stringify({
        schemaVersion: 1,
        sourceType: 'normalized',
        summary: 'Build an admin panel for operator triage and compliance review.',
        lane: 'admin-panel',
        laneConfidence: 0.93,
        targetStack: 'nextjs-app-router',
        riskTier: 'medium',
        enterprisePacks: ['design-system', 'observability', 'auth-rbac'],
        constraints: ['Use server-side enforcement for operator-only routes.'],
        requiredIntegrations: ['telemetry-provider'],
        acceptanceCriteria: ['Deliver operator triage queues and review screens.'],
        validationProfile: 'admin-panel',
        deliveryTarget: 'local-repo',
        requiresHumanReview: false
      }, null, 2)}\n`,
      'utf8'
    );

    const result = runCli(projectRoot, [
      'workflow',
      'run',
      'minion',
      'docs/prd/admin-panel.spec.json',
      '--validate',
      'none',
      '--doc-sync',
      'off'
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.payload.ok, true);
    assert.equal(result.payload.data.sourceType, 'normalized');
    assert.equal(result.payload.data.sourcePath, 'docs/prd/admin-panel.spec.json');
    assert.equal(result.payload.data.canonicalSpec.sourceType, 'normalized');
    assert.equal(result.payload.data.canonicalSpec.lane, 'admin-panel');
    assert.equal(result.payload.data.canonicalSpec.targetStack, 'nextjs-app-router');
    assert.equal(result.payload.data.outcome, 'HANDOFF_READY');
  });
});

test('workflow run minion fails fast when runtime activation is inactive', () => {
  withFixture((projectRoot) => {
    seedGoFixture(projectRoot, { activationActive: false });

    const result = runCli(projectRoot, [
      'workflow',
      'run',
      'minion',
      'Build an admin panel for operator triage and compliance review.',
      '--validate',
      'none',
      '--doc-sync',
      'off'
    ]);

    assert.equal(result.code, 1, result.stderr);
    assert.equal(result.payload.ok, false);
    assert.equal(result.payload.data.outcome, 'BLOCKED');
    assert.equal(result.payload.data.preflight.activation.active, false);
    assert.match(result.payload.data.blockingIssues[0], /Runtime activation is not active/i);
    assert.equal(typeof result.payload.data.downstreamRunArtifact, 'undefined');

    const artifact = JSON.parse(fs.readFileSync(result.payload.data.runArtifact, 'utf8'));
    assert.equal(artifact.status, 'BLOCKED');
    assert.equal(artifact.preflight.activation.active, false);
  });
});

test('harness ui snapshot and command commands round-trip over the RPC client', async () => {
  await withRpcServer(
    [
      {
        ok: true,
        processedCommandId: null,
        snapshot: {
          selectedRunId: 'run-123',
          selectedRuntime: 'codex'
        },
        error: null
      },
      {
        ok: true,
        processedCommandId: 'cli-1',
        snapshot: {
          selectedTab: 'swarm'
        },
        error: null
      }
    ],
    async ({ port, requests }) => {
      await withFixture(async (projectRoot) => {
        const snapshot = await runCliAsync(projectRoot, ['harness', 'ui', 'snapshot', '--port', String(port)]);
        assert.equal(snapshot.code, 0, snapshot.stderr);
        assert.equal(snapshot.payload.data.response.snapshot.selectedRunId, 'run-123');

        const command = await runCliAsync(projectRoot, [
          'harness',
          'ui',
          'command',
          '--port',
          String(port),
          '--id',
          'cli-1',
          '--type',
          'selectTab',
          '--tab',
          'swarm'
        ]);
        assert.equal(command.code, 0, command.stderr);
        assert.equal(command.payload.data.response.processedCommandId, 'cli-1');
      });

      assert.equal(requests.length, 2);
      assert.deepEqual(requests[0], { type: 'snapshot' });
      assert.deepEqual(requests[1], {
        type: 'command',
        command: {
          id: 'cli-1',
          type: 'selectTab',
          tab: 'swarm'
        }
      });
    }
  );
});

test('harness ui batch sends sequential command envelopes', async () => {
  await withRpcServer(
    [
      { ok: true, processedCommandId: 'cmd-1', snapshot: { selectedTab: 'swarm' }, error: null },
      { ok: true, processedCommandId: 'cmd-2', snapshot: { selectedProblemId: 'problem-1' }, error: null }
    ],
    async ({ port, requests }) => {
      await withFixture(async (projectRoot) => {
        const batch = await runCliAsync(projectRoot, [
          'harness',
          'ui',
          'batch',
          '--port',
          String(port),
          '--commands',
          '[{"id":"cmd-1","type":"selectTab","tab":"swarm"},{"id":"cmd-2","type":"selectProblem","problemId":"problem-1"}]'
        ]);
        assert.equal(batch.code, 0, batch.stderr);
        assert.equal(batch.payload.data.responses.length, 2);
        assert.equal(batch.payload.data.responses[0].processedCommandId, 'cmd-1');
        assert.equal(batch.payload.data.responses[1].processedCommandId, 'cmd-2');
      });

      assert.equal(requests.length, 2);
      assert.deepEqual(requests.map((entry) => entry.command.id), ['cmd-1', 'cmd-2']);
    }
  );
});
