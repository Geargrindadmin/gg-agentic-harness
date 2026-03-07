import * as fs from 'fs';
import { globSync } from 'glob';
import matter from 'gray-matter';
import * as path from 'path';

export interface SkillEntry {
  name: string;
  slug: string; // directory name (e.g. "api-patterns")
  description: string;
  triggers: string[]; // keyword trigger phrases from frontmatter
  category: string; // derived from slug prefix
  filePath: string; // absolute path to SKILL.md
  content: string; // full markdown content (loaded on demand)
}

/** Derive a human-readable category from the skill slug */
function deriveCategory(slug: string): string {
  if (slug.startsWith('ads-') || slug === 'ads') return 'Advertising';
  if (slug.startsWith('bmad-os-')) return 'OSS Tooling';
  if (slug.startsWith('eval-')) return 'Evaluation';
  if (slug.startsWith('loop-')) return 'Evaluate-Loop';
  if (
    [
      'frontend-design',
      'frontend-checklist',
      'tailwind-patterns',
      'web-design-guidelines',
      'web-artifacts-builder',
    ].includes(slug)
  )
    return 'Frontend';
  if (
    ['api-patterns', 'nodejs-best-practices', 'database-design', 'backend-patterns'].includes(slug)
  )
    return 'Backend';
  if (['vulnerability-scanner', 'red-team-tactics', 'insecure-defaults'].includes(slug))
    return 'Security';
  if (['mobile-design', 'mobile-audit'].includes(slug)) return 'Mobile';
  if (
    ['tdd-workflow', 'test-driven-development', 'testing-patterns', 'webapp-testing'].includes(slug)
  )
    return 'Testing';
  if (['deployment-procedures', 'server-management', 'deployment-patterns'].includes(slug))
    return 'DevOps';
  if (['pdf', 'pptx', 'docx', 'xlsx'].includes(slug)) return 'Documents';
  return 'Core';
}

/** Parse trigger keywords from frontmatter */
function parseTriggers(data: Record<string, unknown>): string[] {
  const raw = data['trigger'] ?? data['triggers'] ?? data['keywords'];
  if (!raw) return [];
  if (Array.isArray(raw)) return raw.map(String);
  if (typeof raw === 'string')
    return raw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
  return [];
}

export class SkillsLoader {
  private skillsDir: string;

  constructor(skillsDir: string) {
    this.skillsDir = skillsDir;
  }

  /** Load all skills from disk. Content is deferred until use_skill() is called. */
  load(): SkillEntry[] {
    const skillFiles = globSync('*/SKILL.md', {
      cwd: this.skillsDir,
      absolute: true,
    });

    const skills: SkillEntry[] = [];

    for (const filePath of skillFiles) {
      try {
        const raw = fs.readFileSync(filePath, 'utf-8');
        const { data, content } = matter(raw);

        const slug = path.basename(path.dirname(filePath));
        const name = String(data['name'] ?? slug);
        const description = String(data['description'] ?? '').trim();

        skills.push({
          name,
          slug,
          description,
          triggers: parseTriggers(data as Record<string, unknown>),
          category: deriveCategory(slug),
          filePath,
          content: content.trim(),
        });
      } catch {
        // Skip malformed files
      }
    }

    return skills.sort((a, b) => a.slug.localeCompare(b.slug));
  }

  /** Load full content for a specific skill */
  loadContent(slug: string): string | null {
    const filePath = path.join(this.skillsDir, slug, 'SKILL.md');
    if (!fs.existsSync(filePath)) return null;
    const raw = fs.readFileSync(filePath, 'utf-8');
    return raw; // return full raw content including frontmatter
  }
}
