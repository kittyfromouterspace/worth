# Model Selection & Routing Pipeline

This document describes the model selection, routing, and credential architecture across the three codebases: **recollect**, **agentic**, and **worth**.

---

## 1. Codebase Responsibilities

| Codebase | Role |
|----------|------|
| **recollect** (`../recollect`) | Model-agnostic framework. Defines behaviours for embeddings and extraction. Never owns a model name or API key. Delegates everything to the host app via callbacks. |
| **agentic** (`../agentic`) | Core LLM engine. Owns all model selection, routing, failover, error classification, health reporting, credential resolution, and cost tracking. |
| **worth** (`/home/lenz/code/worth`) | Host application. Provides user preferences as parameters, encrypted secret storage, Brain orchestration, and UI. Thin dispatch layer over agentic — contains no routing or failover logic. |

---

## 2. Recollect — Behaviour-Only Framework

### 2.1 Key Files

| File | Role |
|------|------|
| `lib/recollect/embedding_provider.ex` | Behaviour: `generate/2`, `embed/2`, `model_id/1`, `dimensions/1` |
| `lib/recollect/extraction_provider.ex` | Behaviour: `extract/2` |
| `lib/recollect/config.ex` | Resolves provider + opts from Application env |
| `lib/recollect/embedding/openrouter.ex` | Concrete OpenRouter embedding provider (default: `text-embedding-3-small`) |
| `lib/recollect/embedding/local.ex` | Local Bumblebee/NX embeddings (default: `all-MiniLM-L6-v2`, 384 dims) |
| `lib/recollect/embedding/mock.ex` | Deterministic SHA-256 mock for tests |
| `lib/recollect/extraction/llm_json.ex` | Extraction via `llm_fn` callback provided by host |
| `lib/recollect/pipeline/embedder.ex` | Orchestrates embedding calls |
| `lib/recollect/pipeline/extractor.ex` | Orchestrates entity/relation extraction |
| `lib/recollect/search/completion.ex` | LLM-augmented retrieval (requires `llm_fn`) |
| `lib/recollect/search/vector.ex` | Vector similarity search via pgvector |

### 2.2 Model Selection

Recollect has two model selection paths:

**Embeddings:** Config-driven chain:
```
config :recollect, embedding: [provider: Worth.Memory.Embeddings.Adapter, tier: :embeddings]
  → Recollect.Config.embedding_provider() → Worth.Memory.Embeddings.Adapter
  → Recollect.Config.embedding_opts() → [provider: ..., tier: :embeddings]
  → Worth.Memory.Embeddings.Adapter.generate/2 → resolves model + provider + credentials
```

**Extraction:** Requires `llm_fn` in opts. Worth does not configure Recollect extraction; it uses its own `FactExtractor` instead.

### 2.3 Credential Handling

Recollect's `Config.embedding_credentials/0` resolves through:
1. `credentials_fn` callback (host provides a zero-arity function returning `%{api_key: ...}` or `:disabled`)
2. Static config fallback (`:api_key` key in embedding config)
3. Mock mode (`mock: true` — no key needed)
4. Disabled if none of the above

Env-var fallback in `OpenRouter.resolve_api_key/1` remains for other host applications; Worth always provides `credentials_fn` so this path is never reached.

---

## 3. Agentic — Core LLM Engine

### 3.1 Architecture Layers

