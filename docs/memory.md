# Memory Architecture

Worth uses a unified global memory model. There is one central knowledge store. Every workspace draws from it. Workspaces provide overlays, not silos.

Recollect provides two tiers of storage:

- **Tier 1 — Full Pipeline:** Collections → Documents → Chunks → Entities → Relations. For structured ingestion of documents with chunking, embedding, entity extraction, and graph queries.
- **Tier 2 — Lightweight Knowledge:** Entries + Edges. For simple knowledge storage with embeddings, access tracking, and edge traversal.

Worth uses Tier 2 (lightweight) for general knowledge storage and optionally Tier 1 when ingesting codebases.

## Core Principle

```
┌─────────────────────────────────────────────────────────┐
│                  Global Knowledge Store                   │
│               (one Recollect instance, one database)          │
│                                                          │
│  All facts, preferences, patterns, skills, integrations    │
│  ever learned, stored in one place.                       │
│                                                          │
│  scope_id: "worth" (global)                              │
└──────────────────────┬──────────────────────────────────┘
                       │
                       │  Every workspace queries the same store
                       │  with optional workspace filter
                       │
         ┌─────────────┼─────────────┐
         │             │             │
    ┌────▼─────┐  ┌────▼──────┐  ┌────▼───────┐
    │ Project A  │  │ Research │  │ Personal │
    │           │  │          │  │          │
    │ overlay:  │  │ overlay:  │  │ overlay:  │
    │ - skills  │  │ - mode   │  │ - prefs  │
    │ - identity│  │ - tools  │  │ - style  │
    └───────────┘  └──────────┘  └──────────┘
```

## The Three Tiers

### Tier 0: Working Memory (ContextKeeper)

Per-workspace GenServer that holds ephemeral session state. This is the **only per-workspace state** in the entire system.

- Facts: structured triples `{entity, relation, value, confidence, source_turn}`, capped at 500
- Working set: key-value pairs with TTL and priority
- Lifetime: started on workspace activation, flushed on deactivation
- Flush target: **global** Recollect knowledge store (not a per-workspace store)

Working memory is not a memory silo. It's a staging area. When a workspace is deactivated, high-confidence facts flush into the **global** knowledge store with metadata tagging the originating workspace. This means knowledge flows freely between workspaces over time.

### Tier 1: Full Pipeline (Optional)

For large codebases, worth can ingest files through recollect's pipeline:

```
Codebase files → Recollect.ingest/3 → Documents → Chunks → Embeddings → Entities → Relations
```

Schema hierarchy:
- **Collection** — Groups documents (e.g., by repository)
- **Document** — Original content with content_hash for deduplication
- **Chunk** — Text fragment with sequence, offsets, token_count, and embedding
- **Entity** — Named entity extracted via LLM (10 types: concept, person, goal, obstacle, domain, strategy, emotion, place, event, tool)
- **Relation** — Graph edge between entities (8 types: supports, blocks, causes, relates_to, part_of, depends_on, precedes, contradicts)

This is workspace-triggered (via `/index` command) but stored globally. The scope is `worth` (global), and entries are tagged with `metadata: %{workspace: "my-project", source_type: "codebase"}` for filtering.

### Tier 2: Lightweight Knowledge (Global Store)

**One database, one scope.** All knowledge lives under `scope_id: "worth"`.

```elixir
# Storing a fact (always global scope)
Recollect.remember("User prefers conventional commits with scope prefix", %{
  scope_id: "worth",
  entry_type: "preference",
  metadata: %{
    workspace: "my-project",          # where this was learned
    skill: "git-workflow",             # what skill generated it (if any)
  }
})
```

Key Entry fields:
- `content` — The knowledge content
- `scope_id` — Always "worth" for global store
- `owner_id` — User/workspace owner UUID
- `entry_type` — "outcome", "event", "decision", "observation", "hypothesis", "note", "session_summary", "conversation_turn", "archived"
- `embedding` — Pgvector embedding for similarity search
- `confidence` — Float 0.0-1.0, decays over time via half_life_days
- `half_life_days` — Decay rate (default 7.0 days)
- `pinned` — Boolean, prevents decay
- `emotional_valence` — "neutral", "positive", "negative", "critical"
- `schema_fit` — Float 0.0-1.0, how well the entry fits structured knowledge patterns
- `outcome_score` — Integer, derived from outcome feedback signals
- `context_hints` — Map capturing git repo, path, OS for context-aware retrieval
- `metadata` — User-defined map for workspace/skill provenance

Entry-to-entry relationships via Edges:
- `relation` — "leads_to", "supports", "contradicts", "derived_from", "supersedes", "related_to"
- `weight` — Float 0.0-1.0 for graph traversal ranking

```elixir
# Retrieving context (global search, optional workspace boost)
Recollect.search("how should I commit?", %{
  scope_id: "worth",
  # workspace boost: entries tagged with current workspace get higher relevance
})
```

