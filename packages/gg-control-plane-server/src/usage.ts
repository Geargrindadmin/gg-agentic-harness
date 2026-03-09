import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { nowIso } from './store.js';

export interface UsageWindowSnapshot {
  id: string;
  label: string;
  usedPercent: number;
  resetAt: string | null;
  detail: string;
}

export interface UsageCreditSnapshot {
  label: string;
  balance: number;
  limit: number | null;
  unit: string;
}

export interface UsageProviderSnapshot {
  id: string;
  name: string;
  status: 'ok' | 'warning' | 'needs_login' | 'unavailable';
  plan: string | null;
  summary: string;
  source: string | null;
  windows: UsageWindowSnapshot[];
  credits: UsageCreditSnapshot | null;
  error: string | null;
  lastCheckedAt: string;
}

export interface UsageSnapshot {
  generatedAt: string;
  providers: UsageProviderSnapshot[];
}

function homePath(relativePath: string): string {
  return path.join(os.homedir(), relativePath.replace(/^~\//, ''));
}

function fileExists(filePath: string): boolean {
  return fs.existsSync(filePath);
}

function readJsonFile<T>(filePath: string): T | null {
  if (!fileExists(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T;
}

function decodePossibleHexJson(value: string): string | null {
  const trimmed = value.trim().replace(/^0x/i, '');
  if (!trimmed || trimmed.length % 2 !== 0 || !/^[0-9a-fA-F]+$/.test(trimmed)) {
    return null;
  }
  try {
    return Buffer.from(trimmed, 'hex').toString('utf8');
  } catch {
    return null;
  }
}

function readMacOSKeychain(service: string): unknown | null {
  if (process.platform !== 'darwin') {
    return null;
  }
  const result = spawnSync('security', ['find-generic-password', '-w', '-s', service], {
    encoding: 'utf8'
  });
  if (result.status !== 0) {
    return null;
  }
  const raw = result.stdout.trim();
  if (!raw) {
    return null;
  }
  try {
    return JSON.parse(raw);
  } catch {
    const decoded = decodePossibleHexJson(raw);
    if (!decoded) {
      return null;
    }
    try {
      return JSON.parse(decoded);
    } catch {
      return null;
    }
  }
}

async function fetchJson(url: string, headers: Record<string, string>): Promise<{ status: number; data: unknown }> {
  const response = await fetch(url, {
    headers
  });

  let data: unknown = null;
  const text = await response.text();
  if (text.trim()) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  return {
    status: response.status,
    data
  };
}

function providerUnavailable(id: string, name: string, summary: string): UsageProviderSnapshot {
  return {
    id,
    name,
    status: 'unavailable',
    plan: null,
    summary,
    source: null,
    windows: [],
    credits: null,
    error: null,
    lastCheckedAt: nowIso()
  };
}

function providerNeedsLogin(
  id: string,
  name: string,
  source: string | null,
  summary: string,
  error: string | null = null
): UsageProviderSnapshot {
  return {
    id,
    name,
    status: 'needs_login',
    plan: null,
    summary,
    source,
    windows: [],
    credits: null,
    error,
    lastCheckedAt: nowIso()
  };
}

function roundPercent(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value * 10) / 10));
}

function detailForPercent(label: string, percent: number): string {
  return `${roundPercent(percent)}% used`;
}

async function probeClaude(): Promise<UsageProviderSnapshot> {
  const filePath = homePath('~/.claude/.credentials.json');
  const raw =
    readJsonFile<{ claudeAiOauth?: { accessToken?: string; subscriptionType?: string } }>(filePath) ||
    (readMacOSKeychain('Claude Code-credentials') as { claudeAiOauth?: { accessToken?: string; subscriptionType?: string } } | null);

  const oauth = raw?.claudeAiOauth;
  const source = raw ? (fileExists(filePath) ? filePath : 'macOS Keychain') : null;
  if (!oauth?.accessToken) {
    return providerNeedsLogin('claude', 'Claude Code', source, 'Run Claude login to restore usage visibility.');
  }

  const result = await fetchJson('https://api.anthropic.com/api/oauth/usage', {
    Authorization: `Bearer ${oauth.accessToken}`,
    Accept: 'application/json',
    'Content-Type': 'application/json',
    'anthropic-beta': 'oauth-2025-04-20'
  });

  if (result.status === 401 || result.status === 403) {
    return providerNeedsLogin('claude', 'Claude Code', source, 'Claude credentials need reauthentication.', 'Authentication failed');
  }

  if (result.status < 200 || result.status >= 300 || typeof result.data !== 'object' || !result.data) {
    return {
      id: 'claude',
      name: 'Claude Code',
      status: 'warning',
      plan: oauth.subscriptionType || null,
      summary: 'Unable to read Claude usage right now.',
      source,
      windows: [],
      credits: null,
      error: typeof result.data === 'string' ? result.data : `HTTP ${result.status}`,
      lastCheckedAt: nowIso()
    };
  }

  const data = result.data as Record<string, any>;
  const windows: UsageWindowSnapshot[] = [];
  if (data.five_hour?.utilization !== undefined) {
    windows.push({
      id: 'session',
      label: '5h Session',
      usedPercent: roundPercent(Number(data.five_hour.utilization || 0)),
      resetAt: data.five_hour.resets_at || null,
      detail: detailForPercent('5h Session', Number(data.five_hour.utilization || 0))
    });
  }
  if (data.seven_day?.utilization !== undefined) {
    windows.push({
      id: 'weekly',
      label: '7d Weekly',
      usedPercent: roundPercent(Number(data.seven_day.utilization || 0)),
      resetAt: data.seven_day.resets_at || null,
      detail: detailForPercent('7d Weekly', Number(data.seven_day.utilization || 0))
    });
  }
  if (data.seven_day_opus?.utilization !== undefined) {
    windows.push({
      id: 'opus',
      label: '7d Opus',
      usedPercent: roundPercent(Number(data.seven_day_opus.utilization || 0)),
      resetAt: data.seven_day_opus.resets_at || null,
      detail: detailForPercent('7d Opus', Number(data.seven_day_opus.utilization || 0))
    });
  }

  const credits = data.extra_usage?.is_enabled
    ? {
        label: 'Extra Usage',
        balance: Number(data.extra_usage.used_credits || 0),
        limit:
          data.extra_usage.monthly_limit === 0 || data.extra_usage.monthly_limit === undefined
            ? null
            : Number(data.extra_usage.monthly_limit),
        unit: data.extra_usage.currency || 'USD cents'
      }
    : null;

  return {
    id: 'claude',
    name: 'Claude Code',
    status: 'ok',
    plan: oauth.subscriptionType || null,
    summary: windows.length ? windows.map((window) => `${window.label}: ${window.usedPercent}%`).join(' • ') : 'Usage available',
    source,
    windows,
    credits,
    error: null,
    lastCheckedAt: nowIso()
  };
}

async function probeKimi(): Promise<UsageProviderSnapshot> {
  const filePath = homePath('~/.kimi/credentials/kimi-code.json');
  const creds = readJsonFile<{ access_token?: string }>(filePath);
  if (!creds?.access_token) {
    return providerNeedsLogin('kimi', 'Kimi Code', filePath, 'Run kimi login to restore usage visibility.');
  }

  const result = await fetchJson('https://api.kimi.com/coding/v1/usages', {
    Authorization: `Bearer ${creds.access_token}`,
    Accept: 'application/json',
    'User-Agent': 'GG Agentic Harness'
  });

  if (result.status === 401 || result.status === 403) {
    return providerNeedsLogin('kimi', 'Kimi Code', filePath, 'Kimi credentials need reauthentication.', 'Authentication failed');
  }

  if (result.status < 200 || result.status >= 300 || typeof result.data !== 'object' || !result.data) {
    return {
      id: 'kimi',
      name: 'Kimi Code',
      status: 'warning',
      plan: null,
      summary: 'Unable to read Kimi usage right now.',
      source: filePath,
      windows: [],
      credits: null,
      error: typeof result.data === 'string' ? result.data : `HTTP ${result.status}`,
      lastCheckedAt: nowIso()
    };
  }

  const data = result.data as Record<string, any>;
  const windows: UsageWindowSnapshot[] = [];
  const overallLimit = Number(data.usage?.limit || 0);
  const overallRemaining = Number(data.usage?.remaining || 0);
  if (overallLimit > 0) {
    const usedPercent = roundPercent(((overallLimit - overallRemaining) / overallLimit) * 100);
    windows.push({
      id: 'overall',
      label: 'Overall',
      usedPercent,
      resetAt: data.usage?.resetTime || null,
      detail: `${Math.max(0, overallLimit - overallRemaining)}/${overallLimit} used`
    });
  }

  for (const limit of Array.isArray(data.limits) ? data.limits : []) {
    const rawLimit = Number(limit?.detail?.limit || 0);
    const rawRemaining = Number(limit?.detail?.remaining || 0);
    if (rawLimit <= 0) {
      continue;
    }
    const windowMinutes = Number(limit?.window?.duration || 0);
    const label = windowMinutes >= 60 ? `${Math.round(windowMinutes / 60)}h Window` : `${windowMinutes}m Window`;
    windows.push({
      id: `${windowMinutes}m`,
      label,
      usedPercent: roundPercent(((rawLimit - rawRemaining) / rawLimit) * 100),
      resetAt: limit?.detail?.resetTime || null,
      detail: `${Math.max(0, rawLimit - rawRemaining)}/${rawLimit} used`
    });
  }

  return {
    id: 'kimi',
    name: 'Kimi Code',
    status: 'ok',
    plan: String(data.user?.membership?.level || '').replace(/^LEVEL_/, '').replace(/_/g, ' ') || null,
    summary: windows.length ? windows.map((window) => `${window.label}: ${window.usedPercent}%`).join(' • ') : 'Usage available',
    source: filePath,
    windows,
    credits: null,
    error: null,
    lastCheckedAt: nowIso()
  };
}

async function probeCodex(): Promise<UsageProviderSnapshot> {
  const authPaths = [
    process.env.CODEX_HOME ? path.join(process.env.CODEX_HOME, 'auth.json') : null,
    homePath('~/.config/codex/auth.json'),
    homePath('~/.codex/auth.json')
  ].filter((entry): entry is string => Boolean(entry));

  let authSource: string | null = null;
  let auth:
    | {
        tokens?: {
          access_token?: string;
          account_id?: string;
        };
      }
    | null = null;

  for (const authPath of authPaths) {
    auth = readJsonFile(authPath);
    if (auth?.tokens?.access_token) {
      authSource = authPath;
      break;
    }
  }

  if (!auth?.tokens?.access_token) {
    const keychain = readMacOSKeychain('Codex Auth') as { tokens?: { access_token?: string; account_id?: string } } | null;
    if (keychain?.tokens?.access_token) {
      auth = keychain;
      authSource = 'macOS Keychain';
    }
  }

  if (!auth?.tokens?.access_token) {
    return providerNeedsLogin('codex', 'Codex', authPaths[0] || null, 'Run codex to restore usage visibility.');
  }

  const headers: Record<string, string> = {
    Authorization: `Bearer ${auth.tokens.access_token}`,
    Accept: 'application/json',
    'User-Agent': 'GG Agentic Harness'
  };
  if (auth.tokens.account_id) {
    headers['ChatGPT-Account-Id'] = auth.tokens.account_id;
  }

  const result = await fetchJson('https://chatgpt.com/backend-api/wham/usage', headers);
  if (result.status === 401 || result.status === 403) {
    return providerNeedsLogin('codex', 'Codex', authSource, 'Codex credentials need reauthentication.', 'Authentication failed');
  }

  if (result.status < 200 || result.status >= 300 || typeof result.data !== 'object' || !result.data) {
    return {
      id: 'codex',
      name: 'Codex',
      status: 'warning',
      plan: null,
      summary: 'Unable to read Codex usage right now.',
      source: authSource,
      windows: [],
      credits: null,
      error: typeof result.data === 'string' ? result.data : `HTTP ${result.status}`,
      lastCheckedAt: nowIso()
    };
  }

  const data = result.data as Record<string, any>;
  const windows: UsageWindowSnapshot[] = [];
  const primary = data.rate_limit?.primary_window;
  const secondary = data.rate_limit?.secondary_window;
  const review = data.code_review_rate_limit?.primary_window;
  if (primary?.used_percent !== undefined) {
    windows.push({
      id: 'session',
      label: '5h Session',
      usedPercent: roundPercent(Number(primary.used_percent || 0)),
      resetAt: primary.reset_at ? new Date(Number(primary.reset_at) * 1000).toISOString() : null,
      detail: detailForPercent('5h Session', Number(primary.used_percent || 0))
    });
  }
  if (secondary?.used_percent !== undefined) {
    windows.push({
      id: 'weekly',
      label: '7d Weekly',
      usedPercent: roundPercent(Number(secondary.used_percent || 0)),
      resetAt: secondary.reset_at ? new Date(Number(secondary.reset_at) * 1000).toISOString() : null,
      detail: detailForPercent('7d Weekly', Number(secondary.used_percent || 0))
    });
  }
  if (review?.used_percent !== undefined) {
    windows.push({
      id: 'reviews',
      label: 'Code Reviews',
      usedPercent: roundPercent(Number(review.used_percent || 0)),
      resetAt: review.reset_at ? new Date(Number(review.reset_at) * 1000).toISOString() : null,
      detail: detailForPercent('Code Reviews', Number(review.used_percent || 0))
    });
  }

  const credits = data.credits?.has_credits
    ? {
        label: 'Credits',
        balance: Number(data.credits.balance || 0),
        limit: null,
        unit: 'USD'
      }
    : null;

  return {
    id: 'codex',
    name: 'Codex',
    status: 'ok',
    plan: data.plan_type || null,
    summary: windows.length ? windows.map((window) => `${window.label}: ${window.usedPercent}%`).join(' • ') : 'Usage available',
    source: authSource,
    windows,
    credits,
    error: null,
    lastCheckedAt: nowIso()
  };
}

export async function collectUsageSnapshot(): Promise<UsageSnapshot> {
  const providers = await Promise.all([probeClaude(), probeCodex(), probeKimi()]);
  return {
    generatedAt: nowIso(),
    providers
  };
}
