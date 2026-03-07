#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');
const vaultPath = process.env.OBSIDIAN_VAULT_PATH || path.join(repoRoot, 'docs');
const appBin = '/Applications/Obsidian.app/Contents/MacOS/Obsidian';

const results = [];

function addResult(name, ok, detail) {
  results.push({ name, ok, detail });
}

function run(bin, args = []) {
  return spawnSync(bin, args, { encoding: 'utf8' });
}

const appInstalled = fs.existsSync(appBin);
addResult('Obsidian app binary', appInstalled, appInstalled ? appBin : 'Obsidian.app not found in /Applications');

const which = run('sh', ['-lc', 'command -v obsidian || true']);
const whichLoginZsh = run('zsh', ['-lc', 'command -v obsidian || true']);
const activePathCmd = (which.stdout || '').trim();
const loginPathCmd = (whichLoginZsh.stdout || '').trim();
const obsidianOnPath = Boolean(activePathCmd || loginPathCmd);
addResult(
  'obsidian command on PATH',
  obsidianOnPath,
  activePathCmd || loginPathCmd || 'Run: export PATH="$PATH:/Applications/Obsidian.app/Contents/MacOS"'
);

let cliEnabled = false;
if (appInstalled) {
  const help = run(appBin, ['help']);
  const output = `${help.stdout || ''}${help.stderr || ''}`;
  cliEnabled = !output.includes('Command line interface is not enabled');
  addResult('Obsidian CLI enabled', cliEnabled, cliEnabled ? 'Enabled' : 'Enable in Obsidian: Settings > General > Advanced > Command line interface');
}

const vaultExists = fs.existsSync(vaultPath);
addResult('Vault path exists', vaultExists, vaultPath);

const obsidianConfigExists = fs.existsSync(path.join(vaultPath, '.obsidian'));
addResult('Vault has .obsidian config', obsidianConfigExists, obsidianConfigExists ? '.obsidian found' : 'Open this folder as a vault in Obsidian once');

let failures = 0;
for (const r of results) {
  const mark = r.ok ? 'PASS' : 'FAIL';
  console.log(`${mark} ${r.name}: ${r.detail}`);
  if (!r.ok) failures += 1;
}

if (!cliEnabled) {
  console.log('\nNext manual step: open Obsidian app and enable CLI in Settings > General > Advanced.');
}

process.exit(failures > 0 ? 1 : 0);
