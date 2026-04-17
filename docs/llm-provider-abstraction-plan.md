# LLM Provider Abstraction — Implementation Plan

> Status: **All phases (1-6) complete.** Decisions locked. See `BACKLOG.md` for follow-up cleanup and refinement items.
> Phases are written so each one is independently shippable. The plan
> still expects refinement during implementation but the architectural
> choices are settled. See the **Implementation progress** section at
> the bottom for the running log.

## Goal

Replace the current ad-hoc adapter pile (`Worth.LLM.{Anthropic, OpenAI,
OpenRouter}`) with a layered abstraction in `agentic` that cleanly
separates the wire-protocol family (transport) from the service
(provider), and adds first-class concepts for catalogs, capabilities,
quotas, credentials, and embeddings.

The forcing function: **adding Groq, Together, Fireworks, Cerebras, Mistral,
DeepSeek, etc. should be one new ~50-line provider module each**, with
zero edits to dispatch/routing/UI code. Embedding providers (Ollama,
OpenAI text-embedding-3-small, OpenRouter embedding models) should
follow the same shape.

## Non-goals (for this iteration)

- OAuth flows, CLI credential reuse (Claude CLI, Codex CLI), provider
  setup wizards — deferred to a follow-up "Auth Profiles & Config UI"
  iteration.
- Streaming chat. Current synchronous `Req.post` path is preserved.
  Streaming is layered on the transport behaviour later.
- Tool-schema normalization pipelines à la openclaw — direct one-shot
  translation per transport is enough until proven otherwise.
- Reasoning level mapping across providers (`/think low|medium|high`).
  Anthropic prompt caching is the only "advanced model feature" we add
  in this round.
- Multi-tenant SaaS provider configs. Providers are code modules in the
  agentic repo, not DB rows.

## Architecture overview

```
                          ┌────────────────────────────────────┐
                          │   Agentic.LLM.Catalog (GenServer)  │
                          │   models: %{provider => [Model]}   │
                          │   persisted to ~/.worth/catalog    │
                          └─────────────┬──────────────────────┘
                                        │
                          ┌─────────────▼──────────────────────┐
                          │   Agentic.ModelRouter              │
                          │   (tier resolution + cooldowns)    │
                          │   queries Catalog                  │
                          └─────────────┬──────────────────────┘
                                        │
                          ┌─────────────▼──────────────────────┐
                          │   Agentic.LLM (entry point)        │
                          │   chat/2  chat_tier/3              │
                          │   embed/2  embed_tier/3            │
                          └─────────────┬──────────────────────┘
                                        │
              ┌─────────────────────────┼─────────────────────────┐
              │                         │                         │
     ┌────────▼─────────┐     ┌─────────▼──────────┐     ┌────────▼─────────┐
     │ Provider         │     │ Provider           │     │ Provider         │
     │   .OpenRouter    │     │   .Anthropic       │     │   .Ollama        │
     │ (chat+embed)     │     │ (chat only)        │     │ (chat+embed)     │
     │ transport=oai    │     │ transport=anthr    │     │ transport=ollama │
     └────────┬─────────┘     └─────────┬──────────┘     └────────┬─────────┘
              │                         │                         │
              └────────────┬────────────┴────────────┬────────────┘
                           │                         │
                  ┌────────▼─────────┐      ┌────────▼─────────┐
                  │ Transport        │      │ Transport        │
                  │   .OpenAI        │      │   .Anthropic     │
                  │   ChatCompletions│      │   Messages       │
                  │ + Embeddings     │      │                  │
                  └──────────────────┘      └──────────────────┘
```

## Layers

### Layer 1 — `Agentic.LLM.Transport`

**Behaviour describing one wire-protocol family.** Pure functions, no
auth, no provider-specific quirks, no rate-limit policy.

```elixir
defmodule Agentic.LLM.Transport do
  @callback id() :: atom()
  @callback build_chat_request(canonical_params, opts) :: %{
    method: :post,
    url: String.t(),
    body: map(),
    headers: keyword()
  }
  @callback parse_chat_response(http_status, http_body, http_headers) ::
    {:ok, Agentic.LLM.Response.t()} | {:error, Agentic.LLM.Error.t()}
  @callback parse_rate_limit(http_headers) :: Agentic.LLM.RateLimit.t() | nil

  # Embedding support is optional per transport.
  @callback build_embedding_request(text_or_list, opts) :: map() | :not_supported
  @callback parse_embedding_response(http_status, http_body) ::
    {:ok, [vector]} | {:error, Agentic.LLM.Error.t()} | :not_supported

  @optional_callbacks build_embedding_request: 2, parse_embedding_response: 2
end
```

**Initial implementations:**

| Transport | Chat | Embeddings | Notes |
|---|---|---|---|
| `AnthropicMessages` | ✓ | — | Anthropic doesn't expose an embeddings endpoint |
| `OpenAIChatCompletions` | ✓ | ✓ (`/v1/embeddings`) | Used by OpenAI, OpenRouter, Groq, Together, Fireworks, Cerebras, Mistral, DeepSeek, LM Studio, vLLM, … |
| `Ollama` | ✓ | ✓ (`/api/embed`) | Local-first |
| `GoogleGenerativeAI` | ✓ | ✓ (`:embedContent`) | Phase 4 add |

**Why these and not more:** these four cover ~95% of providers we'd
realistically integrate. Bedrock, Vertex, Azure-OpenAI Responses are
follow-ups when someone actually needs them.

### Layer 2 — `Agentic.LLM.Provider`

**Behaviour describing one service.** Each provider is a small module
that declares which transport it uses, points at a base URL, declares
env vars for credentials, and optionally implements catalog and usage
fetchers.

```elixir
defmodule Agentic.LLM.Provider do
  @callback id() :: atom()
  @callback label() :: String.t()
  @callback transport() :: module()
  @callback default_base_url() :: String.t() | nil
  @callback env_vars() :: [String.t()]                    # priority order
  @callback default_models() :: [Agentic.LLM.Model.t()]   # static seed
  @callback request_headers(creds) :: keyword()           # provider-specific extras
  @callback supports() :: MapSet.t(:chat | :embeddings | :vision | :tools)

  # Optional dynamic discovery / quota
  @callback fetch_catalog(creds) :: {:ok, [Model.t()]} | {:error, term} | :not_supported
  @callback fetch_usage(creds)   :: {:ok, Agentic.LLM.Usage.t()} | :not_supported
  @callback classify_http_error(status, body, headers) ::
    {failure_type, retry_after_ms | nil} | :default

  @optional_callbacks fetch_catalog: 1, fetch_usage: 1, classify_http_error: 3
end
```

**A concrete provider stays under 100 lines:**

```elixir
defmodule Agentic.LLM.Provider.Groq do
  @behaviour Agentic.LLM.Provider
  alias Agentic.LLM.{Model, Transport}

  def id, do: :groq
  def label, do: "Groq"
  def transport, do: Transport.OpenAIChatCompletions
  def default_base_url, do: "https://api.groq.com/openai/v1"
  def env_vars, do: ["GROQ_API_KEY"]
  def supports, do: MapSet.new([:chat, :tools])
  def request_headers(_creds), do: []

  def default_models, do: [
    %Model{id: "llama-3.3-70b-versatile", tier: :primary, ...},
    %Model{id: "llama-3.1-8b-instant", tier: :lightweight, ...}
  ]

  def fetch_catalog(creds), do: Agentic.LLM.OpenAICompatCatalog.fetch(default_base_url(), creds)
end
```

**Initial provider modules:**

| Provider | Transport | Catalog | Usage | Embeddings |
|---|---|---|---|---|
| `Anthropic` | `AnthropicMessages` | static | `/v1/usage` (oauth) | — |
| `OpenAI` | `OpenAIChatCompletions` | `/v1/models` | `/v1/usage/...` | ✓ |
| `OpenRouter` | `OpenAIChatCompletions` | `/api/v1/models` (already) | `/api/v1/auth/key` | ✓ via `?output_modalities=embeddings` filter |
| `Groq` | `OpenAIChatCompletions` | `/openai/v1/models` | — | — |
| `Ollama` | `Ollama` | `/api/tags` (local) | — | ✓ |

The `Anthropic`, `OpenAI`, `OpenRouter` modules **replace** the existing
`Worth.LLM.{Anthropic, OpenAI, OpenRouter}` adapter files entirely. The
old adapters get deleted.

### Layer 3 — Shared structs

```elixir
defmodule Agentic.LLM.Model do
  defstruct [
    :id,                  # provider-local model id, e.g. "claude-opus-4-6"
    :provider,            # :anthropic
    :label,               # human-readable
    :context_window,      # tokens
    :max_output_tokens,
    :cost,                # %{input: $/1M, output: $/1M, cache_read:, cache_write:}
    :capabilities,        # MapSet of tags — see "Capability tags" below
    :tier_hint,           # :primary | :lightweight (provider-suggested)
    :source               # :static | :discovered | :user_config
  ]
end

defmodule Agentic.LLM.Route do
  @enforce_keys [:provider_id, :transport, :model_id]
  defstruct [
    :provider_id, :transport, :model_id, :label,
    :base_url, :context_tokens, :max_output_tokens,
    :tier, :source, :priority, :capabilities
  ]
end

defmodule Agentic.LLM.Response do
  defstruct [:content, :stop_reason, :usage, :model_id, :raw]
  # content: [%{type: :text, text}, %{type: :tool_use, id, name, input}, ...]
  # stop_reason: :end_turn | :tool_use | :max_tokens | :error
  # usage: %{input_tokens, output_tokens, cache_read, cache_write}
end

defmodule Agentic.LLM.Error do
  defstruct [:message, :status, :retry_after_ms, :rate_limit, :classification, :raw]
  # classification: :rate_limit | :auth | :transient | :permanent
end

defmodule Agentic.LLM.RateLimit do
  defstruct [:remaining, :limit, :reset_at_ms]
end

defmodule Agentic.LLM.Usage do
  defstruct [:provider, :label, :plan, :windows, :credits, :error, :fetched_at]
end

defmodule Agentic.LLM.UsageWindow do
  defstruct [:label, :used, :limit, :unit, :reset_at]
end
```

These structs are the contract between layers. **No more loosely-typed
maps passed across module boundaries.** The current `_route` map and
`{:error, "string"}` shapes go away — the KeyError-on-missing-key bugs
go with them.

