#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const skillsDir = '.agent/skills';
const catalogPath = 'mcp-servers/gg-skills/skills-catalog.json';

function readJson(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8'));
}

function listRootSkillDirs() {
  return fs
    .readdirSync(skillsDir, { withFileTypes: true })
    .filter(d => d.isDirectory() && !d.name.startsWith('_'))
    .map(d => d.name)
    .sort();
}

function hasRootSkill(slug) {
  return fs.existsSync(path.join(skillsDir, slug, 'SKILL.md'));
}

function isKebabCase(slug) {
  return /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug);
}

const rootDirs = listRootSkillDirs();
const discoverable = rootDirs.filter(hasRootSkill);
const nonDiscoverable = rootDirs.filter(s => !hasRootSkill(s));

const catalog = readJson(catalogPath);
const registered = new Set((catalog.skills || []).map(s => s.slug));
const discoverableSet = new Set(discoverable);

const missingInRegistry = discoverable.filter(s => !registered.has(s));
const missingOnDisk = [...registered].filter(s => !discoverableSet.has(s)).sort();
const nonKebab = discoverable.filter(s => !isKebabCase(s));

const enterpriseSeeds = [
  'api-patterns',
  'database-design',
  'deployment-procedures',
  'nodejs-best-practices',
  'vulnerability-scanner',
  'red-team-tactics',
  'tdd-workflow',
  'systematic-debugging',
  'verification-before-completion',
  'conductor-orchestrator',
  'message-bus'
];
const enterprisePresent = enterpriseSeeds.filter(s => registered.has(s));

const result = {
  rootDirectories: rootDirs.length,
  discoverableSkills: discoverable.length,
  registeredSkills: registered.size,
  nonDiscoverableContainers: nonDiscoverable,
  missingInRegistry,
  missingOnDisk,
  nonKebab,
  enterprisePresentCount: enterprisePresent.length,
  hasSkillCreator: registered.has('skill-creator')
};

console.log(JSON.stringify(result, null, 2));

if (missingInRegistry.length || missingOnDisk.length || nonKebab.length) {
  process.exit(1);
}
