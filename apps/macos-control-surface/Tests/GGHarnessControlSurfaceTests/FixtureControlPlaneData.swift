import Foundation

enum FixtureControlPlaneData {
    static let agentAnalytics = Data(
        """
        {
          "summary": {
            "totalRuns": 5,
            "totalWorkers": 18,
            "activeWorkers": 4,
            "failedWorkers": 1,
            "distinctPersonas": 3,
            "distinctRuntimes": 3,
            "lastUpdatedAt": "2026-03-09T13:00:00.000Z"
          },
          "coordinators": [
            { "key": "codex", "label": "Codex", "type": "coordinator", "calls": 3, "failures": 0, "active": 1, "avgDurationMs": 812.5, "lastUsed": "2026-03-09T13:00:00.000Z" }
          ],
          "workerRuntimes": [
            { "key": "kimi", "label": "Kimi", "type": "worker-runtime", "calls": 9, "failures": 1, "active": 2, "avgDurationMs": 1420.0, "lastUsed": "2026-03-09T12:58:00.000Z" }
          ],
          "personas": [
            { "key": "backend-specialist", "label": "backend-specialist", "type": "persona", "calls": 7, "failures": 1, "active": 2, "avgDurationMs": 980.0, "lastUsed": "2026-03-09T12:58:00.000Z" }
          ],
          "roles": [
            { "key": "builder", "label": "Builder", "type": "role", "calls": 7, "failures": 1, "active": 2, "avgDurationMs": 980.0, "lastUsed": "2026-03-09T12:58:00.000Z" }
          ]
        }
        """.utf8
    )

    static let busStatus = Data(
        """
        {
          "runId": "run-fixture",
          "totalMessages": 6,
          "workers": {
            "builder-1": {
              "status": "running",
              "progressPct": 45,
              "lastHeartbeat": "2026-03-09T13:05:00.000Z",
              "currentTask": "Implement planner flow",
              "worktreePath": "/tmp/run-fixture/builder-1",
              "runtime": "codex",
              "role": "builder",
              "personaId": "backend-specialist",
              "launchTransport": "background-terminal",
              "executionStatus": "running",
              "lastSummary": "Working through planner state updates"
            }
          },
          "activeLocks": {},
          "telemetry": {
            "coordinatorRuntime": "claude",
            "totalWorkers": 4,
            "activeWorkers": 2,
            "queuedWorkers": 1,
            "completedWorkers": 1,
            "failedWorkers": 0,
            "handoffReadyWorkers": 0,
            "activeLocks": 0,
            "totalMessages": 6,
            "delegationCount": 3,
            "runtimeBreakdown": [
              { "key": "codex", "label": "Codex", "count": 2 },
              { "key": "claude", "label": "Claude", "count": 1 }
            ],
            "roleBreakdown": [
              { "key": "builder", "label": "Builder", "count": 2 }
            ],
            "governorAllowedAgents": 4,
            "governorActiveWorkers": 2,
            "governorQueuedWorkers": 1,
            "updatedAt": "2026-03-09T13:05:00.000Z"
          }
        }
        """.utf8
    )

    static let plannerSnapshot = Data(
        """
        {
          "project": {
            "id": "project-1",
            "name": "GG Harness",
            "root": "/Users/shawn/Documents/gg-agentic-harness"
          },
          "tasks": [
            {
              "id": "task-1",
              "projectId": "project-1",
              "title": "Integrate planner with swarm",
              "description": "Push shared context into swarm and console surfaces.",
              "status": "in_progress",
              "priority": 3,
              "source": "planner-ui",
              "sourceSession": null,
              "labels": ["planner", "swarm"],
              "attachments": [],
              "isGlobal": false,
              "runId": "run-fixture",
              "runtime": "codex",
              "linkedRunStatus": "running",
              "assignedAgentId": "builder-1",
              "worktreePath": "/tmp/run-fixture/builder-1",
              "createdAt": "2026-03-09T12:00:00.000Z",
              "updatedAt": "2026-03-09T12:05:00.000Z",
              "completedAt": null,
              "notes": [
                {
                  "id": "note-1",
                  "title": "Telemetry",
                  "content": "Show run graph state in Swarm.",
                  "pinned": true,
                  "taskId": "task-1",
                  "projectId": "project-1",
                  "source": "planner-ui",
                  "createdAt": "2026-03-09T12:01:00.000Z",
                  "updatedAt": "2026-03-09T12:01:00.000Z"
                }
              ]
            }
          ],
          "notes": [
            {
              "id": "note-1",
              "title": "Telemetry",
              "content": "Show run graph state in Swarm.",
              "pinned": true,
              "taskId": "task-1",
              "projectId": "project-1",
              "source": "planner-ui",
              "createdAt": "2026-03-09T12:01:00.000Z",
              "updatedAt": "2026-03-09T12:01:00.000Z"
            }
          ],
          "counts": {
            "todo": 1,
            "inProgress": 1,
            "done": 0,
            "archived": 0
          },
          "updatedAt": "2026-03-09T12:05:00.000Z"
        }
        """.utf8
    )

