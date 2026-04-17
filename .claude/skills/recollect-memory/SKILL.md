---
name: recollect-memory
description: "Use this skill when working with the Recollect Elixir memory engine. Consult for knowledge storage, search, document pipelines, working memory, session handoff, maintenance, and extension points."
metadata:
  managed-by: usage-rules
---


<!-- usage-rules-skill-start -->
## Overview

Recollect is a pluggable memory engine for Elixir (~> 1.17). It provides three
tiers: working memory (session-scoped), lightweight knowledge (store-embed-search),
and a full document pipeline (chunk, embed, extract, graph).

## Quick Reference

### Critical: No Top-Level Module

All API lives on submodules:

- `Recollect.Knowledge.remember/2` — store entries
- `Recollect.Knowledge.forget/1` — delete entries
- `Recollect.Knowledge.connect/4` — link entries
- `Recollect.Search.search/2` — hybrid search
- `Recollect.Search.ContextFormatter.format/1` — format for LLM
- `Recollect.Pipeline.Ingester.ingest/3` — ingest documents
- `Recollect.Pipeline.process/2` — run full pipeline
- `Recollect.Maintenance.Decay.run/1` — archive stale entries
- `Recollect.Maintenance.Reembed.run/1` — re-embed with new model
- `Recollect.Consolidation.run/1` — sleep consolidation
- `Recollect.Invalidation.invalidate/3` — weaken deprecated memories
- `Recollect.WorkingMemory.push/3` — session-scoped notes
- `Recollect.Handoff.create/2` — session continuity
- `Recollect.Outcome.good/1` / `bad/1` — feedback on recalled memories
- `Recollect.Export.export_all/2` / `Recollect.Import.import_all/2` — portability

### Embedding Providers

- `Recollect.Embedding.Local` — Default, Bumblebee, 384 dims, no API key
- `Recollect.Embedding.OpenRouter` — API, 1536 dims

No OpenAI or Ollama providers exist.

### Database Adapters

- `Recollect.DatabaseAdapter.Postgres` (default, requires pgvector)
- `Recollect.DatabaseAdapter.SQLiteVec` (SQLite3 + sqlite-vec)
- `Recollect.DatabaseAdapter.LibSQL`

### Configuration

Required: `config :recollect, :repo`. Everything else has defaults.
Use `:credentials_fn` for API keys, never static config in production.

## References

See the reference files for detailed information:
- [knowledge.md](references/knowledge.md) — Knowledge API, entry types, lifecycle
- [pipeline.md](references/pipeline.md) — Document ingestion and processing
- [search.md](references/search.md) — Search, context formatting, completion
- [embedding.md](references/embedding.md) — Providers, dimensions, credentials
- [maintenance.md](references/maintenance.md) — Decay, reembed, consolidation, invalidation
- [extension-points.md](references/extension-points.md) — All behaviours and extension APIs
<!-- usage-rules-skill-end -->
