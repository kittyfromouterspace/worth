# Architecture Overview

## System Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Worth (BEAM Node)                      │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐                   │
│  │  LiveView     │    │  Brain       │                   │
│  │  (Phoenix)    │◄──►│  (GenServer) │                   │
│  │              │    │              │                     │
│  │  - Chat      │    │  - Agentic   │                    │
│  │  - Input     │    │    .run/1    │                     │
│  │  - PubSub    │    │  - Recollect     │                    │
│  │              │    │  - Skills    │                    │
│  └──────────────┘    │  - Workspaces│                    │
│                      │  - MCP       │                    │
│                      └──────┬───────┘                    │
│                             │                            │
│                      ┌──────▼───────┐                    │
│                      │  Agentic     │                    │
│                      │  Loop Engine │                    │
│                      │              │                    │
│                      │  Stages:     │                    │
│                      │  ContextGuard│                    │
│                      │  LLMCall     │                    │
│                      │  ToolExecutor│                    │
│                      │  CommitGate  │                    │
│                      └──────┬───────┘                    │
│                             │                            │
│               ┌─────────────┼─────────────┐              │
│               │             │             │              │
│        ┌──────▼──┐  ┌──────▼──┐  ┌──────▼──┐           │
│        │ Recollect   │  │ File    │  │ Skills  │  │ MCP     │           │
│        │ Memory  │  │ Tools   │  │ System  │  │ Servers │            │
│        └──────┬──┘  └─────────┘  └─────────┘  └─────────┘           │
│               │                                           │
│        ┌──────▼──┐                                       │
│        │Database │                                       │
│        │(pg/lib) │                                       │
│        └─────────┘                                       │
└─────────────────────────────────────────────────────────┘
```

## Technical Stack

| Layer | Library | Role |
|-------|---------|------|
| UI | Phoenix LiveView + Bandit | Web UI served over HTTP, HEEx templates, real-time via Phoenix channels |
| Agent Runtime | `agentic` (local path) | Composable pipeline loop engine with stages, profiles, tools |
| Memory | `recollect` (local path, via agentic) | Three-tier memory: working memory, knowledge graph, vector search |
| Database | PostgreSQL + pgvector or libSQL | Database for recollect (adapter selected at compile time) |
| MCP | `hermes_mcp` (~> 0.14.1) | MCP client/server, JSON-RPC 2.0, stdio + Streamable HTTP |
| HTTP | `req` (~> 0.5) | LLM API calls, embedding API calls, GitHub API |
| LLM | OpenRouter / Anthropic / OpenAI | Configurable provider routing |
| PubSub | `phoenix_pubsub` (~> 2.1) | Cross-component event broadcasting (LiveView + Brain) |
| Domain Model | `ash` (~> 3.23) + `ash_postgres` (~> 2.8) | Skill lifecycle, kits, workspaces -- state machines, policies, code interfaces |
| Observability | `telemetry` + `telemetry_metrics` | Metrics: cost, tokens, latency, tool calls |
| Config | `nimble_options` | Compile-time config schema validation |
| CLI | `owl` | Rich terminal output outside the web UI |
| Web Server | `bandit` | HTTP server for Phoenix LiveView |

## Dependency Graph

```
worth
├── phoenix           (hex, ~> 1.7)
├── phoenix_live_view (hex, ~> 1.0)
├── bandit            (hex, ~> 1.0)
├── agentic          (path: ../agentic)
│   └── recollect         (path: ../recollect, transitive)
│       ├── ecto_sql + postgrex (or libsql)
│       └── req
├── hermes_mcp        (hex, ~0.14.1) -- also transitive via agentic
│   ├── finch         (HTTP client for Streamable HTTP transport)
│   ├── peri          (JSON Schema validation)
│   └── jason
├── phoenix_pubsub    (hex, ~> 2.1)
├── ash               (hex, ~> 3.23)
├── ash_postgres      (hex, ~> 2.8)
├── telemetry         (hex) -- already transitive via recollect
├── telemetry_metrics (hex)
├── nimble_options    (hex)
├── owl               (hex)
└── ecto_sql + postgrex (or libsql)  (worth owns the Repo)
```

## Key Architectural Principles

### One Brain

A single GenServer coordinates the agent loop. It delegates state to specialized stores (ETS, :persistent_term, PostgreSQL) rather than holding everything in its GenServer state. See [beam-architecture.md](beam-architecture.md) for the supervision tree and storage strategy.

### One Memory

One Recollect instance, one database, one `scope_id: "worth"`. Workspaces provide context boosts, not memory silos. See [memory.md](memory.md).

### Lazy Discovery

Tools, skills, and MCP integrations use progressive disclosure. Metadata is loaded always; full content is loaded on demand. This keeps token usage low regardless of how many tools/skills/integrations are installed.

### Phoenix LiveView UI

The UI follows Phoenix LiveView patterns: `mount/3`, `handle_event/3`, `handle_info/2`. The Brain and UI communicate via PubSub events. Agent streaming events flow asynchronously to keep the UI responsive.

### Callback Composition

Agentic's callback system provides clean separation. Worth provides integration callbacks (LLM, memory, tools, streaming) without modifying the loop engine. This means agentic improvements flow into worth automatically.

### Supervision & Fault Tolerance

Each subsystem has its own supervisor. An MCP server crash does not kill the web UI. A memory flush failure does not kill the brain. See [beam-architecture.md](beam-architecture.md) for the full supervision tree.

### Observability

All subsystems emit `:telemetry` events. Worth consumes events from agentic (`[:agentic, ...]`), recollect (`[:recollect, ...]`), and its own (`[:worth, ...]`). Metrics drive the LiveView status display (cost, tokens, latency) without polling. See [beam-architecture.md](beam-architecture.md) for the event hierarchy.
