# Multi-Model Control Plane Operational Runbook

> **Version:** 1.0  
> **Date:** 2026-03-09  
> **Scope:** Operational procedures for running and maintaining the multi-model control plane

---

## Daily Operations

### Morning Checklist

```bash
# 1. Verify no orphaned beads
bd prime --json

# 2. Check runtime parity
npm run harness:runtime-parity

# 3. Validate persona registry
npm run harness:persona:audit

# 4. Check control plane health (if running)
curl -s http://localhost:3000/api/v1/health | jq .

# 5. Review active worktrees
ls -la .agent/control-plane/worktrees/
```

### Starting a Work Session

```bash
# Option A: Headless control plane
npm run control-plane:start

# Option B: macOS control surface
npm run macos:control-surface:run

# Option C: Direct CLI (no server)
npm run gg -- workflow run go "task description"
```

### Ending a Work Session

```bash
# 1. Complete any pending run artifacts
node scripts/agent-run-artifact.mjs complete --id {run-id} --status success

# 2. Sync beads
bd sync

# 3. Verify clean state
bd prime --json
git status

# 4. Stop control plane (if running)
# Ctrl+C or kill the process
```

---

## Deployment Procedures

### Pre-Deployment Checklist

Before deploying the control plane to a new environment:

```bash
# 1. Build all packages
npm run build

# 2. Run full test suite
npm test

# 3. Runtime parity check
npm run harness:runtime-parity

# 4. Persona registry validation
npm run harness:persona:audit

# 5. Lint check
npm run lint

# 6. Verify no uncommitted changes
./scripts/dirty-worktree-guard.sh
```

### Production Deployment

```bash
# 1. Set environment variables
export GG_COORDINATOR_RUNTIME="codex"  # or claude, kimi
export GG_COORDINATOR_PREFERENCE="codex,claude,kimi"
export NODE_ENV="production"

# 2. Start control plane with PM2 (recommended)
pm2 start packages/gg-control-plane-server/dist/index.js \
  --name gg-control-plane \
  --env production

# 3. Verify health
curl http://localhost:3000/api/v1/health

# 4. Monitor logs
pm2 logs gg-control-plane
```

### Rolling Update

```bash
# 1. Build new version
npm run build

# 2. Restart control plane (zero-downtime with PM2)
pm2 reload gg-control-plane

# 3. Verify new version
pm2 show gg-control-plane
curl http://localhost:3000/api/v1/health
```

---

## Incident Response

### Control Plane Down

**Symptoms:**
- `curl: (7) Failed to connect to localhost port 3000`
- macOS app shows "Disconnected"
- Workers failing to spawn

**Response:**

```bash
# 1. Check if process is running
pm2 status
# or
ps aux | grep gg-control-plane

# 2. Check logs
pm2 logs gg-control-plane --lines 100

# 3. Restart if needed
pm2 restart gg-control-plane

# 4. Verify recovery
curl http://localhost:3000/api/v1/health
```

### Worker Stuck / Unresponsive

**Symptoms:**
- Worker shows "in_progress" for extended period
- No new messages in mailbox
- Worktree has uncommitted changes

**Response:**

```bash
# 1. Check worker process
ps aux | grep {agentId}

# 2. Check worktree status
cd .agent/control-plane/worktrees/{runId}/{agentId}
git status

# 3. Option A: Graceful termination
curl -X POST http://localhost:3000/api/v1/runs/{runId}/terminate \
  -H "Content-Type: application/json" \
  -d '{"agentId": "{agentId}", "reason": "stuck"}'

# 4. Option B: Force kill (if graceful fails)
kill -9 {pid}

# 5. Mark run artifact as failed
node scripts/agent-run-artifact.mjs complete \
  --id {runId} \
  --status failed \
  --reason "Worker terminated: stuck"
```

### Runtime Authentication Failure

**Symptoms:**
- `401 Unauthorized` from runtime API
- Preflight checks failing
- Workers failing to start

**Response:**

```bash
# 1. Check credential files
cat ~/.codex/auth.json
cat ~/.claude/.credentials.json
cat ~/.kimi/credentials/kimi-code.json

# 2. Verify environment variables
echo $OPENAI_API_KEY
echo $ANTHROPIC_API_KEY
echo $MOONSHOT_API_KEY

# 3. Re-authenticate if needed
# Codex: codex login
# Claude: claude login
# Kimi: kimi login

# 4. Verify status
npm run harness:runtime:status
```

### Worktree Corruption

**Symptoms:**
- Git errors in worktree
- Missing files
- Permission denied errors

**Response:**

```bash
# 1. Identify corrupted worktree
ls -la .agent/control-plane/worktrees/{runId}/

# 2. Preserve any valuable state (if applicable)
cp -r .agent/control-plane/worktrees/{runId}/{agentId} /tmp/backup-{agentId}

# 3. Remove corrupted worktree
rm -rf .agent/control-plane/worktrees/{runId}/{agentId}

# 4. Re-create worktree (if run is still active)
# The control plane will re-allocate on next spawn request

# 5. If run is complete, clean up entire run
rm -rf .agent/control-plane/worktrees/{runId}
rm .agent/runs/{runId}.json
```

### High Memory Usage

**Symptoms:**
- System sluggish
- OOM errors in logs
- Governor rejecting spawns

**Response:**

