# Maintenance

## Decay

### `Recollect.Maintenance.Decay.run/1`

Archives stale entries. Entries not accessed in N days with fewer than M
accesses are archived (entry_type set to `"archived"`).

```elixir
{:ok, count} = Recollect.Maintenance.Decay.run(
  max_age_days: 90,     # default: 90
  min_access_count: 3   # default: 3
)
```

Pinned entries are never archived.

## Reembed

### `Recollect.Maintenance.Reembed.run/1`

Re-embed rows using the configured embedding provider. Tracks provenance via
`embedding_model_id`.

```elixir
{:ok, count} = Recollect.Maintenance.Reembed.run(
  batch_size: 100,       # default: 100
  concurrency: 2,        # default: 2
  tables: ["recollect_chunks", "recollect_entries", "recollect_entities"],
  scope: :nil_only       # :nil_only | :all | {:stale_model, "model_id"}
)
```

## Consolidation

### `Recollect.Consolidation.run/1`

Multi-pass consolidation cycle: decay -> merge overlapping -> detect conflicts
-> rebuild schema index -> persist.

```elixir
{:ok, result} = Recollect.Consolidation.run(
  scope_id: scope_id,          # required
  decay_threshold: 0.05,       # minimum strength to survive
  merge_threshold: 0.35,       # text overlap for merging
  min_cluster: 3,              # minimum entries to form a cluster
  dry_run: false               # preview without persisting
)
```

Returns `%{decayed: n, removed: n, merged: n, semantic_created: n,
conflicts_detected: n, duration_ms: n}`.

### `Recollect.Consolidation.dry_run/1`

Preview consolidation without persisting changes.

## Invalidation

### `Recollect.Invalidation.run_from_git/1`

Scans recent git commits for migration patterns and weakens related memories.

```elixir
{:ok, result} = Recollect.Invalidation.run_from_git(
  scope_id: scope_id,  # required
  days: 7              # default: 7
)
```

Detects patterns like "migrated from X to Y", "refactor: X -> Y",
"replaced X with Y", "BREAKING CHANGE:".

### `Recollect.Invalidation.invalidate/3`

Manually weaken memories matching a pattern.

```elixir
{:ok, result} = Recollect.Invalidation.invalidate(scope_id, "webpack",
  reason: "migrated to vite",
  replacement: "We now use Vite for bundling",
  weaken_factor: 0.1     # multiply half_life by this
)
```

## Outcome Feedback

### `Recollect.Outcome.good/1` and `Recollect.Outcome.bad/1`

Signal whether the last-retrieved entries were helpful. Adjusts `half_life_days`
and sets `confidence_state` to `"verified"`.

```elixir
Recollect.Outcome.good(scope_id)   # +5 days to half_life
Recollect.Outcome.bad(scope_id)    # -3 days to half_life
Recollect.Outcome.apply([id1, id2], :good)
```

Values are configurable via `config :recollect, :outcome_feedback,
positive_half_life_delta: 5, negative_half_life_delta: 3`.