    static let replaySources = Data(
        """
        {
          "sources": [
            {
              "key": "claude",
              "label": "Claude Code",
              "root": "/Users/shawn/.claude/projects",
              "available": true
            }
          ]
        }
        """.utf8
    )

    static let replaySessions = Data(
        """
        {
          "sessions": [
            {
              "id": "session-1",
              "source": "claude",
              "path": "/Users/shawn/.claude/projects/demo/session.jsonl",
              "title": "demo / session",
              "format": "claude-jsonl",
              "turnCount": 42,
              "modifiedAt": "2026-03-09T12:05:00.000Z",
              "sizeBytes": 4096
            }
          ]
        }
        """.utf8
    )

    static let replayRender = Data(
        """
        {
          "sessionId": "session-1",
          "title": "demo / session",
          "inputPath": "/Users/shawn/.claude/projects/demo/session.jsonl",
          "outputPath": "/tmp/replays/session-1.html",
          "outputUrl": "/api/replays/file?path=%2Ftmp%2Freplays%2Fsession-1.html",
          "turnCount": 42
        }
        """.utf8
    )

    static let modelFit = Data(
        """
        {
          "available": true,
          "binaryPath": "/opt/homebrew/bin/llmfit",
          "system": {
            "availableRamGb": 54.2,
            "totalRamGb": 64,
            "cpuCores": 12,
            "cpuName": "Apple M3 Max",
            "hasGpu": true,
            "gpuName": "Apple GPU",
            "gpuVramGb": 32,
            "backend": "mlx",
            "unifiedMemory": true
          },
          "recommendations": [
            {
              "name": "lmstudio-community/Qwen2.5-Coder-7B-Instruct-GGUF",
              "shortName": "Qwen2.5-Coder-7B-Instruct-GGUF",
              "provider": "lmstudio-community",
              "category": "coding",
              "useCase": "coding",
              "fitLevel": "excellent",
              "score": 93,
              "estimatedTps": 48.5,
              "memoryRequiredGb": 8.2,
              "memoryAvailableGb": 54.2,
              "runtime": "gguf",
              "runtimeLabel": "GGUF / LM Studio",
              "bestQuant": "Q4_K_M",
              "contextLength": 131072,
              "notes": ["Fits comfortably on this machine"],
              "lmStudioQuery": "Qwen2.5 Coder 7B"
            }
          ],
          "error": null
        }
        """.utf8
    )

    static let freeModels = Data(
        """
        {
          "providers": [
            {
              "key": "openrouter",
              "name": "OpenRouter",
              "signupUrl": "https://openrouter.ai/",
              "modelCount": 2,
              "tiers": ["free"],
              "models": [
                {
                  "id": "qwen/qwen-2.5-coder-32b-instruct",
                  "label": "Qwen 2.5 Coder 32B Instruct",
                  "tier": "free",
                  "sweScore": "63.1",
                  "context": "128K"
                }
              ]
            }
          ],
          "totalProviders": 1,
          "totalModels": 2
        }
        """.utf8
    )

    static let harnessSettings = Data(
        """
        {
          "diagram": {
            "autoRefreshSeconds": 20,
            "primaryArtifact": "docs/architecture/agentic-harness-dynamic-user-diagram.html"
          },
          "execution": {
            "loopBudget": 28,
            "retryLimit": 2,
            "retryBackoffSeconds": [1, 3],
            "promptImproverMode": "force",
            "contextSource": "hybrid",
            "hydraMode": "shadow",
            "validateMode": "all",
            "docSyncMode": "off"
          },
          "governor": {
            "cpuHighPct": 90,
            "cpuLowPct": 66,
            "modelVramGb": null,
            "perAgentOverheadGb": 0.7,
            "reservedRamGb": 8
          },
          "artifacts": {
            "promptVersion": "v1.2.0",
            "workflowVersion": "v1.1.0",
            "blueprintVersion": "v1.0.3",
            "toolBundle": "tight-default",
            "riskTier": "medium"
          }
        }
        """.utf8
    )