All retrieval is global by default. The workspace context provides **boosting**, not filtering. When working in `my-project`, entries tagged with `workspace: "my-project"` get a relevance boost via Recollect's outcome feedback system, but entries from other workspaces are still visible.

## Memory Flow Per Turn

```
1. User sends message in workspace "my-project"
       │
       ▼
2. Brain assembles context:
   a. System prompt (worth core + workspace identity + always-loaded skills)
   b. Memory retrieval → Recollect.search(query, scope_id: "worth")
   c. Working memory → ContextKeeper for "my-project" (ephemeral session state)
   d. Merge: Recollect results (global) + ContextKeeper facts (session-local)
       │
       ▼
3. Agentic runs the loop with merged context
       │
       ▼
4. After response, FactExtractor extracts facts
       │
       ▼
5. Facts stored:
   a. ContextKeeper (ephemeral, session-local)
   b. Recollect.remember/2 (persistent, global, tagged with workspace metadata)
       │
       ▼
6. Outcome feedback:
   - Recollect.Outcome.good("worth") → boosts recently retrieved entries
   - Recollect.Outcome.bad("worth") → reduces half-life of bad entries
```

## Workspace Overlays

A workspace overlay is not a separate memory store. It is a **context assembly strategy** that determines what goes into the system prompt for a given workspace.

```
System Prompt Assembly for "my-project":

┌─────────────────────────────────────────────────┐
│  1. Worth Core Prompt                            │  (global)
│     "You are worth, a terminal AI assistant..."   │
├─────────────────────────────────────────────────┤
│  2. Workspace Identity                            │  (overlay)
│     IDENTITY.md + AGENTS.md from my-project     │
├─────────────────────────────────────────────────┤
│  3. Always-Loaded Skills                         │  (overlay)
│     agent-tools + human-agency + tool-discovery   │
├─────────────────────────────────────────────────┤
│  4. On-Demand Skill Listings                    │  (overlay)
│     Names of skills installed in this workspace  │
├─────────────────────────────────────────────────┤
│  5. Memory Context (from global store)            │  (global + overlay boost)
│     Recollect.search results, workspace-boosted     │
├─────────────────────────────────────────────────┤
│  6. Working Memory (session-local)               │  (overlay)
│     ContextKeeper facts for this workspace        │
├─────────────────────────────────────────────────┤
│  7. Workspace Snapshot                            │  (overlay)
│     File tree, key files, project structure     │
└─────────────────────────────────────────────────┘
```

Items 2, 3, 4, 6, 7 are workspace-specific overlays. Items 1 and 5 are global.

## Global Integrations

### MCP Servers

MCP servers are global resources. Configured once in `~/.worth/config.exs`, available to all workspaces:

```elixir
# ~/.worth/config.exs
config :worth,
  mcp: [
    servers: %{
      github: %{type: :stdio, command: "npx", args: ["-y", "@anthropic/mcp-server-github"], ...},
      postgres: %{type: :stdio, command: "npx", args: ["-y", "@anthropic/mcp-server-postgres"], ...},
      brave: %{type: :streamable_http, url: "https://api.brave.com/mcp", ...}
    }
  ]
```

Workspaces can override MCP config for project-specific needs (e.g., a different database connection):

```json
// my-project/.worth/mcp.json
{
  "mcpServers": {
    "postgres": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-postgres", "postgresql://localhost/myapp"]
    }
  }
}
```

This override is **merge-style**: workspace config wins for conflicting server names, everything else stays global.

### Skills

Skills are global artifacts stored in the global skills directory with optional workspace-specific installations:

```
~/.worth/
├── skills/                    # Global skills (available everywhere)
│   ├── git-workflow/
│   │   └── SKILL.md
│   ├── elixir-conventions/
│   │   └── SKILL.md
│   └── learned/               # Agent-created skills (global)
│       └── extract-validation/
│           └── SKILL.md
│
└── workspaces/
    └── my-project/
        ├── skills/                # Workspace-specific skill installations
        │   └── my-project-conventions/
        │       └── SKILL.md
        └── .worth/
            └── skills.json        # Workspace skill manifest
```

`skills.json` specifies which global skills are active in this workspace and which are overridden:

```json
{
  "active": ["git-workflow", "elixir-conventions", "tool-discovery"],
  "override": {
    "elixir-conventions": "my-project-conventions"
  }
}
```

Skills learned by the agent (trust level `learned`) are always stored globally in `~/.worth/skills/learned/` because the patterns they capture may be useful across workspaces.

### Memory Entries

All Recollect knowledge entries use `scope_id: "worth"`. Workspace provenance is stored in metadata:

```elixir
%{
  scope_id: "worth",
  content: "This project uses Ecto 3.12 with the new Ash integration",
  entry_type: "convention",
  metadata: %{
    workspace: "my-project",
    source: "fact_extractor",
    confidence: 0.9,
    created_at: "2026-04-07T10:00:00Z"
  }
}
```

When retrieving context for workspace "my-project", the memory manager:

