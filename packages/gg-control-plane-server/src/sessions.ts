import fs from 'node:fs';
import path from 'node:path';
import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import * as pty from 'node-pty';

export interface BackgroundSessionLaunchPlan {
  runId: string;
  agentId: string;
  executionId: string;
  binary: string;
  args: string[];
  cwd: string;
  env: NodeJS.ProcessEnv;
  requestFile: string;
  responseFile: string;
  transcriptFile: string;
  summary: string;
}

export interface StructuredHarnessMessage {
  to?: string;
  type?: string;
  body?: string;
  payload?: Record<string, unknown>;
  requiresAck?: boolean;
}

export interface StructuredHarnessState {
  status?: string;
  summary?: string;
  reason?: string;
  payload?: Record<string, unknown>;
}

export interface SessionExitEvent {
  exitCode: number;
  signal?: number;
  rawOutput: string;
  cleanedOutput: string;
  lastMeaningfulLine: string;
}

interface WorkerSessionCallbacks {
  onChunk?: (chunk: string) => void;
  onLine?: (line: string) => void;
  onMessage?: (message: StructuredHarnessMessage) => void;
  onState?: (state: StructuredHarnessState) => void;
  onExit?: (event: SessionExitEvent) => void;
}

interface WorkerSessionRecord {
  process: pty.IPty | ChildProcessWithoutNullStreams;
  transport: 'python-pty' | 'node-pty';
  runId: string;
  agentId: string;
  lineBuffer: string;
  rawOutput: string;
  cleanedOutput: string;
  lastMeaningfulLine: string;
  callbacks: WorkerSessionCallbacks;
  plan: BackgroundSessionLaunchPlan;
}

function routeKey(runId: string, agentId: string): string {
  return `${runId}:${agentId}`;
}

function stripAnsi(value: string): string {
  return value
    .replace(/\u001B\][^\u0007]*(?:\u0007|\u001B\\)/g, '')
    .replace(/\u001B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])/g, '');
}

function extractMarkerJson(line: string, marker: '@@GG_MSG' | '@@GG_STATE'): string | null {
  const index = line.indexOf(marker);
  if (index === -1) {
    return null;
  }
  const json = line.slice(index + marker.length).trim();
  return json.startsWith('{') ? json : null;
}

const PYTHON_PTY_BRIDGE = `
import json
import os
import pty
import select
import signal
import fcntl
import struct
import sys
import termios

binary = sys.argv[1]
args = json.loads(sys.argv[2])
cwd = sys.argv[3]

master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 240, 0, 0))
pid = os.fork()

if pid == 0:
    os.setsid()
    os.dup2(slave, 0)
    os.dup2(slave, 1)
    os.dup2(slave, 2)
    try:
        os.close(master)
    except OSError:
        pass
    try:
        os.close(slave)
    except OSError:
        pass
    os.chdir(cwd)
    os.execvpe(binary, [binary] + args, os.environ)

os.close(slave)

def handle_term(signum, frame):
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass

signal.signal(signal.SIGTERM, handle_term)

while True:
    readers = [master, sys.stdin.fileno()]
    ready, _, _ = select.select(readers, [], [], 0.1)
    if master in ready:
        try:
            data = os.read(master, 4096)
        except OSError:
            data = b''
        if not data:
            break
        os.write(sys.stdout.fileno(), data)
    if sys.stdin.fileno() in ready:
        data = os.read(sys.stdin.fileno(), 4096)
        if data:
            os.write(master, data)

_, status = os.waitpid(pid, 0)
if os.WIFEXITED(status):
    sys.exit(os.WEXITSTATUS(status))
if os.WIFSIGNALED(status):
    sys.exit(128 + os.WTERMSIG(status))
sys.exit(1)
`.trim();

export class WorkerSessionManager {
  private readonly sessions = new Map<string, WorkerSessionRecord>();

  count(): number {
    return this.sessions.size;
  }

  has(runId: string, agentId: string): boolean {
    return this.sessions.has(routeKey(runId, agentId));
  }

