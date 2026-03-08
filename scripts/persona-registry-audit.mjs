#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { loadCompoundRegistry, loadRegistry, REPO_ROOT } from './persona-registry-lib.mjs';

const registry = loadRegistry();
const compoundRegistry = loadCompoundRegistry(undefined, registry);
const errors = [];
const warnings = [];
const validRoles = new Set(['scout', 'planner', 'builder', 'reviewer', 'coordinator']);
const agentDir = path.join(REPO_ROOT, '.agent', 'agents');
const agentFiles = fs.readdirSync(agentDir).filter((file) => file.endsWith('.md')).sort();
const registryIds = new Set(registry.personas.map((persona) => persona.id));

for (const file of agentFiles) {
  const id = file.replace(/\.md$/, '');
  if (!registryIds.has(id)) errors.push(`Agent file missing from registry: ${file}`);
}

for (const persona of registry.personas) {
  if (!validRoles.has(persona.role)) errors.push(`Invalid role for ${persona.id}: ${persona.role}`);
  const file = path.join(REPO_ROOT, persona.file);
  if (!fs.existsSync(file)) {
    errors.push(`Registry file missing on disk: ${persona.file}`);
    continue;
  }
  const text = fs.readFileSync(file, 'utf8');
  if (!text.includes('## Agent Constraints')) errors.push(`${persona.file} missing Agent Constraints section.`);
  if (!text.includes(`- Role: ${persona.role}`)) errors.push(`${persona.file} role declaration drift for ${persona.id}.`);
  if (!text.includes('## Persona Dispatch Signals')) errors.push(`${persona.file} missing Persona Dispatch Signals section.`);
  if (!text.includes(persona.memoryQuery)) errors.push(`${persona.file} missing memory query for ${persona.id}.`);
  if (!text.includes('<!-- persona-registry:start -->') || !text.includes('<!-- persona-registry:end -->')) {
    warnings.push(`${persona.file} is missing persona-registry markers; sync recommended.`);
  }
}

if (warnings.length) {
  console.log('Warnings:');
  for (const warning of warnings) console.log(`- ${warning}`);
}

if (errors.length) {
  console.error('Persona registry audit failed:');
  for (const error of errors) console.error(`- ${error}`);
  process.exit(1);
}

console.log(
  `Persona registry audit passed (${registry.personas.length} personas, ${compoundRegistry.compounds.length} compounds).`
);
