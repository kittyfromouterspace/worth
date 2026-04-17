# Search

## `Recollect.Search.search/2`

Hybrid search combining vector similarity and graph traversal.

```elixir
{:ok, context_pack} = Recollect.Search.search(query, opts)
```

Options:
- `:tier` — `:both` (default), `:full` (Tier 1 only), `:lightweight` (Tier 2 only)
- `:hops` — Graph expansion depth (default: `1`)
- `:limit` — Max results (default varies by implementation)
- `:owner_id` — Owner UUID (required for graph expansion)
- `:scope_id` — Scope UUID
- `:filters` — Map with `entry_type`, `temporal` (`:recent` = last 30 days), `confidence_min`

Returns a context pack map:

```elixir
%{
  chunks: [...],          # Tier 1 chunk results with similarity scores
  entries: [...],         # Tier 2 entry results with similarity scores
  related_entries: [...],  # Entries found via edge traversal
  entities: [...],        # Extracted entities from knowledge graph
  relations: [...],       # Graph relations between entities
  query: "..."
}
```

Each result is a map with string keys: `id`, `content`, `score`, `entry_type`,
etc.

## `Recollect.Search.ContextFormatter.format/1`

Format a context pack into readable text for LLM system prompt injection.

```elixir
context_text = Recollect.Search.ContextFormatter.format(context_pack)
```

Produces sections: `## Relevant Memory Chunks`, `## Relevant Knowledge`,
`## Related Knowledge`, `## Known Entities`, `## Known Relationships`.

Returns an empty string if the context pack has no results.

## `Recollect.Search.Completion.complete/2`

LLM-augmented retrieval that combines search with LLM reasoning.

```elixir
{:ok, %{answer: answer, context: context_pack}} =
  Recollect.Search.Completion.complete(question,
    owner_id: user_id,
    scope_id: scope_id,
    llm_fn: fn messages -> {:ok, "answer"} end,
    system_prompt: nil,   # optional override
    limit: 10,
    hops: 2               # overrides default 1
  )
```

`llm_fn` is required. Recollect never calls LLMs directly for completion.
