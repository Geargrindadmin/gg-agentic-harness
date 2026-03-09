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
}
