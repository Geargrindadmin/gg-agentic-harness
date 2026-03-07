import fs from 'node:fs';
import path from 'node:path';

export type CatalogKind = 'skill' | 'workflow';

export interface CatalogEntry {
  kind: CatalogKind;
  slug: string;
  name: string;
  description: string;
  category?: string;
  filePath: string;
}

export interface HarnessPaths {
  projectRoot: string;
  agentDir: string;
  skillsDir: string;
  workflowsDir: string;
  mcpConfigPath: string;
  runArtifactDir: string;
}

function stripQuotes(value: string): string {
  const trimmed = value.trim();
  if (
    (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
    (trimmed.startsWith("'") && trimmed.endsWith("'"))
  ) {
    return trimmed.slice(1, -1).trim();
  }
  return trimmed;
}

function parseFrontmatter(raw: string): Record<string, string> {
  if (!raw.startsWith('---\n')) {
    return {};
  }

  const endIdx = raw.indexOf('\n---\n', 4);
  if (endIdx === -1) {
    return {};
  }

  const section = raw.slice(4, endIdx);
  const data: Record<string, string> = {};
  for (const line of section.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }
    const match = /^([A-Za-z0-9_-]+)\s*:\s*(.+)$/.exec(trimmed);
    if (!match) {
      continue;
    }
    data[match[1]] = stripQuotes(match[2]);
  }

  return data;
}

function deriveCategory(slug: string): string {
  if (slug.startsWith('ads-') || slug === 'ads') return 'Advertising';
  if (slug.startsWith('eval-')) return 'Evaluation';
  if (slug.startsWith('loop-')) return 'Evaluate-Loop';
  if (['frontend-design', 'tailwind-patterns', 'web-design-guidelines'].includes(slug)) {
    return 'Frontend';
  }
  if (['api-patterns', 'nodejs-best-practices', 'database-design'].includes(slug)) {
    return 'Backend';
  }
  if (['vulnerability-scanner', 'red-team-tactics'].includes(slug)) {
    return 'Security';
  }
  if (['tdd-workflow', 'test-driven-development', 'testing-patterns', 'webapp-testing'].includes(slug)) {
    return 'Testing';
  }
  if (['deployment-procedures', 'server-management'].includes(slug)) {
    return 'DevOps';
  }
  if (['pdf', 'pptx', 'docx', 'xlsx'].includes(slug)) {
    return 'Documents';
  }
  return 'Core';
}

function scoreText(haystack: string, needleTokens: string[]): number {
  const lower = haystack.toLowerCase();
  let score = 0;
  for (const token of needleTokens) {
    if (lower.includes(token)) {
      score += token.length;
    }
  }
  return score;
}

function ensureDirExists(dirPath: string): void {
  if (!fs.existsSync(dirPath)) {
    throw new Error(`Path not found: ${dirPath}`);
  }
}

export function resolveProjectRoot(startDir = process.cwd()): string {
  let current = path.resolve(startDir);

  while (true) {
    const hasPkg = fs.existsSync(path.join(current, 'package.json'));
    const hasAgent = fs.existsSync(path.join(current, '.agent'));
    if (hasPkg && hasAgent) {
      return current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      throw new Error(`Could not resolve project root from: ${startDir}`);
    }
    current = parent;
  }
}

export function getHarnessPaths(projectRoot = resolveProjectRoot()): HarnessPaths {
  return {
    projectRoot,
    agentDir: path.join(projectRoot, '.agent'),
    skillsDir: path.join(projectRoot, '.agent', 'skills'),
    workflowsDir: path.join(projectRoot, '.agent', 'workflows'),
    mcpConfigPath: path.join(projectRoot, '.mcp.json'),
    runArtifactDir: path.join(projectRoot, '.agent', 'runs')
  };
}

export function loadSkills(projectRoot = resolveProjectRoot()): CatalogEntry[] {
  const { skillsDir } = getHarnessPaths(projectRoot);
  ensureDirExists(skillsDir);

  const entries: CatalogEntry[] = [];
  const dirents = fs.readdirSync(skillsDir, { withFileTypes: true });

  for (const dirent of dirents) {
    if (!dirent.isDirectory()) {
      continue;
    }

    const slug = dirent.name;
    const filePath = path.join(skillsDir, slug, 'SKILL.md');
    if (!fs.existsSync(filePath)) {
      continue;
    }

    const raw = fs.readFileSync(filePath, 'utf8');
    const fm = parseFrontmatter(raw);
    const description = fm.description || '';
    const name = fm.name || slug;

    entries.push({
      kind: 'skill',
      slug,
      name,
      description,
      category: deriveCategory(slug),
      filePath
    });
  }

  return entries.sort((a, b) => a.slug.localeCompare(b.slug));
}

export function loadWorkflows(projectRoot = resolveProjectRoot()): CatalogEntry[] {
  const { workflowsDir } = getHarnessPaths(projectRoot);
  ensureDirExists(workflowsDir);

  const entries: CatalogEntry[] = [];
  const dirents = fs.readdirSync(workflowsDir, { withFileTypes: true });

  for (const dirent of dirents) {
    if (!dirent.isFile() || !dirent.name.endsWith('.md')) {
      continue;
    }

    const slug = dirent.name.replace(/\.md$/u, '');
    const filePath = path.join(workflowsDir, dirent.name);
    const raw = fs.readFileSync(filePath, 'utf8');
    const fm = parseFrontmatter(raw);
    const description = fm.description || '';
    const name = fm.name || slug;

    entries.push({
      kind: 'workflow',
      slug,
      name,
      description,
      filePath
    });
  }

  return entries.sort((a, b) => a.slug.localeCompare(b.slug));
}

export function searchCatalog(entries: CatalogEntry[], query: string, limit = 5): CatalogEntry[] {
  const trimmed = query.trim().toLowerCase();
  if (!trimmed) {
    return entries.slice(0, limit);
  }

  const tokens = trimmed.split(/\s+/u).filter(Boolean);

  const ranked = entries
    .map((entry) => {
      const base = `${entry.slug} ${entry.name} ${entry.description}`;
      const score = scoreText(base, tokens);
      const exactBoost = entry.slug.toLowerCase() === trimmed ? 1000 : 0;
      return { entry, score: score + exactBoost };
    })
    .filter((row) => row.score > 0)
    .sort((a, b) => b.score - a.score || a.entry.slug.localeCompare(b.entry.slug));

  return ranked.slice(0, limit).map((row) => row.entry);
}

export function readCatalogEntryContent(entry: CatalogEntry): string {
  return fs.readFileSync(entry.filePath, 'utf8');
}

export function readJsonFile<T = unknown>(filePath: string): T | null {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T;
  } catch {
    return null;
  }
}
