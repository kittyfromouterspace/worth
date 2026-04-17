# Full Pipeline (Tier 1)

## Ingest

### `Recollect.Pipeline.Ingester.ingest/3`

Ingest text content as a document with content-hash deduplication.

```elixir
{:ok, document} = Recollect.Pipeline.Ingester.ingest(title, content,
  owner_id: owner_id,           # required
  scope_id: scope_id,           # optional
  collection_name: "default",   # default: "default"
  source_type: "manual",        # "artifact" | "conversation" | "manual"
  source_id: nil,               # external ID for dedup
  metadata: %{}                 # arbitrary map
)
```

Returns:
- `{:ok, document}` — created or updated
- `{:ok, :unchanged}` — content hash matches existing (no re-processing)
- `{:error, reason}`

A `Recollect.Schema.Collection` is auto-created if it doesn't exist.

### Document Status Lifecycle

`pending` -> `processing` -> `ready` | `failed`

If re-ingested with changed content, status resets to `pending`.

## Process

### `Recollect.Pipeline.process/2`

Run the full pipeline synchronously on a document.

```elixir
{:ok, run} = Recollect.Pipeline.process(document, opts)
```

Pipeline stages: chunk -> embed chunks -> extract entities/relations ->
embed entities -> complete.

Returns `{:ok, pipeline_run}` with `run.status` and `run.step_details`.

### `Recollect.Pipeline.process_async/2`

Fire-and-forget. Delegates to `Recollect.Pipeline.process/2` via the
configured `TaskSupervisor`.

## Chunking

The `Recollect.Pipeline.Chunker` splits content into markdown-aware chunks
preserving section hierarchy and paragraph boundaries. Chunks are created as
`Recollect.Schema.Chunk` records with sequence numbers, token counts, and
heading context in metadata.

On re-processing, existing chunks are deleted before creating new ones.

## Extraction

The `Recollect.Pipeline.Extractor` uses the configured
`Recollect.ExtractionProvider` (default: `Recollect.Extraction.LlmJson`) to
extract entities and relations from each chunk.

Entities are persisted as `Recollect.Schema.Entity` records. Relations are
persisted as `Recollect.Schema.Relation` records. Entity embedding is done
asynchronously after extraction.

Extraction failure for a single chunk logs a warning and continues — it does
not fail the entire pipeline.
