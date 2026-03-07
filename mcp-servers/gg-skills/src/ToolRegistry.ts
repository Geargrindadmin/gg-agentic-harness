import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';
import * as vm from 'vm';

export type ToolRuntime = 'javascript' | 'shell';

export interface DynamicTool {
  name: string;
  description: string;
  runtime: ToolRuntime;
  implementation: string; // JS function body or shell script
  inputSchema: Record<string, unknown>;
  createdAt: string;
  createdBy?: string; // agent ID for traceability
}

export interface ToolResult {
  output: string;
  exitCode: number;
  durationMs: number;
}

/**
 * ToolRegistry — persistent store for AI-defined runtime tools.
 * Inspired by ai-meta-mcp-server (alxspiker/ai-meta-mcp-server).
 *
 * Agents call define_tool() to create a new tool.
 * Tools are persisted to TOOLS_DB_PATH (default: ./dynamic-tools.json).
 * call_tool() executes the stored implementation in a sandboxed context.
 */
export class ToolRegistry {
  private tools = new Map<string, DynamicTool>();
  private readonly dbPath: string;

  constructor(dbPath: string) {
    this.dbPath = dbPath;
    this._load();
  }

  // ── CRUD ────────────────────────────────────────────────────────────────

  define(tool: DynamicTool): void {
    this.tools.set(tool.name, tool);
    this._persist();
  }

  get(name: string): DynamicTool | undefined {
    return this.tools.get(name);
  }

  list(): DynamicTool[] {
    return [...this.tools.values()];
  }

  delete(name: string): boolean {
    if (!this.tools.has(name)) return false;
    this.tools.delete(name);
    this._persist();
    return true;
  }

  // ── Execution ────────────────────────────────────────────────────────────

  execute(name: string, args: Record<string, unknown>): ToolResult {
    const tool = this.tools.get(name);
    if (!tool) throw new Error(`Dynamic tool "${name}" not found`);

    const start = Date.now();

    if (tool.runtime === 'javascript') {
      return this._runJS(tool, args, start);
    } else if (tool.runtime === 'shell') {
      return this._runShell(tool, args, start);
    } else {
      throw new Error(`Unsupported runtime: ${tool.runtime}`);
    }
  }

  // ── Persistence ─────────────────────────────────────────────────────────

  private _persist(): void {
    const data = Object.fromEntries(this.tools.entries());
    fs.writeFileSync(this.dbPath, JSON.stringify(data, null, 2), 'utf8');
  }

  private _load(): void {
    if (!fs.existsSync(this.dbPath)) return;
    try {
      const raw = JSON.parse(fs.readFileSync(this.dbPath, 'utf8')) as Record<string, DynamicTool>;
      for (const [name, tool] of Object.entries(raw)) {
        this.tools.set(name, tool);
      }
      process.stderr.write(
        `[gg-skills] Loaded ${this.tools.size} dynamic tools from ${path.basename(this.dbPath)}\n`
      );
    } catch (err) {
      process.stderr.write(`[gg-skills] Warning: could not load dynamic tools: ${err}\n`);
    }
  }

  // ── Sandboxed JS execution ──────────────────────────────────────────────

  private _runJS(tool: DynamicTool, args: Record<string, unknown>, start: number): ToolResult {
    // Wrap implementation in an async function, inject args
    const code = `
(async function(args) {
    ${tool.implementation}
})(args)`;

    let output = '';
    const sandbox = {
      args,
      console: {
        log: (...a: unknown[]) => {
          output += a.map(String).join(' ') + '\n';
        },
        error: (...a: unknown[]) => {
          output += '[err] ' + a.map(String).join(' ') + '\n';
        },
      },
      JSON,
      Math,
      Date,
      // Explicitly block dangerous globals
      process: undefined,
      require: undefined,
      fetch: undefined,
    };

    try {
      const script = new vm.Script(code);
      const ctx = vm.createContext(sandbox);
      const result = script.runInContext(ctx, { timeout: 10_000 });
      if (result && typeof result === 'object' && 'then' in result) {
        // Sync-ish: for simple cases, resolve immediately or stringify
        output = output || JSON.stringify(result);
      } else if (result !== undefined) {
        output = output || String(result);
      }
      return {
        output: output.trim() || '(no output)',
        exitCode: 0,
        durationMs: Date.now() - start,
      };
    } catch (err) {
      return { output: String(err), exitCode: 1, durationMs: Date.now() - start };
    }
  }

  // ── Shell execution ─────────────────────────────────────────────────────

  private _runShell(tool: DynamicTool, args: Record<string, unknown>, start: number): ToolResult {
    if (process.env['ALLOW_SHELL_EXECUTION'] !== 'true') {
      return {
        output: 'Shell execution disabled. Set ALLOW_SHELL_EXECUTION=true to enable.',
        exitCode: 1,
        durationMs: 0,
      };
    }

    // Inject args as env vars: TOOL_ARG_MYKEY=value
    const env: Record<string, string> = { ...(process.env as Record<string, string>) };
    for (const [k, v] of Object.entries(args)) {
      env[`TOOL_ARG_${k.toUpperCase()}`] = String(v);
    }

    try {
      const result = execSync(tool.implementation, { env, timeout: 30_000, encoding: 'utf8' });
      return { output: result.trim(), exitCode: 0, durationMs: Date.now() - start };
    } catch (err: unknown) {
      const e = err as { message?: string; stderr?: Buffer };
      return {
        output: (e.stderr ? e.stderr.toString() : '') + (e.message ?? String(e)),
        exitCode: 1,
        durationMs: Date.now() - start,
      };
    }
  }
}