| Layer | Files | Purpose |
|-------|-------|---------|
| **Provider Behaviour** | `lib/agentic/llm/provider.ex`, `lib/agentic/llm/transport.ex` | Behaviour definitions |
| **Providers** | `lib/agentic/llm/provider/{anthropic,openai,openrouter,groq,ollama}.ex` | Concrete implementations |
| **Transports** | `lib/agentic/llm/transport/{anthropic_messages,openai_chat_completions,ollama}.ex` | HTTP protocol adapters |
| **Catalog** | `lib/agentic/llm/catalog.ex`, `lib/agentic/llm/model.ex` | Unified model catalog (static + dynamic discovery), persisted to disk |
| **Credentials** | `lib/agentic/llm/credentials.ex` | ETS store (priority 2) + env var fallback (priority 3). No redundant lookups — store and env paths are strictly sequential. |
| **Provider Registry** | `lib/agentic/llm/provider_registry.ex` | Provider name (atom or string) → module lookup |
| **Router** | `lib/agentic/model_router.ex`, `lib/agentic/model_router/{selector,analyzer,preference}.ex` | Manual (tier) and auto (analysis) routing |
| **Error Handling** | `lib/agentic/llm/error.ex`, `lib/agentic/llm/error_classifier.ex`, `lib/agentic/llm/error_patterns.ex` | Error classification and retry logic |
| **Rate Limiting** | `lib/agentic/llm/rate_limit.ex`, `lib/agentic/llm/usage.ex`, `lib/agentic/llm/usage_window.ex`, `lib/agentic/llm/usage_manager.ex` | Quota tracking per provider |
| **Loop** | `lib/agentic/loop/stages/llm_call.ex`, `lib/agentic/loop/context.ex` | Pipeline stage: resolve routes, walk with failover |
| **LLM** | `lib/agentic/llm.ex` | Top-level entry points: `chat_tier/3`, `embed_tier/3`. Embedding model preference is configurable (not hardcoded). |
| **Config** | `lib/agentic/config.ex` | Typed accessors for Application env, including `embedding_model/0` |
| **Application** | `lib/agentic/application.ex` | Supervision tree: ProviderRegistry, Catalog, UsageManager, ModelRouter, Credentials ETS |

### 3.2 Provider Implementations

| Provider ID | Transport | Base URL | Env Var(s) | Dynamic Catalog? |
|-------------|-----------|----------|------------|------------------|
| `:anthropic` | `AnthropicMessages` | `https://api.anthropic.com/v1` | `ANTHROPIC_API_KEY` | No |
| `:openai` | `OpenAIChatCompletions` | `https://api.openai.com/v1` | `OPENAI_API_KEY` | No |
| `:openrouter` | `OpenAIChatCompletions` | `https://openrouter.ai/api/v1` | `OPENROUTER_API_KEY` | Yes — fetches from `/api/v1/models` |
| `:groq` | `OpenAIChatCompletions` | `https://api.groq.com/openai/v1` | `GROQ_API_KEY` | Yes — fetches from `/models` |
| `:ollama` | `Ollama` | `http://localhost:11434` (or `OLLAMA_HOST`) | `OLLAMA_HOST` | Yes — fetches from `/api/tags` |

### 3.3 Transport Protocols

| Transport | Endpoint | Auth Header |
|-----------|----------|-------------|
| `AnthropicMessages` | `POST {base}/messages` | `x-api-key` + `anthropic-version: 2023-06-01` |
| `OpenAIChatCompletions` | `POST {base}/chat/completions` | `Authorization: Bearer {key}` |
| `Ollama` | `POST {base}/api/chat` / `POST {base}/api/embed` | None (local) |

### 3.4 Model Catalog

**Sources (priority order):**
1. **User overrides** from `~/.worth/config.exs` (source: `:user_config`)
2. **Dynamic discovery** — provider fetches models from its API (source: `:discovered`)
3. **Static defaults** from `provider.default_models/0` (source: `:static`)

Persisted to `~/.local/share/worth/catalog.json`. Refreshed every 10 minutes.

**Static default models:**

| Provider | Model | Tier | Cost (in/out per 1M) |
|----------|-------|------|---------------------|
| `:anthropic` | `claude-sonnet-4-20250514` | primary | $3 / $15 |
| `:anthropic` | `claude-haiku-4-20250414` | lightweight | $0.80 / $4 |
| `:anthropic` | `claude-opus-4-20250514` | primary | $15 / $75 |
| `:openai` | `gpt-4o` | primary | $2.50 / $10 |
| `:openai` | `gpt-4o-mini` | lightweight | $0.15 / $0.60 |
| `:openai` | `text-embedding-3-small` | embeddings | $0.02 |
| `:openrouter` | `minimax/minimax-m2.5:free` | primary | free |
| `:groq` | `llama-3.3-70b-versatile` | primary | $0.59 / $0.79 |
| `:groq` | `llama-3.1-8b-instant` | lightweight | $0.05 / $0.08 |
| `:ollama` | `llama3.2` | primary | free (local) |

