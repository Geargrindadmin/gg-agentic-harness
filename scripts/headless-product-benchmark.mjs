#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

import {
  loadHeadlessProductBenchmarkCorpus,
  summarizeHeadlessBenchmarkResults
} from '../packages/gg-core/dist/index.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(__dirname, '..');
const cliEntry = path.join(projectRoot, 'packages', 'gg-cli', 'dist', 'index.js');

function parseArgs(argv) {
  const flags = {};
  const positionals = [];

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith('--')) {
      positionals.push(token);
      continue;
    }

    const key = token.slice(2);
    const next = argv[index + 1];
    if (!next || next.startsWith('--')) {
      flags[key] = true;
      continue;
    }

    flags[key] = next;
    index += 1;
  }

  return { flags, positionals };
}

function stringFlag(flags, key, fallback = '') {
  return typeof flags[key] === 'string' ? flags[key] : fallback;
}

function boolFlag(flags, key) {
  return flags[key] === true;
}

function nowStamp() {
  return new Date().toISOString().replace(/[:.]/gu, '-');
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function runCliJson(args) {
  const result = spawnSync('node', [cliEntry, '--json', '--project-root', projectRoot, ...args], {
    cwd: projectRoot,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 20
  });

  const stdout = result.stdout.trim();
  let payload = null;
  if (stdout) {
    try {
      payload = JSON.parse(stdout);
    } catch (error) {
      payload = {
        ok: false,
        parseError: error instanceof Error ? error.message : String(error),
        rawStdout: stdout
      };
    }
  }

  return {
    code: result.status ?? 1,
    stdout: result.stdout,
    stderr: result.stderr,
    payload
  };
}

function runCommand(command, args, cwd) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 20
  });

  return {
    code: result.status ?? 1,
    stdout: result.stdout,
    stderr: result.stderr,
    command,
    args
  };
}

function normalizeCaseRequest(testCase) {
  if (testCase.sourceType === 'prompt') {
    return testCase.request || '';
  }
  return testCase.sourcePath || '';
}

function captureTrackedConfig(bundleDir) {
  const tracked = ['tsconfig.json', 'next.config.ts'];
  const snapshot = {};

  for (const file of tracked) {
    const absolutePath = path.join(bundleDir, file);
    snapshot[file] = fs.existsSync(absolutePath) ? fs.readFileSync(absolutePath, 'utf8') : null;
  }

  return snapshot;
}

function compareTrackedConfig(bundleDir, beforeSnapshot) {
  const tracked = Object.keys(beforeSnapshot);
  const diffs = [];
  let stable = true;

  for (const file of tracked) {
    const absolutePath = path.join(bundleDir, file);
    const after = fs.existsSync(absolutePath) ? fs.readFileSync(absolutePath, 'utf8') : null;
    if (after !== beforeSnapshot[file]) {
      stable = false;
      diffs.push(file);
    }
  }

  return { stable, diffs };
}

function verifyBundle(bundleDir) {
  const before = captureTrackedConfig(bundleDir);
  const commands = [
    runCommand('npm', ['install'], bundleDir),
    runCommand('npm', ['run', 'typecheck'], bundleDir),
    runCommand('npm', ['run', 'lint'], bundleDir),
    runCommand('npm', ['run', 'build'], bundleDir)
  ];
  const failed = commands.find((item) => item.code !== 0) || null;
  const configDiff = compareTrackedConfig(bundleDir, before);

  return {
    commands,
    failed,
    configStable: configDiff.stable,
    changedConfigFiles: configDiff.diffs
  };
}

function renderMarkdownReport(corpus, results, summary, options, jsonPath) {
  const lines = [
    '# Headless Product Benchmark Report',
    '',
    `- Generated: ${new Date().toISOString()}`,
    `- Corpus version: ${corpus.version}`,
    `- Build verification: ${options.verifyBuild ? 'enabled' : 'disabled'}`,
    `- Downstream cases included: ${options.includeDownstream ? 'yes' : 'no'}`,
    `- JSON results: ${path.relative(projectRoot, jsonPath)}`,
    '',
    '## Totals',
    `- Total cases: ${summary.totals.totalCases}`,
    `- Passed: ${summary.totals.passed}`,
    `- Failed: ${summary.totals.failed}`,
    `- Skipped: ${summary.totals.skipped}`,
    `- Overall status: ${summary.overallStatus}`,
    '',
    '## Lane Scorecard',
    '| Lane | Total | Passed | Failed | Skipped |',
    '| --- | ---: | ---: | ---: | ---: |'
  ];

  for (const [lane, laneSummary] of Object.entries(summary.lanes)) {
    lines.push(`| ${lane} | ${laneSummary.total} | ${laneSummary.passed} | ${laneSummary.failed} | ${laneSummary.skipped} |`);
  }

  lines.push('', '## Case Results', '| Case | Workflow | Lane | Status | Outcome | Notes |', '| --- | --- | --- | --- | --- | --- |');

  for (const result of results) {
    lines.push(`| ${result.caseId} | ${result.workflow} | ${result.lane} | ${result.status} | ${result.outcome} | ${result.notes.join('<br>') || '-'} |`);
  }

  lines.push('');
  return `${lines.join('\n')}\n`;
}