  start(plan: BackgroundSessionLaunchPlan, callbacks: WorkerSessionCallbacks): void {
    const key = routeKey(plan.runId, plan.agentId);
    if (this.sessions.has(key)) {
      return;
    }

    const transport = process.platform === 'win32' ? 'node-pty' : 'python-pty';
    const child =
      transport === 'python-pty'
        ? spawn('python3', ['-u', '-c', PYTHON_PTY_BRIDGE, plan.binary, JSON.stringify(plan.args), plan.cwd], {
            cwd: plan.cwd,
            env: plan.env,
            stdio: ['pipe', 'pipe', 'pipe']
          })
        : pty.spawn(plan.binary, plan.args, {
            name: 'xterm-color',
            cols: 140,
            rows: 36,
            cwd: plan.cwd,
            env: plan.env
          });

    const record: WorkerSessionRecord = {
      process: child,
      transport,
      runId: plan.runId,
      agentId: plan.agentId,
      lineBuffer: '',
      rawOutput: '',
      cleanedOutput: '',
      lastMeaningfulLine: '',
      callbacks,
      plan
    };

    if (transport === 'python-pty') {
      const scriptChild = child as ChildProcessWithoutNullStreams;
      scriptChild.stdout.on('data', (chunk) => {
        this.handleChunk(record, chunk.toString());
      });
      scriptChild.stderr.on('data', (chunk) => {
        this.handleChunk(record, chunk.toString());
      });
      scriptChild.on('close', (exitCode, signal) => {
        this.flushPartialLine(record);
        this.writeArtifacts(record, exitCode ?? -1, signal ? 0 : undefined);
        this.sessions.delete(key);
        callbacks.onExit?.({
          exitCode: exitCode ?? -1,
          signal: signal ? 0 : undefined,
          rawOutput: record.rawOutput,
          cleanedOutput: record.cleanedOutput,
          lastMeaningfulLine: record.lastMeaningfulLine
        });
      });
    } else {
      const ptyChild = child as pty.IPty;
      ptyChild.onData((chunk) => {
        this.handleChunk(record, chunk);
      });

      ptyChild.onExit(({ exitCode, signal }) => {
        this.flushPartialLine(record);
        this.writeArtifacts(record, exitCode, signal);
        this.sessions.delete(key);
        callbacks.onExit?.({
          exitCode,
          signal,
          rawOutput: record.rawOutput,
          cleanedOutput: record.cleanedOutput,
          lastMeaningfulLine: record.lastMeaningfulLine
        });
      });
    }

    this.sessions.set(key, record);
  }

  send(runId: string, agentId: string, text: string): boolean {
    const record = this.sessions.get(routeKey(runId, agentId));
    if (!record) {
      return false;
    }

    const normalized = text.endsWith('\n') ? text : `${text}\n`;
    if (record.transport === 'python-pty') {
      (record.process as ChildProcessWithoutNullStreams).stdin.write(normalized, 'utf8');
    } else {
      (record.process as pty.IPty).write(normalized.replace(/\n/g, '\r'));
    }
    return true;
  }

  terminate(runId: string, agentId: string): boolean {
    const key = routeKey(runId, agentId);
    const record = this.sessions.get(key);
    if (!record) {
      return false;
    }
    if (record.transport === 'python-pty') {
      (record.process as ChildProcessWithoutNullStreams).kill('SIGTERM');
    } else {
      (record.process as pty.IPty).kill();
    }
    this.sessions.delete(key);
    return true;
  }

  private handleChunk(record: WorkerSessionRecord, chunk: string): void {
    record.rawOutput += chunk;
    record.callbacks.onChunk?.(chunk);

    const cleanedChunk = stripAnsi(chunk).replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    record.cleanedOutput += cleanedChunk;
    record.lineBuffer += cleanedChunk;

    const lines = record.lineBuffer.split('\n');
    record.lineBuffer = lines.pop() || '';
    for (const line of lines) {
      this.handleLine(record, line.trim());
    }
  }

  private flushPartialLine(record: WorkerSessionRecord): void {
    const leftover = record.lineBuffer.trim();
    if (!leftover) {
      return;
    }
    this.handleLine(record, leftover);
    record.lineBuffer = '';
  }

  private handleLine(record: WorkerSessionRecord, line: string): void {
    if (!line) {
      return;
    }

    const messageJson = extractMarkerJson(line, '@@GG_MSG');
    if (messageJson) {
      try {
        record.callbacks.onMessage?.(JSON.parse(messageJson) as StructuredHarnessMessage);
        return;
      } catch {
        // Fall through and treat malformed markers as plain output.
      }
    }

    const stateJson = extractMarkerJson(line, '@@GG_STATE');
    if (stateJson) {
      try {
        record.callbacks.onState?.(JSON.parse(stateJson) as StructuredHarnessState);
        return;
      } catch {
        // Fall through and treat malformed markers as plain output.
      }
    }

    record.lastMeaningfulLine = line;
    record.callbacks.onLine?.(line);
  }

  private writeArtifacts(record: WorkerSessionRecord, exitCode: number, signal?: number): void {
    fs.mkdirSync(path.dirname(record.plan.responseFile), { recursive: true });
    fs.mkdirSync(path.dirname(record.plan.transcriptFile), { recursive: true });
    fs.writeFileSync(
      record.plan.responseFile,
      `${JSON.stringify(
        {
          executionId: record.plan.executionId,
          status: exitCode,
          signal: signal ?? null,
          output: record.cleanedOutput.trim(),
          lastMeaningfulLine: record.lastMeaningfulLine
        },
        null,
        2
      )}\n`,
      'utf8'
    );

    const transcript = [
      `# Live Worker Transcript — ${record.plan.agentId}`,
      '',
      `- Run ID: ${record.plan.runId}`,
      `- Execution ID: ${record.plan.executionId}`,
      `- Command: ${record.plan.binary} ${record.plan.args.join(' ')}`,
      '',
      '## Output',
      '',
      record.cleanedOutput.trim() || '_No output captured._',
      ''
    ].join('\n');
    fs.writeFileSync(record.plan.transcriptFile, transcript, 'utf8');
  }
}