### 3.5 Routing Modes

#### Manual Mode (tier-based)

1. Caller sets `model_selection_mode: :manual` and optionally `model_tier: :primary | :lightweight | :any`
2. Optionally `model_filter: :free_only`
3. Workspace tier overrides (from `IDENTITY.md`) remap tiers (e.g., `primary: "anthropic/claude-opus-4-6"`)
4. `ModelRouter.resolve_all/1` queries `Catalog.find(tier: tier, has: [:chat, :tools])`
5. Sorts by priority: primary=10, lightweight=20, free=30, other=50
6. Splits into healthy/unhealthy based on ETS cooldown tracking
7. Returns ordered route list for failover walking

#### Auto Mode (analysis-based)

1. Caller sets `model_selection_mode: :auto`, `model_preference: :optimize_price | :optimize_speed`
2. **Analyzer**: Sends request to a lightweight/free model with a structured prompt (`priv/prompts/model_analysis.md`). LLM classifies: complexity (simple/moderate/complex), required capabilities, vision/audio/reasoning needs, estimated token count. Falls back to `analyze_heuristic/1` (keyword matching) if no LLM callback.
3. **Selector**: Queries catalog for models matching required capabilities, deduplicates.
4. **Preference scoring**: Each candidate scored on:
   - Base: `log(cost)` for price optimization, tier-based for speed
   - Complexity adjustment: lightweight bonus for simple tasks, primary bonus for complex
   - Capability penalties: +100 for missing vision/audio, +5 for missing reasoning, +100 for missing required chat/tools
   - Context adjustment: bonus for large context windows when needed
5. Sorted ascending by score (lower = better). All ranked models returned for failover.

### 3.6 Credential Resolution

**Order (in `Credentials.resolve/2`):**

| Priority | Source | Notes |
|----------|--------|-------|
| 1 | `opts[:api_key]` | Injected by host app per-call |
| 2 | ETS table `:agentic_credentials` | Runtime store, populated by Worth on vault unlock. Checked first via `find_first_in_store/1`. |
| 3 | `System.get_env(var)` | Environment variable fallback for other host apps. Only reached after ETS returns `:none` — no redundant ETS lookup. |
| 4 | N/A for `:ollama` | No key required, always resolves |

The store and env paths are strictly sequential: `resolve_from_store_or_env/1` checks ETS first, and only if that returns `:none` does it fall through to `resolve_from_env/1`, which checks only `System.get_env` (no re-checking ETS).

### 3.7 Failover

Routes sorted by priority. `do_try_routes` walks them:

**In the loop pipeline (`LLMCall` stage):**
- Routes resolved via `ModelRouter.resolve_all/1`
- Each route injected as `params["_route"]` before calling `llm_chat` callback
- On success: `ModelRouter.report_success()` — resets health
- On failure: Error classified via `classify_error/1`, route marked unhealthy with cooldown, next route tried
- All routes exhausted: calls `llm_chat` without `_route` as final fallback

**For standalone tier-based calls (`Agentic.LLM.chat_tier/3`):**
- Same failover logic, but uses a `llm_chat:` callback provided by the caller (or falls back to direct `Provider.chat/3`)
- Worth provides `Worth.LLM.chat/1` as the callback to inject credentials per-route

### 3.8 Error Classification

Used by both `LLMCall` and `chat_tier/3`:

`ErrorClassifier` combines:
- Provider-specific classification fields (from `%Error{}` structs)
- HTTP status code mapping
- Regex/string pattern matching from `ErrorPatterns`

Categories: `:rate_limit`, `:auth_error`, `:connection_error`, `:context_length_exceeded`, `:other`

---

## 4. Worth — Host Application

### 4.1 Key Files