    static let harnessDiagram = Data(
        """
        {
          "generatedAt": "2026-03-09T14:15:00.000Z",
          "projectRoot": "/Users/shawn/Documents/gg-agentic-harness",
          "diagram": {
            "title": "GG Agentic Harness",
            "artifactPath": "/Users/shawn/Documents/gg-agentic-harness/docs/architecture/agentic-harness-dynamic-user-diagram.html",
            "artifactRelativePath": "docs/architecture/agentic-harness-dynamic-user-diagram.html",
            "autoRefreshSeconds": 20
          },
          "settings": {
            "diagram": {
              "autoRefreshSeconds": 20,
              "primaryArtifact": "docs/architecture/agentic-harness-dynamic-user-diagram.html"
            },
            "execution": {
              "loopBudget": 28,
              "retryLimit": 2,
              "retryBackoffSeconds": [1, 3],
              "promptImproverMode": "force",
              "contextSource": "hybrid",
              "hydraMode": "shadow",
              "validateMode": "all",
              "docSyncMode": "off"
            },
            "governor": {
              "cpuHighPct": 90,
              "cpuLowPct": 66,
              "modelVramGb": null,
              "perAgentOverheadGb": 0.7,
              "reservedRamGb": 8
            },
            "artifacts": {
              "promptVersion": "v1.2.0",
              "workflowVersion": "v1.1.0",
              "blueprintVersion": "v1.0.3",
              "toolBundle": "tight-default",
              "riskTier": "medium"
            }
          },
          "live": {
            "status": {
              "codex": { "available": true, "path": "/usr/local/bin/codex", "runningAcp": 1 },
              "kimi": { "available": true, "path": "provider-api", "runningAcp": 2 },
              "claude": { "available": true, "path": "/usr/local/bin/claude", "runningAcp": 1 },
              "pool": { "total": 6, "active": 4, "idle": 2 },
              "runs": { "total": 5, "running": 2 },
              "governor": {
                "timestamp": "2026-03-09T14:15:00.000Z",
                "totalRamGb": 64,
                "freeRamGb": 22.4,
                "availableRamGb": 22.4,
                "reservedRamGb": 8,
                "modelVramGb": 0,
                "perAgentOverheadGb": 0.7,
                "cpuHighPct": 90,
                "cpuLowPct": 66,
                "cpuPressure": 31.5,
                "cpuPaused": false,
                "allowedAgents": 6,
                "activeWorkers": 4,
                "queuedWorkers": 1,
                "canSpawnNow": true,
                "note": "Medium capacity",
                "reason": "usable 14.4 GB / 0.7 GB per agent => 6 workers"
              },
              "uptime": 1452.4
            },
            "runtimeDiscovery": {
              "coordinatorSelection": {
                "selected": "codex",
                "reason": "preferred runtime available",
                "requested": "auto"
              },
              "discoveries": [
                {
                  "runtime": "codex",
                  "label": "Codex",
                  "binaryPath": "/usr/local/bin/codex",
                  "authenticated": true,
                  "localCliAuth": true,
                  "directApiAvailable": false,
                  "preferredTransport": "background-terminal",
                  "summary": "Local Codex CLI available"
                }
              ]
            },
            "activity": {
              "totalRuns": 5,
              "runningRuns": 2,
              "completedRuns": 2,
              "failedRuns": 1,
              "activeWorkers": 4,
              "pendingMessages": 3,
              "latestRunId": "run-fixture",
              "latestTask": "Render the new harness tab",
              "latestStatus": "running",
              "latestUpdatedAt": "2026-03-09T14:13:00.000Z"
            },
            "workersByRole": [
              { "key": "builder", "label": "Builder", "count": 2 }
            ],
            "workersByRuntime": [
              { "key": "kimi", "label": "Kimi", "count": 2 }
            ],
            "recentRuns": [
              {
                "runId": "run-fixture",
                "task": "Render the new harness tab",
                "status": "running",
                "coordinator": "codex",
                "workerBackend": "kimi",
                "updatedAt": "2026-03-09T14:13:00.000Z"
              }
            ]
          }
        }
        """.utf8
    )
}
