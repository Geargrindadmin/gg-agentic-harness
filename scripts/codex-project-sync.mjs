#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { activateRuntimeProject, getRuntimeProjectState } from './runtime-project-sync.mjs';

export function getCodexProjectState(targetRoot, codexHome) {
  return getRuntimeProjectState(targetRoot, 'codex', { codexHome });
}

export function activateCodexProject(targetRoot, codexHome) {
  return activateRuntimeProject(targetRoot, 'codex', { codexHome });
}

function parseArgs(argv) {
  const parsed = {
    action: argv[0] || '',
    targetRoot: process.cwd(),
    codexHome: undefined,
    json: false
  };

  for (let index = 1; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--json') parsed.json = true;
    else if (token === '--codex-home') parsed.codexHome = argv[++index] ?? parsed.codexHome;
    else if (!token.startsWith('--')) parsed.targetRoot = token;
  }

  return parsed;
}

function printState(result, action) {
  console.log(`Codex ${action}: ${result.targetRoot}`);
  console.log(`Active: ${result.active ? 'yes' : 'no'}`);
  for (const check of result.checks) {
    console.log(`[${check.ok ? 'pass' : 'fail'}] ${check.id}: ${check.detail}`);
  }
  if (action === 'activate') {
    console.log(`Restart required: ${result.restartRequired ? 'yes' : 'no'}`);
  }
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!['activate', 'status'].includes(args.action)) {
    console.error('Usage: node scripts/codex-project-sync.mjs <activate|status> [targetRoot] [--codex-home <path>] [--json]');
    process.exit(2);
  }

  const result = args.action === 'activate'
    ? activateCodexProject(args.targetRoot, args.codexHome)
    : getCodexProjectState(args.targetRoot, args.codexHome);

  if (args.json) {
    console.log(JSON.stringify(result, null, 2));
  } else {
    printState(result, args.action);
  }
}

function isDirectExecution() {
  if (!process.argv[1]) return false;

  const modulePath = fs.realpathSync(fileURLToPath(import.meta.url));
  const entryPath = fs.realpathSync(path.resolve(process.argv[1]));
  return modulePath === entryPath;
}

if (isDirectExecution()) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