| File | Role |
|------|------|
| `lib/worth/llm.ex` | **Thin dispatch module** (~190 lines). Extracts route from params, resolves provider + credentials, dispatches to `Agentic.LLM.Provider`. No routing, failover, or error classification logic. `chat_tier/2` pre-builds a credential cache to avoid per-route DB lookups during failover. |
| `lib/worth/config.ex` | Runtime config Agent. Merges compile-time env + Settings DB preferences. `save_routing/1` atomically persists routing config to both in-memory state and DB. |
| `lib/worth/brain.ex` | Per-workspace GenServer. Builds run_opts with model routing parameters, calls `Agentic.run/1`. |
| `lib/worth/brain/session.ex` | Session resume logic. Builds callbacks with simplified `llm_chat` → `Worth.LLM.chat/1`. |
| `lib/worth/settings.ex` | Settings CRUD facade. Preferences (plaintext) + Secrets (AES-GCM encrypted). On lock: clears Agentic ETS. |
| `lib/worth/settings/setting.ex` | Ecto schema for `worth_settings` table. |
| `lib/worth/settings/master_password.ex` | Ecto schema for master password (PBKDF2 hash + salt). |
| `lib/worth/vault.ex` | Cloak Vault. AES-GCM encryption. Starts locked, runtime key configuration. |
| `lib/worth/vault/password.ex` | PBKDF2 password hashing and key derivation (100k iterations, SHA-256). |
| `lib/worth/encrypted/binary.ex` | Cloak.Ecto.Binary type for encrypted DB columns. |
| `lib/worth/config/setup.ex` | First-run wizard. Workspace dir, API key, embedding model. |
| `lib/worth/workspace/identity.ex` | `IDENTITY.md` YAML frontmatter parser for tier overrides and cost ceiling. |
| `lib/worth/workspace/context.ex` | System prompt builder (identity + skills + memory). |
| `lib/worth/memory/embeddings/adapter.ex` | Worth's `Recollect.EmbeddingProvider` implementation. Resolves provider/credentials via Agentic. |
| `lib/worth/memory/manager.ex` | Memory facade. Calls `Recollect.remember/2`, `Recollect.search/2`. |
| `lib/worth/memory/fact_extractor.ex` | LLM-powered fact extraction with regex fallback. Uses `chat_tier/2` for background LLM calls. |
| `lib/worth/metrics.ex` | Per-session cost/token telemetry aggregator. Read-only tracking, no enforcement. |
| `lib/worth/agent/tracker.ex` | Active agent session tracker (ETS + telemetry). |
| `config/config.exs` | Compile-time config. Default provider, models. No API key env refs. Recollect `credentials_fn` wired to vault. |
| `config/test.exs` | Test config. Sets `credentials_fn: nil` to prevent deep-merge override of mock provider. |
| `lib/worth_web/live/commands/model_commands.ex` | `/model` CLI commands for searching/setting models. Uses `Worth.Config.save_routing/1` for persistence. |
| `lib/worth_web/live/chat_live/settings_component.ex` | UI settings panel. Routing mode, cost limits. Uses `Worth.Config.save_routing/1` for persistence. |

### 4.2 LLM Dispatch (`lib/worth/llm.ex`)

Worth.LLM is a thin dispatch module (~190 lines) with three entry points:

- **`stream_chat/2`** — Streaming dispatch for a single route. Agentic's `LLMCall` stage resolves routes and injects `_route` into params. Worth extracts the route, resolves the provider module and credentials, and calls `Provider.stream_chat`.
- **`chat/1`** — Non-streaming dispatch for a single route. Same pattern as `stream_chat` but without streaming.
- **`chat_tier/2`** — Tier-based dispatch for background tasks (fact extraction, skill refinement). Pre-builds a `creds_cache` map (provider id → `{module, api_key}`) by resolving credentials for all enabled providers once upfront, then delegates to `Agentic.LLM.chat_tier/3` with a `dispatch_with_cache/2` callback that uses the cache instead of re-querying the DB per route attempt.

**Provider resolution** uses `Agentic.LLM.ProviderRegistry.get/1` (accepts atoms and strings via internal string→atom conversion) — a single call, no manual atom conversion needed.

