import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const projectRoot = path.resolve(process.cwd(), '..', '..');
const {
  buildInteractiveRuntimeLaunchPlan,
  discoverRuntimeCredentials,
  executeRuntimeLaunch,
  defaultAdapterMode,
  defaultLaunchTransport,
  evaluateRuntimeLaunchPreflight,
  selectCoordinatorRuntime
} = await import('../dist/index.js');

function withEnv(patch, fn) {
  const previous = new Map();
  for (const [key, value] of Object.entries(patch)) {
    previous.set(key, process.env[key]);
    if (value === null) {
      delete process.env[key];
    } else {
      process.env[key] = value;
    }
  }

  const restore = () => {
    for (const [key, value] of previous.entries()) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  };

  try {
    const result = fn();
    if (result && typeof result.then === 'function') {
      return result.finally(restore);
    }
    restore();
    return result;
  } catch (error) {
    restore();
    throw error;
  }
}

test('Kimi prefers cli-session when a local authenticated CLI is available', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-kimi-auth-'));
  const credentialsFile = path.join(tempDir, 'kimi-code.json');
  fs.writeFileSync(credentialsFile, JSON.stringify({ access_token: 'test', refresh_token: 'test' }), 'utf8');

  withEnv(
    {
      GG_KIMI_TRANSPORT: null,
      KIMI_BINARY: process.execPath,
      KIMI_CREDENTIALS_FILE: credentialsFile,
      KIMI_CONFIG_FILE: path.join(tempDir, 'config.toml')
    },
    () => {
      assert.equal(defaultLaunchTransport(projectRoot, 'kimi'), 'cli-session');
      assert.equal(defaultAdapterMode(projectRoot, 'kimi'), 'host-activated');
    }
  );
});

test('Claude prefers background-terminal when local CLI credentials exist', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-claude-auth-'));
  const credentialsFile = path.join(tempDir, '.credentials.json');
  fs.writeFileSync(credentialsFile, JSON.stringify({ accessToken: 'test' }), 'utf8');

  withEnv(
    {
      GG_CLAUDE_TRANSPORT: null,
      CLAUDE_BINARY: process.execPath,
      CLAUDE_CREDENTIALS_FILE: credentialsFile,
      OPENCODE_AUTH_FILE: path.join(tempDir, 'missing-opencode.json'),
      ANTHROPIC_API_KEY: null
    },
    () => {
      const discovery = discoverRuntimeCredentials(projectRoot, 'claude');
      assert.equal(discovery.localCliAuth, true);
      assert.equal(defaultLaunchTransport(projectRoot, 'claude'), 'background-terminal');
      assert.equal(defaultAdapterMode(projectRoot, 'claude'), 'host-activated');
    }
  );
});

test('Codex credential discovery uses auth.json before env fallback', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-codex-auth-'));
  const authFile = path.join(tempDir, 'auth.json');
  fs.writeFileSync(
    authFile,
    JSON.stringify({
      tokens: {
        access_token: 'at_test',
        refresh_token: 'rt_test'
      }
    }),
    'utf8'
  );

  withEnv(
    {
      CODEX_BINARY: process.execPath,
      CODEX_AUTH_FILE: authFile,
      OPENAI_API_KEY: null
    },
    () => {
      const discovery = discoverRuntimeCredentials(projectRoot, 'codex');
      assert.equal(discovery.localCliAuth, true);
      assert.match(discovery.summary, /Codex auth/);

      const report = evaluateRuntimeLaunchPreflight(projectRoot, {
        runId: 'run-test',
        agentId: 'worker-test',
        runtime: 'codex',
        taskSummary: 'Review code',
        worktree: projectRoot,
        toolBundle: ['filesystem'],
        launchTransport: 'background-terminal',
        launchSpec: {
          prompt: 'Review code',
          taskSummary: 'Review code',
          toolBundle: ['filesystem']
        }
      });

      assert.equal(report.status, 'passed');
      assert.ok(report.checks.some((entry) => entry.id === 'codex_auth' && entry.status === 'pass'));
    }
  );
});