1. Searches globally (scope_id: "worth")
2. Sorts results: workspace-tagged entries get a relevance boost
3. All results are candidates, not just workspace-tagged ones

This means a convention learned in one workspace naturally surfaces in others when relevant.

## Outcome Feedback (Global)

```elixir
# After a successful task in ANY workspace:
Recollect.Outcome.good("worth")
# Boosts half-life of ALL recently retrieved entries, regardless of which workspace they came from

# After a failed task:
Recollect.Outcome.bad("worth")
# Reduces half-life of entries that were just retrieved (these were the ones that led to the bad outcome)
```

The outcome signal is global because memory quality is global. A fact that was helpful in workspace A is also helpful in workspace B.

## Workspace Deactivation Flush

When switching workspaces or exiting worth:

```
ContextKeeper (my-project)
    │
    ├──► High-confidence facts → Recollect.remember/2 (global store, tagged with workspace: "my-project")
    │
    └──► Persistent working set entries → Recollect.remember/2 (global store)
```

ContextKeeper is terminated. No per-workspace persistent state remains. Everything goes to the global store.

## Migration from Per-Workspace Scoping

The original design used per-workspace `scope_id` (e.g., `scope_id: workspace:my-project`). The unified model uses `scope_id: "worth"` everywhere with workspace provenance in metadata.

Changes required in Agentic callbacks:

```elixir
# Before (per-workspace):
knowledge_search: fn query, opts ->
  Recollect.search(query, Keyword.put(opts, :scope_id, "workspace:#{brain.workspace_id}))

# After (global):
knowledge_search: fn query, opts ->
  Recollect.search(query, Keyword.put(opts, :scope_id, "worth"))

# Before (per-workspace):
knowledge_create: fn params ->
  Recollect.remember(params.content, Keyword.put(params, :scope_id, "workspace:#{brain.workspace_id}"))

# After (global with workspace tagging):
knowledge_create: fn params ->
  Recollect.remember(params.content, %{
    scope_id: "worth",
    content: params.content,
    entry_type: params[:entry_type] || "fact",
    metadata: Map.put(params[:metadata] || %{}, :workspace, brain.workspace_path)
  })
```

This is a one-line change in the brain's callback setup. Recollect doesn't care about scope semantics -- it's just a string field for filtering.

## Skill-Specific Memory

Skills can request memory scoped to themselves. When the skill-lifecycle system evaluates a skill, it queries:

```elixir
Recollect.search("skill:git-workflow outcomes", %{
  scope_id: "worth",
  metadata_filter: %{skill: "git-workflow"}
})
```

This surfaces all knowledge entries created while the git-workflow skill was active, across all workspaces. This is how the refinement system measures skill quality globally.

## Benefits of the Unified Model

| Aspect | Per-Workspace (old) | Global (new) |
|--------|-------------------|-------------|
| Knowledge transfer | Manual (user must tell each workspace) | Automatic (global availability) |
| Skill learning | Per-workspace silos | Global patterns benefit all workspaces |
| MCP integrations | Per-workspace config duplication | Configure once, use everywhere |
| Memory decay | Independent per workspace | Shared relevance signals |
| Outcome feedback | Per-workspace scope | Cross-pollinates quality signals |
| Disk usage | Multiple knowledge stores | One database |
| Setup complexity | Configure per workspace | One config file |

## Filesystem Layout (Unified)

```
~/.worth/
├── worth.db                          # Single PostgreSQL database (recollect tables)
├── config.exs                        # Global config (LLM, MCP servers, memory, UI)
├── skills/                            # Global skill library
│   ├── git-workflow/
│   │   └── SKILL.md
│   ├── elixir-conventions/
│   │   └── SKILL.md
│   └── learned/                       # Agent-created skills
│       └── extract-validation/
│           └── SKILL.md
├── workspaces/
│   ├── my-project/
│   │   ├── IDENTITY.md               # Workspace personality (overlay)
│   │   ├── AGENTS.md                 # Project instructions (overlay)
│   │   ├── .worth/
│   │   │   ├── transcript.jsonl      # Session transcript (per-workspace)
│   │   │   ├── skills.json            # Skill manifest (overlay)
│   │   │   └── plans/                # Saved plans
│   │   └── mcp.json                  # MCP overrides (merge-style)
│   ├── research/
│   │   ├── IDENTITY.md
│   │   ├── .worth/
│   │   │   ├── transcript.jsonl
│   │   │   └── skills.json
│   │   └── mcp.json
│   └── personal/
│       ├── IDENTITY.md
│       ├── .worth/
│       │   ├── transcript.jsonl
│       │   └── skills.json
│       └── mcp.json
```

Key differences from the old design:
- No per-workspace `knowledge.jsonl` (everything goes to global recollect)
- No per-workspace `MEMORY.md` flush target (flush goes to global recollect)
- Skills are in `~/.worth/skills/` (global), not per-workspace
- `.worth/skills.json` is a manifest (what's active), not a storage location
- `mcp.json` is merge-style overrides, not standalone config
