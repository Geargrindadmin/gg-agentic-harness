import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(__dirname, '..');
const core = await import(path.join(packageRoot, 'dist', 'index.js'));

function makeFixture() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-core-test-'));
  fs.mkdirSync(path.join(root, '.agent', 'skills', 'alpha-skill'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'skills', 'beta-skill'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'workflows'), { recursive: true });
  fs.mkdirSync(path.join(root, '.agent', 'runs'), { recursive: true });
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ name: 'fixture', private: true }, null, 2));
  fs.writeFileSync(path.join(root, '.mcp.json'), JSON.stringify({ mcpServers: {} }, null, 2));
  fs.writeFileSync(
    path.join(root, '.agent', 'skills', 'alpha-skill', 'SKILL.md'),
    [
      '---',
      'name: "Alpha Skill"',
      'description: "Handles alpha feature work"',
      '---',
      '',
      '# Alpha'
    ].join('\n'),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'skills', 'beta-skill', 'SKILL.md'),
    [
      '---',
      'description: "Verification and testing support"',
      '---',
      '',
      '# Beta'
    ].join('\n'),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'workflows', 'go.md'),
    [
      '---',
      'name: "Go Workflow"',
      'description: "Ship a task with staged validation"',
      '---',
      '',
      '# Go'
    ].join('\n'),
    'utf8'
  );
  fs.writeFileSync(
    path.join(root, '.agent', 'workflows', 'review.md'),
    [
      '# Review'
    ].join('\n'),
    'utf8'
  );
  fs.writeFileSync(path.join(root, 'valid.json'), JSON.stringify({ ok: true, nested: { count: 2 } }, null, 2), 'utf8');
  fs.writeFileSync(path.join(root, 'invalid.json'), '{not-json', 'utf8');
  return root;
}

function cleanupFixture(root) {
  fs.rmSync(root, { recursive: true, force: true });
}

function withFixture(fn) {
  const root = makeFixture();
  try {
    return fn(root);
  } finally {
    cleanupFixture(root);
  }
}

test('resolveProjectRoot and getHarnessPaths find the enclosing harness repo from nested paths', () => {
  withFixture((root) => {
    const nested = path.join(root, 'src', 'feature', 'nested');
    fs.mkdirSync(nested, { recursive: true });

    const resolved = core.resolveProjectRoot(nested);
    assert.equal(resolved, root);

    const paths = core.getHarnessPaths(root);
    assert.equal(paths.projectRoot, root);
    assert.equal(paths.agentDir, path.join(root, '.agent'));
    assert.equal(paths.skillsDir, path.join(root, '.agent', 'skills'));
    assert.equal(paths.workflowsDir, path.join(root, '.agent', 'workflows'));
    assert.equal(paths.mcpConfigPath, path.join(root, '.mcp.json'));
    assert.equal(paths.runArtifactDir, path.join(root, '.agent', 'runs'));
  });
});

test('loadSkills and loadWorkflows parse catalog frontmatter and file metadata', () => {
  withFixture((root) => {
    const skills = core.loadSkills(root);
    assert.equal(skills.length, 2);
    assert.equal(skills[0].slug, 'alpha-skill');
    assert.equal(skills[0].name, 'Alpha Skill');
    assert.equal(skills[0].description, 'Handles alpha feature work');
    assert.equal(skills[1].slug, 'beta-skill');
    assert.equal(skills[1].name, 'beta-skill');
    assert.match(skills[1].description, /Verification/);

    const workflows = core.loadWorkflows(root);
    assert.equal(workflows.length, 2);
    assert.equal(workflows[0].slug, 'go');
    assert.equal(workflows[0].name, 'Go Workflow');
    assert.equal(workflows[0].description, 'Ship a task with staged validation');
    assert.equal(workflows[1].slug, 'review');
    assert.equal(workflows[1].name, 'review');
  });
});

test('searchCatalog ranks exact and token matches ahead of weaker results', () => {
  withFixture((root) => {
    const entries = [...core.loadSkills(root), ...core.loadWorkflows(root)];
    const exact = core.searchCatalog(entries, 'alpha-skill', 5);
    assert.equal(exact[0].slug, 'alpha-skill');

    const token = core.searchCatalog(entries, 'verification testing', 5);
    assert.equal(token[0].slug, 'beta-skill');

    const fallback = core.searchCatalog(entries, '', 2);
    assert.equal(fallback.length, 2);
  });
});

test('readCatalogEntryContent and readJsonFile handle valid and invalid inputs safely', () => {
  withFixture((root) => {
    const [entry] = core.loadSkills(root);
    const content = core.readCatalogEntryContent(entry);
    assert.match(content, /Alpha Skill/);

    const valid = core.readJsonFile(path.join(root, 'valid.json'));
    assert.deepEqual(valid, { ok: true, nested: { count: 2 } });

    const invalid = core.readJsonFile(path.join(root, 'invalid.json'));
    assert.equal(invalid, null);

    const missing = core.readJsonFile(path.join(root, 'missing.json'));
    assert.equal(missing, null);
  });
});