test('Coordinator auto-selection prefers the first authenticated local CLI in preference order', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-coordinator-auto-'));
  const codexAuth = path.join(tempDir, 'codex-auth.json');
  const kimiAuth = path.join(tempDir, 'kimi-code.json');

  fs.writeFileSync(
    codexAuth,
    JSON.stringify({
      tokens: {
        access_token: 'at_test'
      }
    }),
    'utf8'
  );
  fs.writeFileSync(kimiAuth, JSON.stringify({ access_token: 'test', refresh_token: 'test' }), 'utf8');

  withEnv(
    {
      GG_COORDINATOR_RUNTIME: null,
      GG_COORDINATOR_PREFERENCE: 'codex,claude,kimi',
      CODEX_BINARY: process.execPath,
      CODEX_AUTH_FILE: codexAuth,
      CLAUDE_BINARY: path.join(tempDir, 'missing-claude'),
      CLAUDE_CREDENTIALS_FILE: path.join(tempDir, 'missing-claude-credentials.json'),
      OPENCODE_AUTH_FILE: path.join(tempDir, 'missing-opencode.json'),
      KIMI_BINARY: process.execPath,
      KIMI_CREDENTIALS_FILE: kimiAuth,
      KIMI_CONFIG_FILE: path.join(tempDir, 'config.toml'),
      OPENAI_API_KEY: null,
      ANTHROPIC_API_KEY: null,
      MOONSHOT_API_KEY: null,
      KIMI_API_KEY: null
    },
    () => {
      const selection = selectCoordinatorRuntime(projectRoot, 'auto');
      assert.equal(selection.selected, 'codex');
      assert.match(selection.reason, /local authenticated CLI session/i);
      assert.deepEqual(selection.order, ['codex', 'claude', 'kimi']);
    }
  );
});

test('Coordinator selection respects explicit pins and environment override', () => {
  withEnv(
    {
      GG_COORDINATOR_RUNTIME: 'kimi',
      KIMI_BINARY: process.execPath,
      KIMI_CREDENTIALS_FILE: path.join(os.tmpdir(), 'missing-kimi-credentials.json'),
      KIMI_CONFIG_FILE: path.join(os.tmpdir(), 'missing-kimi-config.toml')
    },
    () => {
      const autoSelection = selectCoordinatorRuntime(projectRoot, null);
      assert.equal(autoSelection.selected, 'kimi');
      assert.match(autoSelection.reason, /GG_COORDINATOR_RUNTIME=kimi/);

      const pinned = selectCoordinatorRuntime(projectRoot, 'claude');
      assert.equal(pinned.selected, 'claude');
      assert.match(pinned.reason, /pinned to claude/i);
    }
  );
});

test('Kimi preflight fails closed when API credentials are missing', () => {
  withEnv(
    {
      GG_KIMI_TRANSPORT: 'api-session',
      MOONSHOT_API_KEY: null,
      KIMI_API_KEY: null
    },
    () => {
    const report = evaluateRuntimeLaunchPreflight(projectRoot, {
      runId: 'run-test',
      agentId: 'worker-test',
      runtime: 'kimi',
      taskSummary: 'Implement a backend endpoint',
      worktree: projectRoot,
      toolBundle: [],
      launchTransport: 'api-session',
      launchSpec: {
        requestBody: {
          model: 'kimi-k2.5',
          messages: [{ role: 'user', content: 'hello' }]
        }
      }
    });

    assert.equal(report.status, 'failed');
    assert.ok(report.checks.some((entry) => entry.id === 'api_key' && entry.status === 'fail'));
    }
  );
});

