import * as fs from 'fs';
import { globSync } from 'glob';
import matter from 'gray-matter';
import * as path from 'path';

export interface WorkflowEntry {
  name: string;
  slug: string; // filename without extension
  description: string;
  filePath: string;
}

export class WorkflowLoader {
  private workflowsDir: string;

  constructor(workflowsDir: string) {
    this.workflowsDir = workflowsDir;
  }

  load(): WorkflowEntry[] {
    const workflowFiles = globSync('*.md', {
      cwd: this.workflowsDir,
      absolute: true,
    });

    const workflows: WorkflowEntry[] = [];

    for (const filePath of workflowFiles) {
      try {
        const raw = fs.readFileSync(filePath, 'utf-8');
        const { data } = matter(raw);

        const slug = path.basename(filePath, '.md');
        const description = String(data['description'] ?? '').trim();

        workflows.push({
          name: slug,
          slug,
          description,
          filePath,
        });
      } catch {
        // Skip malformed files
      }
    }

    return workflows.sort((a, b) => a.slug.localeCompare(b.slug));
  }

  loadContent(slug: string): string | null {
    const filePath = path.join(this.workflowsDir, `${slug}.md`);
    if (!fs.existsSync(filePath)) return null;
    return fs.readFileSync(filePath, 'utf-8');
  }
}