### Layer 4 — Capability tags **(DECIDED — new)**

Each `Model` carries a `MapSet` of capability tags. Tags are atoms
chosen from a fixed taxonomy:

```
:chat            — supports chat completion
:embeddings      — embedding model
:tools           — supports function/tool calling
:vision          — accepts image inputs
:reasoning       — has explicit reasoning/thinking output
:prompt_caching  — supports Anthropic-style cache_control blocks
:json_mode       — supports structured JSON output mode
:audio_input     — accepts audio inputs (future)
:audio_output    — produces audio (future)
:free            — costs $0/token (free tier model)
```

`Agentic.LLM.Catalog` exposes a tag-aware query:

```elixir
Catalog.find(provider: :openrouter, tier: :lightweight, has: :tools)
Catalog.find(has: :embeddings, provider: :ollama)
Catalog.find(has: [:vision, :tools])
Catalog.find(has: [:embeddings, :free])
```

**This replaces the current `tier: :primary | :lightweight`
free/configured fork.** Free routes become "models with the `:free`
tag". Embedding model selection becomes "models with the `:embeddings`
tag, optionally filtered by `:free` for cost-aware fallback".

The provider's `fetch_catalog/1` infers tags from the upstream
metadata: OpenRouter's `output_modalities` field gives us
`:embeddings`/`:vision`, `supported_parameters` gives us
`:tools`/`:reasoning`, `pricing.prompt == "0"` gives us `:free`.
Anthropic's static catalog gets tags from the model id pattern.

### Layer 5 — `Agentic.LLM.Catalog` **(GenServer)**

Holds all known models, refreshed on a schedule. Sources, in priority
order:

1. User overrides from `~/.worth/config.exs` (highest priority).
2. Dynamic discovery from `provider.fetch_catalog/1` (network).
3. Provider's static `default_models/0` (always present).

```elixir
defmodule Agentic.LLM.Catalog do
  use GenServer

  def all() :: [Model.t()]
  def for_provider(provider_id) :: [Model.t()]
  def find(opts) :: [Model.t()]                # tag/tier/provider filter
  def lookup(provider_id, model_id) :: Model.t() | nil
  def refresh() :: :ok                         # async, non-blocking
  def refresh_provider(provider_id) :: :ok
end
```

**Persistence: `~/.worth/catalog.json` (DECIDED)**. Loaded at boot for
warm-path latency, refreshed in the background. Schema-versioned so we
can evolve the Model struct without trashing existing caches.

Refresh interval: 10 minutes for chat catalogs, 1 hour for embedding
catalogs, on-demand via `/catalog refresh` slash command.

`Agentic.ModelRouter` becomes a thin layer **on top of Catalog**:
`resolve_all/1` queries the catalog with the requested tier and
capability filter, sorts by `priority` then `cost`, and returns
`Route` structs.

### Layer 6 — `Agentic.LLM.Credentials`

Resolves credentials for a provider by walking its declared `env_vars/0`
in order. Returns the first non-empty value as a `%Credentials{}`
struct. The provider knows its own env var names; nothing else does.

```elixir
defmodule Agentic.LLM.Credentials do
  defstruct [:api_key, :headers, :base_url_override, :expires_at, :source]

  def resolve(provider_module) :: {:ok, t} | :not_configured
  def available?(provider_module) :: boolean
end
```

**Phase 1 implementation: env vars only.** A follow-up iteration adds
`~/.worth/credentials.toml` profile storage and a config UI for adding
keys interactively. Provider auth methods (`api-key`/`oauth`/`token`)
stay openclaw-flavored but are **not built in this iteration**.

After this lands, `Worth.Config.resolve_env_values/1`'s `{:env, "VAR"}`
tuple convention can go away — providers handle their own env lookups
and `~/.worth/config.exs` doesn't need to know.

### Layer 7 — `Agentic.LLM.UsageManager` **(GenServer)**

Periodically calls `provider.fetch_usage/1` for every enabled provider
that implements it. Caches snapshots for ~30 seconds. Worth's Status
sidebar reads the cache.

```elixir
defmodule Agentic.LLM.UsageManager do
  use GenServer
  def snapshot() :: [Usage.t()]
  def for_provider(provider_id) :: Usage.t() | nil
  def refresh() :: :ok
end
```

Providers that don't expose a usage endpoint return `:not_supported`
and don't appear in the snapshot.

### Layer 8 — Embeddings

**Recollect needs an embedding provider.** Currently configured via
`config :recollect, embedding: [provider: Recollect.Embedding.Mock, mock: true]`
which is a placeholder.

The plan unifies embeddings into the same provider/transport stack:

```elixir
defmodule Agentic.LLM do
  def chat(params, opts \\ [])
  def chat_tier(params, tier, opts \\ [])

  def embed(text_or_list, opts \\ [])
  def embed_tier(text_or_list, opts \\ [])
end
```

`embed/2` accepts `provider:` / `model:` / `_route:` opts the same way
chat does. `embed_tier/2` resolves a model with the `:embeddings`
capability tag (and optionally `:free`).

A new `Worth.Memory.Embeddings.Adapter` implements Recollect's
`Recollect.EmbeddingProvider` behaviour by delegating to
`Agentic.LLM.embed_tier/2`. Recollect's config becomes:

```elixir
config :recollect,
  embedding: [
    provider: Worth.Memory.Embeddings.Adapter,
    tier: :embeddings_lightweight   # via tag query, not hardcoded model
  ]
```

**Where the embedding catalog comes from:**

- **OpenRouter** publishes embedding models at
  `/api/v1/models?output_modalities=embeddings`. Already implemented in
  homunculus's `Homunculus.Providers.OpenRouter.list_embedding_models/2`
  — port the parsing logic into our OpenRouter provider's
  `fetch_catalog/1` so chat and embedding models come from the same
  catalog refresh, just with different `:capabilities` tags.
- **Ollama** lists local models at `/api/tags`; embedding models are
  identified by name suffix (`:embed`) or by their declared family.
- **OpenAI** has a static set (`text-embedding-3-small`,
  `text-embedding-3-large`, `text-embedding-ada-002`) hardcoded in the
  provider's `default_models/0`.

The free-route discovery in `Agentic.ModelRouter.Free` becomes
**generic over capability**: same code, but instead of "find me free
chat models", `Catalog.find(has: [:embeddings, :free])` returns free
embedding models. The same retry/cooldown machinery applies.

### Layer 9 — Cost telemetry **(OPEN — needs your call)**

Once `Model.cost` and `Response.usage` are both populated, every chat
call can compute its dollar cost at parse time. Two paths to surface it
to the UI:

**Option A — Elixir messages (current pattern).**
`agentic/LLMCall` emits `{:cost, %{usd, model, provider, tokens}}`
through the existing `on_event` callback. Worth's `Events.drain/1`
already handles `:cost` events; just enrich the payload.

- ➕ Same machinery we already use, fits the Elm-style update flow.
- ➖ Tightly couples cost reporting to the agent loop — background fact
  extraction calls (which go through `chat_tier`, not the loop) won't
  emit anything unless we add the same wiring there.

**Option B — `:telemetry` events.**
Emit `[:agentic, :llm, :call, :stop]` with measurements
`%{duration, input_tokens, output_tokens, cost_usd}` and metadata
`%{provider, model, tier, classification}`. Worth attaches a telemetry
handler at boot that reads these into a `Worth.Metrics` GenServer; UI
polls or subscribes.

- ➕ Decoupled, works for any caller (chat, chat_tier, embed). Already
  partially in place — agentic emits `[:llm_call, :stop]` today, just
  with `cost_usd: 0.0` as a placeholder.
- ➕ Lets the same events feed prometheus / live dashboards / log
  aggregation later.
- ➖ One more pattern in the codebase. The `Worth.Metrics` aggregator
  is new code.

**My recommendation: Option B**, because (a) we're going to need
telemetry anyway for prometheus/observability, (b) the existing
`[:llm_call, :start|:stop]` events are already wired and just need
real cost numbers, and (c) it covers background callers cleanly.
The `on_event` callback then becomes optional for any caller that
wants live UI streaming on top of the telemetry stream.

Want to talk through this one before we commit.

## Decisions log

| # | Decision | Choice |
|---|---|---|
| 1 | Where does the abstraction live? | **agentic** |
| 2 | Provider registration mechanism | **Hybrid:** compile-time list of available providers + runtime enable/disable persisted to config. Follow-up iteration: secure API key store + config UI. |
| 3 | Catalog persistence path | **`~/.worth/catalog.json`** |
| 4 | Cost tracking transport | **`:telemetry` events.** `agentic/LLMCall` and `Worth.LLM.embed/2` emit `[:agentic, :llm, :call, :stop]` with real `cost_usd`. A `Worth.Metrics` GenServer attaches a handler at boot and aggregates per-session totals. The current `:cost` event in `on_event` callbacks stays as a thin shim that forwards from telemetry to UI for backwards compat. |
| 5 | Tier semantics | **User-configurable per workspace via IDENTITY.md frontmatter, internal heuristic as default.** Workspace config can override `tier: :primary` to mean a specific model id. Lives in the workspace repo so it's versioned alongside the project. |
| 6 | Anthropic prompt caching | **YES** — implement `cache_control` blocks in `Transport.AnthropicMessages` since `agentic/LLMCall` already computes `stable_prefix_hash` and `prefix_changed`. |
| 7 | Embeddings as separate concept? | **Same provider/transport stack, distinguished by capability tag.** Recollect gets a thin adapter that calls `Agentic.LLM.embed_tier/2`. |
| 8 | Capability tags | **YES** — starter taxonomy, grow as we use the agent. Providers tag their catalog entries, `Catalog.find/1` accepts tag filters. |
| 9 | Catalog refresh on boot | **Async.** First refresh fires ~100 ms after boot. Persisted catalog from `~/.worth/catalog.json` is the warm path so the sidebar isn't `(detecting…)`. |
| 10 | Workspace tier config location | **IDENTITY.md frontmatter.** Lives in the workspace repo, versioned with the project. No new config file. |
| 11 | Provider enable/disable persistence | **Persisted to `~/.worth/config.exs`.** `/provider disable groq` survives restart. |
| 12 | Embedding dimension migration | **Slim tool in worth that calls into Recollect.** If Recollect lacks the underlying re-embed primitive, implement it in `../recollect` first. Worth provides the user-facing CLI/slash command. |
| 13 | Per-provider error classification | **Pre-populate with the openclaw failover taxonomy.** See "Error taxonomy" section below. Adds Phase 2 alongside the Provider behaviour. |
| 14 | `agentic` config namespace | **Yes, add it.** `agentic` is used in other projects, needs its own config surface. See "agentic configuration" section below. |

