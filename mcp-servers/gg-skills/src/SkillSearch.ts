import Fuse from 'fuse.js';

import type { SkillEntry } from './SkillsLoader.js';
import type { WorkflowEntry } from './WorkflowLoader.js';

export class SkillSearch {
  private skillsFuse: Fuse<SkillEntry>;
  private workflowFuse: Fuse<WorkflowEntry>;

  constructor(skills: SkillEntry[], workflows: WorkflowEntry[]) {
    this.skillsFuse = new Fuse(skills, {
      keys: [
        { name: 'name', weight: 0.4 },
        { name: 'slug', weight: 0.3 },
        { name: 'description', weight: 0.2 },
        { name: 'triggers', weight: 0.1 },
      ],
      threshold: 0.4, // 0 = exact, 1 = wildcard
      includeScore: true,
      minMatchCharLength: 2,
    });

    this.workflowFuse = new Fuse(workflows, {
      keys: [
        { name: 'name', weight: 0.5 },
        { name: 'description', weight: 0.5 },
      ],
      threshold: 0.4,
      includeScore: true,
    });
  }

  findSkills(query: string, limit = 5): SkillEntry[] {
    const results = this.skillsFuse.search(query, { limit });
    return results.map((r) => r.item);
  }

  findWorkflows(query: string, limit = 5): WorkflowEntry[] {
    const results = this.workflowFuse.search(query, { limit });
    return results.map((r) => r.item);
  }
}