**Credential injection** per-call:
```elixir
resolve_api_key(provider_module)
  → provider_module.env_vars()           # e.g., ["OPENROUTER_API_KEY"]
  → Enum.find_value(env_vars, fn var ->
      Worth.Settings.get(var)             # reads from encrypted vault
    end)
```

**Default fallback** (when no `_route` in params): reads `config[:llm][:default_provider]` and `config[:llm][:providers][provider][:default_model]`, dispatches directly to that provider.

### 4.3 Brain Model Routing (`lib/worth/brain.ex`)

**`apply_model_routing/1`:**

Reads `Worth.Config.get([:model_routing])` which holds:
```elixir
%{mode: "auto" | "manual",
  preference: "optimize_price" | "optimize_speed",
  filter: "free_only" | nil,
  manual_model: %{provider: ..., model_id: ...}}
```

Translates to Agentic `run_opts`:
- Auto: `%{model_selection_mode: :auto, model_preference: :optimize_price, model_filter: :free_only}`
- Manual with pinned model: `%{model_selection_mode: :manual, tier_overrides: %{primary: "provider/model_id"}}` — converts `manual_model` into a `tier_overrides` map so Agentic prepends the chosen model to the failover list
- Manual without pinned model: `%{model_selection_mode: :manual}` — Agentic resolves routes with full failover

If no manual model is pinned, `default_model_override/0` generates a `tier_overrides` from config defaults. User's explicit manual model selection always takes precedence.

**Turn-by-turn mode** forces `model_selection_mode: :manual` regardless of user config.

**`default_model_override/0`:**

If `config[:llm][:default_provider]` has a `:default_model` and no manual model is pinned, creates tier override:
```elixir
%{primary: "openrouter/minimax/minimax-m2.5:free"}
```
Skipped if `tier_overrides` was already set by manual model selection — user's explicit choice wins over global defaults.

**Workspace tier overrides** (from `IDENTITY.md`):
```yaml
llm:
  tiers:
    primary: "anthropic/claude-opus-4-6"
    lightweight: "anthropic/claude-haiku-4-5"
  cost_ceiling_per_turn: 0.10
```

Parsed by `Worth.Workspace.Identity.tier_overrides/1`, set via `Agentic.ModelRouter.set_tier_overrides/1` at Brain init.

### 4.4 Secret Handling — Vault-Only

#### Layer 1: Encrypted database storage (sole source of truth)

`Worth.Settings` stores secrets in the `worth_settings` table:
- **Encrypted only** (category `"secret"`): `encrypted_value` column, AES-GCM via Cloak Vault. Requires vault unlock.
- No plaintext fallback — `put/3` with category `"secret"` requires the vault to be unlocked (encrypted column).

#### Layer 2: Vault

`Worth.Vault` uses Cloak with AES-GCM:
- Starts locked (no ciphers configured)
- Unlocked by master password → `Worth.Vault.Password.derive_key/2` (PBKDF2, 100k iterations, SHA-256) → 32-byte key
- On unlock: `populate_credentials_from_vault/0` populates Agentic ETS and triggers catalog refresh
- On lock: ETS cleared via `Credentials.delete/1` per key

#### Layer 3: Per-call injection

`Worth.LLM.credential_opts/1` resolves key from `Worth.Settings.get(var)` and passes directly as `api_key:` to `Agentic.LLM.Provider`. This bypasses env var lookup entirely.

#### Layer 4: Recollect credentials_fn

A `credentials_fn` is configured in `config/config.exs` for Recollect's embedding pipeline that reads from `Worth.Settings.get("OPENROUTER_API_KEY")`, returning `:disabled` when no key is available.

**Boundary diagram:**