## Tier configuration **(from decision #5, #10)**

Default tiers come from the provider's catalog metadata + a heuristic:

```elixir
defp default_tier(model) do
  cond do
    model.context_window >= 64_000 -> :primary
    model.context_window >= 8_000  -> :lightweight
    true -> :unknown
  end
end
```

Users override per workspace via `IDENTITY.md` frontmatter at the top
of the file, so the choice is versioned alongside the project's other
identity bits:

```markdown
---
name: my-project
description: A project that does ...
llm:
  tiers:
    primary: "anthropic/claude-opus-4-6"
    lightweight: "anthropic/claude-haiku-4-5"
    embeddings: "openai/text-embedding-3-small"
  prefer_free: true
  cost_ceiling_per_turn: 0.05
  prompt_caching: true
---

# Project description goes here as usual
...
```

Resolution order (highest priority first):

1. Workspace `IDENTITY.md` frontmatter `llm:` block.
2. Global `~/.worth/config.exs` `[:llm, :tiers]` setting.
3. Compile-time provider defaults in `agentic`.
4. Heuristic from catalog metadata (context window thresholds above).

`Worth.Workspace.Identity` already parses frontmatter — extend it with
an `llm` schema validation pass and surface the parsed config to
`Agentic.ModelRouter` per agent turn so a user editing the file mid-run
takes effect on the next message.

## Error taxonomy **(from decision #13)**

Pre-populated from `openclaw/src/agents/pi-embedded-helpers/`'s
`FailoverReason` enum and `failover-matches.ts` patterns. We're starting
with the same vocabulary so we don't have to relearn the lesson of which
strings every provider uses.

### Classification enum

```elixir
@type classification ::
  :rate_limit       # 429, throttled, quota exceeded → cool down route, retry next
  | :overloaded     # 503 + capacity language → cool down briefly, retry next
  | :auth           # 401, ambiguous auth issue → may recover, retry next
  | :auth_permanent # key revoked/disabled/deleted → mark provider broken
  | :billing        # 402, insufficient credits → mark provider broken until topped up
  | :timeout        # network timeout, connection reset → retry same route
  | :format         # bad request format → don't retry, surface to user
  | :model_not_found # 404, model deactivated → drop from catalog, retry next
  | :context_overflow # input too long → don't retry route, trigger compaction
  | :session_expired # 410 → reauth + retry same route
  | :transient      # generic 5xx, unknown server-side issue → retry next
  | :permanent      # everything else, fall through
```

### Status code → classification (provider-agnostic baseline)

```
402 → :billing
401 → :auth
403 → :auth_permanent
404 → :model_not_found
408 → :timeout
410 → :session_expired
429 → :rate_limit
500..502, 504 → :transient
503 → :overloaded (if body matches "high demand"/"capacity") else :transient
other 4xx → :permanent
```

### Pattern-based fallback (when status code is missing/wrong)

These come straight from `failover-matches.ts` — string matching on
the lowercased error body. Implemented in
`Agentic.LLM.ErrorPatterns` so all transports share the same logic.

**`:rate_limit`** patterns:
- `~r/rate[_ ]limit|too many requests|429/`
- `~r/too many (?:concurrent )?requests/i`
- `~r/throttling(?:exception)?/i`
- `"model_cooldown"`, `"exceeded your current quota"`,
  `"resource has been exhausted"`, `"quota exceeded"`,
  `"resource_exhausted"`, `"throttlingexception"`, `"throttled"`,
  `"throttling"`, `"usage limit"`
- `~r/\btpm\b/i`, `"tokens per minute"`, `"tokens per day"`

**`:overloaded`** patterns:
- `~r/overloaded_error|"type"\s*:\s*"overloaded_error"/i`
- `"overloaded"`, `"high demand"`
- `~r/service[_ ]unavailable.*(?:overload|capacity|high[_ ]demand)/i`

**`:billing`** patterns:
- `~r/["']?(?:status|code)["']?\s*[:=]\s*402\b/`
- `"payment required"`, `"insufficient credits"`,
  `"insufficient_quota"`, `"credit balance"`, `"plans & billing"`,
  `"insufficient balance"`, `"insufficient usd or diem balance"`
- `~r/requires?\s+more\s+credits/i`
- `~r/out of extra usage/i`
- `~r/draw from your extra usage/i`

