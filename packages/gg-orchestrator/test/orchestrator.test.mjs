import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const packageRoot = path.resolve(__dirname, '..');
const orchestrator = await import(path.join(packageRoot, 'dist', 'index.js'));

function makeProjectRoot() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'gg-orchestrator-test-'));
  fs.mkdirSync(path.join(root, '.agent', 'registry'), { recursive: true });
  return root;
}

function cleanupProjectRoot(root) {
  fs.rmSync(root, { recursive: true, force: true });
}

function withProjectRoot(fn) {
  const root = makeProjectRoot();
  try {
    return fn(root);
  } finally {
    cleanupProjectRoot(root);
  }
}

test('buildPersonaPacket falls back to built-in personas when project registry is missing', () => {
  withProjectRoot((root) => {
    const persona = orchestrator.buildPersonaPacket(root, 'orchestrator');
    assert.equal(persona.personaId, 'orchestrator');
    assert.equal(persona.role, 'coordinator');
    assert.match(persona.memoryQuery, /coordination/i);
    assert.ok(persona.allowed.length > 0);
  });
});

test('createRunState and spawnWorker persist run topology with built-in persona fallbacks', () => {
  withProjectRoot((root) => {
    const { run } = orchestrator.createRunState(root, {
      runId: 'run-test-basic',
      summary: 'basic orchestrator smoke',
      classification: 'TASK',
      coordinatorRuntime: 'codex'
    });

    assert.equal(run.runId, 'run-test-basic');
    assert.equal(run.bus.nextCursor, 1);
    assert.equal(run.runtimeScorecards.length, 3);

    const plannerPersona = orchestrator.buildPersonaPacket(root, 'project-planner');
    const spawned = orchestrator.spawnWorker(root, {
      runId: run.runId,
      runtime: 'claude',
      agentId: 'planner-1',
      role: 'planner',
      taskSummary: 'Plan implementation slices',
      persona: plannerPersona,
      toolBundle: ['filesystem']
    });

    assert.equal(spawned.worker.agentId, 'planner-1');
    assert.equal(spawned.worker.parentAgentId, null);
    assert.equal(spawned.worker.status, 'spawn_requested');
    assert.equal(spawned.worker.persona.personaId, 'project-planner');
    assert.equal(spawned.worker.launchTransport, 'background-terminal');

    const persisted = orchestrator.readRunState(root, run.runId);
    assert.equal(persisted.workers.length, 1);
    assert.equal(persisted.workers[0].agentId, 'planner-1');
    assert.equal(persisted.workers[0].launchSpec.taskSummary, 'Plan implementation slices');
  });
});

test('delegateTask enforces board approval for high-risk tasks and spawns after approval', () => {
  withProjectRoot((root) => {
    orchestrator.createRunState(root, {
      runId: 'run-test-delegation',
      summary: 'delegation policy',
      classification: 'TASK',
      coordinatorRuntime: 'codex'
    });

    orchestrator.spawnWorker(root, {
      runId: 'run-test-delegation',
      runtime: 'codex',
      agentId: 'coordinator-1',
      role: 'coordinator',
      taskSummary: 'Coordinate the run',
      persona: orchestrator.buildPersonaPacket(root, 'orchestrator')
    });

    const blocked = orchestrator.delegateTask(root, {
      runId: 'run-test-delegation',
      fromAgentId: 'coordinator-1',
      toRuntime: 'kimi',
      role: 'builder',
      taskSummary: 'Implement auth and payments workflow',
      classification: 'TASK',
      persona: orchestrator.buildPersonaPacket(root, 'backend-specialist')
    });

    assert.equal(blocked.decision.status, 'rejected');
    assert.equal(blocked.decision.boardRequired, true);
    assert.equal(blocked.worker, null);
    assert.match(blocked.decision.rationale, /board approval/i);

    const approved = orchestrator.delegateTask(root, {
      runId: 'run-test-delegation',
      fromAgentId: 'coordinator-1',
      toRuntime: 'kimi',
      role: 'builder',
      taskSummary: 'Implement auth and payments workflow',
      classification: 'TASK',
      persona: orchestrator.buildPersonaPacket(root, 'backend-specialist'),
      boardApproved: true,
      agentId: 'builder-1'
    });

    assert.equal(approved.decision.status, 'approved');
    assert.equal(approved.decision.spawnedAgentId, 'builder-1');
    assert.ok(approved.worker);
    assert.equal(approved.worker.agentId, 'builder-1');
    assert.equal(approved.worker.parentAgentId, 'coordinator-1');

    const persisted = orchestrator.readRunState(root, 'run-test-delegation');
    assert.equal(persisted.delegationDecisions.length, 2);
    assert.equal(persisted.workers.length, 2);
  });
});

test('postMessage, fetchInbox, ackMessage, and terminateWorker update the durable bus state', () => {
  withProjectRoot((root) => {
    orchestrator.createRunState(root, {
      runId: 'run-test-bus',
      summary: 'bus durability',
      classification: 'TASK',
      coordinatorRuntime: 'codex'
    });

    orchestrator.spawnWorker(root, {
      runId: 'run-test-bus',
      runtime: 'codex',
      agentId: 'coordinator-1',
      role: 'coordinator',
      taskSummary: 'Coordinate bus state',
      persona: orchestrator.buildPersonaPacket(root, 'orchestrator')
    });
    orchestrator.spawnWorker(root, {
      runId: 'run-test-bus',
      runtime: 'claude',
      agentId: 'reviewer-1',
      parentAgentId: 'coordinator-1',
      role: 'reviewer',
      taskSummary: 'Review generated changes',
      persona: orchestrator.buildPersonaPacket(root, 'test-engineer')
    });

    const sent = orchestrator.postMessage(root, {
      runId: 'run-test-bus',
      fromAgentId: 'coordinator-1',
      toAgentId: 'reviewer-1',
      type: 'TASK_SPEC',
      payload: { summary: 'Review the latest patch set' },
      requiresAck: true
    });

    assert.equal(sent.message.cursor, 1);
    assert.equal(sent.message.requiresAck, true);

    const inbox = orchestrator.fetchInbox(root, {
      runId: 'run-test-bus',
      agentId: 'reviewer-1'
    });
    assert.equal(inbox.messages.length, 1);
    assert.equal(inbox.messages[0].messageId, sent.message.messageId);

    const acked = orchestrator.ackMessage(root, {
      runId: 'run-test-bus',
      agentId: 'reviewer-1',
      messageId: sent.message.messageId
    });
    assert.ok(acked.message.ackedAt);

    const terminated = orchestrator.terminateWorker(root, {
      runId: 'run-test-bus',
      agentId: 'reviewer-1',
      reason: 'operator stop'
    });
    assert.equal(terminated.worker.status, 'terminated');
    assert.match(terminated.worker.execution.lastError, /operator stop/i);

    const persistedMessages = orchestrator.listRunMessages(root, 'run-test-bus');
    assert.equal(persistedMessages.length, 2);
    assert.equal(persistedMessages[1].type, 'BLOCKED');
    assert.equal(persistedMessages[1].toAgentId, 'coordinator-1');
  });
});