```
┌─────────────────────────────────────────────────────────┐
│  WORTH (host application)                                │
│                                                          │
│  Vault (encrypted DB) ──► Worth.LLM.credential_opts/1   │
│        │                      │                          │
│        │                      ▼                          │
│        │              api_key: injected via opts         │
│        │                      │                          │
│        │                      ▼                          │
│        └────────────► Agentic ETS (on unlock only)      │
│                           │                              │
└───────────────────────────┼──────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────┐
│  AGENTIC (shared library)                                │
│                                                          │
│  Credentials.resolve/2                                   │
│    1. opts[:api_key]  ← Worth always injects this       │
│    2. ETS store       ← Worth populates on unlock       │
│    3. System.get_env  ← available for OTHER host apps   │
│                                                          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  MNEME (shared library)                                  │
│                                                          │
│  resolve_api_key/1                                       │
│    1. opts[:api_key] / credentials_fn  ← Worth injects  │
│    2. System.get_env    ← available for OTHER host apps │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

Worth guarantees credentials reach agentic and recollect through **injection** (priority 1 in their resolution chains). The env-var fallbacks in both libraries remain intact for other consumers but are never reached under Worth.

**Known secret keys:** `["OPENROUTER_API_KEY", "ANTHROPIC_API_KEY", "OPENAI_API_KEY"]`

**No export to process environment.** Worth never calls `System.put_env` with secrets.

#### Vault Lock/Unlock Behavioral Contract

| State | What works | What doesn't |
|-------|-----------|--------------|
| **No password set** (first run) | Setup wizard prompts for master password + API keys. On submit: vault created, unlocked, credentials stored encrypted. | LLM calls, embeddings, catalog refresh — nothing can authenticate. |
| **Password set, vault locked** | UI renders. Preferences (theme, routing, memory) readable. Chat history visible. Agentic ETS is empty. | All LLM calls fail (`:not_configured` — opts have no `api_key`, ETS is empty, env has nothing). Embeddings disabled. User sees "Unlock vault" prompt. |
| **Password set, vault unlocked** | ETS populated from vault. Per-call injection active. LLM calls, embeddings, catalog refresh all succeed. | — |
| **Vault locked after being unlocked** | Same as "vault locked". ETS cleared. In-flight requests complete; new ones fail. | No new LLM calls until re-unlock. |

### 4.5 Embedding Pipeline (Memory)

Separate from chat. `Worth.Memory.Embeddings.Adapter` implements `Recollect.EmbeddingProvider`:

1. `model_id/1` → opts `:model` → opts `:model_override` → `Worth.Config.get([:memory, :embedding_model])` → default `"text-embedding-3-small"`
2. `resolve_provider/1` → opts `:provider` via `ProviderRegistry.get/1` → model lookup in `Agentic.LLM.Catalog` for `:embeddings` tag → fallback `ProviderRegistry.get(:openrouter)`
3. Credentials via `Agentic.LLM.Credentials.resolve(provider)`
4. `provider.transport().build_embedding_request/2` → `Req.post` → `provider.transport().parse_embedding_response/3`

**Embedding model preference in Agentic:** When no explicit model+provider pair is given, `Agentic.LLM.resolve_embedding_target/2` sorts candidates by `embedding_preference/2`, which prefers a configurable `preferred_id` (from `Agentic.Config.embedding_model/0` or an explicit `:model` opt) over hardcoded names. Falls back to neutral sorting (non-Ollama > Ollama) if no preference is set.

### 4.6 Cost Tracking

- `cost_limit` (default $5.00) from `config/config.exs`, changeable via UI settings
- Passed to `Agentic.run/1` as `run_opts[:cost_limit]` — enforced inside Agentic
- `Worth.Metrics` GenServer attaches to `[:agentic, :llm_call, :stop]` telemetry:
  - Accumulates: `cost`, `calls`, `input_tokens`, `output_tokens`, `cache_read`, `cache_write`
  - Tracks `by_provider` breakdown
  - `session_cost/0` returns current total USD
  - `reset/0` on `/clear` or workspace switch
- `IDENTITY.md` can set `cost_ceiling_per_turn` (per-turn limit)

### 4.7 Compile-time Defaults

From `config/config.exs`:

```elixir
config :worth,
  llm: [
    default_provider: :openrouter,
    providers: %{
      openrouter: [
        default_model: "minimax/minimax-m2.5:free"
      ],
      anthropic: [
        default_model: "claude-sonnet-4-20250514"
      ]
    }
  ],
  cost_limit: 5.0