**`:auth_permanent`** patterns (high confidence — won't recover):
- `~r/api[_ ]?key[_ ]?(?:revoked|deactivated|deleted)/i`
- `"key has been disabled"`, `"key has been revoked"`,
  `"account has been deactivated"`,
  `"not allowed for this organization"`

**`:auth`** patterns (ambiguous — might recover):
- `~r/invalid[_ ]?api[_ ]?key/`
- `~r/could not (?:authenticate|validate).*(?:api[_ ]?key|credentials)/i`
- `"permission_error"`, `"incorrect api key"`, `"invalid token"`,
  `"authentication"`, `"re-authenticate"`,
  `"oauth token refresh failed"`, `"unauthorized"`, `"forbidden"`,
  `"access denied"`, `"insufficient permissions"`
- `~r/missing scopes?:/i`
- `"expired"`, `"token has expired"`, `~r/\b401\b/`, `~r/\b403\b/`
- `"no credentials found"`, `"no api key found"`

**`:timeout`** patterns:
- `"timeout"`, `"timed out"`, `"deadline exceeded"`,
  `"context deadline exceeded"`, `"connection error"`,
  `"network error"`, `"network request failed"`, `"fetch failed"`,
  `"socket hang up"`
- `~r/\beconn(?:refused|reset|aborted)\b/i`,
  `~r/\benetunreach\b/i`, `~r/\behostunreach\b/i`,
  `~r/\bhostdown\b/i`, `~r/\benetreset\b/i`,
  `~r/\betimedout\b/i`, `~r/\besockettimedout\b/i`,
  `~r/\bepipe\b/i`, `~r/\benotfound\b/i`, `~r/\beai_again\b/i`
- `~r/\boperation was aborted\b/i`,
  `~r/\bstream (?:was )?(?:closed|aborted)\b/i`

**`:format`** patterns (don't retry — these are bugs in our request):
- `"string should match pattern"`, `"tool_use.id"`,
  `"tool_use_id"`, `"invalid request format"`
- `~r/tool call id was.*must be/i`

**`:context_overflow`** patterns (handled separately — see below):
- `~r/\binput token count exceeds the maximum number of input tokens\b/i`
  (Bedrock)
- `~r/\binput is too long for this model\b/i`
- `~r/\binput exceeds the maximum number of tokens\b/i` (Vertex/Gemini)
- `~r/\bollama error:\s*context length exceeded/i`
- `~r/\btotal tokens?.*exceeds? (?:the )?(?:model(?:'s)? )?(?:max|maximum|limit)/i`
  (Cohere/generic)
- `~r/\binput (?:is )?too long for (?:the )?model\b/i`
- Generic two-pass test: text contains both
  `~r/\b(?:context|window|prompt|token|tokens|input|request|model)\b/i`
  AND
  `~r/\b(?:too\s+(?:large|long|many)|exceed(?:s|ed|ing)?|overflow|limit|maximum|max)\b/i`

**Provider-specific overrides** (the `Provider.classify_http_error/3`
optional callback):
- Z.ai code 1311 → `:billing` (model not in subscription plan)
- Z.ai code 1113 → `:auth`
- Bedrock `ThrottlingException` → `:rate_limit`
- Bedrock `ModelNotReadyException` → `:overloaded`
- Cloudflare workers_ai quota → `:rate_limit`
- Groq `model_is_deactivated` → `:model_not_found`

### Module structure

```
agentic/lib/agentic/llm/
├── error.ex                    # %Error{} struct (already in plan)
├── error_patterns.ex           # Generic pattern tables + classify_message/1
├── error_classifier.ex         # classify/3 — combines status + headers + body
└── transport/
    └── <transport>.ex          # parse_response calls into ErrorClassifier
```

`ErrorClassifier.classify/3`:
1. Check provider-specific override via `Provider.classify_http_error/3`.
2. Look up status code in the baseline table.
3. If still unknown, run pattern matching against body text.
4. If still unknown, fall through to `:permanent`.
5. Always test for `:context_overflow` separately, regardless of
   status — context overflow can happen with status 200 too on some
   transports.

### Why context overflow is separate

It's the one classification that **doesn't trigger failover**. The
right response to "your prompt is too long" is to compact the
conversation (drop old turns, summarize, prune tool results), not to
try a different model — every model will fail the same way until you
shrink the input. The agentic loop already has hooks for this; the
`:context_overflow` classification feeds into them rather than into
the route retry walk.

## `agentic` configuration namespace **(from decision #14)**

`agentic` gets its own application config surface. Hosts (worth and
others) configure agentic through the standard Elixir config flow:

```elixir
# config/config.exs in any host project
config :agentic,
  providers: [
    Agentic.LLM.Provider.Anthropic,
    Agentic.LLM.Provider.OpenAI,
    Agentic.LLM.Provider.OpenRouter,
    Agentic.LLM.Provider.Groq,
    Agentic.LLM.Provider.Ollama
  ],
  catalog: [
    persist_path: "~/.worth/catalog.json",   # host-specific
    refresh_interval_ms: 600_000,
    refresh_on_boot: :async,
    initial_refresh_delay_ms: 100
  ],
  usage: [
    refresh_interval_ms: 300_000             # 5 minutes
  ],
  router: [
    cooldown_threshold: 2,
    default_cooldown_ms: 120_000,
    rate_limit_cooldown_ms: 240_000
  ],
  telemetry: [
    enabled: true
  ]
```

Worth's `config/config.exs` provides the `agentic` block with worth-
specific paths. Other future projects (e.g. a non-TUI CLI tool, a
Phoenix LiveView app embedding the agent loop) provide their own.

`Agentic.Config` (new module, mirrors `Worth.Config`) loads from
`Application.get_all_env(:agentic)` at boot, exposes typed accessors
(`Agentic.Config.providers/0`, `Agentic.Config.catalog_path/0`, etc.),
validates with `nimble_options`. **Worth's `Worth.Config` stays
worth-specific** (workspaces, UI theme, MCP servers, cost limit) and
delegates anything LLM-related to `Agentic.Config`.

## Embedding dimension migration **(from decision #12)**

Switching embedding providers mid-project breaks existing embeddings —
the new model has a different dimensionality and `pgvector` similarity
search returns garbage.

### Worth side: thin tool

```elixir
defmodule Worth.Tools.Memory.Reembed do
  @moduledoc """
  Re-embed all stored memories with the currently configured embedding
  model. Calls into Recollect.Maintenance.Reembed.

  Triggered by `/memory reembed` slash command, or by automatic
  detection when the embedding model changes between runs.
  """

  def execute(args, workspace) do
    Recollect.Maintenance.Reembed.run(
      workspace: workspace,
      llm_fn: &Agentic.LLM.embed_tier(&1, :embeddings, []),
      progress_callback: &report_progress/1
    )
  end
end
```

The tool is exposed as a slash command (`/memory reembed`) and as an
agent tool (`memory_reembed`) so the agent can suggest re-running it
when it notices retrieval quality has dropped.

### Recollect side: implement what's missing

`../recollect` already has `Recollect.Maintenance.Reembed` (we saw it in the
homunculus build artifacts). Audit it before Phase 4 starts:

1. Confirm `Recollect.Maintenance.Reembed.run/1` exists and accepts a
   pluggable embedding callback.
2. Confirm it stores the embedding model id alongside each row so a
   change is detectable.
3. If either is missing, **implement it in `../recollect` first** before
   wiring the worth tool. The recollect side is the right home — it's a
   memory subsystem concern.
4. Add startup detection: when worth boots and the configured
   embedding model differs from the one stored in the most recent
   memory rows, log a warning suggesting `/memory reembed`.

Implementation order: **Recollect audit/patch → Worth tool → Phase 4
Recollect adapter switch.**

## Phased migration

Each phase ends in a green build with all existing tests passing. No
phase is allowed to break the running app.

### Phase 1 — Extract transports

**Goal:** wire-format translation moves out of per-provider adapters
into shared transport modules. No new provider behaviour yet, no
catalog changes, no embeddings.

1. Define `Agentic.LLM.Response`, `Agentic.LLM.Error`,
   `Agentic.LLM.RateLimit` structs in `agentic/lib/agentic/llm/`.
2. Implement `Agentic.LLM.Transport` behaviour.
3. Implement `Agentic.LLM.Transport.OpenAIChatCompletions`. Move all
   request building / response normalization / rate-limit header
   parsing / finish_reason translation / tool_calls parsing **out** of
   `Worth.LLM.OpenRouter` and into the transport.
4. Implement `Agentic.LLM.Transport.AnthropicMessages`. Move
   `Worth.LLM.Anthropic`'s logic in.
5. Rewrite `Worth.LLM.OpenRouter` and `Worth.LLM.Anthropic` as ~30-line
   shims that call into the transports with their respective base URLs
   and provider-specific request headers.
6. `Worth.LLM.classify_error/1` and `agentic/LLMCall.classify_error/1`
   forks **delete** — `Error.classification` is set at parse time.
7. `chat_tier/3` retry walk and `LLMCall.do_try_routes/6` retry walk
   read `error.classification` and `error.retry_after_ms` directly.

**Deliverable:** behavior unchanged, but `Worth.LLM.OpenRouter` is
trivially copyable to add Groq.

### Phase 2 — Provider behaviour + error taxonomy + Groq forcing function

**Goal:** introduce the `Provider` behaviour, the shared error
classifier, and prove the abstraction works by adding Groq with zero
edits outside the new file.

1. Define `Agentic.LLM.Provider` behaviour.
2. Define `Agentic.LLM.Model` and `Agentic.LLM.Credentials` structs.
3. Implement `Agentic.LLM.Credentials.resolve/1`.
4. **Implement `Agentic.LLM.ErrorPatterns`** with the full pattern
   tables from the "Error taxonomy" section above. Pure functions,
   string-based, exhaustively unit-tested.
5. **Implement `Agentic.LLM.ErrorClassifier.classify/3`** that combines
   status code lookup + pattern fallback + provider-specific override.
6. Add `Agentic.Config` module (per the agentic configuration
   namespace section) with `nimble_options` validation.
7. Re-implement Anthropic, OpenAI, OpenRouter as `Agentic.LLM.Provider.*`
   modules (move from `worth/lib/worth/llm/` to
   `agentic/lib/agentic/llm/provider/`). Each implements the
   optional `classify_http_error/3` callback only if it has a
   provider-specific override (e.g. Z.ai code 1311). Old `Worth.LLM.*`
   adapter modules **deleted**.
8. Add hybrid registration: `Agentic.LLM.ProviderRegistry` GenServer
   with compile-time list from `config :agentic, providers: [...]`,
   runtime `enable/1` and `disable/1` calls. **Disable state persists
   to `~/.worth/config.exs`** via `Worth.Config.update/2` (per
   decision #11).
9. Rewrite `Worth.LLM.chat/2` as a thin dispatcher: lookup provider →
   call transport. Retry logic in `chat_tier/3` and
   `agentic/LLMCall.do_try_routes/6` reads `Error.classification` and
   `Error.retry_after_ms` directly — no more string-matching.
10. **Add `Agentic.LLM.Provider.Groq`** as the forcing-function test.
    New file under `agentic/lib/agentic/llm/provider/`. **No edits
    to any other file.** If the abstraction is right, this works the
    first time. If anything else needs to change, the abstraction is
    wrong and we iterate.
11. Add slash commands: `/provider list`, `/provider enable <id>`,
    `/provider disable <id>`.

**Deliverable:** Groq runs through worth's chat with `GROQ_API_KEY` set,
no edits to dispatch/routing code, sidebar shows it as a provider, and
every transport reports structured errors with consistent
classifications across providers.

### Phase 3 — Catalog + capability tags + workspace tiers

**Goal:** unified model catalog with capability tags, replacing the
OpenRouter-specific free-model discovery, with workspace-level tier
overrides.

1. Define `Agentic.LLM.Catalog` GenServer with `find/1`, `lookup/2`,
   `refresh/0`.
2. Implement `~/.worth/catalog.json` persistence (schema-versioned).
3. **Async refresh on boot** (per decision #9):
   `Process.send_after(self(), :first_refresh, 100)` so the warm path
   from disk is the first paint, network refresh kicks in shortly
   after.
4. Move OpenRouter free-model discovery from `Agentic.ModelRouter.Free`
   into `Agentic.LLM.Provider.OpenRouter.fetch_catalog/1`. Tag models
   with `:chat`, `:tools`, `:reasoning`, `:free`, `:vision` based on
   the upstream metadata.
5. Delete `Agentic.ModelRouter.Free` (its job is now done by the
   catalog + per-provider fetch_catalog).
6. Refactor `Agentic.ModelRouter.resolve_all/1` to query
   `Agentic.LLM.Catalog.find(tier: tier, ...)`. Cooldown table stays.
7. **Extend `Worth.Workspace.Identity`** to parse the `llm:` block
   from `IDENTITY.md` frontmatter (per decisions #5, #10). Validate
   with `nimble_options`. Surface to `Agentic.ModelRouter` per agent
   turn.
8. Status sidebar reads model metadata (context window, cost) from the
   catalog instead of just labels.

**Deliverable:** `Catalog.find(provider: :openrouter, has: :tools)`
returns the same set the old `Free` module produced, plus full metadata
for cost/context/capabilities. Workspace `IDENTITY.md` can pin model
choices and they take effect on the next agent turn.

### Phase 4 — Embeddings + reembed migration

**Goal:** Recollect uses real embedding models via the same provider stack,
with a working migration path when the embedding model changes.

**Pre-work in `../recollect`** (per decision #12):

1. Audit `Recollect.Maintenance.Reembed` — confirm it exists and accepts
   a pluggable embedding callback. The build artifacts in homunculus
   suggest it does, but verify against the current source.
2. Confirm Recollect stores `embedding_model_id` alongside each embedded
   row so a model switch is detectable.
3. If either is missing, **implement them in `../recollect` first**. The
   API surface should be:
   ```elixir
   Recollect.Maintenance.Reembed.run(
     workspace: workspace,
     embedding_fn: (text_or_list -> {:ok, vector_or_list} | {:error, term}),
     progress_callback: (progress -> :ok),
     batch_size: 100
   )
   ```

**Worth + agentic side:**

4. Add `build_embedding_request/2` and `parse_embedding_response/2` to
   `Transport.OpenAIChatCompletions` and `Transport.Ollama`.
5. Implement `Agentic.LLM.Provider.Ollama` (chat + embeddings, hits
   `localhost:11434`).
6. Add `:embeddings` tag detection in `OpenRouter.fetch_catalog/1` via
   `?output_modalities=embeddings` filter (port from homunculus's
   `Homunculus.Providers.OpenRouter.list_embedding_models/2`).
7. Add `Agentic.LLM.embed/2` and `embed_tier/2` entry points.
8. Implement `Worth.Memory.Embeddings.Adapter` conforming to
   `Recollect.EmbeddingProvider` behaviour, delegating to
   `Agentic.LLM.embed_tier/2`.
9. Switch Recollect config away from `Recollect.Embedding.Mock`.
10. Add `embeddings` tier slot to the IDENTITY.md frontmatter schema.
11. **Implement `Worth.Tools.Memory.Reembed`** as a thin wrapper around
    `Recollect.Maintenance.Reembed.run/1`. Expose as `/memory reembed`
    slash command and as agent tool `memory_reembed`.
12. **Boot-time detection:** when worth starts and the configured
    embedding model differs from the most recent embedding row's
    stored model id, log an info-level message suggesting
    `/memory reembed`. Don't auto-trigger — let the user decide when
    to spend the time/tokens.

**Deliverable:** Recollect stores real embeddings, sidebar shows the
embedding model in addition to chat models, both can fall back to free
via the same retry/cooldown machinery, and switching embedding models
is a single slash command away.

### Phase 5 — Usage / quota + cost telemetry

**Goal:** see your quota and your spend in the TUI.

1. Define `Agentic.LLM.Usage` and `Agentic.LLM.UsageWindow` structs.
2. Implement `Provider.Anthropic.fetch_usage/1` (`/v1/organizations/<id>/usage`
   with oauth credential).
3. Implement `Provider.OpenRouter.fetch_usage/1` (`/api/v1/auth/key`).
4. Add `Agentic.LLM.UsageManager` GenServer polling every 5 minutes,
   on-demand via `/usage refresh`.
5. **Cost telemetry via `:telemetry` events** (decision #4):
   - `agentic/LLMCall` and `Agentic.LLM.embed/2` already emit
     `[:agentic, :llm_call, :stop]` with placeholder `cost_usd: 0.0`.
     Replace with real cost computed from `Model.cost` × `Response.usage`.
   - New event: `[:agentic, :llm, :embed, :stop]` for embedding calls,
     same shape.
   - New module `Worth.Metrics` (GenServer): attaches handlers to
     these events at boot, aggregates per-session totals (cost,
     tokens, calls per provider), exposes `Worth.Metrics.session/0`
     and `Worth.Metrics.reset/0`.
   - Existing `{:cost, amount}` event in `Worth.Brain.handle_info/2`
     becomes a thin shim that reads from `Worth.Metrics` and forwards
     deltas to the UI for live updates.
6. New Status sidebar tab **`:usage`** showing:
   ```
   Providers
     OpenRouter   credits: $4.21 / $10.00
     Anthropic    5h:  ███░░ 67% (resets in 1h12m)
                  7d:  █░░░░ 23%
     Groq         rate: 47/100  (resets in 38s)
   Session
     Cost: $0.0042 (4 turns)
     Tokens: 8,341 in / 1,127 out
     By provider:
       openrouter   $0.0028 (3 turns)
       anthropic    $0.0014 (1 turn)
   ```
7. `/usage` slash command for one-shot snapshot output.

**Deliverable:** Status panel shows live quota for every provider that
exposes one. Session cost matches reality, broken down by provider,
sourced from telemetry events that any host (not just worth) can
attach to.

### Phase 6 — Anthropic prompt caching

**Goal:** stop paying full price for the system prompt every turn.

1. `agentic/LLMCall` already computes `stable_prefix_hash` and
   `prefix_changed`. Pass this through to the transport in
   `canonical_params`.
2. `Transport.AnthropicMessages.build_chat_request/2` adds
   `cache_control: {type: "ephemeral"}` to the last block of the
   stable prefix when `prefix_changed == false`.
3. Parse `cache_creation_input_tokens` and `cache_read_input_tokens`
   from Anthropic responses into `Response.usage`.
4. Cost calculation uses `Model.cost.cache_read` and `cache_write` to
   compute savings.
5. Telemetry events surface cache hit/miss.

**Deliverable:** session cost on Claude drops by ~70% on multi-turn
conversations once the prompt cache warms up.

### Future phases (not in this plan)

- **Auth profiles + secure key storage + config UI** — read api keys
  from `~/.worth/credentials.json` (encrypted with libsodium / OS
  keyring), `/auth login <provider>` slash command, in-TUI form for
  pasting keys without putting them in shell history.
- **Streaming chat** — `Transport.stream_chat/2` callback, Worth UI
  consumes a `Stream.t()` of events.
- **OAuth flows** — Anthropic web auth, OpenAI Codex CLI reuse, Google
  Gemini CLI reuse.
- **Bedrock / Vertex / Azure-OpenAI Responses transports** — when
  someone needs them.
- **Tool schema normalization** — only if a future provider needs
  per-call schema rewrites we can't express in the transport.

## Things to refine during implementation

The architectural questions are settled. These are the smaller calls
that should be made during the relevant phase but aren't worth
blocking the plan on:

- **Schema versioning for `~/.worth/catalog.json`:** start at v1, bump
  on any breaking field change, drop the cache and force a refresh on
  version mismatch.
- **Catalog merge order when a user override conflicts with discovery:**
  user wins, but log a warning if the dynamic catalog says the model
  has different capabilities than the override claims (e.g. user
  pinned a model as `:tools`-capable but discovery says it isn't).
- **`Worth.Metrics` retention:** session-only, reset on `/clear` and
  on workspace switch. No long-term metrics history in this iteration.
- **`/provider list` output format:** start with one line per provider
  (`name | enabled | model count | last refresh | usage status`), grow
  if needed.
- **Slash command for re-embed progress reporting:** the
  `progress_callback` from Recollect should pipe into a `:reembed_progress`
  agent event so the UI can show a progress bar.
- **Provider-specific test harness:** every provider module should
  have a smoke test that hits `test_key/1` (validate auth) and
  `fetch_catalog/1` (validate parsing) in a `live_test` config block,
  so adding a provider includes a "does it actually work" check.

## Forward references (deferred to follow-up iterations)

Documented here so we don't lose them:

1. **Secure API key storage + config UI** — `~/.worth/credentials.toml`
   encrypted with libsodium or OS keyring (macOS Keychain, Linux
   secret service via `:portal`), `/auth login <provider>` slash
   command with in-TUI form for pasting keys without leaving them in
   shell history. Prerequisite for #2.
2. **Multi-profile auth per provider** — work-anthropic vs
   personal-anthropic. The credential resolution chain in Phase 2 lays
   the foundation; this iteration just adds the storage layer and
   profile selection UI.
3. **OAuth flows** — Anthropic web auth, OpenAI Codex CLI reuse,
   Google Gemini CLI reuse. Each is its own provider auth method.
4. **Streaming chat** — `Transport.stream_chat/2` callback returning
   a `Stream.t()` of canonical events (`{:text_chunk, ...}`,
   `{:tool_call, ...}`, `{:done, ...}`).
5. **Bedrock / Vertex / Azure-OpenAI Responses** transports — when
   someone needs them.
6. **Long-term metrics history** — persist `Worth.Metrics` snapshots
   to disk so users can see "you spent $X this week".
7. **Per-workspace credential overrides** — let a workspace pin
   `OPENROUTER_API_KEY` for a specific repo without polluting the
   global env. Probably via the IDENTITY.md frontmatter.

## Implementation progress

Updated as phases land. Each entry records what shipped, what was
deferred, and any judgment calls future phases need to know about.

### Phase 1 — Extract transports ✅ (2026-04-08)

**Status:** Shipped. `mix compile --warnings-as-errors` clean in both
repos; `worth` 117 tests / `agentic` 266 tests, 0 failures.

**Files created (agentic):**
- `lib/agentic/llm/response.ex` — `Agentic.LLM.Response` struct
- `lib/agentic/llm/error.ex` — `Agentic.LLM.Error` struct
- `lib/agentic/llm/rate_limit.ex` — `Agentic.LLM.RateLimit` struct
- `lib/agentic/llm/transport.ex` — `Transport` behaviour + canonical-params typespec
- `lib/agentic/llm/transport/openai_chat_completions.ex`
- `lib/agentic/llm/transport/anthropic_messages.ex`

**Files created (worth):**
- `lib/worth/llm/shim.ex` — shared canonical-params builder, `Req.post`
  driver, and legacy-map projection used by all three adapter shims

**Files modified:**
- `worth/lib/worth/llm/{openrouter,anthropic,openai}.ex` — now ~50-line
  shims over the new transports. OpenAI is migrated alongside Anthropic
  and OpenRouter (per user instruction — plan tables only mentioned the
  other two).
- `worth/lib/worth/llm.ex` — `chat_tier/3` retry walk now reads
  `error.classification` first, with the legacy `{:error, binary}`
  clauses retained as a fallback shim.
- `agentic/lib/agentic/loop/stages/llm_call.ex` — same treatment in
  `do_try_routes/6`.

**Phase 1 classification scope (deliberately partial — full taxonomy
in Phase 2):** `:rate_limit` / `:auth` / `:transient` / `:permanent`
only. Body-string fallback covers `rate_limit`, `rate limit`, `too
many requests`, `overloaded`. Phase 2 replaces this with the openclaw
pattern table.

**Judgment calls Phase 2+ needs to know about:**

1. **Legacy classification clauses kept alongside the new struct
   path.** Several error sites still produce untyped shapes
   (`{:error, "OPENROUTER_API_KEY not configured"}`,
   `{:error, "Unknown route provider: ..."}`, network-failure
   fallbacks in the shim). The new `classification:`-keyed clause runs
   first, so any shim-produced error goes through the new path. **Phase
   2's `ErrorClassifier` should remove the legacy clauses entirely**
   once those sites are migrated.
2. **`Worth.LLM.Shim` lives in worth, not agentic.** Its
   `project_response/1` translates the new `%Response{}` back into the
   legacy Worth map shape because `Agentic.Loop.Stages.ModeRouter`
   still matches on `response["stop_reason"] == "end_turn"`. **Phase 2
   should move the canonical-params builder + Req driver into agentic
   alongside the `Provider` behaviour, and switch ModeRouter to atom
   matching so the projection layer can be deleted.**
3. **`Response.stop_reason` is an atom in the struct, string in the
   projected legacy map.** Same root cause as #2 — flip ModeRouter to
   atoms in the same commit that retires the projection layer.
4. **`canonical_params.tools` defaults to `[]`, not `nil`.** Concrete
   default chosen in `Worth.LLM.Shim.canonical_params/2` so the request
   body path is uniform; both transports also tolerate `nil`.
5. **Anthropic transport now parses
   `anthropic-ratelimit-requests-*` headers** (legacy adapter parsed
   nothing). Small behavior improvement, not a regression.
6. **`Response.raw` carries the decoded body** so `Worth.LLM.Cost`
   and any other consumer that needs provider-specific details can
   still reach them. `Error.raw` does the same for error bodies.
7. **`legacy_failure/1` mapping is duplicated** between
   `Worth.LLM.chat_tier/3` and `LLMCall.do_try_routes/6` — Phase 2's
   shared classifier should collapse them.

### Phase 2 — Provider behaviour, error taxonomy, Groq ✅ (2026-04-08)

**Status:** Shipped. `mix compile --warnings-as-errors` clean in both
repos; `agentic` 352 tests / `worth` 117 tests, 0 failures.

**Files created (agentic):**
- `lib/agentic/llm/credentials.ex` — `%Credentials{}` struct + `resolve/1`
- `lib/agentic/llm/error_patterns.ex` — Full pattern tables from openclaw
- `lib/agentic/llm/error_classifier.ex` — `classify/3` combining status + patterns + provider override
- `lib/agentic/llm/provider.ex` — `Provider` behaviour + `Provider.chat/3` entry point
- `lib/agentic/llm/provider/anthropic.ex`
- `lib/agentic/llm/provider/openai.ex`
- `lib/agentic/llm/provider/openrouter.ex`
- `lib/agentic/llm/provider/groq.ex` — Forcing-function test: zero edits to dispatch code
- `lib/agentic/llm/provider_registry.ex` — Hybrid registration GenServer
- `lib/agentic/config.ex` — `Agentic.Config` with `nimble_options` validation
- `test/agentic/llm/error_patterns_test.exs` — 86 new tests
- `test/agentic/llm/error_classifier_test.exs`
- `test/agentic/llm/provider_test.exs`

**Files modified (agentic):**
- `lib/agentic/llm/error.ex` — Expanded classification type to full 12-value taxonomy
- `lib/agentic/llm/transport/openai_chat_completions.ex` — Uses `ErrorClassifier` instead of inline `classify/2`
- `lib/agentic/llm/transport/anthropic_messages.ex` — Same
- `lib/agentic/loop/stages/mode_router.ex` — Atom-based `stop_reason` matching with `normalize_stop_reason/1` for backward compat
- `lib/agentic/loop/stages/llm_call.ex` — Expanded `legacy_failure/1` mapping for all 12 classifications
- `lib/agentic/loop/stages/transcript_recorder.ex` — Handles atom stop_reasons
- `lib/agentic/loop/stages/plan_tracker.ex` — Same
- `lib/agentic/application.ex` — Added `ProviderRegistry` to supervision tree
- `config/config.exs` — Added `providers:` list with all four providers
- `test/support/test_helpers.ex` — Mock responses now use atom `stop_reason`
- `mix.exs` — Added `nimble_options` dep

**Files modified (worth):**
- `lib/worth/llm.ex` — Rewritten as thin dispatcher over `Agentic.LLM.Provider.chat/3`
- `lib/worth/llm/cost.ex` — Uses `Model.cost` struct when available, falls back to legacy pricing
- `lib/worth/ui/commands.ex` — Added `/provider list`, `/provider enable <id>`, `/provider disable <id>`

**Old adapter files retained (not deleted yet):**
- `lib/worth/llm/adapter.ex` — Superseded by `Agentic.LLM.Provider` but kept for safety
- `lib/worth/llm/anthropic.ex` — No longer called from `Worth.LLM`, can delete
- `lib/worth/llm/openai.ex` — Same
- `lib/worth/llm/openrouter.ex` — Same
- `lib/worth/llm/shim.ex` — Legacy projection layer, no longer called

**Key design decisions:**

1. **`Provider.chat/3` is the single entry point.** It handles credential
   resolution, canonical params building, transport delegation, and HTTP
   execution. The old `Worth.LLM.Shim` is no longer called.
2. **`project_result/1` in `Worth.LLM`** still projects `%Response{}` to
   legacy map shape for ModeRouter compat. Phase 3 should retire this.
3. **ModeRouter now uses atom stop reasons** (`:end_turn`, `:tool_use`,
   `:max_tokens`). A `normalize_stop_reason/1` function converts known
   string values. Unknown strings pass through to the catch-all route.
4. **ProviderRegistry is a GenServer** backed by ETS. Compile-time
   provider list from config, runtime enable/disable persisted via
   `Application.put_env`. The `Worth.Config.update/2` integration uses
   `Code.ensure_loaded/1` to avoid compile-time coupling.
5. **Groq provider was added with zero edits** to any dispatch/routing
   file, proving the abstraction works.
6. **ErrorClassifier runs `:context_overflow` check last** on every
   classification call, regardless of status code, since some providers
   return context overflow with non-obvious status codes.

**Judgment calls Phase 3+ needs to know about:**

1. **Legacy adapter files are still on disk** (`anthropic.ex`, `openai.ex`,
   `openrouter.ex`, `shim.ex`, `adapter.ex`). They compile but nothing
   calls them. Delete them early in Phase 3 once Catalog is in place.
2. **`Worth.LLM` still projects `%Response{}` to legacy map shape.** The
   `project_result/1` / `project_block/1` functions in `Worth.LLM` create
   the string-keyed maps the agentic loop consumes. Phase 3 should
   switch the loop to consume `%Response{}` directly and delete the
   projection layer.
3. **ProviderRegistry doesn't yet feed ModelRouter.** The current
   ModelRouter still uses the `Agentic.ModelRouter.Free` module for route
   discovery. Phase 3's Catalog will replace this: `Catalog.find/1`
   replaces `Free.free_routes/1`, and `ProviderRegistry.enabled/0`
   determines which providers to query.
4. **`fetch_catalog/1` on OpenRouter and Groq** makes live HTTP calls
   but is not yet wired into a scheduled refresh. Phase 3's Catalog
   GenServer will call `fetch_catalog/1` on boot and every 10 minutes.

### Phase 3 — Catalog + capability tags + IDENTITY tiers ✅ (2026-04-08)

**Status:** Shipped. `mix compile --warnings-as-errors` clean in both
repos; `agentic` 363 tests / `worth` 123 tests, 0 failures.

**Files created (agentic):**
- `lib/agentic/llm/catalog.ex` — GenServer with `find/1`, `lookup/2`,
  `for_provider/1`, `all/0`, `refresh/0`, `refresh_provider/1`, `info/0`
- `test/agentic/llm/catalog_test.exs` — 11 tests

**Files created (worth):**
- `lib/worth/workspace/identity.ex` — Frontmatter parser with `llm:`
  block schema validation via `nimble_options`
- `test/worth/workspace/identity_test.exs` — 6 tests

**Files modified (agentic):**
- `lib/agentic/model_router.ex` — Rewritten to query `Catalog.find/1`
  instead of `Free.free_routes/1`. Added `set_tier_overrides/1`,
  `clear_tier_overrides/0`. Cooldown table preserved as ETS-backed
  per-model-id health tracking.
- `lib/agentic/application.ex` — Added `Catalog` to supervision tree
  (before ModelRouter)
- `config/config.exs` — Added `catalog:` config block with persist path
- `lib/agentic.ex` — Added `:tier_overrides` option support alongside
  legacy `:model_routes`

**Files modified (worth):**
- `lib/worth/brain.ex` — `init/1` and `switch_workspace` handler now
  load tier overrides from IDENTITY.md frontmatter and pass them to
  `Agentic.ModelRouter.set_tier_overrides/1`
- `lib/worth/ui/sidebar.ex` — Status tab now shows catalog model count,
  provider fetch statuses, and context window metadata. Tab functions
  changed from `defp` to `def` for root.ex access.
- `lib/worth/ui/commands.ex` — Added `/catalog refresh` slash command
- `lib/worth/ui/root.ex` — Fixed pre-existing warnings (unused vars,
  missing Style alias)

**Key design decisions:**

1. **Catalog is schema-versioned at v1.** Persisted to `~/.worth/catalog.json`.
   On version mismatch, the cache is dropped and a network refresh is forced.
2. **Boot sequence:** Catalog loads from disk immediately (warm path),
   then fires async network refresh ~100ms later. The sidebar paints
   instantly from cached data.
3. **ModelRouter now queries Catalog for everything.** The old
   `ModelRouter.Free` module is still in the supervision tree (for
   backward compat during tests) but `resolve_all/1` no longer calls it.
   It can be deleted in a follow-up cleanup.
4. **Workspace tier overrides work via IDENTITY.md frontmatter.** The
   `llm.tiers.primary: "provider/model-id"` syntax is parsed on workspace
   switch and overrides the catalog's default tier resolution.
5. **`Catalog.find/1` supports compound capability filters:**
   `Catalog.find(has: [:chat, :tools, :free])` returns free models with
   tool support from any provider.

**Judgment calls Phase 4+ needs to know about:**

1. **`ModelRouter.Free` is still supervised but unused.** Tests that
   depend on it (the `Free` route discovery tests) still pass because
   the GenServer starts and refreshes independently. It can be safely
   removed in a cleanup commit.
2. **Catalog persistence happens on every refresh**, not just on clean
   shutdown. If the process crashes mid-write, the JSON may be corrupt.
   A follow-up should write to a temp file and rename atomically.
3. **The `project_result/1` projection layer still exists in `Worth.LLM`.**
   It should be retired once ModeRouter is updated to read `%Response{}`
   structs directly (deferring to a future cleanup).

### Phase 4 — Embeddings + reembed migration ✅ (2026-04-08)

**Status:** Shipped. `mix compile` clean in all three repos;
`recollect` 56 tests / `agentic` 386 tests / `worth` 128 tests, 0 failures.

**Files created (recollect):**
- `priv/repo/migrations/20260408000000_embedding_model_id_and_1536_dim.exs` — drops/recreates `embedding` columns on `recollect_chunks/entries/entities` as `vector(1536)`, adds nullable `embedding_model_id :string` column, recreates HNSW indexes
- `test/recollect/maintenance/reembed_test.exs` — 3 new tests covering callback path, `:stale_model` scope, and progress callback capture

**Files created (agentic):**
- `lib/agentic/llm.ex` — `Agentic.LLM` entry point with `chat/2`, `chat_tier/3`, `embed/2`, `embed_tier/3`
- `lib/agentic/llm/transport/ollama.ex` — full transport (chat + embeddings) hitting `/api/chat` and `/api/embed`, atom `stop_reason`, `parse_rate_limit/1` returns `nil`
- `lib/agentic/llm/provider/ollama.ex` — `OLLAMA_HOST` override, `:not_supported` on connection failure, embedding-model name detection by `embed`/`bge`/`nomic-embed`/`mxbai-embed`/`all-minilm`/`snowflake-arctic-embed` substrings
- `test/agentic/llm/transport/ollama_test.exs`, `test/agentic/llm/provider/ollama_test.exs`, `test/agentic/llm_test.exs`

**Files created (worth):**
- `lib/worth/memory/embeddings/adapter.ex` — `Worth.Memory.Embeddings.Adapter` implementing `Recollect.EmbeddingProvider` and delegating to `Agentic.LLM.embed_tier/3`
- `lib/worth/memory/embeddings/stale_check.ex` — boot-time check that compares configured model id vs latest stored row's id, logs at info level suggesting `/memory reembed`
- `lib/worth/tools/memory/reembed.ex` — `Worth.Tools.Memory.Reembed` thin wrapper around `Recollect.Maintenance.Reembed.run/1` with embed_fn pre-wired to `Agentic.LLM.embed_tier/3`
- `priv/repo/migrations/20260408000000_embedding_model_id_and_1536_dim.exs` — copy of the recollect migration (worth bundles its own copies of recollect migrations)

**Files modified (recollect):**
- `lib/recollect/embedding_provider.ex` — added optional `model_id/1` callback (chosen over the 3-tuple shape so existing 2-tuple returns from generate/embed stay intact); added `EmbeddingProvider.model_id/1` helper
- `lib/recollect/maintenance/reembed.ex` — full rewrite. New `run/1` accepts `:embedding_fn`, `:progress_callback`, `:scope` (`:nil_only` | `:all` | `{:stale_model, id}`), `:tables`, `:batch_size`. Default `embedding_fn` calls the global `EmbeddingProvider`. UUID handled via `uuid_to_binary/1` (handles both 16-byte binary and string forms)
- `lib/recollect/pipeline/embedder.ex` — every embedding write now passes `model_id` through to `store_embedding/5` which sets `embedding_model_id` alongside the vector via raw SQL, with the same UUID binary helper
- `lib/recollect/embedding/mock.ex` — 1536 dims, `model_id/1` returns `"mock-1536"`
- `lib/recollect/config.ex` — default dimensions 768 → 1536
- `lib/recollect/schema/{chunk,entity,entry}.ex` — added `embedding_model_id` field + cast
- `lib/mix/tasks/recollect.gen.migration.ex` — default `--dimensions` 768 → 1536
- **Deleted** `lib/recollect/embedding/{openai,ollama,openrouter}.ex` per the "adapter + delete" choice — worth's adapter is now the canonical embedding path, and these were duplicating logic that lives in agentic providers

**Files modified (agentic):**
- `lib/agentic/llm/transport.ex` — added optional `build_embedding_request/2` and `parse_embedding_response/3` callbacks
- `lib/agentic/llm/transport/openai_chat_completions.ex` — implements both new callbacks; covers OpenAI/OpenRouter/Groq/etc. via standard `/embeddings` endpoint
- `lib/agentic/llm/provider/openrouter.ex` — `fetch_catalog/1` now does dual fetch (`/models` + `/models?output_modalities=embeddings`), merges, dedupes by id, logs warning + degrades gracefully when embedding fetch fails
- `config/config.exs` — `Provider.Ollama` added to `providers:` list

**Files modified (worth):**
- `config/config.exs` — `:recollect` `embedding:` switched from `Recollect.Embedding.Mock` to `Worth.Memory.Embeddings.Adapter` with `tier: :embeddings, dimensions: 1536`. `config/test.exs` keeps Mock for fast unit tests
- `lib/worth/application.ex` — async `Worth.Memory.Embeddings.StaleCheck.run/0` after boot via `Worth.SkillInit` task supervisor
- `lib/worth/ui/commands.ex` — `/memory reembed` parse + dispatch (runs reembed in a background `Task` so the UI doesn't block) + help text entry

**Key design decisions:**

1. **`model_id/1` callback over 3-tuple return.** The plan offered both shapes;
   the callback is less invasive — existing host providers don't need to
   change their `generate/2`/`embed/2` return shape, and Reembed/Embedder
   read the id once per batch via `EmbeddingProvider.model_id/0`. Worth's
   adapter pulls the id from `opts[:model]` (or its `@default_model`)
   when called from the boot-time stale check.
2. **Reembed is now synchronous within a transaction**, not async-streamed.
   Async + Ecto sandbox tests don't mix — each spawned task hit
   `OwnershipError` because it left the test connection. Sync keeps the
   test path clean and the perf hit is irrelevant since the embedding
   HTTP call dominates.
3. **`:scope` selects the rows.** `:nil_only` is the default (current
   behavior), `:all` re-embeds everything, `{:stale_model, id}` re-embeds
   only rows where `embedding_model_id != id` or is NULL. Worth's
   `StaleCheck` uses the latter implicitly by suggesting the user run
   `/memory reembed` when the configured model differs from the most
   recent row's stored id.
4. **`Agentic.LLM.embed/2` and `embed_tier/3` always return a list of
   vectors plus a model id.** Single-text input is a 1-element list.
   `{:ok, [vector, ...], model_id}`. Caller flattens when it knows.
5. **OpenRouter dual catalog fetch.** Chat models from `/models`,
   embedding models from `/models?output_modalities=embeddings`. The
   second call's failures log + degrade rather than failing the entire
   refresh — chat models stay authoritative.
6. **Embedding tier resolution preference.** When IDENTITY.md doesn't
   pin a model, `embed_tier/3` walks the catalog and sorts: prefer
   `text-embedding-3-small` (the documented default), then non-Ollama
   providers, then anything else.
7. **Worth bundles its own copy of recollect migrations** in
   `priv/repo/migrations/`. The new migration was copied across — both
   repos run the migration independently.
8. **Recollect's `Recollect.Embedding.{OpenAI,Ollama,OpenRouter}` deleted.**
   Per decision in conversation: worth's adapter is the canonical embed
   path, and the agentic provider stack is where those providers now
   live. Mock stays for tests.
9. **`config/test.exs` in worth keeps Mock.** Routing tests through the
   adapter would require a live agentic catalog and providers — too
   heavy for unit tests. Mock now produces 1536-dim vectors so the
   schema dim matches production.

**Judgment calls Phase 5+ needs to know about:**

1. **Pre-existing async ownership warnings** in
   `Recollect.Pipeline.Embedder.embed_entry_async/1` show up in worth's test
   output. They are NOT Phase 4 regressions — `embed_entry_async` spawns
   into `Task.Supervisor` outside the test sandbox connection, and
   always has. Worth fixing in a future cleanup pass via `:caller`
   allowance on the task's connection checkout.
2. **Boot-time `StaleCheck` is best-effort** — wrapped in `rescue` and
   logs at `:debug` on failure, so a host that hasn't run the migration
   yet won't crash on boot.
3. **Reembed's transaction-wrapped sync writes** can be slow for large
   memory stores. If performance becomes a concern, the right fix is
   batched COPY-style upserts rather than reintroducing async tasks.
4. **`Worth.Memory.Embeddings.Adapter.model_id/1`** returns
   `text-embedding-3-small` when called with no `:model` opt — this is
   the *configured default*, not necessarily what `embed_tier/3` will
   actually pick when the catalog has a different match. The id stored
   on a row reflects what the underlying `embed_tier` call returned,
   not what `Adapter.model_id/0` reports — the embedder calls
   `EmbeddingProvider.model_id/0` once per batch so they can disagree
   if the adapter's default and the catalog's pick differ. Worth
   tightening in a follow-up by having the adapter cache the last
   model id from `embed_tier`.
5. **The slash command runs reembed in a fire-and-forget `Task`** —
   no progress bar, no completion notification beyond the initial
   "Re-embedding memories in the background..." message. The plan's
   "things to refine during implementation" section calls out wiring
   the `progress_callback` into a `:reembed_progress` agent event;
   that's the natural follow-up.

### Phase 5 — Usage / quota + cost telemetry ✅ (2026-04-08)

**Status:** Shipped. `mix compile` clean in all three repos;
`agentic` 386 tests / `recollect` 56 tests / `worth` 128 tests, 0 failures.

**Files created (agentic):**
- `lib/agentic/llm/usage.ex` — `%Usage{}` struct (provider, label, plan, windows, credits, error, fetched_at)
- `lib/agentic/llm/usage_window.ex` — `%UsageWindow{}` struct (label, used, limit, unit, reset_at)
- `lib/agentic/llm/usage_manager.ex` — `UsageManager` GenServer that polls every 5min via `Process.send_after`, exposes `snapshot/0`, `for_provider/1`, `refresh/0`, `refresh_provider/1`. Walks `ProviderRegistry.enabled/0` and calls `fetch_usage/1` on each, normalizing the result to `%Usage{}`. Skips providers that return `:not_supported`.

**Files created (worth):**
- `lib/worth/metrics.ex` — `Worth.Metrics` GenServer that attaches `:telemetry` handlers to `[:agentic, :llm_call, :stop]` and `[:agentic, :llm, :embed, :stop]`. Aggregates per-session totals (cost, calls, input/output/cache tokens, embed calls/cost) and a `by_provider` breakdown. Exposes `session/0`, `session_cost/0`, `by_provider/0`, `reset/0`.

**Files modified (agentic):**
- `lib/agentic/loop/stages/llm_call.ex` — `[:llm_call, :stop]` event now carries real `cost_usd` (computed from `Catalog.lookup` × token counts), plus `cache_read`/`cache_write` measurements and `provider` metadata. New private `compute_cost/2` + `route_model/1` + `safe_atom/1` helpers. The route map fields are `:provider_name` (string) and `:model_id` (string) — `safe_atom/1` converts to atom for catalog lookup.
- `lib/agentic/llm.ex` — `embed_via_provider/3` now wraps `Req.post` in a telemetry span and emits `[:agentic, :llm, :embed, :stop]` with `duration`, `input_count`, `cost_usd: 0.0` (placeholder — embedding cost requires per-vector pricing not yet in Model.cost). Helper `input_size/1` works for both list and single-string requests.
- `lib/agentic/llm/provider/openrouter.ex` — `fetch_usage/1` now parses the `/auth/key` response into a `%Usage{}` struct with `credits` from `data.usage`/`data.limit` and `windows` from `data.rate_limit`. Falls back to flat-body parsing when the response doesn't have a `data` envelope.
- `lib/agentic/application.ex` — `UsageManager` added to supervision tree after `Catalog`.

**Files modified (worth):**
- `lib/worth/application.ex` — `Worth.Metrics` added to supervision tree after `Worth.Telemetry`.
- `lib/worth/brain.ex` — `:get_status` now returns `Worth.Metrics.session_cost()` instead of `state.cost_total`. `switch_workspace` calls `Worth.Metrics.reset/0`.
- `lib/worth/ui/commands.ex` — `/clear` now resets `Worth.Metrics`. New `/usage` command shows provider quota + session cost breakdown. New `/usage refresh` triggers `UsageManager.refresh/0`. Help text updated.
- `lib/worth/ui/sidebar.ex` — New `:usage` tab added to `@tabs` (between `:status` and `:logs`). New `usage_tab/1` function renders provider quota lines from `UsageManager.snapshot()` and session totals + per-provider breakdown from `Worth.Metrics.session()`. Helper functions `usage_snapshot_lines/1`, `format_window/1`, `format_provider/1`, `format_int/1`.

**Key design decisions:**

1. **Anthropic `fetch_usage/1` stays `:not_supported`.** The plan's `/v1/organizations/<id>/usage` endpoint requires OAuth admin credentials, and OAuth is explicitly deferred to a follow-up iteration. Phase 5 ships with OpenRouter as the only provider exposing real quota — Groq has no public usage endpoint, OpenAI's `/v1/usage` requires admin keys, Ollama has no quota.
2. **Embedding cost is a 0.0 placeholder.** Embedding pricing is per-token but the response from `/v1/embeddings` doesn't include token usage in a portable shape, and `Model.cost` for embedding models stores per-1M-input pricing differently from chat models. Wiring real embedding cost requires (a) parsing usage out of each transport's embedding response, and (b) extending `Model.cost` to support embedding-only fields. Both deferred — telemetry events ship with the placeholder so the UI/Metrics path works end-to-end and the value can be flipped on without further plumbing.
3. **`compute_cost/2` lives in `LLMCall`, not in a standalone Cost module.** The plan referenced `Worth.LLM.Cost.calculate/2` which existed but was never wired up — the route walks happen inside agentic, so doing the lookup there avoids the host having to know about catalog details. Worth's `Worth.LLM.Cost` module is now dead code (kept for backward compat, can be deleted in a follow-up).
4. **Brain's `cost_total` field is now stale.** It still exists in the struct for backward compat with the dead `{:cost, amount}` event handler, but `:get_status` reads from `Worth.Metrics.session_cost()`. The `{:cost, amount}` handler in `Brain.handle_info/2` is now dead code paths nothing emits — removed in a follow-up cleanup is fine.
5. **Cost limit enforcement still happens in agentic via `ContextGuard`** (which already emits `[:context, :cost_limit]`). The brain doesn't need to track cost itself for the limit — the agent loop bails when its own `total_cost` exceeds `cost_limit`. Worth.Metrics is purely observational.
6. **`Worth.Metrics.reset/0` is called from `/clear` and `switch_workspace`.** Per-session metrics, not long-term history — matches the plan's "session-only, reset on /clear and on workspace switch" guidance.
7. **`Worth.Metrics.handle_event/4` is `cast`-only.** The telemetry callback runs in the caller's process and dispatches to the GenServer asynchronously to keep the agent loop fast. Order is preserved by the GenServer mailbox.
8. **The telemetry handler is registered in `Worth.Metrics.init/1`** via `:telemetry.attach_many/4` with handler id `"worth-metrics-handler"`. No detach on shutdown — the GenServer dying is rare enough that leaking the handler is acceptable for now.
9. **`/usage` command output is line-based plain text**, not a structured agent event. Mirrors `/cost`, `/status`, `/provider list` style. The sidebar `:usage` tab provides the live, continuously-updated view.

**Judgment calls Phase 6+ needs to know about:**

1. **Per-provider rate-limit windows are a stub.** OpenRouter exposes `data.rate_limit.{requests, interval}` but no `used` counter, so the sidebar shows the limit and a `?` for current usage. Anthropic's 5h/7d windows would populate `used` properly but require OAuth (deferred). Real per-window enforcement waits on Phase 5+.
2. **Catalog `cost` field is read with both atom and string keys.** `Model.cost` uses atom keys (`%{input: 3.0, ...}`), but the `compute_cost/2` helper falls back to string keys defensively in case a host populates the catalog with a JSON-decoded map. Belt and suspenders.
3. **`Worth.LLM.Cost`** is now unused dead code. Phase 6 can delete it cleanly along with `Worth.Brain.cost_total` and the dead `{:cost, amount}` handler.
4. **`UsageManager` polls with a fixed 5-minute interval.** The `:agentic, :usage, :refresh_interval_ms` config key is read at boot but there's no live reload. Restart the app to change it. Acceptable for an observability cache.
5. **The sidebar `:usage` tab is the 5th tab** (between `:status` and `:logs`). Tab number key `5` selects `:logs` per the existing `event_to_msg` handler — adding a 6th tab means either rebinding `5`→`:usage` and `6`→`:logs` (ugly because of tens), or accepting that `:usage` is reachable only via arrow keys. Left as-is for now; the user can adjust the keymap when they touch `root.ex` next.
6. **Phase 6 (Anthropic prompt caching) will need to read `cache_read`/`cache_write` from the response and populate `Response.usage`.** The telemetry path is already wired — `LLMCall` reads `usage["cache_read"]`/`usage["cache_creation_input_tokens"]`/`usage["cache_read_input_tokens"]` defensively, so Phase 6 just needs the transport to populate them and the cost computation will start showing real cache savings.

### Phase 6 — Anthropic prompt caching ✅ (2026-04-08)

**Status:** Shipped. `mix compile --warnings-as-errors` clean in
`agentic`; `agentic` 395 tests / `worth` 128 tests, 0 failures.

**Files modified (agentic):**
- `lib/agentic/llm/transport.ex` — extended `canonical_params` typespec to include `optional(:cache_control) => map() | nil`. Updated moduledoc to describe how transports may opt into provider-side prompt caching by reading `cache_control.prefix_changed`.
- `lib/agentic/llm/provider.ex` — `build_canonical/2` now reads `cache_control` from the input params (both atom and string keys) via a new `normalize_cache_control/1` helper. The normalized form is `%{stable_hash:, prefix_changed:}` regardless of input key style.
- `lib/agentic/llm/transport/anthropic_messages.ex` — `build_chat_request/2` now applies cache breakpoints when `cache_control.prefix_changed == false`. New helpers `cache_breakpoint_enabled?/1`, `apply_system_cache_control/2`, `apply_tool_cache_control/2`. The system prompt (whether passed as a string or as a list of content blocks) gets wrapped/marked with `cache_control: %{type: "ephemeral"}`. The last tool definition gets the same marker. `parse_chat_response/3` was already extracting `cache_creation_input_tokens` and `cache_read_input_tokens` into `Response.usage` (Phase 5 prep) — no change needed there.

**Files created (agentic):**
- `test/agentic/llm/transport/anthropic_messages_test.exs` — 9 new tests covering: `id/0`, no cache breakpoints when `cache_control` absent, no breakpoints when `prefix_changed: true`, system prompt cache marker when `prefix_changed: false`, last-tool cache marker, string-keyed cache_control map, nil-system handling, cache token extraction, and cache token defaults to 0.

**Key design decisions:**

1. **Cache the system prompt and the last tool definition.** Anthropic's prompt cache works in cumulative segments — a `cache_control` marker tells the API "cache everything up to and including this point." System prompt and tools change least often across turns, so caching them gets ~70% of the benefit per the plan's deliverable target. Per-message cache breakpoints would catch more savings but require knowing the stable/volatile message split, which lives in `LLMCall` and isn't exposed to the transport. Deferred as a refinement.
2. **`cache_control` flows in via canonical params, not via opts.** `LLMCall` already builds `base_params["cache_control"] = %{"stable_hash" => ..., "prefix_changed" => ...}`. `Worth.LLM.chat_with_route` passes the params through `Agentic.LLM.Provider.chat/3` which calls `build_canonical/2`. The new `build_canonical/2` reads `cache_control` and adds it to the canonical params map. Transports that don't care (OpenAIChatCompletions, Ollama) ignore the field; AnthropicMessages reads it.
3. **`normalize_cache_control/1` accepts both atom and string keys.** `LLMCall` uses string keys (`%{"prefix_changed" => false}`), but tests and direct callers may use atoms. The normalizer produces a uniform atom-keyed shape for the transport.
4. **System prompt structure.** Anthropic accepts both `system: "string"` and `system: [%{type: "text", text: ..., cache_control: %{type: "ephemeral"}}]`. When caching is enabled, we wrap a string into the structured form so we can attach the cache_control marker. When disabled, we leave the string as-is so the wire format stays minimal.
5. **Tool cache marker is key-style-agnostic.** `apply_tool_cache_control/2` checks whether the tool map uses atom or string keys (`Map.has_key?(last, :name)`) and inserts `cache_control` with the matching key style. Jason serializes both the same way on the wire, but mixing key styles within a single map looks ugly in iex/inspect. This keeps tools consistent.
6. **`parse_chat_response/3` already populated `cache_read`/`cache_write` from Phase 5 prep work.** The cost computation in `LLMCall.compute_cost/2` already reads these fields and multiplies them by `Model.cost.cache_read`/`cache_write`. Anthropic provider's `default_models/0` already has those rates. Phase 6 just connects the wire-level data flow.

**Judgment calls / follow-ups:**

1. **Cache hit ratio in the sidebar.** `Worth.Metrics` already accumulates `cache_read`/`cache_write` totals via the existing `[:agentic, :llm_call, :stop]` telemetry handler. The `:usage` sidebar tab shows them as raw counts (`Cache: N read / N write`). A "hit ratio" or "savings" line on top of those is straightforward to add but deferred — gets tracked in `BACKLOG.md`.
2. **Per-message cache breakpoints.** The current implementation caches up through tools. For very long system prompts that include workspace snapshots or large core instructions, this captures most of the savings. For long conversation histories where the early messages are stable, an additional cache breakpoint on the last stable user message would help. Requires plumbing the stable/volatile split point through to the transport — deferred as a future refinement.
3. **No real-world verification yet.** Tests cover the request shape and the parse path but not actual Anthropic API behavior. A live smoke test (with `LIVE_TESTS=1` env gate) is in `BACKLOG.md` under "Test infrastructure".
4. **No per-call opt-out.** Cache breakpoints are always added when `prefix_changed: false`. There's no way to disable caching for a specific call. The `cache_control` field could grow a `:disabled` flag if a future caller needs it, but no caller does today.
5. **Wire format on first turn is unchanged.** The first call after a prefix change has `prefix_changed: true` (LLMCall computes the hash, sees it differs from the previous, and sets the flag). On that call no cache_control markers are added — the request looks identical to the pre-Phase-6 wire format. Cache markers only start appearing on the second-and-subsequent calls of a stable prefix sequence, which is exactly when the cache pays off.
