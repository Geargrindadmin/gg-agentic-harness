---
name: swarm-orchestration
description: Multi-agent swarm orchestration patterns from kyegomez/swarms. Sequential, Concurrent, MoA, GroupChat, Hierarchical, and SwarmRouter architectures for coordinating multiple agents.
trigger: multi-agent orchestration, swarm coordination, agent workflow, parallel agents, sequential workflow, agent communication
---

# Swarm Orchestration Patterns

Reference patterns extracted from kyegomez/swarms — The Enterprise-Grade Multi-Agent Orchestration Framework.

## Architecture Patterns

### SequentialWorkflow
Agents execute tasks in linear order, each building on the previous output.
- Use when: Tasks have strict dependencies
- Pattern: Agent A → Agent B → Agent C

### ConcurrentWorkflow
Agents execute tasks in parallel, results aggregated.
- Use when: Independent tasks can run simultaneously
- Pattern: Fan-out → parallel execution → fan-in

### AgentRearrange
Dynamic agent routing based on a topology string (e.g., `"A → B, A → C, B → D, C → D"`).
- Use when: Complex DAG workflows with conditional branching

### SwarmRouter (Universal Orchestrator)
Routes tasks to the optimal swarm type automatically.
- Use when: You want automatic orchestration selection based on task characteristics

### MixtureOfAgents (MoA)
Multiple agents provide independent assessments, synthesized by a coordinator.
- Use when: Decisions require diverse perspectives (board meetings, peer review)

### GroupChat
Agents converse in a shared context, building on each other's contributions.
- Use when: Collaborative problem-solving, brainstorming

### HierarchicalSwarm
Tree-structured agent hierarchy. Manager agents delegate to specialist sub-agents.
- Use when: Large-scale tasks with clear domain separation

### HeavySwarm
All agents process full context and vote on outputs.
- Use when: Critical decisions requiring consensus

## Communication Protocols

- **Agent-to-Agent**: Direct message passing with typed interfaces
- **Broadcast**: One-to-many task distribution
- **Coordinator Pattern**: Central coordinator manages agent lifecycle
- **AOP (Agent Orchestration Protocol)**: Standardized agent discovery and communication

## GGV3 Application

For GearGrind, use these patterns in the existing Agent Orchestration system:
- **Board meetings** → MixtureOfAgents (CA, CPO, CSO, COO, CXO)
- **Implementation** → SequentialWorkflow (Research → Plan → Implement → Test → Ship)
- **Multi-domain tasks** → HierarchicalSwarm (Coordinator → specialist agents)
- **Code review** → ConcurrentWorkflow (Security + Quality + Design agents in parallel)