function runBenchmarkCase(testCase, options) {
  if (testCase.deliveryTarget === 'downstream-install' && !options.includeDownstream) {
    return {
      caseId: testCase.id,
      lane: testCase.lane,
      workflow: testCase.workflow,
      status: 'skipped',
      outcome: 'SKIPPED',
      expectedOutcome: testCase.expectedOutcome,
      checks: {
        laneMatch: true,
        packMatch: true,
        bundleCreated: false,
        buildVerified: false,
        configStable: false
      },
      notes: ['Skipped downstream-install case by default']
    };
  }

  const request = normalizeCaseRequest(testCase);
  const benchmarkBundleDir = path.join('.agent', 'product-benchmarks', testCase.id);
  const cliArgs = ['workflow', 'run', testCase.workflow, request];
  if (testCase.workflow === 'create') {
    cliArgs.push('--output-dir', benchmarkBundleDir, '--force');
  } else if (testCase.workflow === 'minion') {
    cliArgs.push('--validate', 'none', '--doc-sync', 'off');
  }

  const cliResult = runCliJson(cliArgs);
  const data = cliResult.payload?.data || {};
  const actualOutcome = typeof data.outcome === 'string'
    ? data.outcome
    : cliResult.code === 0
      ? 'HANDOFF_READY'
      : 'FAILED';
  const actualLane = typeof data?.canonicalSpec?.lane === 'string' ? data.canonicalSpec.lane : '';
  const actualPacks = Array.isArray(data?.canonicalSpec?.enterprisePacks)
    ? data.canonicalSpec.enterprisePacks.filter((entry) => typeof entry === 'string')
    : [];
  const bundleDir = typeof data.bundleDir === 'string' ? data.bundleDir : '';
  const bundleCreated = bundleDir ? fs.existsSync(bundleDir) : false;
  const laneMatch = actualLane === testCase.lane;
  const packMatch = testCase.expectedPacks.every((pack) => actualPacks.includes(pack));
  const notes = [];

  if (typeof data.runArtifact === 'string') {
    notes.push(`runArtifact=${path.relative(projectRoot, data.runArtifact)}`);
  }
  if (bundleDir) {
    notes.push(`bundleDir=${path.relative(projectRoot, bundleDir)}`);
  }
  if (cliResult.payload?.parseError) {
    notes.push(`parseError=${cliResult.payload.parseError}`);
  }
  if (cliResult.code !== 0 && cliResult.stderr.trim()) {
    notes.push(`stderr=${cliResult.stderr.trim().split('\n')[0]}`);
  }

  let buildVerified = false;
  let configStable = false;
  if (
    options.verifyBuild &&
    testCase.expectedOutcome === 'HANDOFF_READY' &&
    bundleCreated &&
    actualOutcome === 'HANDOFF_READY'
  ) {
    const verification = verifyBundle(bundleDir);
    buildVerified = verification.failed === null;
    configStable = verification.configStable;
    if (verification.failed) {
      notes.push(`verificationFailed=${verification.failed.command} ${verification.failed.args.join(' ')}`);
    }
    if (!verification.configStable) {
      notes.push(`configChanged=${verification.changedConfigFiles.join(',')}`);
    }
  }

  const pass =
    actualOutcome === testCase.expectedOutcome &&
    laneMatch &&
    packMatch &&
    (testCase.expectedOutcome !== 'HANDOFF_READY' || bundleCreated) &&
    (!options.verifyBuild || testCase.expectedOutcome !== 'HANDOFF_READY' || (buildVerified && configStable));

  return {
    caseId: testCase.id,
    lane: testCase.lane,
    workflow: testCase.workflow,
    status: pass ? 'pass' : 'fail',
    outcome: actualOutcome,
    expectedOutcome: testCase.expectedOutcome,
    checks: {
      laneMatch,
      packMatch,
      bundleCreated,
      buildVerified,
      configStable
    },
    notes
  };
}

function main() {
  const { flags } = parseArgs(process.argv.slice(2));
  const selectedCases = stringFlag(flags, 'case')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
  const includeDownstream = boolFlag(flags, 'include-downstream');
  const verifyBuild = !boolFlag(flags, 'no-verify-build');
  const jsonMode = boolFlag(flags, 'json');
  const corpusPath = stringFlag(flags, 'corpus', path.join('evals', 'headless-product-corpus.json'));
  const outputDir = stringFlag(flags, 'output-dir', path.join('.agent', 'benchmarks', 'headless-product'));
  const corpus = loadHeadlessProductBenchmarkCorpus(projectRoot, corpusPath);
  const cases = corpus.cases.filter((entry) => selectedCases.length === 0 || selectedCases.includes(entry.id));
  const results = cases.map((entry) => runBenchmarkCase(entry, { includeDownstream, verifyBuild }));
  const summary = summarizeHeadlessBenchmarkResults(corpus, results);

  const absoluteOutputDir = path.join(projectRoot, outputDir);
  const absoluteReportDir = path.join(projectRoot, 'docs', 'reports');
  ensureDir(absoluteOutputDir);
  ensureDir(absoluteReportDir);

  const stamp = nowStamp();
  const jsonPath = path.join(absoluteOutputDir, `headless-product-benchmark-${stamp}.json`);
  const markdownPath = path.join(absoluteReportDir, `headless-product-benchmark-${stamp}.md`);

  fs.writeFileSync(jsonPath, `${JSON.stringify({
    generatedAt: new Date().toISOString(),
    corpusPath,
    verifyBuild,
    includeDownstream,
    summary,
    results
  }, null, 2)}\n`, 'utf8');
  fs.writeFileSync(markdownPath, renderMarkdownReport(corpus, results, summary, { verifyBuild, includeDownstream }, jsonPath), 'utf8');

  const payload = {
    ok: summary.overallStatus === 'pass',
    summary,
    results,
    jsonPath,
    markdownPath
  };

  if (jsonMode) {
    console.log(JSON.stringify(payload, null, 2));
  } else {
    console.log(`Headless product benchmark: ${summary.overallStatus}`);
    console.log(`JSON: ${jsonPath}`);
    console.log(`Markdown: ${markdownPath}`);
  }

  process.exit(summary.overallStatus === 'pass' ? 0 : 1);
}

main();
