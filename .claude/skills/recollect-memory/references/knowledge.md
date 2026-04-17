# Knowledge API (Tier 2)

## `Recollect.Knowledge.remember/2`

Store a knowledge entry with auto-embedding.

```elixir
{:ok, entry} = Recollect.Knowledge.remember(content,
  scope_id: scope_id,       # required
  owner_id: owner_id,       # required
  entry_type: "note",       # default: "note"
  auto_classify: false,     # LLM-free pattern matching
  tags: [],                 # list of strings
  summary: nil,             # optional summary
  source: "system",         # "agent" | "system" | "user"
  source_id: nil,           # external reference
  metadata: %{},            # arbitrary map
  confidence: 1.0,          # 0.0-1.0
  half_life_days: 7.0,      # decay rate
  pinned: false             # exempt from decay
)
```

`auto_classify: true` uses `Recollect.Classification.classify/2` (LLM-free
pattern matching) to detect the entry type automatically.

Context is auto-captured via `Recollect.Context.Detector.detect/0` unless
`context_hints` is provided in opts.

## `Recollect.Knowledge.forget/1`

Delete a knowledge entry by ID. Returns `{:ok, entry}` or `{:error, :not_found}`.

## `Recollect.Knowledge.connect/4`

Create an edge between two entries.

```elixir
{:ok, edge} = Recollect.Knowledge.connect(source_id, target_id, relation, weight: 1.0)
```

`relation` must be one of the edge relation types: `leads_to`, `supports`,
`contradicts`, `derived_from`, `supersedes`, `related_to`.

## `Recollect.Knowledge.recent/2`

Get recent entries for a scope.

```elixir
entries = Recollect.Knowledge.recent(scope_id, limit: 20)
```

## `Recollect.Knowledge.check_contradiction/3`

Check if content contradicts existing knowledge in a scope.

```elixir
:ok                                  # no conflicts
{:conflict, [%{existing: "...", type: :attribution_conflict, claim: ...}]}
{:conflict, [%{existing: "...", type: :status_conflict, claim: ...}]}
```

Uses `Recollect.Classification.extract_claims/1` to extract entity claims
and checks against entries with `confidence > 0.3`.

## `Recollect.Knowledge.supersede/4`

Demote old entries matching an entity+relation pattern by setting confidence
to 0.1.

```elixir
Recollect.Knowledge.supersede(scope_id, "webpack", "build tool", "vite")
```

## Memory Lifecycle Fields

Entries have several fields that drive the memory lifecycle:

- `confidence` (0.0-1.0) — Overall confidence, decayed by `half_life_days`
- `half_life_days` — Exponential decay rate. Default 7.0. Adjusted by
  `Recollect.SchemaFit` on creation.
- `access_count` / `last_accessed_at` — Bumped on retrieval via search
- `pinned` — If true, exempt from decay and consolidation removal
- `emotional_valence` — `"neutral"`, `"positive"`, `"negative"`, `"critical"`.
  Inferred via `Recollect.Valence.infer/1`.
- `schema_fit` (0.0-1.0) — How well content fits existing patterns.
  Computed by `Recollect.SchemaFit.compute/3`.
- `confidence_state` — `"active"`, `"stale"`, `"verified"`. Updated by
  outcome feedback.
- `outcome_score` — Set by `Recollect.Outcome.apply/2` feedback.
