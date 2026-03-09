import os from 'node:os';

export interface GovernorSnapshot {
  timestamp: string;
  totalRamGb: number;
  freeRamGb: number;
  availableRamGb: number;
  reservedRamGb: number;
  modelVramGb: number;
  perAgentOverheadGb: number;
  cpuPressure: number;
  cpuPaused: boolean;
  allowedAgents: number;
  activeWorkers: number;
  queuedWorkers: number;
  canSpawnNow: boolean;
  note: string;
  reason: string;
}

interface CpuTimes {
  idle: number;
  total: number;
}

function roundGb(value: number): number {
  return Math.round(value * 10) / 10;
}

function nowIso(): string {
  return new Date().toISOString();
}

function envNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }
  const value = Number(raw);
  return Number.isFinite(value) ? value : fallback;
}

export class HarnessResourceGovernor {
  private readonly cpuHighPct: number;
  private readonly cpuLowPct: number;
  private readonly modelVramGb: number;
  private readonly perAgentOverheadGb: number;
  private readonly reservedRamGbOverride: number | null;
  private cpuPaused = false;
  private previousCpuTimes: CpuTimes[] = [];

  constructor() {
    this.cpuHighPct = envNumber('HARNESS_CPU_HIGH_PCT', 85);
    this.cpuLowPct = envNumber('HARNESS_CPU_LOW_PCT', 70);
    this.modelVramGb = envNumber('HARNESS_MODEL_VRAM_GB', 0);
    this.perAgentOverheadGb = envNumber('HARNESS_PER_AGENT_OVERHEAD_GB', 0.5);
    this.reservedRamGbOverride = process.env.HARNESS_RESERVED_RAM_GB ? envNumber('HARNESS_RESERVED_RAM_GB', 0) : null;
  }

  snapshot(activeWorkers: number, queuedWorkers: number): GovernorSnapshot {
    const totalRamGb = roundGb(os.totalmem() / 1024 / 1024 / 1024);
    const freeRamGb = roundGb(os.freemem() / 1024 / 1024 / 1024);
    const availableRamGb = freeRamGb;
    const reservedRamGb = roundGb(
      this.reservedRamGbOverride ?? Math.max(2, totalRamGb * 0.2)
    );
    const afterModelGb = Math.max(0, availableRamGb - this.modelVramGb);
    const usableGb = Math.max(0, afterModelGb - reservedRamGb);
    const perAgentGb = Math.max(0.1, this.perAgentOverheadGb);
    const rawAgents = Math.floor(usableGb / perAgentGb);
    const allowedAgents = Math.max(0, Math.min(64, rawAgents));
    const cpuPressure = this.cpuUsage();

    if (!this.cpuPaused && cpuPressure > this.cpuHighPct) {
      this.cpuPaused = true;
    } else if (this.cpuPaused && cpuPressure < this.cpuLowPct) {
      this.cpuPaused = false;
    }

    const note =
      allowedAgents === 0
        ? 'Insufficient free memory — spawning is paused until resources recover'
        : allowedAgents >= 30
        ? 'High capacity — system can run large swarms'
        : allowedAgents >= 10
          ? 'Medium capacity — standard swarms supported'
          : 'Low capacity — limit spawning, close other apps';

    const reason = this.cpuPaused
      ? `CPU pressure ${cpuPressure.toFixed(1)}% is above the high-water mark ${this.cpuHighPct}%`
      : `usable ${roundGb(usableGb)} GB / ${perAgentGb.toFixed(1)} GB per agent => ${allowedAgents} workers`;

    return {
      timestamp: nowIso(),
      totalRamGb,
      freeRamGb,
      availableRamGb,
      reservedRamGb,
      modelVramGb: this.modelVramGb,
      perAgentOverheadGb: perAgentGb,
      cpuPressure,
      cpuPaused: this.cpuPaused,
      allowedAgents,
      activeWorkers,
      queuedWorkers,
      canSpawnNow: !this.cpuPaused && activeWorkers < allowedAgents,
      note,
      reason
    };
  }

  private cpuUsage(): number {
    const cpus = os.cpus();
    if (!cpus.length) {
      return 0;
    }

    const current = cpus.map((cpu) => {
      const idle = cpu.times.idle;
      const total = Object.values(cpu.times).reduce((sum, value) => sum + value, 0);
      return { idle, total };
    });

    if (this.previousCpuTimes.length !== current.length) {
      this.previousCpuTimes = current;
      return 0;
    }

    let totalDelta = 0;
    let idleDelta = 0;

    for (let index = 0; index < current.length; index += 1) {
      const previous = this.previousCpuTimes[index];
      const sample = current[index];
      totalDelta += sample.total - previous.total;
      idleDelta += sample.idle - previous.idle;
    }

    this.previousCpuTimes = current;
    if (totalDelta === 0) {
      return 0;
    }

    return Math.round(((totalDelta - idleDelta) / totalDelta) * 1000) / 10;
  }
}
