---
name: ai-engineering-patterns
description: AI engineering patterns relevant to GGV3 - agentic RAG, financial analysis, MCP infrastructure, context engineering, and multi-agent deep research. Source patterns from patchy631/ai-engineering-hub.
trigger: RAG implementation, AI search, financial analysis, MCP server, context engineering, knowledge graph, agent memory, deep research
---

# AI Engineering Patterns for GGV3

Curated patterns from patchy631/ai-engineering-hub relevant to the GearGrind tactical marketplace.

## Agentic RAG (Retrieval-Augmented Generation)

### When to use
- Product search & discovery with semantic understanding
- Customer support with document-aware responses
- Content moderation with context-aware analysis

### Pattern
1. **Document Ingestion** → Chunk + embed documents
2. **Query Processing** → Analyze intent + generate search queries
3. **Retrieval** → Vector search + keyword search (hybrid)
4. **Agent Decision** → If retrieval insufficient, fall back to web search
5. **Response Generation** → Synthesize answer from retrieved context

### Key Implementation Details
- Use embedding models (e.g., OpenAI ada-002, Cohere embed) for vector representation
- Hybrid search: combine vector similarity with BM25 keyword matching
- Implement re-ranking to improve retrieval relevance
- Add guardrails for hallucination prevention

## Financial Analysis Patterns

### When to use
- Auction pricing intelligence
- Market trend analysis for tactical gear
- Revenue forecasting and reporting

### Pattern
- LLM-powered analysis with structured output (TypeScript interfaces)
- MCP server for financial data access
- Chart generation from computed metrics

## Context Engineering

### When to use
- Long-running agent sessions
- Multi-step complex tasks
- Knowledge persistence across conversations

### Pattern
1. **Context Collection** → Gather relevant docs, conversation history, tool outputs
2. **Context Compression** → Summarize, prioritize, trim to fit window
3. **Memory Persistence** → Store important findings in knowledge graph (Graphiti/Zep)
4. **Context Injection** → Load relevant context at each step

## MCP Infrastructure

### When to use
- Connecting to external data sources (DB, APIs, services)
- Providing tools to AI agents
- Unified interface for heterogeneous data

### Pattern
- Define tools with typed schemas
- Implement resource providers for data access
- Use server-sent events for streaming responses
- MindsDB pattern: unified MCP for all data sources

## Multi-Agent Deep Research

### When to use
- Complex investigation tasks
- Market research for tactical gear categories
- Competitive analysis

### Pattern
1. **Query Decomposition** → Break complex question into sub-queries
2. **Parallel Research** → Multiple agents research different aspects
3. **Source Evaluation** → Verify and rank sources by reliability
4. **Synthesis** → Combine findings into structured report
5. **Iteration** → Identify gaps, generate follow-up queries
