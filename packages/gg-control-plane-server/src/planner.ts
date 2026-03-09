import fs from 'node:fs';
import path from 'node:path';
import { nowIso, readTaskRecord, serverPaths } from './store.js';

export type PlannerTaskStatus = 'todo' | 'in_progress' | 'done' | 'archived';

export interface PlannerProjectRecord {
  id: string;
  name: string;
  root: string;
}

export interface PlannerTaskRecord {
  id: string;
  projectId: string;
  title: string;
  description: string | null;
  status: PlannerTaskStatus;
  priority: number;
  source: string;
  sourceSession: string | null;
  labels: string[];
  attachments: string[];
  isGlobal: boolean;
  runId: string | null;
  runtime: string | null;
  linkedRunStatus: string | null;
  assignedAgentId: string | null;
  worktreePath: string | null;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
}

export interface PlannerNoteRecord {
  id: string;
  title: string;
  content: string;
  pinned: boolean;
  taskId: string | null;
  projectId: string | null;
  source: string;
  createdAt: string;
  updatedAt: string;
}

export interface PlannerTaskView extends PlannerTaskRecord {
  notes: PlannerNoteRecord[];
}

export interface PlannerSnapshot {
  project: PlannerProjectRecord;
  tasks: PlannerTaskView[];
  notes: PlannerNoteRecord[];
  counts: {
    todo: number;
    inProgress: number;
    done: number;
    archived: number;
  };
  updatedAt: string;
}

interface PlannerStoreFile {
  version: number;
  updatedAt: string;
  project: PlannerProjectRecord;
  tasks: PlannerTaskRecord[];
  notes: PlannerNoteRecord[];
}

export interface PlannerTaskInput {
  projectId?: string | null;
  title: string;
  description?: string | null;
  status?: PlannerTaskStatus;
  priority?: number;
  source?: string;
  sourceSession?: string | null;
  labels?: string[];
  attachments?: string[];
  isGlobal?: boolean;
  runId?: string | null;
  runtime?: string | null;
  linkedRunStatus?: string | null;
  assignedAgentId?: string | null;
  worktreePath?: string | null;
}

export interface PlannerTaskPatch {
  title?: string;
  description?: string | null;
  status?: PlannerTaskStatus;
  priority?: number;
  source?: string;
  sourceSession?: string | null;
  labels?: string[];
  attachments?: string[];
  isGlobal?: boolean;
  runId?: string | null;
  runtime?: string | null;
  linkedRunStatus?: string | null;
  assignedAgentId?: string | null;
  worktreePath?: string | null;
}

export interface PlannerNoteInput {
  title?: string;
  content: string;
  pinned?: boolean;
  taskId?: string | null;
  projectId?: string | null;
  source?: string;
}

export interface PlannerNotePatch {
  title?: string;
  content?: string;
  pinned?: boolean;
  taskId?: string | null;
  projectId?: string | null;
  source?: string;
}

function plannerFile(projectRoot: string): string {
  return path.join(serverPaths(projectRoot).root, 'planner.json');
}

function readJson<T>(filePath: string): T | null {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8')) as T;
}

function writeJson(filePath: string, value: unknown): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