```bash
# 1. Check current memory usage
free -h  # Linux
vm_stat  # macOS

# 2. List active workers
curl http://localhost:3000/api/v1/worktrees | jq .

# 3. Terminate non-critical workers
curl -X POST http://localhost:3000/api/v1/runs/{runId}/terminate \
  -d '{"agentId": "{agentId}"}'

# 4. Adjust reserved RAM (temporary)
export HARNESS_RESERVED_RAM_GB=8

# 5. Restart control plane with new limits
pm2 restart gg-control-plane
```

---

## Maintenance Procedures

### Weekly Maintenance

```bash
# 1. Clean up old run artifacts
find .agent/runs -name "*.json" -mtime +7 -delete

# 2. Clean up old worktrees
find .agent/control-plane/worktrees -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

# 3. Update persona registry cache
npm run harness:persona:sync

# 4. Run benchmark
npm run harness:persona:benchmark

# 5. Verify all scripts still work
npm run harness:runtime-parity
```

### Monthly Maintenance

```bash
# 1. Full dependency update
npm update
npm audit fix

# 2. Rebuild all packages
npm run build

# 3. Full test suite
npm test

# 4. Update project context
npm run harness:project-context

# 5. Review and archive old beads
bd list --status closed --json | jq '.[] | select(.updated < (now - 2592000))'
```

### Backup Procedures

```bash
# 1. Backup run artifacts
tar czf runs-backup-$(date +%Y%m%d).tar.gz .agent/runs/

# 2. Backup active worktrees (optional)
tar czf worktrees-backup-$(date +%Y%m%d).tar.gz .agent/control-plane/worktrees/

# 3. Backup registry state
cp .agent/registry/persona-registry.json persona-registry-backup-$(date +%Y%m%d).json
cp .agent/registry/persona-compounds.json persona-compounds-backup-$(date +%Y%m%d).json
```

---

## Monitoring

### Key Metrics

| Metric | Source | Alert Threshold |
|--------|--------|-----------------|
| Active runs | `/api/v1/worktrees` | > 10 |
| Worker spawn rate | Control plane logs | > 5/min sustained |
| Failed spawns | Control plane logs | > 3 in 5 min |
| Memory usage | System metrics | > 80% |
| API latency | `/api/v1/health` | > 500ms |

### Health Check Endpoint

```bash
# Basic health
curl http://localhost:3000/api/v1/health

# Expected response:
{
  "status": "healthy",
  "version": "0.1.0",
  "uptime": 3600,
  "activeRuns": 3,
  "activeWorkers": 7
}
```

### Log Aggregation

Control plane logs to stdout/stderr. In production, configure log aggregation:

```bash
# PM2 log rotation
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 100M
pm2 set pm2-logrotate:retain 10

# Structured logging (JSON)
export GG_LOG_FORMAT=json
npm run control-plane:start
```

---

## Security Procedures

### Credential Rotation

```bash
# 1. Update API keys in environment
export OPENAI_API_KEY="new-key"
export ANTHROPIC_API_KEY="new-key"
export MOONSHOT_API_KEY="new-key"

# 2. Update credential files
# ~/.codex/auth.json
# ~/.claude/.credentials.json
# ~/.kimi/credentials/kimi-code.json

# 3. Restart control plane
pm2 restart gg-control-plane

# 4. Verify new credentials
npm run harness:runtime:status

# 5. Revoke old keys at provider
```

### Access Control

```bash
# Restrict worktree permissions
chmod 700 .agent/control-plane/worktrees

# Secure run artifacts
chmod 600 .agent/runs/*.json

# Audit registry access
ls -la .agent/registry/
```

---

## Recovery Procedures

### Full Control Plane Recovery

```bash
# 1. Stop any running instances
pm2 stop gg-control-plane
pm2 delete gg-control-plane

# 2. Clean up state (optional - preserves runs)
rm -rf .agent/control-plane/worktrees/*

# 3. Rebuild
npm run build

# 4. Restart
pm2 start packages/gg-control-plane-server/dist/index.js --name gg-control-plane

# 5. Verify
curl http://localhost:3000/api/v1/health
```

### Registry Corruption Recovery

```bash
# 1. Restore from backup
cp persona-registry-backup-YYYYMMDD.json .agent/registry/persona-registry.json

# 2. Validate restored registry
npm run harness:persona:audit

# 3. Re-sync if needed
npm run harness:persona:sync
```

---

## Escalation Matrix

| Issue | First Response | Escalate To | Timeline |
|-------|---------------|-------------|----------|
| Control plane down | Restart service | Platform team | 15 min |
| Worker stuck | Terminate worker | Run coordinator | 30 min |
| Auth failure | Re-authenticate | Security team | 1 hour |
| Data corruption | Restore backup | Data team | 2 hours |
| Security incident | Isolate system | Security + Legal | Immediate |

---

## Contact Information

- **Platform Team:** platform@geargrind.dev
- **Security Team:** security@geargrind.dev
- **On-Call Escalation:** +1-XXX-XXX-XXXX

---

## References

- [Implementation Notes](../implementation-notes/multi-model-control-plane-implementation.md)
- [Usage Guide](./multi-model-control-plane-usage.md)
- [Runtime Profiles](../runtime-profiles.md)
- [Agentic Harness](../agentic-harness.md)
