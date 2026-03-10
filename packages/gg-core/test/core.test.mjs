import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(__dirname, '..');
const core = await import(path.join(packageRoot, 'dist', 'index.js'));

function makeFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-core-test-'));
  fs.mkdirSync(path.join(root, '.agent', 'skills', 'alpha-skill'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'skills', 'beta-skill'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'workflows'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'runs'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'product-lanes'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'packs'), { recursive: true });
  fs.mkdirSync(path.join(root, 'evals'), { recursive: true });
  fs.mkdirSync(path.join(root, 'docs'), { recursive: true });
  fs.mkdirSync(path.join(root, 'scripts'), { recursive: true });
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ name: 'fixture', private: true }, null, 2));
  fs.writeFileSync(path.join(root, '.mcp.json'), JSON.stringify({ mcpServers: {} }, null, 2));
  fs.writeFileSync(path.join(root, 'docs', 'project-context.md'), '# Project Context\n', 'utf8');
  fs.writeFileSync(
    path.join(root, '.agent', 'skills', 'alpha-skill', 'SKILL.md'),
    [
      '---',
      'name: "Alpha Skill"',
      'description: "Handles alpha feature work"',
      '---',
      '',
      '# Alpha'
    ].join('\n'),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'skills', 'beta-skill', 'SKILL.md'),
    [
      '---',
      'description: "Verification and testing support"',
      '---',
      '',
      '# Beta'
    ].join('\n'),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'workflows', 'go.md'),
    [
      '---',
      'name: "Go Workflow"',
      'description: "Ship a task with staged validation"',
      '---',
      '',
      '# Go'
    ].join('\n'),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'workflows', 'review.md'),
    [
      '# Review'
    ].join('\n'),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'product-lanes', 'marketing-site.json'),
    JSON.stringify({
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
    }, null, 2),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'product-lanes', 'saas-dashboard.json'),
    JSON.stringify({
      id: 'saas-dashboard',
      name: 'SaaS Dashboard',
      description: 'Authenticated enterprise dashboard',
      v1Mandatory: true,
      category: 'web-app',
      allowedStacks: ['nextjs-app-router', 'vite-react-node'],
      defaultStack: 'nextjs-app-router',
      requiredCapabilities: ['authenticated-shell', 'typed-api-layer'],
      defaultPacks: ['design-system', 'observability', 'auth-rbac'],
      allowedPacks: ['design-system', 'observability', 'auth-rbac', 'billing-stripe'],
      requiredGates: ['typecheck', 'lint', 'targeted-tests']
    }, null, 2),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'packs', 'design-system.json'),
    JSON.stringify({
      id: 'design-system',
      name: 'Design System',
      description: 'Shared UI patterns',
      v1Unattended: true,
      riskTier: 'low',
      compatibleLanes: ['marketing-site', 'saas-dashboard'],
      requiredConfig: [],
      addsCapabilities: ['ui-tokens'],
      requiredGates: ['ui-smoke'],
      reviewRequired: false
    }, null, 2),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'packs', 'observability.json'),
    JSON.stringify({
      id: 'observability',
      name: 'Observability',
      description: 'Telemetry hooks',
      v1Unattended: true,
      riskTier: 'low',
      compatibleLanes: ['marketing-site', 'saas-dashboard'],
      requiredConfig: [],
      addsCapabilities: ['logging-hooks'],
      requiredGates: ['docs-bundle'],
      reviewRequired: false
    }, null, 2),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'packs', 'auth-rbac.json'),
    JSON.stringify({
      id: 'auth-rbac',
      name: 'Auth and RBAC',
      description: 'Authenticated shell and permissions',
      v1Unattended: true,
      riskTier: 'medium',
      compatibleLanes: ['saas-dashboard'],
      requiredConfig: ['auth-provider', 'session-strategy'],
      addsCapabilities: ['authenticated-shell'],
      requiredGates: ['targeted-tests'],
      reviewRequired: true
    }, null, 2),
    'utf8'
  );
  fs.writeFileSync(path.join(root, 'valid.json'), JSON.stringify({ ok: true, nested: { count: 2 } }, null, 2), 'utf8');
  fs.writeFileSync(path.join(root, 'invalid.json'), '{not-json', 'utf8');
  fs.writeFileSync(
    path.join(root, 'scripts', 'runtime-project-sync.mjs'),
    `console.log(JSON.stringify({
  active: true,
  activationType: 'host-config',
  checks: [
    { id: 'config_toml_exists', ok: true, detail: 'config.toml' },
    { id: 'gg_skills_json', ok: true, detail: 'mcp.json' }
  ]
}));\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, 'scripts', 'runtime-parity-smoke.mjs'),
    `console.log(JSON.stringify({
  ok: true,
  strict: true,
  results: [
    { id: 'runtime_registry', status: 'pass', summary: 'Runtime registry is aligned', detail: 'fixture' }
  ]
}));
process.exit(0);\n`,
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, 'scripts', 'generate-project-context.mjs'),
    "console.log('Project context is up to date.');\nprocess.exit(0);\n",
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, 'evals', 'headless-product-corpus.json'),
    JSON.stringify({
      version: 1,
      policy: {
        fixtureFirst: true,
        downstreamProofAfterFixturePass: true,
        firstDownstreamTarget: 'GGV3'
      },
      mandatoryLanes: ['marketing-site', 'saas-dashboard', 'admin-panel'],
      unattendedV1Packs: ['design-system', 'observability', 'auth-rbac'],
      cases: [
        {
          id: 'marketing-go-prompt',
          workflow: 'go',
          sourceType: 'prompt',
          request: 'Build a marketing site for an automation company with pricing and contact.',
          lane: 'marketing-site',
          expectedPacks: ['design-system', 'observability'],
          deliveryTarget: 'local-repo',
          expectedOutcome: 'HANDOFF_READY'
        },
        {
          id: 'dashboard-minion-spec',
          workflow: 'minion',
          sourceType: 'normalized',
          sourcePath: 'evals/fixtures/dashboard.spec.json',
          lane: 'saas-dashboard',
          expectedPacks: ['design-system', 'observability', 'auth-rbac'],
          deliveryTarget: 'local-repo',
          expectedOutcome: 'HANDOFF_READY'
        },
        {
          id: 'unsupported-crud-shell',
          workflow: 'go',
          sourceType: 'prompt',
          request: 'Build a CRUD shell for inventory management with generic tables and forms.',
          lane: 'crud-shell',
          expectedPacks: ['design-system'],
          deliveryTarget: 'local-repo',
          expectedOutcome: 'BLOCKED'
        }
      ]
    }, null, 2),
    'utf8'
  );
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

test('resolveProjectRoot and getHarnessPaths find the enclosing harness repo from nested paths', () => {
  withFixture((root) => {
    const nested = path.join(root, 'src', 'feature', 'nested');
    fs.mkdirSync(nested, { recursive: true });

    const resolved = core.resolveProjectRoot(nested);
    assert.equal(resolved, root);

    const paths = core.getHarnessPaths(root);
    assert.equal(paths.projectRoot, root);
    assert.equal(paths.agentDir, path.join(root, '.agent'));
    assert.equal(paths.skillsDir, path.join(root, '.agent', 'skills'));
    assert.equal(paths.workflowsDir, path.join(root, '.agent', 'workflows'));
    assert.equal(paths.mcpConfigPath, path.join(root, '.mcp.json'));
    assert.equal(paths.runArtifactDir, path.join(root, '.agent', 'runs'));
  });
});

test('loadSkills and loadWorkflows parse catalog frontmatter and file metadata', () => {
  withFixture((root) => {
    const skills = core.loadSkills(root);
    assert.equal(skills.length, 2);
    assert.equal(skills[0].slug, 'alpha-skill');
    assert.equal(skills[0].name, 'Alpha Skill');
    assert.equal(skills[0].description, 'Handles alpha feature work');
    assert.equal(skills[1].slug, 'beta-skill');
    assert.equal(skills[1].name, 'beta-skill');
    assert.match(skills[1].description, /Verification/);

    const workflows = core.loadWorkflows(root);
    assert.equal(workflows.length, 2);
    assert.equal(workflows[0].slug, 'go');
    assert.equal(workflows[0].name, 'Go Workflow');
    assert.equal(workflows[0].description, 'Ship a task with staged validation');
    assert.equal(workflows[1].slug, 'review');
    assert.equal(workflows[1].name, 'review');
  });
});

test('searchCatalog ranks exact and token matches ahead of weaker results', () => {
  withFixture((root) => {
    const entries = [...core.loadSkills(root), ...core.loadWorkflows(root)];
    const exact = core.searchCatalog(entries, 'alpha-skill', 5);
    assert.equal(exact[0].slug, 'alpha-skill');

    const token = core.searchCatalog(entries, 'verification testing', 5);
    assert.equal(token[0].slug, 'beta-skill');

    const fallback = core.searchCatalog(entries, '', 2);
    assert.equal(fallback.length, 2);
  });
});

test('readCatalogEntryContent and readJsonFile handle valid and invalid inputs safely', () => {
  withFixture((root) => {
    const [entry] = core.loadSkills(root);
    const content = core.readCatalogEntryContent(entry);
    assert.match(content, /Alpha Skill/);

    const valid = core.readJsonFile(path.join(root, 'valid.json'));
    assert.deepEqual(valid, { ok: true, nested: { count: 2 } });

    const invalid = core.readJsonFile(path.join(root, 'invalid.json'));
    assert.equal(invalid, null);

    const missing = core.readJsonFile(path.join(root, 'missing.json'));
    assert.equal(missing, null);
  });
});

test('harness settings round-trip with normalization and reset semantics', () => {
  withFixture((root) => {
    const defaults = core.readHarnessSettings(root);
    assert.equal(defaults.execution.loopBudget, 50);
    assert.equal(defaults.execution.retryLimit, 3);
    assert.equal(defaults.diagram.primaryArtifact, 'docs/architecture/agentic-harness-dynamic-user-diagram.html');

    const written = core.writeHarnessSettings(root, {
      execution: {
        loopBudget: 75,
        retryLimit: 4,
        retryBackoffSeconds: [2, 5, 8],
        promptImproverMode: 'force',
        contextSource: 'hybrid',
        hydraMode: 'shadow',
        validateMode: 'all',
        docSyncMode: 'off'
      },
      governor: {
        cpuHighPct: 92,
        cpuLowPct: 65
      },
      artifacts: {
        toolBundle: 'tight-default',
        riskTier: 'medium'
      }
    });

    assert.equal(written.execution.loopBudget, 75);
    assert.equal(written.execution.retryBackoffSeconds[1], 5);
    assert.equal(written.execution.promptImproverMode, 'force');
    assert.equal(written.governor.cpuHighPct, 92);
    assert.equal(written.artifacts.toolBundle, 'tight-default');

    const reset = core.resetHarnessSettings(root);
    assert.equal(reset.execution.loopBudget, 50);
    assert.equal(reset.governor.cpuHighPct, null);
    assert.equal(reset.artifacts.toolBundle, null);
  });
});

test('getHarnessExecutionPreflight reports runnable status from harness scripts', () => {
  withFixture((root) => {
    const preflight = core.getHarnessExecutionPreflight(root, 'codex');
    assert.equal(preflight.isRunnable, true);
    assert.equal(preflight.activation.active, true);
    assert.equal(preflight.parity.ok, true);
    assert.equal(preflight.context.status, 'current');
    assert.equal(preflight.blockingIssues.length, 0);
  });
});

test('resolveGoSourceInput and buildCanonicalProductSpec normalize prompt intake in core', () => {
  withFixture((root) => {
    const source = core.resolveGoSourceInput(
      root,
      'Build a SaaS dashboard for vendor analytics with RBAC, settings, and admin views.',
      {}
    );
    const resolution = core.buildCanonicalProductSpec(
      root,
      source,
      {
        normalizedObjective: source.sourceText,
        constraints: ['Keep deterministic validation inside the harness core.'],
        acceptanceCriteria: ['Objective is normalized into one primary workflow recommendation.']
      },
      {}
    );

    assert.equal(source.sourceType, 'prompt');
    assert.equal(resolution.canonicalSpec.lane, 'saas-dashboard');
    assert.equal(resolution.canonicalSpec.targetStack, 'nextjs-app-router');
    assert.deepEqual(resolution.canonicalSpec.enterprisePacks, ['design-system', 'observability', 'auth-rbac']);
    assert.equal(resolution.canonicalSpec.riskTier, 'medium');
    assert.equal(resolution.reviewReasons.length > 0, true);
  });
});

test('buildCanonicalProductSpec does not infer billing-stripe from informational billing context in marketing PRDs', () => {
  withFixture((root) => {
    const prdPath = path.join(root, 'docs', 'prd', 'signalforge.md');
    fs.mkdirSync(path.dirname(prdPath), { recursive: true });
    fs.writeFileSync(
      prdPath,
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

    const source = core.resolveGoSourceInput(root, 'docs/prd/signalforge.md', {});
    const resolution = core.buildCanonicalProductSpec(
      root,
      source,
      {
        normalizedObjective: source.sourceText,
        constraints: [],
        acceptanceCriteria: ['Deliver a launch-ready marketing shell.']
      },
      {}
    );

    assert.equal(source.sourceType, 'prd');
    assert.equal(resolution.canonicalSpec.lane, 'marketing-site');
    assert.deepEqual(resolution.requestedPackIds, []);
    assert.deepEqual(resolution.unsupportedRequestedPackIds, []);
    assert.deepEqual(resolution.canonicalSpec.enterprisePacks, ['design-system', 'observability']);
  });
});

test('createProductBundle writes a marketing-site bundle with manifest and lane pages', () => {
  withFixture((root) => {
    const source = core.resolveGoSourceInput(
      root,
      'Build a marketing site for an AI automation platform with pricing, case studies, and a contact funnel.',
      {}
    );
    const resolution = core.buildCanonicalProductSpec(
      root,
      source,
      {
        normalizedObjective: source.sourceText,
        constraints: [],
        acceptanceCriteria: ['Deliver a launch-ready marketing shell.']
      },
      {}
    );

    const bundle = core.createProductBundle({
      projectRoot: root,
      spec: resolution.canonicalSpec,
      lane: resolution.lane,
      selectedPacks: resolution.selectedPacks,
      bundleId: 'bundle-marketing-smoke'
    });

    assert.equal(fs.existsSync(bundle.bundleDir), true);
    assert.equal(fs.existsSync(path.join(bundle.bundleDir, 'package.json')), true);
    assert.equal(fs.existsSync(path.join(bundle.bundleDir, 'src', 'app', 'page.tsx')), true);
    assert.equal(fs.existsSync(path.join(bundle.bundleDir, 'src', 'app', 'pricing', 'page.tsx')), true);
    assert.equal(fs.existsSync(path.join(bundle.bundleDir, 'src', 'app', 'contact', 'page.tsx')), true);

    const manifest = JSON.parse(fs.readFileSync(bundle.manifestPath, 'utf8'));
    assert.equal(manifest.lane, 'marketing-site');
    assert.equal(Array.isArray(manifest.files), true);
    assert.equal(manifest.files.some((item) => item.path === 'src/app/pricing/page.tsx'), true);

    const tsconfig = JSON.parse(fs.readFileSync(path.join(bundle.bundleDir, 'tsconfig.json'), 'utf8'));
    assert.equal(tsconfig.compilerOptions.jsx, 'react-jsx');
    assert.equal(tsconfig.include.includes('.next/types/**/*.ts'), true);
    assert.equal(tsconfig.include.includes('.next/dev/types/**/*.ts'), true);

    const nextConfig = fs.readFileSync(path.join(bundle.bundleDir, 'next.config.ts'), 'utf8');
    assert.match(nextConfig, /turbopack/u);
    assert.match(nextConfig, /outputFileTracingRoot/u);

    const gitignore = fs.readFileSync(path.join(bundle.bundleDir, '.gitignore'), 'utf8');
    assert.match(gitignore, /tsconfig\.tsbuildinfo/u);
  });
});

test('createProductBundle writes auth-ready dashboard bundles for application lanes', () => {
  withFixture((root) => {
    const source = core.resolveGoSourceInput(
      root,
      'Build a SaaS dashboard for vendor analytics with RBAC, settings, alerting, and admin views.',
      {}
    );
    const resolution = core.buildCanonicalProductSpec(
      root,
      source,
      {
        normalizedObjective: source.sourceText,
        constraints: [],
        acceptanceCriteria: ['Deliver a role-aware dashboard shell.']
      },
      {}
    );

    const bundle = core.createProductBundle({
      projectRoot: root,
      spec: resolution.canonicalSpec,
      lane: resolution.lane,
      selectedPacks: resolution.selectedPacks,
      bundleId: 'bundle-dashboard-smoke'
    });

    assert.equal(fs.existsSync(path.join(bundle.bundleDir, 'src', 'app', 'dashboard', 'page.tsx')), true);
    assert.equal(fs.existsSync(path.join(bundle.bundleDir, 'src', 'app', 'dashboard', 'settings', 'page.tsx')), true);
    assert.equal(fs.existsSync(path.join(bundle.bundleDir, 'src', 'app', 'sign-in', 'page.tsx')), true);
    assert.equal(fs.existsSync(path.join(bundle.bundleDir, 'src', 'lib', 'auth.ts')), true);
    assert.equal(fs.existsSync(path.join(bundle.bundleDir, 'src', 'lib', 'telemetry.ts')), true);
  });
});

test('loadHeadlessProductBenchmarkCorpus and summarizeHeadlessBenchmarkResults normalize certification inputs', () => {
  withFixture((root) => {
    const corpus = core.loadHeadlessProductBenchmarkCorpus(root);
    assert.equal(corpus.version, 1);
    assert.equal(corpus.cases.length, 3);
    assert.equal(corpus.cases[0].workflow, 'go');
    assert.equal(corpus.cases[1].sourcePath, 'evals/fixtures/dashboard.spec.json');
    assert.equal(corpus.cases[2].expectedOutcome, 'BLOCKED');

    const summary = core.summarizeHeadlessBenchmarkResults(corpus, [
      {
        caseId: 'marketing-go-prompt',
        lane: 'marketing-site',
        workflow: 'go',
        status: 'pass',
        outcome: 'HANDOFF_READY',
        expectedOutcome: 'HANDOFF_READY',
        checks: { laneMatch: true, packMatch: true, bundleCreated: true, buildVerified: true, configStable: true },
        notes: []
      },
      {
        caseId: 'dashboard-minion-spec',
        lane: 'saas-dashboard',
        workflow: 'minion',
        status: 'fail',
        outcome: 'FAILED',
        expectedOutcome: 'HANDOFF_READY',
        checks: { laneMatch: true, packMatch: true, bundleCreated: false, buildVerified: false, configStable: false },
        notes: ['bundle generation failed']
      },
      {
        caseId: 'unsupported-crud-shell',
        lane: 'crud-shell',
        workflow: 'go',
        status: 'pass',
        outcome: 'BLOCKED',
        expectedOutcome: 'BLOCKED',
        checks: { laneMatch: true, packMatch: true, bundleCreated: false, buildVerified: false, configStable: false },
        notes: ['unsupported lane correctly blocked']
      }
    ]);

    assert.equal(summary.totals.totalCases, 3);
    assert.equal(summary.totals.passed, 2);
    assert.equal(summary.totals.failed, 1);
    assert.equal(summary.overallStatus, 'fail');
    assert.equal(summary.lanes['marketing-site'].passed, 1);
    assert.equal(summary.lanes['saas-dashboard'].failed, 1);
    assert.equal(summary.lanes['crud-shell'].passed, 1);
  });
});
