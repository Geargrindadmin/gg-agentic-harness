#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function usage() {
  console.error(
    'Usage: node scripts/feedback-loop-report.mjs [--window-days 7] [--format text|json] [--limit 20] [--write-proposal slug]'
  );
  process.exit(2);
}

function parseArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith('--')) {
      args[key] = true;
    } else {
      args[key] = next;
      i += 1;
    }
  }
  return args;
}

function inferProposalKind(signature) {
  if (/\bTS\d{4}\b|typescript|tsc/i.test(signature)) return 'rule';
  if (/eslint|lint|@typescript-eslint|prettier/i.test(signature)) return 'rule';
  if (/playwright|jest|vitest|test/i.test(signature)) return 'workflow';
  return 'skill';
}

function inferThreshold(signature) {
  if (/playwright|jest|vitest|flaky|test/i.test(signature)) return 2;
  return 3;
}

function collectRecords(run) {
  const records = [];
  const signatures = Array.isArray(run.failureSignatures) ? run.failureSignatures : [];

  if (signatures.length) {
    for (const entry of signatures) {
      records.push({
        signature: entry.signature,
        gate: entry.gate || 'unknown',
        count: entry.count || 1,
        failureCode: entry.failureCode || '',
        failurePath: entry.failurePath || ''
      });
    }
    return records;
  }

  for (const gate of Array.isArray(run.gates) ? run.gates : []) {
    if (gate.status !== 'fail') continue;
    records.push({
      signature: gate.signature || `${gate.name}|${gate.command}`,
      gate: gate.name || 'unknown',
      count: 1,
      failureCode: '',
      failurePath: ''
    });
  }

  return records;
}

function loadRuns(windowDays) {
  const runsDir = path.join('.agent', 'runs');
  if (!fs.existsSync(runsDir)) return [];

  const cutoff = Date.now() - windowDays * 24 * 60 * 60 * 1000;
  const runs = [];

  for (const file of fs.readdirSync(runsDir)) {
    if (!file.endsWith('.json')) continue;
    const fullPath = path.join(runsDir, file);

    try {
      const run = JSON.parse(fs.readFileSync(fullPath, 'utf8'));
      const createdAt = Date.parse(run.createdAt || '');
      if (Number.isNaN(createdAt) || createdAt < cutoff) continue;
      runs.push(run);
    } catch (error) {
      console.warn(`Skipping unreadable run artifact: ${fullPath} (${String(error)})`);
    }
  }

  return runs;
}

function buildReport(runs) {
  const groups = new Map();

  for (const run of runs) {
    for (const record of collectRecords(run)) {
      const key = record.signature;
      const existing = groups.get(key) || {
        signature: key,
        gates: new Set(),
        runIds: new Set(),
        runtimes: new Set(),
        occurrences: 0,
        firstSeenAt: run.createdAt || '',
        lastSeenAt: run.updatedAt || run.createdAt || '',
        failureCode: record.failureCode || '',
        failurePath: record.failurePath || ''
      };

      existing.gates.add(record.gate);
      existing.runIds.add(run.runId || path.basename(String(run.file || 'unknown')));
      existing.runtimes.add(run.runtimeProfile || 'unknown');
      existing.occurrences += Math.max(record.count || 1, 1);
      if (!existing.firstSeenAt || (run.createdAt && run.createdAt < existing.firstSeenAt)) {
        existing.firstSeenAt = run.createdAt || existing.firstSeenAt;
      }
      if (!existing.lastSeenAt || (run.updatedAt && run.updatedAt > existing.lastSeenAt)) {
        existing.lastSeenAt = run.updatedAt || existing.lastSeenAt;
      }
      if (!existing.failureCode && record.failureCode) existing.failureCode = record.failureCode;
      if (!existing.failurePath && record.failurePath) existing.failurePath = record.failurePath;

      groups.set(key, existing);
    }
  }

  const entries = [...groups.values()].map((entry) => {
    const runCount = entry.runIds.size;
    const threshold = inferThreshold(entry.signature);
    return {
      signature: entry.signature,
      gates: [...entry.gates].sort(),
      runIds: [...entry.runIds].sort(),
      runtimes: [...entry.runtimes].sort(),
      runCount,
      occurrences: entry.occurrences,
      threshold,
      triggered: runCount >= threshold,
      proposalKind: inferProposalKind(entry.signature),
      firstSeenAt: entry.firstSeenAt,
      lastSeenAt: entry.lastSeenAt,
      failureCode: entry.failureCode,
      failurePath: entry.failurePath
    };
  });

  return entries.sort((a, b) => b.runCount - a.runCount || b.occurrences - a.occurrences);
}