function nextId(prefix: string): string {
  return `${prefix}-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

function defaultProject(projectRoot: string): PlannerProjectRecord {
  return {
    id: 'workspace',
    name: path.basename(projectRoot) || 'workspace',
    root: projectRoot
  };
}

function defaultPlannerStore(projectRoot: string): PlannerStoreFile {
  return {
    version: 1,
    updatedAt: nowIso(),
    project: defaultProject(projectRoot),
    tasks: [],
    notes: []
  };
}

function loadPlannerStore(projectRoot: string): PlannerStoreFile {
  const existing = readJson<PlannerStoreFile>(plannerFile(projectRoot));
  if (existing) {
    return {
      version: existing.version || 1,
      updatedAt: existing.updatedAt || nowIso(),
      project: existing.project || defaultProject(projectRoot),
      tasks: Array.isArray(existing.tasks) ? existing.tasks : [],
      notes: Array.isArray(existing.notes) ? existing.notes : []
    };
  }
  const defaults = defaultPlannerStore(projectRoot);
  writeJson(plannerFile(projectRoot), defaults);
  return defaults;
}

function savePlannerStore(projectRoot: string, store: PlannerStoreFile): PlannerStoreFile {
  const next: PlannerStoreFile = {
    ...store,
    updatedAt: nowIso(),
    project: store.project || defaultProject(projectRoot),
    tasks: [...store.tasks],
    notes: [...store.notes]
  };
  writeJson(plannerFile(projectRoot), next);
  return next;
}

function sanitizeStatus(status?: string | null): PlannerTaskStatus {
  switch (String(status || '').trim().toLowerCase()) {
    case 'in_progress':
    case 'in-progress':
    case 'running':
      return 'in_progress';
    case 'done':
    case 'complete':
    case 'completed':
      return 'done';
    case 'archived':
      return 'archived';
    default:
      return 'todo';
  }
}

function sanitizePriority(priority?: number | null): number {
  const value = Number(priority ?? 0);
  if (!Number.isFinite(value)) {
    return 0;
  }
  return Math.max(0, Math.min(4, Math.round(value)));
}

function sanitizeArray(values?: string[] | null): string[] {
  return Array.from(
    new Set(
      (values || [])
        .map((entry) => String(entry).trim())
        .filter(Boolean)
    )
  );
}

function noteTitleFromContent(content: string): string {
  const firstLine = content
    .split('\n')
    .map((line) => line.trim())
    .find(Boolean);
  return firstLine ? firstLine.slice(0, 80) : 'Untitled note';
}

function attachNotes(tasks: PlannerTaskRecord[], notes: PlannerNoteRecord[]): PlannerTaskView[] {
  const notesByTask = new Map<string, PlannerNoteRecord[]>();
  for (const note of notes) {
    if (!note.taskId) {
      continue;
    }
    const bucket = notesByTask.get(note.taskId) || [];
    bucket.push(note);
    notesByTask.set(note.taskId, bucket);
  }

  const statusRank: Record<PlannerTaskStatus, number> = {
    in_progress: 0,
    todo: 1,
    done: 2,
    archived: 3
  };

  return [...tasks]
    .sort((left, right) => {
      const leftRank = statusRank[left.status];
      const rightRank = statusRank[right.status];
      if (leftRank !== rightRank) {
        return leftRank - rightRank;
      }
      if (left.priority !== right.priority) {
        return right.priority - left.priority;
      }
      return right.updatedAt.localeCompare(left.updatedAt);
    })
    .map((task) => ({
      ...task,
      notes: (notesByTask.get(task.id) || []).sort((left, right) => right.updatedAt.localeCompare(left.updatedAt))
    }));
}

function syncLinkedRunState(projectRoot: string, task: PlannerTaskRecord): PlannerTaskRecord {
  if (!task.runId) {
    return task;
  }
  const run = readTaskRecord(projectRoot, task.runId);
  if (!run) {
    return task;
  }

  const next: PlannerTaskRecord = {
    ...task,
    linkedRunStatus: run.status,
    updatedAt: task.updatedAt
  };

  if ((run.status === 'accepted' || run.status === 'running') && next.status === 'todo') {
    next.status = 'in_progress';
    next.updatedAt = nowIso();
  }

  if (run.status === 'complete' && next.status !== 'done') {
    next.status = 'done';
    next.completedAt = next.completedAt || nowIso();
    next.updatedAt = nowIso();
  }

  return next;
}

function syncPlannerStore(projectRoot: string, store: PlannerStoreFile): PlannerStoreFile {
  let changed = false;
  const syncedTasks = store.tasks.map((task) => {
    const synced = syncLinkedRunState(projectRoot, task);
    if (JSON.stringify(synced) !== JSON.stringify(task)) {
      changed = true;
    }
    return synced;
  });

  if (!changed) {
    return store;
  }

  return savePlannerStore(projectRoot, {
    ...store,
    tasks: syncedTasks
  });
}

export function readPlannerSnapshot(projectRoot: string): PlannerSnapshot {
  const synced = syncPlannerStore(projectRoot, loadPlannerStore(projectRoot));
  const tasks = attachNotes(synced.tasks, synced.notes);
  return {
    project: synced.project,
    tasks,
    notes: [...synced.notes].sort((left, right) => {
      if (left.pinned !== right.pinned) {
        return left.pinned ? -1 : 1;
      }
      return right.updatedAt.localeCompare(left.updatedAt);
    }),
    counts: {
      todo: tasks.filter((task) => task.status === 'todo').length,
      inProgress: tasks.filter((task) => task.status === 'in_progress').length,
      done: tasks.filter((task) => task.status === 'done').length,
      archived: tasks.filter((task) => task.status === 'archived').length
    },
    updatedAt: synced.updatedAt
  };
}

export function createPlannerTask(projectRoot: string, input: PlannerTaskInput): PlannerTaskView {
  const title = input.title.trim();
  if (!title) {
    throw new Error('Task title is required');
  }

  const store = loadPlannerStore(projectRoot);
  const createdAt = nowIso();
  const task: PlannerTaskRecord = {
    id: nextId('task'),
    projectId: input.projectId || store.project.id,
    title,
    description: input.description?.trim() || null,
    status: sanitizeStatus(input.status),
    priority: sanitizePriority(input.priority),
    source: input.source?.trim() || 'manual',
    sourceSession: input.sourceSession?.trim() || null,
    labels: sanitizeArray(input.labels),
    attachments: sanitizeArray(input.attachments),
    isGlobal: Boolean(input.isGlobal),
    runId: input.runId?.trim() || null,
    runtime: input.runtime?.trim() || null,
    linkedRunStatus: input.linkedRunStatus?.trim() || null,
    assignedAgentId: input.assignedAgentId?.trim() || null,
    worktreePath: input.worktreePath?.trim() || null,
    createdAt,
    updatedAt: createdAt,
    completedAt: sanitizeStatus(input.status) === 'done' ? createdAt : null
  };

  store.tasks.push(task);
  const saved = savePlannerStore(projectRoot, store);
  return attachNotes(saved.tasks, saved.notes).find((entry) => entry.id === task.id)!;
}

export function updatePlannerTask(projectRoot: string, taskId: string, patch: PlannerTaskPatch): PlannerTaskView {
  const store = loadPlannerStore(projectRoot);
  const index = store.tasks.findIndex((task) => task.id === taskId);
  if (index < 0) {
    throw new Error(`Planner task not found: ${taskId}`);
  }

  const existing = store.tasks[index];
  const nextStatus = patch.status ? sanitizeStatus(patch.status) : existing.status;
  const updated: PlannerTaskRecord = {
    ...existing,
    title: patch.title !== undefined ? patch.title.trim() || existing.title : existing.title,
    description: patch.description !== undefined ? patch.description?.trim() || null : existing.description,
    status: nextStatus,
    priority: patch.priority !== undefined ? sanitizePriority(patch.priority) : existing.priority,
    source: patch.source !== undefined ? patch.source.trim() || existing.source : existing.source,
    sourceSession: patch.sourceSession !== undefined ? patch.sourceSession?.trim() || null : existing.sourceSession,
    labels: patch.labels !== undefined ? sanitizeArray(patch.labels) : existing.labels,
    attachments: patch.attachments !== undefined ? sanitizeArray(patch.attachments) : existing.attachments,
    isGlobal: patch.isGlobal !== undefined ? Boolean(patch.isGlobal) : existing.isGlobal,
    runId: patch.runId !== undefined ? patch.runId?.trim() || null : existing.runId,
    runtime: patch.runtime !== undefined ? patch.runtime?.trim() || null : existing.runtime,
    linkedRunStatus:
      patch.linkedRunStatus !== undefined ? patch.linkedRunStatus?.trim() || null : existing.linkedRunStatus,
    assignedAgentId:
      patch.assignedAgentId !== undefined ? patch.assignedAgentId?.trim() || null : existing.assignedAgentId,
    worktreePath: patch.worktreePath !== undefined ? patch.worktreePath?.trim() || null : existing.worktreePath,
    updatedAt: nowIso(),
    completedAt:
      nextStatus === 'done'
        ? existing.completedAt || nowIso()
        : patch.status !== undefined
          ? null
          : existing.completedAt
  };

  store.tasks[index] = updated;
  const saved = savePlannerStore(projectRoot, store);
  return attachNotes(saved.tasks, saved.notes).find((entry) => entry.id === taskId)!;
}

export function deletePlannerTask(projectRoot: string, taskId: string): void {
  const store = loadPlannerStore(projectRoot);
  const next = {
    ...store,
    tasks: store.tasks.filter((task) => task.id !== taskId),
    notes: store.notes.filter((note) => note.taskId !== taskId)
  };
  savePlannerStore(projectRoot, next);
}

export function createPlannerNote(projectRoot: string, input: PlannerNoteInput): PlannerNoteRecord {
  const content = input.content.trim();
  if (!content) {
    throw new Error('Note content is required');
  }

  const store = loadPlannerStore(projectRoot);
  const createdAt = nowIso();
  const note: PlannerNoteRecord = {
    id: nextId('note'),
    title: input.title?.trim() || noteTitleFromContent(content),
    content,
    pinned: Boolean(input.pinned),
    taskId: input.taskId?.trim() || null,
    projectId: input.projectId?.trim() || store.project.id,
    source: input.source?.trim() || 'manual',
    createdAt,
    updatedAt: createdAt
  };

  store.notes.push(note);
  savePlannerStore(projectRoot, store);
  return note;
}

export function updatePlannerNote(projectRoot: string, noteId: string, patch: PlannerNotePatch): PlannerNoteRecord {
  const store = loadPlannerStore(projectRoot);
  const index = store.notes.findIndex((note) => note.id === noteId);
  if (index < 0) {
    throw new Error(`Planner note not found: ${noteId}`);
  }

  const existing = store.notes[index];
  const nextContent = patch.content !== undefined ? patch.content.trim() : existing.content;
  if (!nextContent) {
    throw new Error('Note content is required');
  }

  const updated: PlannerNoteRecord = {
    ...existing,
    title:
      patch.title !== undefined
        ? patch.title.trim() || noteTitleFromContent(nextContent)
        : existing.title || noteTitleFromContent(nextContent),
    content: nextContent,
    pinned: patch.pinned !== undefined ? Boolean(patch.pinned) : existing.pinned,
    taskId: patch.taskId !== undefined ? patch.taskId?.trim() || null : existing.taskId,
    projectId: patch.projectId !== undefined ? patch.projectId?.trim() || null : existing.projectId,
    source: patch.source !== undefined ? patch.source.trim() || existing.source : existing.source,
    updatedAt: nowIso()
  };

  store.notes[index] = updated;
  savePlannerStore(projectRoot, store);
  return updated;
}

export function deletePlannerNote(projectRoot: string, noteId: string): void {
  const store = loadPlannerStore(projectRoot);
  savePlannerStore(projectRoot, {
    ...store,
    notes: store.notes.filter((note) => note.id !== noteId)
  });
}
