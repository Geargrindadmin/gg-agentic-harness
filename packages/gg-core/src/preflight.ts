import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

export interface HarnessJsonScriptResult {
  code: number;
  payload: Record<string, unknown> | null;
  stdout: string;
  stderr: string;
  parseError?: string;
}

export interface HarnessActivationCheck {
  id: string;
  ok: boolean;
  detail: string;
}

export interface HarnessParityCheck {
  id: string;
  status: 'pass' | 'warn' | 'fail';
  summary: string;
  detail: string;
}

export interface HarnessExecutionPreflight {
  activation: {
    active: boolean;
    activationType: string | null;
    checks: HarnessActivationCheck[];
    parseError?: string;
  };
  parity: {
    ok: boolean;
    strict: boolean;
    checks: HarnessParityCheck[];
    parseError?: string;
  };
  context: {
    status: 'current' | 'stale' | 'missing';
    detail: string;
  };
  isRunnable: boolean;
  blockingIssues: string[];
}

export function runHarnessJsonScript(
  projectRoot: string,
  scriptRelativePath: string,
  args: string[]
): HarnessJsonScriptResult {
  const scriptPath = path.join(projectRoot, scriptRelativePath);
  if (!fs.existsSync(scriptPath)) {
    return {
      code: 1,
      payload: null,
      stdout: '',
      stderr: '',
      parseError: `Missing script: ${scriptRelativePath}`
    };
  }

  const result = spawnSync('node', [scriptPath, ...args], {
    cwd: projectRoot,
    encoding: 'utf8'
  });
  const stdout = result.stdout || '';
  const stderr = result.stderr || '';
  const trimmed = stdout.trim();

  if (!trimmed) {
    return {
      code: result.status ?? 1,
      payload: null,
      stdout,
      stderr,
      parseError: 'Script did not emit JSON on stdout'
    };
  }

  try {
    return {
      code: result.status ?? 0,
      payload: JSON.parse(trimmed) as Record<string, unknown>,
      stdout,
      stderr
    };
  } catch (error) {
    return {
      code: result.status ?? 1,
      payload: null,
      stdout,
      stderr,
      parseError: error instanceof Error ? error.message : 'Invalid JSON payload'
    };
  }
}

export function getHarnessExecutionPreflight(
  projectRoot: string,
  runtime = 'codex'
): HarnessExecutionPreflight {
  const activationResult = runHarnessJsonScript(projectRoot, path.join('scripts', 'runtime-project-sync.mjs'), [
    'status',
    '--runtime',
    runtime,
    '--json'
  ]);
  const activationPayload = activationResult.payload;
  const activationChecksRaw = Array.isArray(activationPayload?.checks)
    ? (activationPayload.checks as Array<Record<string, unknown>>)
    : [];
  const activationChecks: HarnessActivationCheck[] = activationChecksRaw.map((check) => ({
    id: String(check.id || 'runtime-activation-check'),
    ok: Boolean(check.ok),
    detail: String(check.detail || '')
  }));

  const parityResult = runHarnessJsonScript(projectRoot, path.join('scripts', 'runtime-parity-smoke.mjs'), ['--json']);
  const parityPayload = parityResult.payload;
  const parityChecksRaw = Array.isArray(parityPayload?.results)
    ? (parityPayload.results as Array<Record<string, unknown>>)
    : [];
  const parityChecks: HarnessParityCheck[] = parityChecksRaw.map((check) => ({
    id: String(check.id || 'runtime-parity-check'),
    status: check.status === 'pass' ? 'pass' : check.status === 'warn' ? 'warn' : 'fail',
    summary: String(check.summary || check.id || 'runtime parity check'),
    detail: String(check.detail || '')
  }));

  const contextScriptPath = path.join(projectRoot, 'scripts', 'generate-project-context.mjs');
  const contextResult = fs.existsSync(contextScriptPath)
    ? spawnSync('node', [contextScriptPath, '--check'], {
      cwd: projectRoot,
      encoding: 'utf8'
    })
    : null;
  const contextStatus: HarnessExecutionPreflight['context']['status'] = !fs.existsSync(contextScriptPath)
    ? 'missing'
    : (contextResult?.status ?? 1) === 0
      ? 'current'
      : 'stale';
  const contextDetail = contextStatus === 'missing'
    ? contextScriptPath
    : ((contextResult?.stdout || contextResult?.stderr || '').trim() || 'Project context check produced no output');

  const blockingIssues = [
    !Boolean(activationPayload?.active)
      ? 'Runtime activation is not active for this repo.'
      : '',
    activationResult.parseError
      ? `Runtime activation status could not be parsed: ${activationResult.parseError}`
      : '',
    !Boolean(parityPayload?.ok)
      ? 'Runtime parity check is failing for this repo.'
      : '',
    parityResult.parseError
      ? `Runtime parity status could not be parsed: ${parityResult.parseError}`
      : '',
    contextStatus === 'stale'
      ? 'Project context is stale.'
      : '',
    contextStatus === 'missing'
      ? 'Project context generator is missing.'
      : ''
  ].filter(Boolean);

  return {
    activation: {
      active: Boolean(activationPayload?.active),
      activationType: typeof activationPayload?.activationType === 'string' ? activationPayload.activationType : null,
      checks: activationChecks,
      parseError: activationResult.parseError
    },
    parity: {
      ok: Boolean(parityPayload?.ok),
      strict: Boolean(parityPayload?.strict),
      checks: parityChecks,
      parseError: parityResult.parseError
    },
    context: {
      status: contextStatus,
      detail: contextDetail
    },
    isRunnable: blockingIssues.length === 0,
    blockingIssues
  };
}
