# Rules for working with Recollect

Recollect is a pluggable memory engine for Elixir applications (~> 1.17). It
provides three tiers: working memory (session-scoped), lightweight knowledge
(store-embed-search), and a full document pipeline (chunk, embed, extract,
graph). Read the source moduledocs and type specs before attempting to use its
features. Do not assume prior knowledge of the framework or its conventions.

## Critical Conventions

### No Top-Level Recollect Module

There is no `Recollect.remember/2` or `Recollect.search/2`. All public API
lives on submodules. Use the correct module paths:

```elixir
# CORRECT
Recollect.Knowledge.remember(content, opts)
Recollect.Search.search(query, opts)
Recollect.Search.ContextFormatter.format(context_pack)
Recollect.Pipeline.Ingester.ingest(title, content, opts)
Recollect.Pipeline.process(document, opts)
Recollect.Maintenance.Decay.run(opts)
Recollect.Maintenance.Reembed.run(opts)
Recollect.Consolidation.run(opts)
Recollect.Invalidation.invalidate(scope_id, pattern, opts)

# WRONG
Recollect.remember(content, opts)
Recollect.search(query, opts)
Recollect.build_context(results)
Recollect.ingest(title, content, opts)
Recollect.process(document)
Recollect.decay()
Recollect.reembed()
```

### Owner and Scope on Every Schema

All schemas carry both `owner_id` and `scope_id` (UUID columns). Your app
decides what they map to. `owner_id` is the user; `scope_id` is the
workspace/project. Pass them in opts, never hardcode.

### Tuple Returns

All API functions return `{:ok, result}` or `{:error, reason}` tuples. Never
raise on expected error paths. Pattern match on the return value.

### Embedding Providers

Only two providers exist. Do not invent others:

- `Recollect.Embedding.Local` — Default. Uses Bumblebee with
  `all-MiniLM-L6-v2` (384 dims). No API key needed.
- `Recollect.Embedding.OpenRouter` — API-based. Default model is
  `openai/text-embedding-3-small` (1536 dims).

There is no `Recollect.Embedding.OpenAI` or `Recollect.Embedding.Ollama`.

### Database Adapters

Three adapters exist. Configure via `config :recollect, :database_adapter`:

- `Recollect.DatabaseAdapter.Postgres` — Default. Requires pgvector.
- `Recollect.DatabaseAdapter.SQLiteVec` — SQLite3 + sqlite-vec.
- `Recollect.DatabaseAdapter.LibSQL` — libSQL with native vector support.

### Source Field Validation

Entry `source` field must be one of: `"agent"`, `"system"`, `"user"`.

### Entry Type Constants

Use these exact strings for `entry_type`:

`outcome`, `event`, `decision`, `observation`, `hypothesis`, `note`,
`session_summary`, `conversation_turn`, `preference`, `milestone`, `problem`,
`emotional`, `archived`

### Entity and Relation Types

Entity types: `concept`, `person`, `goal`, `obstacle`, `domain`, `strategy`,
`emotion`, `place`, `event`, `tool`

Relation types: `supports`, `blocks`, `causes`, `relates_to`, `part_of`,
`depends_on`, `precedes`, `contradicts`

Edge relation types: `leads_to`, `supports`, `contradicts`, `derived_from`,
`supersedes`, `related_to`

## Configuration

All config is via `config :recollect, ...` in the host application. Recollect
never starts its own Repo, never stores API keys, and never makes assumptions
about the host app's secret management.

Required: `:repo`. Everything else has defaults.

Embedding credentials use a `:credentials_fn` callback that returns a map or
`:disabled`. Never pass raw API keys as static config in production.

## Tier Quick Reference

- **Tier 0** (`Recollect.WorkingMemory`) — Session-scoped, no embeddings,
  importance-based eviction
- **Tier 1** (`Recollect.Pipeline`) — Document ingestion: chunk, embed,
  extract entities, graph
- **Tier 2** (`Recollect.Knowledge`) — Simple remember/forget/search with
  edges

## Subtopics

- `usage-rules/knowledge.md` — Knowledge API (Tier 2): remember, forget,
  connect, search, contradiction detection
- `usage-rules/pipeline.md` — Full pipeline (Tier 1): ingest, process,
  chunking, extraction
- `usage-rules/search.md` — Search, context formatting, LLM completion
- `usage-rules/embedding.md` — Embedding providers, dimensions, credentials
- `usage-rules/maintenance.md` — Decay, reembed, consolidation, invalidation
- `usage-rules/extension-points.md` — Behaviours: EmbeddingProvider,
  ExtractionProvider, GraphStore, DatabaseAdapter, Learner