test('Kimi cli-session execution launches the local binary and captures output', async () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-kimi-cli-'));
  const fakeBinary = path.join(tempDir, 'kimi');
  const credentialsFile = path.join(tempDir, 'kimi-code.json');

  fs.writeFileSync(
    fakeBinary,
    ['#!/bin/sh', 'echo "HANDOFF_READY: cli inherited session works"', 'exit 0', ''].join('\n'),
    { mode: 0o755 }
  );
  fs.writeFileSync(credentialsFile, JSON.stringify({ access_token: 'test', refresh_token: 'test' }), 'utf8');

  await withEnv(
    {
      KIMI_BINARY: fakeBinary,
      KIMI_CREDENTIALS_FILE: credentialsFile,
      KIMI_CONFIG_FILE: path.join(tempDir, 'config.toml')
    },
    async () => {
      const result = await executeRuntimeLaunch(
        tempDir,
        {
          runId: 'run-test',
          agentId: 'worker-test',
          runtime: 'kimi',
          taskSummary: 'Verify inherited CLI auth path',
          worktree: tempDir,
          toolBundle: [],
          launchTransport: 'cli-session',
          launchSpec: {
            requestBody: {
              model: 'kimi-code/kimi-for-coding',
              messages: [
                { role: 'system', content: 'You are inside the harness.' },
                { role: 'user', content: 'Reply with HANDOFF_READY: cli inherited session works' }
              ]
            }
          }
        },
        {}
      );

      assert.equal(result.status, 'completed');
      assert.match(result.outputText, /HANDOFF_READY: cli inherited session works/);
      assert.ok(result.requestFile);
      assert.ok(result.responseFile);
      assert.ok(result.transcriptFile);
      assert.ok(fs.existsSync(result.requestFile));
      assert.ok(fs.existsSync(result.responseFile));
      assert.ok(fs.existsSync(result.transcriptFile));
    }
  );
});

test('Interactive launch plans use the documented autonomy flags', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-live-flags-'));
  const fakeCodex = path.join(tempDir, 'codex');
  const fakeClaude = path.join(tempDir, 'claude');
  const fakeKimi = path.join(tempDir, 'kimi');
  const credentialsFile = path.join(tempDir, 'kimi-code.json');

  for (const binary of [fakeCodex, fakeClaude, fakeKimi]) {
    fs.writeFileSync(binary, '#!/bin/sh\nexit 0\n', { mode: 0o755 });
  }
  fs.writeFileSync(credentialsFile, JSON.stringify({ access_token: 'test', refresh_token: 'test' }), 'utf8');

  withEnv(
    {
      CODEX_BINARY: fakeCodex,
      CLAUDE_BINARY: fakeClaude,
      KIMI_BINARY: fakeKimi,
      KIMI_CREDENTIALS_FILE: credentialsFile,
      KIMI_CONFIG_FILE: path.join(tempDir, 'config.toml')
    },
    () => {
      const codex = buildInteractiveRuntimeLaunchPlan(projectRoot, {
        runId: 'run-test',
        agentId: 'codex-worker',
        runtime: 'codex',
        taskSummary: 'Implement a small refactor',
        worktree: projectRoot,
        toolBundle: ['filesystem'],
        launchTransport: 'background-terminal',
        launchSpec: { prompt: 'Codex prompt', taskSummary: 'Implement a small refactor', toolBundle: ['filesystem'] }
      });
      assert.ok(codex.args.includes('--dangerously-bypass-approvals-and-sandbox'));

      const claude = buildInteractiveRuntimeLaunchPlan(projectRoot, {
        runId: 'run-test',
        agentId: 'claude-worker',
        runtime: 'claude',
        taskSummary: 'Review the plan',
        worktree: projectRoot,
        toolBundle: ['filesystem'],
        launchTransport: 'background-terminal',
        launchSpec: { prompt: 'Claude prompt', taskSummary: 'Review the plan', toolBundle: ['filesystem'] }
      });
      assert.ok(claude.args.includes('--dangerously-skip-permissions'));

      const kimi = buildInteractiveRuntimeLaunchPlan(projectRoot, {
        runId: 'run-test',
        agentId: 'kimi-worker',
        runtime: 'kimi',
        taskSummary: 'Build the feature',
        worktree: projectRoot,
        toolBundle: ['filesystem'],
        launchTransport: 'cli-session',
        launchSpec: {
          requestBody: {
            model: 'kimi-k2.5',
            messages: [
              { role: 'system', content: 'Kimi system prompt' },
              { role: 'user', content: 'Build the feature' }
            ]
          }
        }
      });
      assert.ok(kimi.args.includes('--yolo'));
      assert.ok(!kimi.args.includes('--print'));
    }
  );
});
