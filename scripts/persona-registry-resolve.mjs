#!/usr/bin/env node
import { resolvePrompt } from './persona-registry-lib.mjs';

function parseArgs(argv) {
  const args = { json: false, classification: 'TASK', prompt: '' };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--json') args.json = true;
    else if (arg === '--classification') args.classification = argv[++i] ?? args.classification;
    else if (arg === '--prompt') args.prompt = argv[++i] ?? '';
    else if (!arg.startsWith('--')) args.prompt = [args.prompt, arg].filter(Boolean).join(' ');
  }
  return args;
}

function printText(result) {
  console.log(`Prompt: ${result.prompt}`);
  console.log(`Classification: ${result.classification}`);
  console.log(`Dispatch Plan: ${result.dispatchPlan}`);
  console.log(`Confidence: ${result.confidence}`);
  console.log(`Board Required: ${result.boardRequired ? 'yes' : 'no'}`);
  if (result.highRiskTerms.length) {
    console.log(`High-Risk Terms: ${result.highRiskTerms.join(', ')}`);
  }
  console.log('');
  console.log(`Primary Persona: ${result.primaryPersona.id} (${result.primaryPersona.role})`);
  if (result.primaryPersona.reasons.length) {
    console.log(`  Reasons: ${result.primaryPersona.reasons.join(', ')}`);
  }
  if (result.compoundPersona) {
    console.log('');
    console.log(`Compound Persona: ${result.compoundPersona.id} (${result.compoundPersona.source})`);
    console.log(`  Compound Plan: ${result.compoundPersona.dispatchPlan}`);
    console.log(`  Members: ${result.compoundPersona.memberPersonaIds.join(', ')}`);
    console.log(`  Summary: ${result.compoundPersona.summary}`);
  }
  if (result.collaboratorPersonas.length) {
    console.log('Collaborators:');
    for (const persona of result.collaboratorPersonas) {
      console.log(`- ${persona.id} (${persona.role})`);
    }
  }
  if (result.notes.length) {
    console.log('');
    console.log('Notes:');
    for (const note of result.notes) console.log(`- ${note}`);
  }
}

const args = parseArgs(process.argv.slice(2));
if (!args.prompt.trim()) {
  console.error('Usage: node scripts/persona-registry-resolve.mjs --prompt "<task>" [--classification TASK|TASK_LITE|DECISION|CRITICAL|SIMPLE] [--json]');
  process.exit(1);
}

const result = resolvePrompt(args.prompt, { classification: args.classification });
if (args.json) console.log(JSON.stringify(result, null, 2));
else printText(result);