function writeProposal(slug, report, windowDays) {
  const triggered = report.filter((entry) => entry.triggered);
  const date = new Date().toISOString().slice(0, 10);
  const dir = path.join('docs', 'governance', 'feedback-loop-proposals');
  fs.mkdirSync(dir, { recursive: true });

  const filePath = path.join(dir, `${date}-${slug}.md`);
  const body = [
    `# Feedback Loop Proposal: ${slug}`,
    '',
    `Date: ${date}`,
    `Window: last ${windowDays} days`,
    '',
    '## Triggered Signatures',
    ''
  ];

  if (!triggered.length) {
    body.push('No triggered recurring signatures were found in the selected window.');
  } else {
    for (const entry of triggered) {
      body.push(`### ${entry.signature}`);
      body.push('');
      body.push(`- Proposed hardening type: \`${entry.proposalKind}\``);
      body.push(`- Runs: ${entry.runIds.join(', ')}`);
      body.push(`- Gates: ${entry.gates.join(', ')}`);
      body.push(`- Runtimes: ${entry.runtimes.join(', ')}`);
      body.push(`- Threshold: ${entry.runCount}/${entry.threshold}`);
      if (entry.failureCode) body.push(`- Failure code: \`${entry.failureCode}\``);
      if (entry.failurePath) body.push(`- Failure path: \`${entry.failurePath}\``);
      body.push('');
    }
  }

  body.push('## Recommendation');
  body.push('');
  body.push('Create or update one of the following based on the dominant signature:');
  body.push('- `.agent/rules/*.md` for policy gaps');
  body.push('- `.agent/workflows/*.md` for orchestration gaps');
  body.push('- `.agent/skills/*/SKILL.md` for repeated operator knowledge gaps');
  body.push('');

  fs.writeFileSync(filePath, `${body.join('\n')}\n`);
  return filePath;
}

const args = parseArgs(process.argv.slice(2));
if (args.help) usage();

const windowDays = Number(args['window-days'] || 7);
const format = String(args.format || 'text');
const limit = Number(args.limit || 20);

if (!Number.isFinite(windowDays) || windowDays <= 0) usage();
if (!Number.isFinite(limit) || limit <= 0) usage();

const runs = loadRuns(windowDays);
const report = buildReport(runs).slice(0, limit);

if (args['write-proposal']) {
  const proposalPath = writeProposal(String(args['write-proposal']), report, windowDays);
  if (format === 'json') {
    process.stdout.write(`${JSON.stringify({ proposalPath, report }, null, 2)}\n`);
  } else {
    console.log(`Proposal written: ${proposalPath}`);
  }
  process.exit(0);
}

if (format === 'json') {
  process.stdout.write(`${JSON.stringify({ windowDays, runs: runs.length, report }, null, 2)}\n`);
  process.exit(0);
}

console.log(`Feedback loop report (${runs.length} runs, window ${windowDays}d)`);
for (const entry of report) {
  const marker = entry.triggered ? 'TRIGGERED' : 'watch';
  console.log(
    `- [${marker}] ${entry.signature} | runs=${entry.runCount}/${entry.threshold} | kind=${entry.proposalKind}`
  );
}
