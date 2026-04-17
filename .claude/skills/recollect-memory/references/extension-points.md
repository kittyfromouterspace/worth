# Extension Points

## `Recollect.EmbeddingProvider`

Behaviour for embedding backends. Callbacks:

- `dimensions(opts)` — Number of embedding dimensions (required)
- `generate(texts, opts)` — Batch embed, returns `{:ok, [[float()]]}` (required)
- `embed(text, opts)` — Single embed, returns `{:ok, [float()]}` (optional)
- `model_id(opts)` — Model identifier for provenance (optional)

## `Recollect.ExtractionProvider`

Behaviour for entity/relation extraction. Callbacks:

- `extract(text, opts)` — Returns `{:ok, %{entities: [...], relations: [...]}}`

## `Recollect.GraphStore`

Behaviour for graph backends (default: `Recollect.Graph.PostgresGraph`).
Callbacks:

- `get_neighbors(owner_id, entity_id, hops)` — Returns `{:ok, [entity]}`
- `get_relations(owner_id, entity_id)` — Returns `{:ok, [relation]}`

## `Recollect.DatabaseAdapter`

Behaviour for database-specific implementations. Key callbacks:

- `vector_type(dimensions)` — SQL type for vector column
- `vector_ecto_type()` — Ecto type atom for embedding fields
- `format_embedding(list)` — Format embedding for insertion
- `vector_index_sql(table, column, opts)` — SQL for creating vector index
- `vector_distance_sql(column, query_ref)` — Cosine distance SQL
- `vector_similarity_sql(column, query_ref)` — Cosine similarity SQL
- `create_vector_extension_sql()` — SQL for vector extension (or nil)
- `uuid_type()` — `:binary_id` or `:uuid`
- `format_uuid(uuid)` — Format UUID for insertion
- `dialect()` — `:postgres | :sqlite | :libsql`
- `placeholder(n)` — `$1` or `?`
- `requires_pgvector?()` — Boolean
- `repo_adapter()` — Ecto adapter module
- `parse_embedding(data)` — DB format to list (optional)
- `top_k_sql(table, index, query, k)` — Approximate search (optional)
- `supports_recursive_ctes?()` — Boolean
- `supports_vector_index?()` — Boolean

## `Recollect.Learner`

Behaviour for learning sources. Callbacks:

- `source()` — Atom identifying the source
- `fetch_since(since, scope_id)` — Returns `{:ok, [events]}`
- `extract(event)` — Returns `{:ok, %{content:, entry_type:, ...}}` or `{:skip, reason}`
- `detect_patterns(events)` — Returns pattern list (can return `[]`)

Built-in learners: `Recollect.Learner.Git`, `Recollect.Learner.ClaudeCode`,
`Recollect.Learner.OpenCode`.

## Working Memory

`Recollect.WorkingMemory` is a GenServer-per-scope bounded buffer. No
behaviour to implement — it's used directly.

Config: `config :recollect, :working_memory, max_entries_per_scope: 20`

## Handoff

`Recollect.Handoff` stores session context in the `recollect_handoffs` table.
No behaviour — used directly.

## Export / Import

`Recollect.Export` and `Recollect.Import` handle JSONL portability. No
behaviour — used directly.

## Telemetry

All operations emit `:telemetry` events. Attach handlers to monitor:
`[:recollect, :remember, :start/:stop]`, `[:recollect, :search, :start/:stop]`,
`[:recollect, :pipeline, :start/:stop]`, `[:recollect, :embed, :stop]`,
`[:recollect, :decay, :stop]`, `[:recollect, :learning, :start/:stop]`,
`[:recollect, :consolidation, :stop]`, `[:recollect, :invalidation, :start/:stop]`,
`[:recollect, :completion, :start/:stop]`, `[:recollect, :handoff, ...]`,
`[:recollect, :mipmap, :generate, :stop]`.

All `:stop` events include `%{duration: native_time}`.
