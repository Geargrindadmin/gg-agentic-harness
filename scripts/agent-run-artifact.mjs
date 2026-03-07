#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

function usage() {
  console.error('Usage: node scripts/agent-run-artifact.mjs <init|gate|mcp|complete> [--key value ...]');
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

function requireArg(args, key) {
  if (!args[key]) {
    console.error(`Missing required argument --${key}`);
    usage();
  }
  return args[key];
}

function nowIso() {
  return new Date().toISOString();
}

function runPath(runId) {
  return path.join('.agent', 'runs', `${runId}.json`);
}

function readRun(runId) {
  const p = runPath(runId);
  if (!fs.existsSync(p)) {
    console.error(`Run artifact not found: ${p}`);
    process.exit(1);
  }
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function writeRun(runId, data) {
  const p = runPath(runId);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  data.updatedAt = nowIso();
  fs.writeFileSync(p, `${JSON.stringify(data, null, 2)}\n`);
  console.log(p);
}

const [command, ...rest] = process.argv.slice(2);
if (!command) usage();
const args = parseArgs(rest);

if (command === 'init') {
  const runId = requireArg(args, 'id');
  const runtimeProfile = args.runtime || 'codex';
  const classification = args.classification || 'TASK';
  const taskSummary = args.summary || '';
  const now = nowIso();

  const artifact = {
    schemaVersion: 1,
    runId,
    createdAt: now,
    updatedAt: now,
    status: 'in_progress',
    runtimeProfile,
    classification,
    taskSummary,
    selectedSkills: [],
    mcpCalls: [],
    gates: [],
    retries: [],
    rollback: null
  };

  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'gate') {
  const runId = requireArg(args, 'id');
  const name = requireArg(args, 'name');
  const gateCommand = requireArg(args, 'command');
  const exitCode = Number(requireArg(args, 'exit-code'));
  const attempt = Number(args.attempt || 1);

  const artifact = readRun(runId);
  artifact.gates.push({
    name,
    command: gateCommand,
    exitCode,
    attempt,
    timestamp: nowIso()
  });
  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'mcp') {
  const runId = requireArg(args, 'id');
  const server = requireArg(args, 'server');
  const tool = requireArg(args, 'tool');
  const status = args.status || 'pass';
  const detail = args.detail || '';

  const artifact = readRun(runId);
  artifact.mcpCalls.push({
    server,
    tool,
    status,
    detail,
    timestamp: nowIso()
  });
  writeRun(runId, artifact);
  process.exit(0);
}

if (command === 'complete') {
  const runId = requireArg(args, 'id');
  const status = args.status || 'success';
  const summary = args.summary || '';

  const artifact = readRun(runId);
  artifact.status = status;
  if (summary) artifact.summary = summary;
  writeRun(runId, artifact);
  process.exit(0);
}

usage();
