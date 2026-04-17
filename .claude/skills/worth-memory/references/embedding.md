# Embedding

## Providers

### `Recollect.Embedding.Local` (default)

Uses Bumblebee with `sentence-transformers/all-MiniLM-L6-v2`. 384 dimensions.
No API key needed. Model weights downloaded from HuggingFace Hub on first use.

Requires `{:bumblebee, "~> 0.6.0"}` in deps. The `Nx.Serving` process is
started by `Recollect.Application` at boot.

Config:

```elixir
config :recollect, :local_embedding,
  model: "sentence-transformers/all-MiniLM-L6-v2",
  compile: [batch_size: 32, sequence_length: 128]
```

If Bumblebee is not installed, the provider returns `{:error, ...}` gracefully.

### `Recollect.Embedding.OpenRouter`

Uses OpenRouter's `/api/v1/embeddings` endpoint (OpenAI-compatible). Default
model: `openai/text-embedding-3-small` (1536 dimensions).

Config:

```elixir
config :recollect,
  embedding: [
    provider: Recollect.Embedding.OpenRouter,
    credentials_fn: fn ->
      %{
        api_key: System.get_env("OPENROUTER_API_KEY"),
        model: "openai/text-embedding-3-small",
        dimensions: 1536
      }
    end
  ]
```

## Credentials

API credentials are resolved at runtime via `:credentials_fn`. The function
returns a map with `:api_key` (required) and optional `:model`, `:dimensions`,
`:base_url`. Return `:disabled` if no credentials available.

Static config (`api_key: "..."`) works but is not recommended for production.

## Dimensions

Must be consistent across your entire deployment. Set via:
1. `:dimensions` in the credentials map
2. `:dimensions` in the embedding config
3. Provider default (384 for Local, 1536 for OpenRouter)

The migration generator `mix recollect.gen.migration --dimensions N` creates
tables with the specified vector size. This must match your embedding model.