config :recollect,
  embedding: [
    provider: Worth.Memory.Embeddings.Adapter,
    tier: :embeddings,
    credentials_fn: fn ->
      case Worth.Settings.get("OPENROUTER_API_KEY") do
        key when is_binary(key) and key != "" -> %{api_key: key}
        _ -> :disabled
      end
    end
  ]

config :agentic,
  providers: [
    Agentic.LLM.Provider.OpenRouter,
    Agentic.LLM.Provider.Anthropic,
    Agentic.LLM.Provider.OpenAI
  ],
  catalog: [persist_path: Path.join(System.get_env("HOME") || "~", ".local/share/worth/catalog.json")]
```

No `api_key: {:env, "VAR"}` tuples anywhere in Worth's config. No `resolve_env_values` function. All credential resolution goes through the vault.

---

## 5. End-to-End Pipeline

```
USER SENDS MESSAGE
  │
  ▼
Worth.Brain.handle_call({:send_message, text})
  │
  ├── build_callbacks(state, brain_pid)
  │     └── llm_chat = fn params ->
  │           on_chunk = if internal, do: noop, else: broadcast
  │           Worth.LLM.stream_chat(params, on_chunk)
  │         end
  │
  ├── apply_model_routing(run_opts)
  │     ├── reads Worth.Config.get([:model_routing])
  │     ├── auto:   sets model_selection_mode: :auto, model_preference, model_filter
  │     ├── manual (with manual_model): sets model_selection_mode: :manual
  │     │     + tier_overrides: %{primary: "provider/model_id"}
  │     ├── manual (no manual_model): sets model_selection_mode: :manual
  │     └── default_model_override() → tier_overrides from config (only if not already set)
  │
  └── Agentic.run(run_opts)
        │
        ├── Context.new with routing params
        │
        └── LLMCall.call(ctx, next)  [pipeline stage]
              │
              ├── ModelRouter.resolve_for_context(ctx)
              │     │
              │     ├── MANUAL: Catalog.find(tier, has: [:chat, :tools])
              │     │         → workspace tier overrides applied
              │     │         → sorted by priority (primary=10, lightweight=20, free=30)
              │     │         → healthy/unhealthy split
              │     │
              │     └── AUTO:   Analyzer → classify complexity
              │               Selector → fetch candidates from catalog
              │               Preference.score → rank by cost/speed/capability
              │               → all ranked models as routes
              │
              └── do_try_routes(routes, ...)
                    │
                    ├── For each route:
                    │     │
                    │     ▼
                    │   llm_chat.(params_with_route)
                    │     │
                    │     ▼
                    │   Worth.LLM.stream_chat(params, on_chunk)
                    │     │
                    │     ├── route_from_params(params)
                    │     │     → extracts params["_route"] (injected by Agentic)
                    │     │
                    │     ├── resolve_provider(name)
                    │     │     → ProviderRegistry.get(name) → provider module
                    │     │
                    │     ├── credential_opts(provider_module)
                    │     │     → resolve_api_key(module)
                    │     │     → Worth.Settings.get("OPENROUTER_API_KEY")
                    │     │     → [api_key: "sk-or-..."]
                    │     │
                    │     └── Provider.stream_chat(provider_module, params, opts)
                    │           │
                    │           ├── Credentials.resolve(provider, opts)
                    │           │     → uses injected :api_key (priority 1)
                    │           │
                    │           ├── transport.build_chat_request(canonical, transport_opts)
                    │           │
                    │           ├── Req.post(url, json: body, headers: headers, into: stream_fun)
                    │           │
                    │           └── parse response → {:ok, %Response{content, stop_reason, usage, cost}}
                    │
                    ├── On success: ModelRouter.report_success()
                    │
                    └── On failure: ErrorClassifier → mark unhealthy (cooldown) → try next route
                        If all routes exhausted: call llm_chat without _route (default fallback)
