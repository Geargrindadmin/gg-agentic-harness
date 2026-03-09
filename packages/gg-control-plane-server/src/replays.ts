import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { serverPaths } from './store.js';

export interface ReplaySourceInfo {
  key: string;
  label: string;
  root: string;
  available: boolean;
}

export interface ReplaySessionInfo {
  id: string;
  source: string;
  path: string;
  title: string;
  format: string;
  turnCount: number;
  modifiedAt: string;
  sizeBytes: number;
}

export interface ReplayRenderResult {
  sessionId: string;
  title: string;
  inputPath: string;
  outputPath: string;
  outputUrl: string;
  turnCount: number;
}

interface ClaudeReplayModules {
  detectFormat(filePath: string): string;
  parseTranscript(filePath: string): any[];
  applyPacedTiming(turns: any[]): void;
  render(turns: any[], options?: Record<string, unknown>): string;
}

function replayRoots(): ReplaySourceInfo[] {
  const home = os.homedir();
  return [
    {
      key: 'claude',
      label: 'Claude Code',
      root: path.join(home, '.claude', 'projects'),
      available: fs.existsSync(path.join(home, '.claude', 'projects'))
    },
    {
      key: 'cursor',
      label: 'Cursor',
      root: path.join(home, '.cursor', 'projects'),
      available: fs.existsSync(path.join(home, '.cursor', 'projects'))
    }
  ];
}

function walkJsonlFiles(root: string, maxFiles = 250): string[] {
  const files: string[] = [];
  const queue = [root];

  while (queue.length && files.length < maxFiles) {
    const current = queue.shift() as string;
    let entries: fs.Dirent[] = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }

    for (const entry of entries) {
      if (files.length >= maxFiles) {
        break;
      }
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        queue.push(fullPath);
      } else if (entry.isFile() && entry.name.endsWith('.jsonl')) {
        files.push(fullPath);
      }
    }
  }

  return files;
}

async function loadClaudeReplayModules(projectRoot: string): Promise<ClaudeReplayModules> {
  const vendorRoot = path.join(projectRoot, 'third-party', 'claude-replay', 'src');
  const parser = await import(pathToFileURL(path.join(vendorRoot, 'parser.mjs')).href);
  const renderer = await import(pathToFileURL(path.join(vendorRoot, 'renderer.mjs')).href);
  return {
    detectFormat: parser.detectFormat,
    parseTranscript: parser.parseTranscript,
    applyPacedTiming: parser.applyPacedTiming,
    render: renderer.render
  };
}

function isWithinReplayRoots(candidate: string): boolean {
  const resolved = path.resolve(candidate);
  return replayRoots().some((source) => {
    if (!source.available) {
      return false;
    }
    const root = path.resolve(source.root);
    return resolved === root || resolved.startsWith(`${root}${path.sep}`);
  });
}

function titleFromPath(filePath: string): string {
  const parent = path.basename(path.dirname(filePath));
  const base = path.basename(filePath, '.jsonl');
  return parent && parent !== base ? `${parent} / ${base}` : base;
}

export function listReplaySources(): ReplaySourceInfo[] {
  return replayRoots();
}

export async function listReplaySessions(projectRoot: string, limit = 100): Promise<ReplaySessionInfo[]> {
  const modules = await loadClaudeReplayModules(projectRoot);
  const sessions: ReplaySessionInfo[] = [];

  for (const source of replayRoots()) {
    if (!source.available) {
      continue;
    }
    for (const filePath of walkJsonlFiles(source.root)) {
      try {
        const stat = fs.statSync(filePath);
        const format = modules.detectFormat(filePath);
        const turns = modules.parseTranscript(filePath);
        sessions.push({
          id: createHash('sha1').update(filePath).digest('hex').slice(0, 16),
          source: source.key,
          path: filePath,
          title: titleFromPath(filePath),
          format,
          turnCount: turns.length,
          modifiedAt: stat.mtime.toISOString(),
          sizeBytes: stat.size
        });
      } catch {
        continue;
      }
    }
  }

  return sessions
    .sort((left, right) => right.modifiedAt.localeCompare(left.modifiedAt))
    .slice(0, limit);
}

export async function renderReplay(projectRoot: string, inputPath: string): Promise<ReplayRenderResult> {
  const resolved = path.resolve(inputPath);
  if (!fs.existsSync(resolved)) {
    throw new Error(`Transcript not found: ${resolved}`);
  }
  if (!isWithinReplayRoots(resolved)) {
    throw new Error('Replay render is restricted to approved transcript roots');
  }

  const modules = await loadClaudeReplayModules(projectRoot);
  const turns = modules.parseTranscript(resolved);
  if (!turns.some((turn) => turn.timestamp)) {
    modules.applyPacedTiming(turns);
  }

  const html = modules.render(turns, {
    title: titleFromPath(resolved),
    assistantLabel: 'Assistant'
  });

  const replayDir = path.join(serverPaths(projectRoot).root, 'replays');
  fs.mkdirSync(replayDir, { recursive: true });

  const sessionId = createHash('sha1').update(resolved).digest('hex').slice(0, 16);
  const outputPath = path.join(replayDir, `${sessionId}.html`);
  fs.writeFileSync(outputPath, html, 'utf8');

  return {
    sessionId,
    title: titleFromPath(resolved),
    inputPath: resolved,
    outputPath,
    outputUrl: `/api/replays/file?path=${encodeURIComponent(outputPath)}`,
    turnCount: turns.length
  };
}