```

### Background Tasks (fact extraction, skill refinement)

```
Worth.Brain (or FactExtractor/Refiner)
  │
  └── Worth.LLM.chat_tier(%{messages: messages}, :lightweight)
        │
        ├── build_creds_cache()  ← resolves credentials once for all enabled providers
        │
        └── Agentic.LLM.chat_tier(params, :lightweight,
              llm_chat: fn p -> dispatch_with_cache(p, creds_cache) end)
              │
              ├── ModelRouter.resolve_all(:lightweight)
              │
              └── walk_routes(routes, params, :lightweight, llm_chat, ...)
                    │
                    ├── For each route: llm_chat.(params_with_route)
                    │     └── dispatch_with_cache(params, creds_cache)
                    │           → Map.get(creds_cache, provider_name) → {module, api_key}
                    │           → Provider.chat(module, params, [model: ..., api_key: ...])
                    │           (no per-route DB lookup — credentials from cache)
                    │
                    ├── On success: report_success
                    └── On failure: classify → mark unhealthy → try next
```

---

## 6. Embedding Pipeline

```
Worth.Memory.Manager
  │
  ├── Recollect.remember(text, opts)
  │     → Recollect.Pipeline.Embedder.embed_entry_async/1
  │     → Recollect.EmbeddingProvider.embed(text)
  │     → Worth.Memory.Embeddings.Adapter.embed(text, opts)
  │           │
  │           ├── model_id/1
  │           │     → opts[:model] → opts[:model_override]
  │           │     → Worth.Config.get([:memory, :embedding_model])
  │           │     → default: "text-embedding-3-small"
  │           │
  │           ├── resolve_provider/1
  │           │     → Agentic.LLM.Catalog lookup for :embeddings tag
  │           │     → fallback: :openrouter
  │           │
  │           ├── Agentic.LLM.Credentials.resolve(provider)
  │           │
  │           └── provider.transport().build_embedding_request → Req.post → parse
  │
  └── Recollect.search(query, opts)
        → Recollect.Search.Vector.search(query, opts)
        → embed query via same pipeline
        → SQL vector similarity via pgvector
```

---

## 7. Credential Flow Summary

Every entry point where Worth calls into agentic or recollect injects credentials from the vault:

| Entry point | How credentials reach the library | Env-var fallback reached? |
|-------------|----------------------------------|---------------------------|
| `Worth.LLM.stream_chat/2` → `Provider.stream_chat/3` | `credential_opts/1` injects `api_key:` kwarg | No — `opts[:api_key]` is priority 1 |
| `Worth.LLM.chat/1` → `Provider.chat/3` | Same injection | No |
| `Worth.LLM.chat_tier/2` → `Agentic.LLM.chat_tier/3` | Pre-built `creds_cache` (provider→key map) passed to `dispatch_with_cache/2` callback | No |
| `Worth.Memory.Embeddings.Adapter` | `Credentials.resolve(provider)` | Only if ETS empty — Worth populates ETS on unlock |
| Recollect internal paths | `credentials_fn` callback | No — callback reads from vault |

On vault lock, ETS is cleared, so even the ETS path returns nothing. The env-var fallback in agentic/recollect would technically be reached, but Worth never writes to `System.put_env`, so there is nothing to find.

---

## 8. Environment Variables

| Variable | Used By | Purpose |
|----------|---------|---------|
| `OPENROUTER_API_KEY` | Worth (encrypted vault only), Agentic (fallback for other apps), Recollect (fallback for other apps) | OpenRouter API auth |
| `ANTHROPIC_API_KEY` | Worth (encrypted vault only), Agentic (fallback for other apps) | Anthropic API auth |
| `OPENAI_API_KEY` | Worth (encrypted vault only), Agentic (fallback for other apps) | OpenAI API auth |
| `GROQ_API_KEY` | Agentic (fallback for other apps) | Groq API auth |
| `OLLAMA_HOST` | Agentic | Override Ollama base URL (default `http://localhost:11434`) |

**Worth resolution path (vault-only):** `Worth.Settings.get(key)` → per-call `api_key:` injection → Agentic uses injected key directly (priority 1 in `Credentials.resolve/2`). On vault unlock, ETS is also populated as a secondary path. No `System.get_env` or `System.put_env` for secrets.

**Agentic/Recollect env-var fallbacks** remain available for other host applications but are never used by Worth.
