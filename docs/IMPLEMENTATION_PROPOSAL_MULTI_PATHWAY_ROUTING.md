# Implementation Proposal: Multi-Pathway Model Routing with Subscription Tracking

## Implementation Progress

Tracked here as the work lands. Sub-task IDs match the TaskCreate list.

| Phase / Step | Status | Notes |
|--------------|--------|-------|
| 1.1 Canonical GenServer + models.dev fetcher | ✅ done | `agentic/lib/agentic/llm/canonical.ex` — ETS-cached, JSON snapshot at `~/.agentic/models_dev.json`, 24h refresh, static overrides for Codex/Claude Code/z.ai |
| 1.2 Model struct: `canonical_id` field | ✅ done | additive; capabilities were already per-pathway via `MapSet` |
| 1.3 Provider→Canonical wiring | ✅ done | done at the Catalog layer via `backfill_canonical/2` so individual providers don't need edits |
| 1.4 `ProviderAccount` struct + resolver | ✅ done | `agentic/lib/agentic/llm/provider_account.ex` with `default/1`, `for_provider/2`, `quota_pressure/1` |
| 1.5 `Catalog.find/1` — `canonical:` and `requires:` queries + `by_canonical/1` | ✅ done | |
| 1.6 `Preference.score_pathway/3` (renamed from /4 — collision with auto-mode `score/3`) | ✅ done | adds `cost_profile_score/3`, `availability_score/1`; quota_pressure lives on `ProviderAccount` |
| 1.7 `ModelRouter.routes_for_tier/2` groups by canonical, scores pathways | ✅ done | routes carry `canonical_model_id`, `account_id`, `cost_profile`, `pathway_score`, `pathway_fallbacks` |
| 1.8 Sticky record carries `canonical_id` | ✅ done | full canonical-as-bucket-key follow-up deferred; current sticky still uses `{tier, filter}` bucket |
| 1.9 `mix agentic.routes` debug command | ✅ done | `agentic/lib/mix/tasks/agentic.routes.ex` |
| **Phase 1 status** | ✅ all 568 tests pass | additive — no test churn |
| 2 Gateway cost telemetry + SQLite SpendTracker | ✅ done | `:ex_money` + `:exqlite` deps; `agentic/lib/agentic/llm/spend_tracker.ex`; Gateway `:stop` event now carries `actual_cost` (OpenRouter `usage.cost`) and `estimated_cost` (catalog-derived); `Agentic.Cldr` backend |
| 3 CLI provider wrappers + `model_arg` injection | ✅ done | `Provider.ClaudeCode/OpenCode/Codex` (catalog-only); `model_arg: "--model"` set on each protocol's `build_config/1`, args injected from `profile_config[:model]` (Brain passes the resolved route's `model_id`) |
| 4 Worth Provider Management UI | ✅ done | `Worth.LLM.PathwayPreferences` + `Worth.LLM.ProviderAccountResolver`; Provider Accounts, Admin Keys, and Model Pathways settings cards; Brain pushes `[ProviderAccount]` and pathway preferences into `ctx.metadata` for every agent run; router applies a −100 score bonus for the user's preferred pathway as a hard tie-breaker |
| 5 z.ai provider + admin-key polling (agentic side) | ✅ done | `Agentic.LLM.Provider.Zai` (OpenAI-compatible Bearer, static GLM list); `Agentic.LLM.AdminUsage` with `poll_anthropic/2` + `poll_openai/2` returning normalized buckets with Money-typed `actual_cost` |
| 5 Worth-side admin-key UI | ✅ done | `Worth.LLM.AdminKeys` (vault-backed); admin key entry card in settings with explicit "read-only billing" disclosure |
| 6 Subscription dashboard | ✅ done | `Worth.LLM.UsageSummary` + `WorthWeb.Components.Usage`; `/usage` slash command repurposed to open the dashboard view; per-provider cards with effective $/Mtok, monthly tokens, today/month spend, balance, subscription savings |
| 7 OXR relay (deferred) | 🕓 deferred | future milestone |
| **Refactor: detected CLI agents drive pathway suggestions** | ✅ done | `Worth.LLM.ProviderTaxonomy` classifies provider as `:coding_agent_cli` vs `:http_api`; CLI providers default to `:subscription_included` cost_profile (auto, no setup); Provider Accounts UI shows "auto-detected" badge + CLI tag; Model Pathways UI shows implicit picks as dashed-border buttons; Brain merges implicit CLI pathway picks into `pathway_preferences` so the router score-bonus applies. User-set explicit preferences always win. |

**Verification:** `mix test` in `agentic` → 568 tests pass; `mix test` in `worth` → 198 tests pass.

**Out of scope, explicitly deferred:**

- The Worth-side scheduled poller that calls `Agentic.LLM.AdminUsage` and reconciles results against SpendTracker rows. The polling adapter exists (Phase 5) and the admin-key vault entry exists (Phase 4) — what remains is a `Worth.LLM.AdminUsagePoller` GenServer that fires every N minutes when admin keys are present. Trivial follow-up; left out to keep the diff focused on UI surfaces.
- FX rate provider for the Money library is configured but `auto_start_exchange_rate_service` is `false` in dev/test. v1 production builds will set `WORTH_OXR_APP_ID` env var and flip the flag; v2 (Phase 7) adds a Worth-hosted relay so all clients share rate fetches.

Legend: ⏳ pending · 🔄 in progress · ✅ done · 🕓 deferred

---

## Status: DRAFT — For Research & Review (rev 2)

**Authors:** Agentic / Worth team
**Date:** 2026-04-25 (rev 2)
**Scope:** Agentic runtime + Worth desktop app

### Revision history

- **rev 1 (2026-04-25):** initial proposal
- **rev 2 (2026-04-25):** review feedback incorporated — `ProviderAccount` separation,
  per-pathway capabilities, graded availability, quota-pressure scoring, unified
  `[:agentic, :llm, :request, :complete]` telemetry covering CLI subprocesses via
  the existing Gateway proxy auto-injection, subscription amortization, currency
  normalization via `ex_money`, SQLite-backed `SpendTracker`, centralized
  canonical mapping, `endpoints` field dropped, no migration of sticky routes
  (no users yet).
- **rev 3 (2026-04-25):** open-question research resolved —
  - `Agentic.LLM.Canonical` becomes a **fetched-and-cached** module backed by
    [models.dev](https://models.dev) (50+ providers, ~all major canonical IDs,
    free no-auth API), with a small static override table for things models.dev
    doesn't cover (Codex internal aliases, Worth-specific renames). See §3.6.
  - **Anthropic Admin API** — `GET /v1/organizations/usage_report/messages` and
    `/v1/organizations/cost_report` confirmed; require a separate
    `sk-ant-admin-...` org-admin key, organization-tier accounts only.
    **No weekly-cap header exists** — Pro/Max plan caps are visible only in the
    Console, so we cannot auto-populate `ProviderAccount.quotas` from API
    headers. The user enters their plan tier manually; we estimate the cap from
    Anthropic's published plan limits.
  - **OpenAI Admin API** — `GET /v1/organization/usage/{completions,...}` for
    tokens and `/v1/organization/costs` for USD; require a separate
    `sk-admin-...` admin key minted by an org Owner. Available on all paid
    tiers, not Enterprise-only.
  - **z.ai** — global endpoint `https://api.z.ai/api/paas/v4/`, OpenAI-compatible
    Bearer auth, **no `/models` endpoint, no balance/quota endpoint** (link out
    to z.ai dashboard). USD pricing on the global endpoint, CNY on
    `bigmodel.cn`. Coding-Plan keys must hit `/api/coding/paas/v4/`.
  - **OpenCode / Codex** — OpenCode has `opencode models` and pulls from
    models.dev too (reuse our fetch). Codex has no model list command; we
    hardcode its rolling aliases (`gpt-5.5`, `gpt-5.4`, `gpt-5.3-codex`, …) in
    the `Canonical` static-override table.
  - **OXR distribution** — Worth ships an OXR app id in v1; in a future release
    Worth's own server exposes an OXR-compatible API that all Worth clients
    poll. See §5.5.1 for the migration plan.

---

## 1. Executive Summary

We want to route the same underlying model (e.g. Claude Sonnet 4) through multiple providers with different cost structures, and let the user pick the cheapest or fastest path. We also want to track subscription credit consumption and expose model selection for coding agents (Claude Code, OpenCode, Codex) that currently hide their model picker from us.

This proposal covers:

1. **Canonical model + pathway architecture** — group the same model weights across providers
2. **Coding agent model selection** — expose `--model` args that the CLIs already support
3. **Subscription credit tracking** — per-provider spend/remaining credit dashboards
4. **Gateway cost interception** — use our HTTP proxy to capture pricing from responses

---

## 2. Problem Statement

### 2.1 Same Model, Multiple Economics

| Model Family | Direct API | Coding Agent CLI | OpenRouter |
|--------------|-----------|------------------|------------|
| Claude Sonnet 4 | Anthropic API — subscription included | Claude Code — subscription included | $3 / $15 per 1M tokens |
| Claude Opus 4 | Anthropic API — subscription included | Claude Code — subscription included | $15 / $75 per 1M tokens |
| GPT-5.5 | OpenAI API — subscription metered | Codex CLI — subscription included | varies |
| GLM-4.7 | z.ai API — subscription included | OpenCode — subscription included | varies |

Today Agentic has **no concept** that these are the same model. The Catalog stores:

- `{:anthropic, "claude-sonnet-4-20250514"}`
- `{:openrouter, "anthropic/claude-sonnet-4"}`
- `{:claude_code, ???}` — not even in the Catalog!

The ModelRouter picks one model. It cannot say "try Anthropic direct first, fall back to OpenRouter."

### 2.2 Coding Agents Hide Their Model Selector

Our protocol wrappers for Claude Code, OpenCode, and Codex **do not pass `--model` args**, even though all three CLIs support them:

- **Claude Code:** `claude --model opus` (or `ANTHROPIC_MODEL` env var)
- **OpenCode:** `opencode --model anthropic/claude-sonnet-4-5`
- **Codex:** `codex --model gpt-5.4` (or `-m gpt-5.4`)

The `Agentic.Protocol.CLI` macro has `model_arg` and `model_aliases` fields in its type spec, but **no protocol implementation uses them**.

### 2.3 No Subscription Credit Tracking

- We poll `UsageManager` for account-level quotas every 5 minutes.
- We do **not** track per-request costs from the Gateway proxy.
- We cannot show the user "you have $47.32 remaining on OpenRouter this month."
- We cannot show "your Claude Code subscription includes unlimited usage."

### 2.4 Gateway Proxy Misses Cost Data

Our `Agentic.LLM.Gateway` transparently proxies HTTP traffic. It parses usage from response **bodies** but:

- **OpenRouter** returns `usage.cost` in the body — we currently ignore it.
- **Anthropic / OpenAI / Groq** have no cost headers — we compute cost client-side from token counts × catalog pricing.
- The Gateway emits telemetry events with token counts but never accumulates them into a spend tracker.

---

## 3. Proposed Architecture

### 3.1 Core Data Model: Canonical Models, Pathways, and ProviderAccount

We extend `Agentic.LLM.Model` with **one** new field. The cost profile lives on
the user's `ProviderAccount`, not the model — the same `claude-sonnet-4-20250514`
is `:pay_per_token` for someone using a raw Anthropic API key and
`:subscription_included` for someone on a Pro plan.

```elixir
defmodule Agentic.LLM.Model do
  defstruct [
    # ... existing fields ...
    canonical_id: nil,            # "claude-sonnet-4"
    capabilities: MapSet.new()    # PER-PATHWAY (see §3.2)
  ]
end
```

A `ProviderAccount` (resolved from settings at session start) carries the
per-user economics:

```elixir
defmodule Agentic.LLM.ProviderAccount do
  defstruct [
    :provider,                    # :anthropic | :claude_code | :openrouter | ...
    :cost_profile,                # :free | :subscription_included | :subscription_metered | :pay_per_token
    :subscription,                # %{plan: "Pro", monthly_fee: Money.new(:USD, "20")} | nil
    :credentials_status,          # :ready | :missing | :expired
    :availability,                # :ready | :degraded | :unavailable | {:rate_limited, until_dt}
    :quotas                       # %{tokens_used: int, tokens_limit: int, period_end: dt} | nil
  ]
end
```

**`canonical_id`** is provider-agnostic — it identifies the model weights, not the
namespace they're served under. A central `Agentic.LLM.Canonical` module owns the
mapping (see §3.6); providers consult it instead of hardcoding their own values.

| Provider | Provider Model ID | Canonical ID |
|----------|-------------------|--------------|
| Anthropic direct | `claude-sonnet-4-20250514` | `claude-sonnet-4` |
| Claude Code CLI | `claude-sonnet-4` | `claude-sonnet-4` |
| OpenRouter | `anthropic/claude-sonnet-4` | `claude-sonnet-4` |
| OpenAI direct | `gpt-5.5-2026-04-23` | `gpt-5.5` |
| OpenCode | `openai/gpt-5.5` | `gpt-5.5` |
| z.ai | `glm-4.7` | `glm-4.7` |

**`cost_profile`** values, as resolved on the `ProviderAccount`:

```elixir
@type cost_profile ::
  :free                         # Ollama, OpenRouter :free tier
  | :subscription_included       # Flat fee, unmetered (Claude Code, z.ai sub)
  | :subscription_metered        # Flat fee + overage (Anthropic Pro with weekly caps)
  | :pay_per_token               # Pure usage-based
```

The `Model.cost` map remains the static per-token catalog price — used both for
estimated-cost telemetry on pay-per-token paths and for amortization math on
subscription paths (see §5.5).

### 3.2 Per-Pathway Capabilities

Pathways for the same canonical model are **not fungible**. Claude via Anthropic
direct supports 1M context, extended thinking, prompt caching, image input, and
strict tool-use schemas. Claude via the Claude Code CLI changes the framing
(stdio + the agent's own tool harness) and may not surface the same feature set.

We attach a `MapSet` of capabilities **per pathway model**, not per canonical:

```elixir
%Agentic.LLM.Model{
  id: "claude-sonnet-4-20250514",
  provider: :anthropic,
  canonical_id: "claude-sonnet-4",
  context_window: 1_000_000,
  capabilities: MapSet.new([:chat, :tools, :vision, :prompt_caching,
                            :extended_thinking, :strict_tools])
}

%Agentic.LLM.Model{
  id: "claude-sonnet-4",
  provider: :claude_code,
  canonical_id: "claude-sonnet-4",
  context_window: 200_000,
  capabilities: MapSet.new([:chat, :tools])  # narrower than direct API
}
```

`Catalog.find/1` accepts a `requires: [capability]` filter so the router can
reject pathways that can't service the request before scoring.

### 3.3 Catalog Changes

The Catalog keeps its existing `{provider, model_id}` keying. We add new queries:

```elixir
# Return all models that are pathways to the same canonical model
Catalog.find(canonical: "claude-sonnet-4")
# => [%Model{provider: :anthropic, ...}, %Model{provider: :openrouter, ...}, %Model{provider: :claude_code, ...}]

# Filter by required capabilities at the same time
Catalog.find(canonical: "claude-sonnet-4", requires: [:vision, :prompt_caching])
```

We add a **canonical index** (a map of `canonical_id → [model_keys]`) maintained
alongside the existing catalog state in `Agentic.LLM.Catalog` (a GenServer with
JSON snapshot at `~/.agentic/catalog.json`). No new persistence layer needed.

### 3.4 ModelRouter: Group by Canonical, Score Pathways

Current flow:

```
Catalog.find(tier: :primary)
  → [Model, Model, ...]
  → sort by priority
  → return routes
```

New flow:

```
Catalog.find(tier: :primary, requires: ctx.required_capabilities)
  → [Model, Model, ...]
  → group by canonical_id
  → for each canonical group:
      → for each pathway: resolve ProviderAccount from ctx
      → drop pathways with availability == :unavailable
      → score remaining pathways using Preference.score/4
        (model, account, ctx, preference)
      → pick best pathway
  → sort canonical groups by best-pathway score
  → return routes (one per canonical group)
```

This means `resolve_all(:primary)` returns **one route per canonical model**, representing the best available pathway given the user's accounts.

**Route struct additions:**

```elixir
%{
  id: "catalog-claude-sonnet-4",
  canonical_model_id: "claude-sonnet-4",
  provider_name: "anthropic",
  model_id: "claude-sonnet-4-20250514",
  cost_profile: :subscription_included,   # resolved from ProviderAccount, not Model
  account_id: "anthropic-pro",             # which account was matched
  # ... existing fields ...
}
```

**Sticky routes** use `canonical_model_id` as the key, so if Anthropic fails and
we fall back to OpenRouter, the next session still tries Anthropic first (since
it's the preferred path for that canonical model). Worth has no users yet, so
existing `{provider, model_id}`-keyed sticky entries are dropped on first boot
of the new code — no migration shim required.

### 3.5 Preference Scoring with Cost Profiles & Quota Pressure

`Agentic.ModelRouter.Preference.score/4` takes the model, the account, the ctx,
and the preference. The cost profile and quota pressure both come from the
account, not the model.

```elixir
defp cost_profile_score(account, preference) do
  case {account.cost_profile, preference} do
    {:free, :optimize_price} -> -10.0
    {:subscription_included, :optimize_price} -> -5.0
    {:subscription_metered, :optimize_price} -> 0.0
    {:pay_per_token, :optimize_price} -> base_cost_score(model)

    {:free, :optimize_speed} -> 0.0
    {:subscription_included, :optimize_speed} -> -2.0
    {:subscription_metered, :optimize_speed} -> -1.0
    {:pay_per_token, :optimize_speed} -> base_speed_score(model)
  end
end

# Quota pressure: as a subscription approaches its cap, taper toward
# pay-per-token alternatives. Returns 0..+inf, added to the score.
defp quota_pressure_score(account) do
  case account.quotas do
    nil -> 0.0
    %{tokens_used: u, tokens_limit: l} when l > 0 ->
      pressure = u / l
      cond do
        pressure < 0.7 -> 0.0
        pressure < 0.9 -> 3.0 * (pressure - 0.7) / 0.2   # ramp 0 → 3
        true           -> 3.0 + 50.0 * (pressure - 0.9)  # cliff after 90%
      end
  end
end

# Availability folds in as a continuous penalty rather than a hard filter
# (except for :unavailable, which is filtered upstream).
defp availability_score(account) do
  case account.availability do
    :ready                     -> 0.0
    :degraded                  -> 2.0   # e.g. expired OAuth — usable, but warn
    {:rate_limited, _until_dt} -> 8.0
  end
end
```

**`:optimize_price`** prefers `free > subscription_included > subscription_metered > pay_per_token`,
but quota pressure can flip the ranking once a subscription is near its weekly cap.

**`:optimize_speed`** gives subscriptions a slight edge (no rate-limit anxiety) but
still prefers fast API providers over slow CLI agents.

### 3.6 Canonical Mapping: models.dev + Static Overrides

Per the agentic codebase research, providers today register models via:

- Static `default_models/0` (Anthropic, OpenAI)
- Dynamic `fetch_catalog/1` HTTP discovery (Groq, OpenRouter, sometimes Ollama)
- A merged Catalog GenServer with JSON snapshot at `~/.agentic/catalog.json`

Hardcoding `canonical_id` in each provider's `default_models/0` invites drift.
**Open-question research turned up [models.dev](https://models.dev)** — the same
catalog that OpenCode uses internally. It exposes
`https://models.dev/api.json`: ~50+ providers, full metadata (context window,
modalities, capabilities, per-token pricing), no auth, free, structured. This
is a better canonical source than anything we'd hand-maintain.

We restructure `Agentic.LLM.Canonical` as a **GenServer that fetches and caches
models.dev**, with a small static override table for the cases models.dev
doesn't cover:

```elixir
defmodule Agentic.LLM.Canonical do
  @moduledoc """
  Canonical model identity. Pulls from models.dev (https://models.dev/api.json)
  and merges with a small static override table.

  Resolution order for canonical_id of (provider, model_id):
  1. Static overrides (Codex aliases, Worth renames, manual fixes)
  2. models.dev mapping
  3. Pattern rules (e.g. strip OpenRouter org prefix)
  4. Fallback: "#{provider}:#{model_id}"
  """

  use GenServer

  # Static overrides for what models.dev doesn't cover.
  # Codex uses rolling aliases that aren't in models.dev:
  @overrides %{
    {:codex,        "gpt-5.5"}             => "gpt-5.5",
    {:codex,        "gpt-5.4"}             => "gpt-5.4",
    {:codex,        "gpt-5.4-mini"}        => "gpt-5.4-mini",
    {:codex,        "gpt-5.3-codex"}       => "gpt-5.3-codex",
    {:codex,        "gpt-5.3-codex-spark"} => "gpt-5.3-codex",
    # Claude Code uses short aliases (sonnet/opus); the CLI accepts both
    # short aliases and dated IDs. We pin canonicals to the family name:
    {:claude_code,  "sonnet"}              => "claude-sonnet-4",
    {:claude_code,  "opus"}                => "claude-opus-4",
    {:claude_code,  "claude-sonnet-4"}     => "claude-sonnet-4",
    {:claude_code,  "claude-opus-4"}       => "claude-opus-4"
  }

  @pattern_rules [
    # OpenRouter ids: "anthropic/claude-sonnet-4" → "claude-sonnet-4"
    {:openrouter, fn id -> id |> String.split("/", parts: 2) |> List.last() end},
    # OpenCode uses provider/model too:
    {:opencode,   fn id -> id |> String.split("/", parts: 2) |> List.last() end}
  ]

  # Public API
  def for_model(provider, model_id), do: GenServer.call(__MODULE__, {:lookup, provider, model_id})
  def metadata_for(provider, model_id), do: GenServer.call(__MODULE__, {:metadata, provider, model_id})
  def refresh, do: GenServer.cast(__MODULE__, :refresh)

  # Server: fetch on init + every 24h, persist to ~/.agentic/models_dev.json
  # for offline boot.
end
```

`metadata_for/2` returns the models.dev row (context_window, modalities,
capabilities, pricing) when present, so providers no longer need to hardcode
those fields in `default_models/0` — they delegate to Canonical and the catalog
stays self-updating as models.dev tracks new releases.

**What models.dev does NOT cover (handled via overrides):**

- Codex's rolling aliases (`gpt-5.3-codex-spark`, etc.)
- Claude Code short aliases (`sonnet`, `opus`)
- Any vendor-internal model not yet listed publicly
- z.ai's GLM family — *check at fetch time*; if missing, fall back to a static
  z.ai-specific table seeded from the z.ai docs (see §8.2)

**Persistence:** the fetched catalog snapshots to `~/.agentic/models_dev.json`
so first boot is fast and we degrade cleanly when models.dev is unreachable.
TTL 24h, manual refresh via `Canonical.refresh/0` and a UI button.

Why GenServer + cache, not pure static:

- models.dev is the same catalog OpenCode uses — keeping ours in sync removes
  manual drift work entirely for the common case (Anthropic, OpenAI, Mistral,
  Gemini, OpenRouter).
- GenServer cache + JSON snapshot keeps offline boot working.
- Worth has no DB-of-record requirement here; agentic's existing pattern of
  ETS + JSON snapshots applies.

### 3.7 Credential-Aware Filtering & Graded Availability

Provider availability is **not binary** — it has three states that lead to very
different routing decisions:

| State | Meaning | Routing effect |
|-------|---------|----------------|
| `:ready` | Credentials valid, no rate limit, quota healthy | Score normally |
| `:degraded` | Reachable but suboptimal (OAuth expired but CLI may re-auth lazily; quota high) | +2 penalty, surface UI warning |
| `{:rate_limited, until}` | Provider returned 429 recently | +8 penalty until `until` |
| `:unavailable` | No creds, no binary, or creds invalid | Hard-filter out |

The Provider behaviour gains an optional callback:

```elixir
@callback availability(account :: ProviderAccount.t()) ::
  :ready | :degraded | {:rate_limited, DateTime.t()} | :unavailable
```

Implementation per provider:

| Provider | `availability/1` check |
|----------|-----------------------|
| `:anthropic` | `Credentials.resolve/1` → `:ready` if present, else `:unavailable` |
| `:openai` | same |
| `:openrouter` | same; `:rate_limited` if last 429 within window |
| `:groq` | same |
| `:ollama` | HTTP ping to `OLLAMA_HOST`; `:unavailable` if down |
| `:claude_code` | binary present + check `~/.claude/auth.json` expiry: `:ready` if not expired, `:degraded` if expired (CLI will re-auth lazily), `:unavailable` if no binary |
| `:opencode` | `System.find_executable("opencode")` + config exists |
| `:codex` | `System.find_executable("codex")` + config exists |
| `:zai` | `Credentials.resolve/1` succeeds |

Worth resolves `[ProviderAccount]` from settings at session start and pushes it
into `ctx.metadata`:

```elixir
ctx = %{
  ctx |
  metadata: Map.put(ctx.metadata, :provider_accounts, accounts)
}
```

The ModelRouter pulls accounts from `ctx`, hard-filters `:unavailable` pathways,
and folds `:degraded` / `:rate_limited` into the score continuously.

---

## 4. Coding Agent Model Selection

### 4.1 Current State

Our CLI protocol implementations (`Agentic.Protocol.ClaudeCode`, `OpenCode`, `Codex`) do not pass `--model` arguments. They rely entirely on the CLI binary's internal default model or user-level config files.

### 4.2 Proposed Change: Thread Model via `model_arg`

The `Agentic.Protocol.CLI` macro already has a `model_arg` field. We don't need
per-protocol `model_aliases` tables — `Agentic.LLM.Canonical` (§3.6) already maps
canonical_id → provider_model_id. The CLI layer just needs to:

1. **Set `model_arg` on each CLI protocol:**

```elixir
# lib/agentic/protocol/claude_code.ex
def build_config(_ctx),
  do: %{cli_name: "claude", default_args: ["-p", "--input-format", "stream-json", ...], model_arg: "--model"}

# lib/agentic/protocol/open_code.ex
def build_config(_ctx),
  do: %{cli_name: "opencode", default_args: ["--mode", "agent", "--output", "json"], model_arg: "--model"}

# lib/agentic/protocol/codex.ex
def build_config(_ctx),
  do: %{cli_name: "codex", default_args: ["exec", "--json", "--skip-git-repo-check"], model_arg: "--model"}
```

2. **Update the CLI macro to inject `--model` from the resolved route:**

In `Agentic.Protocol.CLI`, when building the subprocess command, look up the
provider model_id via the route (which already carries `model_id` resolved from
the canonical group):

```elixir
args =
  if config.model_arg && route.model_id do
    [config.model_arg, route.model_id | config.default_args]
  else
    config.default_args
  end
```

No protocol-local alias map is needed — the route's `model_id` is already the
provider-native value (e.g. `claude-sonnet-4-20250514` for Anthropic direct,
`claude-sonnet-4` for Claude Code), set when the route was built from the
Catalog entry registered by the corresponding `Provider`.

3. **Bridge Protocol ↔ Catalog:**

CLI protocols are currently invisible to the Catalog. We add thin **Provider wrappers** for each CLI protocol:

```elixir
defmodule Agentic.LLM.Provider.ClaudeCode do
  @behaviour Agentic.LLM.Provider

  @impl true
  def id, do: :claude_code

  @impl true
  def default_models do
    [
      %Agentic.LLM.Model{
        id: "claude-sonnet-4",
        canonical_id: "anthropic/claude-sonnet-4",
        provider: :claude_code,
        label: "Claude Sonnet 4 (via Claude Code)",
        context_window: 200_000,
        cost: %{input: 0.0, output: 0.0},
        cost_profile: :subscription_included,
        capabilities: MapSet.new([:chat, :tools]),
        tier_hint: :primary,
        source: :static
      },
      # ... Opus, etc.
    ]
  end

  @impl true
  def available? do
    System.find_executable("claude") != nil &&
      # TODO: check OAuth token validity
      true
  end

  # ... other callbacks
end
```

These providers are registered in `ProviderRegistry` alongside API providers. They have `transport: Agentic.LLM.Transport.ClaudeCode` (a new transport that delegates to `Agentic.Protocol.ClaudeCode`).

### 4.3 Open Question: OAuth State for Claude Code

Claude Code requires browser OAuth. Unlike API keys, OAuth tokens expire and need refresh.

**Options:**

1. Treat as "available if binary exists" and let the OAuth happen lazily on first use (the CLI opens a browser tab).
2. Check for an existing OAuth token file (`~/.claude/auth.json`) before marking available.
3. Add an explicit "Authenticate" button in the Worth UI that runs `claude auth login`.

**Recommendation:** Start with option 1 (binary existence). The CLI handles its own auth gracefully — it opens a browser tab on first use if not authenticated.

---

## 5. Subscription Credit Tracking

### 5.1 Current State (verified against agentic codebase)

`Agentic.LLM.UsageManager` polls provider APIs every 5 minutes for account-level quotas:

- **OpenRouter:** `GET /auth/key` → credits used / limit
- **Anthropic:** No usage endpoint — must track client-side
- **OpenAI:** No usage endpoint in standard API
- **Groq:** No usage endpoint

`Agentic.LLM.Gateway` is a transparent HTTP proxy mounted in Worth at
`/proxy/anthropic/...` and `/proxy/openai/...` (`WorthWeb.LLMGatewayController`).
Critically, **all three CLI protocols already auto-attach to the Gateway** — in
`build_config` they call `Agentic.LLM.Gateway.inject_env(base_env, :anthropic)`
which sets `ANTHROPIC_BASE_URL` / `OPENAI_BASE_URL` env vars on the subprocess
so the CLI's HTTP traffic is intercepted by our local proxy. This is also the
backbone of Worth's X-Ray mode (`TelemetryBridge` → `:xray:events` PubSub).

The Gateway emits two telemetry events today:

- `[:agentic, :gateway, :request, :start]` — call_id, provider, path, model, tools, etc.
- `[:agentic, :gateway, :request, :stop]` — duration, input/output/cache tokens, status, TTFT, chunk_count, raw_response (truncated)

The token measurements are present; **no accumulation into a spend ledger exists yet.**

### 5.2 Proposed: SpendTracker, Fed by the Existing Gateway

We add a new GenServer: `Agentic.LLM.SpendTracker`.

**Responsibilities:**

1. Subscribe to `[:agentic, :gateway, :request, :stop]` (Gateway already emits this)
2. Subscribe to a new `[:agentic, :protocol, :cli, :complete]` event for any
   subprocess turns whose cost data appears in stdout but never hit the proxy
   (e.g. Claude Code already emits `total_cost_usd` in its final JSON — see §5.3)
3. Accumulate per-provider spend per billing window (daily / monthly)
4. Expose API for UI dashboards (`SpendTracker.snapshot/0`, `for_provider/1`)
5. Persist via SQLite (see §5.6) — not JSON

**Why CLI subprocesses are covered "for free":** since `Gateway.inject_env/2`
forces Claude Code / OpenCode / Codex to route their HTTP calls through the
local proxy, the same `:stop` telemetry fires whether the LLM call originated
from an Agentic-internal HTTP client or from a CLI subprocess. The spend tracker
therefore sees the full picture without any per-protocol custom plumbing. The
only special case is when a CLI emits its own cost number in stdout (which we
treat as authoritative for that turn — see §5.3).

**Data model:**

```elixir
%Agentic.LLM.SpendTracker.Window{
  provider: :openrouter,
  label: "OpenRouter",
  period: :daily,          # :daily | :monthly
  period_start: ~D[2026-04-25],
  input_tokens: 1_234_567,
  output_tokens: 456_789,
  cache_read_tokens: 100_000,
  cache_write_tokens: 50_000,
  estimated_cost: Money.new(:USD, "4.23"),   # computed from catalog pricing
  actual_cost: Money.new(:USD, "4.18"),      # from provider response body when present
  request_count: 142
}
```

All cost fields are `Money.t()` from the `ex_money` library (see §5.5).

**OpenRouter actual cost:** The Gateway already parses the response body. OpenRouter returns:

```json
{
  "usage": {
    "prompt_tokens": 100,
    "completion_tokens": 50,
    "total_tokens": 150,
    "cost": 0.00045
  }
}
```

We extract `usage.cost` and feed it to the SpendTracker.

**Anthropic / OpenAI estimated cost:** For providers that don't return actual cost, we compute (Decimal arithmetic, then wrapped in Money):

```elixir
import Decimal, only: [div: 2, mult: 2, add: 2]

per_million = Decimal.new("1000000")

estimated =
  Decimal.mult(Decimal.div(Decimal.new(input_tokens), per_million),  cost.input)
  |> Decimal.add(Decimal.mult(Decimal.div(Decimal.new(output_tokens), per_million), cost.output))
  |> Decimal.add(Decimal.mult(Decimal.div(Decimal.new(cache_read),    per_million), cost.cache_read || Decimal.new(0)))
  |> Decimal.add(Decimal.mult(Decimal.div(Decimal.new(cache_write),   per_million), cost.cache_write || Decimal.new(0)))

Money.new(:USD, estimated)
```

We use `Decimal` for precision (LLM costs are routinely sub-cent, e.g. $0.000045
per request) — `Money` is built on `Decimal` internally, so no precision is lost
on construction.

### 5.5 Currency Normalization with `ex_money`

z.ai bills in CNY; most others bill in USD. We use the `ex_money` library
(Hex package `ex_money`, current stable v5.24, RC v6.0) for currency-aware
storage and arithmetic.

**Why ex_money:**

- ISO 4217 + ISO 24165 (crypto) currency codes built in
- `Money.t()` always carries `{currency, amount}` — no implicit USD assumptions
- Built on `Decimal`, so sub-cent values work natively
- `Money.ExchangeRates` behaviour with built-in periodic fetcher (defaults to
  Open Exchange Rates; pluggable backend), ETS-cached
- Companion `ex_money_sql` package provides Ecto types for DB persistence —
  but we're using SQLite directly via `:exqlite`, so we'll persist as
  `(amount NUMERIC, currency TEXT)` columns and reconstruct `Money` on read

**Rules:**

1. Every cost value in the system is a `Money.t()`, never a bare float.
2. Arithmetic across currencies requires explicit conversion via
   `Money.to_currency/3` — the SpendTracker normalizes everything to a single
   "display currency" (default `:USD`) before summing in dashboards, but
   stores rows in their **native currency** so the audit trail is honest.
3. FX rates source: configure `Money.ExchangeRates.OpenExchangeRates` if a key
   is present, else use the static fallback shipped with `ex_money`. Worth
   surfaces "rates last updated at X" in the dashboard so the user knows the
   conversion is approximate.

```elixir
# config/config.exs (v1 — bundled OXR app id)
config :ex_money,
  default_cldr_backend: Worth.Cldr,
  exchange_rates_retrieve_every: :timer.hours(6),
  api_module: Money.ExchangeRates.OpenExchangeRates,
  open_exchange_rates_app_id: {:system, "WORTH_OXR_APP_ID", @bundled_oxr_app_id}
```

#### 5.5.1 FX Rate Distribution: bundled OXR → Worth-hosted relay

**v1 (ship-now):** Worth bundles a Worth-owned OXR app id. Every Worth client
hits `openexchangerates.org` directly. Pros: zero infra. Cons: every install
counts against our OXR rate limit; the app id is recoverable from a desktop
build (mitigated by limiting it to a free-tier-only allowlist).

**v2 (next milestone):** Worth's own server exposes an OXR-compatible relay at
`https://worth.example.com/api/exchange-rates/v1/` mirroring the OXR endpoints
(`/latest.json`, `/historical/{date}.json`). All Worth clients poll the relay
instead of OXR directly:

```elixir
# config/config.exs (v2)
config :ex_money,
  api_module: Worth.LLM.ExchangeRates.WorthRelay,
  worth_relay_url: {:system, "WORTH_FX_RELAY_URL", "https://worth.example.com/api/exchange-rates/v1"}
```

The relay implementation:

- Server-side fetches OXR once per N minutes for the union of currencies any
  client has ever requested; caches in Redis.
- Returns the OXR JSON shape verbatim (so we can implement the relay client
  as a thin subclass of `Money.ExchangeRates.OpenExchangeRates`, swapping just
  the base URL).
- Auth: anonymous read for `/latest.json` (FX is public data); per-user token
  on `/historical/*` (rate-limit per account).
- Worth client falls back to OXR direct if the relay is unreachable, so an
  outage of the relay doesn't break local rate retrieval.

The migration is invisible to the rest of the codebase because it lives behind
the `Money.ExchangeRates` behaviour. SpendTracker, dashboards, and providers
keep calling `Money.to_currency/3` unchanged.

### 5.6 SpendTracker Persistence: SQLite, not JSON

A single `~/.agentic/spend.json` file would race across concurrent agentic
instances (and concurrent agent turns within one instance write to the
accumulator independently). We persist via SQLite at `~/.agentic/spend.sqlite3`
using `:exqlite`:

```sql
CREATE TABLE spend_windows (
  id INTEGER PRIMARY KEY,
  provider TEXT NOT NULL,
  account_id TEXT NOT NULL,           -- distinguishes multiple keys for same provider
  canonical_id TEXT,                  -- nullable for non-LLM rows
  period TEXT NOT NULL,               -- 'daily' | 'monthly'
  period_start TEXT NOT NULL,         -- ISO date
  input_tokens INTEGER DEFAULT 0,
  output_tokens INTEGER DEFAULT 0,
  cache_read_tokens INTEGER DEFAULT 0,
  cache_write_tokens INTEGER DEFAULT 0,
  estimated_amount NUMERIC NOT NULL DEFAULT 0,
  estimated_currency TEXT NOT NULL DEFAULT 'USD',
  actual_amount NUMERIC,
  actual_currency TEXT,
  request_count INTEGER DEFAULT 0,
  updated_at TEXT NOT NULL,
  UNIQUE (provider, account_id, canonical_id, period, period_start)
);
CREATE INDEX idx_spend_period ON spend_windows (period, period_start);

CREATE TABLE spend_events (
  id INTEGER PRIMARY KEY,
  ts TEXT NOT NULL,
  call_id TEXT,
  provider TEXT NOT NULL,
  account_id TEXT NOT NULL,
  canonical_id TEXT,
  model_id TEXT,
  input_tokens INTEGER,
  output_tokens INTEGER,
  cache_read_tokens INTEGER,
  cache_write_tokens INTEGER,
  estimated_amount NUMERIC,
  estimated_currency TEXT,
  actual_amount NUMERIC,
  actual_currency TEXT,
  duration_ms INTEGER,
  status INTEGER
);
CREATE INDEX idx_spend_events_ts ON spend_events (ts);
```

`SpendTracker` writes one event row per request and increments the matching
window row in the same transaction. SQLite's WAL mode handles concurrent writers
cleanly. The `spend_events` table is the audit log for X-Ray and per-request
attribution; `spend_windows` is the materialized aggregate that dashboards read.

### 5.7 Subscription Cost Amortization

Marking subscription-included rows as `Money.zero(:USD)` is misleading — the user
paid $20/mo for Claude Pro. Each `ProviderAccount` carries its `subscription`
metadata (`%{plan: "Pro", monthly_fee: Money.t()}`), and the dashboard surfaces:

```
Anthropic API (Pro plan, $20.00 / month)
  This month: 8.4M tokens     Subscription cost: $20.00
  Effective rate: $2.38 / Mtok      vs OpenRouter list: $9.00 / Mtok
  Savings vs pay-per-use: $55.60 this month
```

The "effective $/Mtok" calculation:

```elixir
def effective_rate(account, window) do
  total_tokens = window.input_tokens + window.output_tokens
  if total_tokens == 0 do
    nil
  else
    Money.div!(account.subscription.monthly_fee, total_tokens / 1_000_000)
  end
end
```

This is the number that lets the user decide whether the subscription is paying
off vs OpenRouter list pricing. We also track `would_have_paid_per_token` (the
estimated cost computed against catalog pricing as if the user were on the
pay-per-token plan) as a second column so "savings vs pay-per-use" is real.

### 5.8 UI Display

```
┌─ Subscription & Usage ──────────────────────────────┐
│                                                      │
│ Anthropic API — Pro plan ($20.00/mo)                │
│   Status: ✓ Active                                   │
│   This month: 8.4M tokens                            │
│   Effective: $2.38 / Mtok  (list: $9.00)             │
│   Savings: $55.60                                    │
│                                                      │
│ Claude Code — Pro plan ($20.00/mo, shared cap)      │
│   Status: ✓ Authenticated                            │
│   Weekly cap: 320k / 500k tokens used (64%)          │
│   This month: 1.2M tokens, $0 marginal               │
│                                                      │
│ OpenRouter — Pre-paid credits                        │
│   Status: ✓ $47.32 remaining                         │
│   Today: $1.23  |  This month: $12.45                │
│   [Refresh balance]                                  │
│                                                      │
│ z.ai — Developer plan (¥150/mo)                      │
│   Status: ✓ Active                                   │
│   This month: 4.1M tokens, ¥150 (~$20.65 USD)        │
│   FX rates as of 2026-04-25 12:00 UTC                │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### 5.3 CLI Cost Capture: Stdout vs Proxy

Claude Code's final JSON includes a `total_cost_usd` field that the existing
`Agentic.Protocol.ClaudeCode` already extracts. There are two streams of cost
data for any CLI turn:

1. **Gateway tap** — the proxy intercepts the actual HTTP call(s) the CLI makes
   to Anthropic/OpenAI. We get authoritative token counts per request.
2. **CLI stdout** — the CLI emits its own summary at turn end (`total_cost_usd`).

These can disagree (CLI summary is rounded; CLI may make multiple HTTP calls per
turn for tools). Policy: **the Gateway tap is the source of truth for token
counts**, and we treat the CLI's `total_cost_usd` only as a sanity-check
warning if it deviates >10% from our computed total.

The new `[:agentic, :protocol, :cli, :complete]` event carries the CLI-reported
cost (when available) so SpendTracker can log the discrepancy without
double-counting.

### 5.4 Subscription Account Polling

For providers with usage endpoints, we keep the existing `UsageManager`
polling. For providers without, we rely on `SpendTracker` accumulation. The
two streams reconcile at the dashboard layer (e.g. when both report spend, the
authoritative-from-provider value shows as the headline figure and our
gateway-derived value as an "in-flight" delta).

**Provider-specific strategies (rev 3 — verified):**

| Provider | Usage Endpoint | Auth | Strategy |
|----------|---------------|------|----------|
| OpenRouter | `GET /auth/key` | Same key as inference | Poll credit balance + accumulate Gateway spend |
| Anthropic | `GET /v1/organizations/usage_report/messages` + `/cost_report` | **Separate** `sk-ant-admin-...` key (org-tier only) | Optional admin-key polling; default to Gateway accumulation |
| OpenAI | `GET /v1/organization/usage/{completions,...}` + `/v1/organization/costs` | **Separate** `sk-admin-...` key (org Owner) | Optional admin-key polling; default to Gateway accumulation |
| Groq | None | — | Gateway accumulation only |
| Claude Code | None (uses Anthropic backend) | — | Gateway accumulation only (via proxy auto-injection) |
| Codex | None (uses OpenAI backend) | — | Gateway accumulation only (via proxy auto-injection) |
| z.ai | None (dashboard-only at z.ai/manage-apikey/billing) | — | Gateway accumulation only; link out to dashboard |
| Ollama | N/A (local) | — | No spend; track tokens for analytics only |

**Anthropic Admin API integration:**

```elixir
# Worth.LLM.Provider.Anthropic — optional admin-key flow
defp poll_usage(admin_key, since) do
  Req.get!("https://api.anthropic.com/v1/organizations/usage_report/messages",
    headers: [
      {"x-api-key", admin_key},
      {"anthropic-version", "2023-06-01"}
    ],
    params: [
      starting_at: DateTime.to_iso8601(since),
      bucket_width: "1d",
      group_by: ["model", "service_tier", "context_window"]
    ]
  )
end
```

Returned per-bucket fields: `uncached_input_tokens`, `output_tokens`,
`cache_read_input_tokens`, `cache_creation: { ephemeral_5m_input_tokens,
ephemeral_1h_input_tokens }`. **Cost lives on the separate `/cost_report`
endpoint, not on usage rows** — poll both if the user wants USD reconciliation.

The admin key is stored separately in Worth's settings (it's strictly more
sensitive than a regular API key — it can read all org usage, list members,
revoke keys). Settings UI surfaces it as an optional "Connect Anthropic
organization" step distinct from the regular API key entry.

**OpenAI Admin API integration:**

```elixir
defp poll_completions(admin_key, since) do
  Req.get!("https://api.openai.com/v1/organization/usage/completions",
    headers: [{"authorization", "Bearer " <> admin_key}],
    params: [
      start_time: DateTime.to_unix(since),
      bucket_width: "1d",
      group_by: ["model", "project_id"]
    ]
  )
end

defp poll_costs(admin_key, since) do
  Req.get!("https://api.openai.com/v1/organization/costs",
    headers: [{"authorization", "Bearer " <> admin_key}],
    params: [start_time: DateTime.to_unix(since), bucket_width: "1d"]
  )
end
```

OpenAI's bucket result returns `input_tokens`, `output_tokens`,
`input_cached_tokens`, `input_audio_tokens`, `output_audio_tokens`,
`num_model_requests`, `model`, `project_id`, `user_id`, `api_key_id`. The
costs endpoint returns `amount: { value, currency }` — already in the right
shape for `Money.new(currency, value)`.

**Caveat from the research:** OpenAI explicitly notes Usage and Costs may not
reconcile exactly. We treat `/costs` as the billing source of truth and
`/usage` as token-analytics only. SpendTracker stores both side-by-side; the
dashboard headlines `/costs` when present, falls back to gateway-estimated
otherwise.

### 5.9 Gateway Enhancements

We extend `Agentic.LLM.Gateway` to:

1. **Parse `usage.cost` from OpenRouter responses** and include it in telemetry metadata.
2. **Add `canonical_model_id` and `account_id` to the existing `:stop` event metadata.**
   We deliberately do NOT introduce a separate `[:gateway, :request, :cost]` event —
   downstream consumers (X-Ray, SpendTracker) already subscribe to `:stop` and
   the Gateway has all the information needed to attach cost data inline.
3. **Add response header inspection** for any providers that add cost headers in the future.

```elixir
# In Gateway proxy_sync/4
{status, resp_headers, resp_body} = ...

actual_cost =
  case get_in(resp_body, ["usage", "cost"]) do
    nil      -> nil
    n when is_number(n) -> Money.new(:USD, Decimal.from_float(n))
  end

estimated_cost = compute_estimated_cost(usage, route)  # Money.t() in route's catalog currency

# Augment the existing :stop event — no new event name.
Agentic.Telemetry.event([:agentic, :gateway, :request, :stop], measurements, %{
  call_id: call_id,
  provider: provider_id,
  model_id: model_id,
  canonical_model_id: route.canonical_model_id,
  account_id: route.account_id,
  actual_cost: actual_cost,         # Money.t() | nil
  estimated_cost: estimated_cost,   # Money.t()
  status: status
})
```

---

## 6. Worth UI: Provider Management & Pathway Selection

### 6.1 Settings Panel Extensions

We add two new cards to the existing settings panel:

#### Card A: Provider Accounts

Shows all providers (API + CLI) with their status:

```
┌─ Provider Accounts ──────────────────────────────────┐
│                                                       │
│ Anthropic API        [✓ Configured]  [Update key] [×]│
│   Models: 2  |  Cost: subscription included          │
│                                                       │
│ Claude Code          [✓ Installed]   [Re-auth]       │
│   Path: /usr/local/bin/claude                        │
│   Models: 2  |  Cost: subscription included          │
│                                                       │
│ OpenRouter           [✓ Configured]  [Update key] [×]│
│   Models: 243  |  Balance: $47.32                    │
│   [Refresh catalog]  [Refresh balance]               │
│                                                       │
│ z.ai                 [✗ Not configured]              │
│   [Add API key]                                      │
│                                                       │
│ OpenCode             [✗ Not installed]               │
│   Install: brew install opencode                     │
│                                                       │
└──────────────────────────────────────────────────────┘
```

#### Card B: Model Pathways

```
┌─ Model Pathways ─────────────────────────────────────┐
│                                                       │
│ Claude models                                         │
│   Preferred: [Anthropic API ▼]                       │
│   Fallbacks: Claude Code → OpenRouter                │
│                                                       │
│ GPT models                                            │
│   Preferred: [OpenAI ▼]                              │
│   Fallbacks: OpenRouter                              │
│                                                       │
│ GLM models                                            │
│   Preferred: [z.ai ▼]                                │
│   Fallbacks: OpenCode → OpenRouter                   │
│                                                       │
│ [Reset to defaults]                                  │
└──────────────────────────────────────────────────────┘
```

### 6.2 Event Handlers

New `ChatLive` events:

- `settings_set_pathway_preference` — `{family, preferred_provider}`
- `settings_add_provider_key` — `{provider_id, key}`
- `settings_remove_provider_key` — `{provider_id}`
- `settings_refresh_provider_catalog` — `{provider_id}`
- `settings_refresh_provider_balance` — `{provider_id}`

### 6.3 Data Persistence

Provider pathway preferences are stored as Settings DB preferences:

```
preference:pathway:anthropic/claude-sonnet-4 = "anthropic"
preference:pathway:openai/gpt-5.5 = "openai"
preference:pathway:z.ai/glm-4.7 = "zai"
```

If no preference is set, the router uses its default scoring.

---

## 7. Implementation Phases

### Phase 1 — Foundation (agentic)

**Goal:** Canonical model support, ProviderAccount, capability filtering, scoring.

1. Add `Agentic.LLM.Canonical` GenServer that fetches `https://models.dev/api.json`
   on init + every 24h, snapshots to `~/.agentic/models_dev.json`, merges with
   static-override table (Codex aliases, Claude Code short aliases, z.ai GLM
   family)
2. Add `canonical_id` and per-pathway `capabilities` to `Agentic.LLM.Model`;
   surface `Canonical.metadata_for/2` so providers can delegate
   context_window/pricing instead of hardcoding
3. Update `OpenRouter.parse_model/1` and the static provider `default_models/0`
   functions to consult `Canonical`
4. Add `Agentic.LLM.ProviderAccount` struct + builder that resolves cost_profile, subscription, availability, and quotas
5. Update `Catalog.find/1` to support `canonical:` and `requires:` queries; build canonical index
6. Add `Preference.score/4` taking `(model, account, ctx, preference)` with cost_profile + quota_pressure + availability terms
7. Update `ModelRouter.routes_for_tier/2` to read `provider_accounts` from ctx, group by `canonical_id`, hard-filter `:unavailable`, score the rest
8. Add `canonical_model_id` and `account_id` to route map
9. Update sticky route bucket to use `canonical_model_id` (no migration — no users yet)
10. Add a `mix agentic.routes --canonical claude-sonnet-4` debug command for inspection

**Estimated effort:** 4-5 days (models.dev fetcher + cache adds half a day)
**Risk:** Low-medium — models.dev is third-party; offline-snapshot fallback
keeps us robust.

### Phase 2 — Gateway Cost Tracking & SpendTracker (agentic)

**Goal:** Capture actual/estimated costs and persist to SQLite.

1. Add `:ex_money` and `:exqlite` deps to agentic; configure `Money.ExchangeRates`
2. Extend `Gateway.proxy_sync/4` to extract `usage.cost` from OpenRouter responses
3. Augment the existing `[:agentic, :gateway, :request, :stop]` metadata with
   `canonical_model_id`, `account_id`, `actual_cost` (Money), `estimated_cost` (Money)
4. Add `[:agentic, :protocol, :cli, :complete]` event for stdout-reported cost
   (sanity-check only; Gateway tap remains source of truth)
5. Create `Agentic.LLM.SpendTracker` GenServer with SQLite-backed
   `~/.agentic/spend.sqlite3` (WAL mode); two tables: `spend_events`,
   `spend_windows`
6. Subscribe to Gateway `:stop`; upsert window row + insert event row per turn
7. Add `SpendTracker.snapshot/0`, `for_provider/2`, `for_canonical/2` APIs
   returning Money values

**Estimated effort:** 2-3 days
**Risk:** Low — self-contained module. Note: Gateway already auto-injects into
all three CLI subprocesses (`Gateway.inject_env/2`), so CLI turns are covered
without per-protocol custom plumbing.

### Phase 3 — CLI Provider Wrappers (agentic)

**Goal:** Bring CLI protocols into the Catalog/ProviderRegistry.

1. Wire `model_arg` injection in `Agentic.Protocol.CLI` macro using
   `route.model_id` directly (no per-protocol alias maps — Canonical is the
   single mapping table)
2. Set `model_arg: "--model"` in `ClaudeCode`, `OpenCode`, `Codex` protocol modules
3. Create `Agentic.LLM.Provider.ClaudeCode` with `default_models/0`
4. Create `Agentic.LLM.Provider.OpenCode` with `default_models/0`
5. Create `Agentic.LLM.Provider.Codex` with `default_models/0`
6. Add optional `availability/1` callback to Provider behaviour
7. Implement `availability/1` for all providers (API key check, binary check, OAuth expiry for Claude Code)

**Estimated effort:** 2-3 days
**Risk:** Medium — requires testing CLI subprocess model injection end-to-end.

### Phase 4 — Provider Management UI (worth)

**Goal:** Let users see and configure pathways and accounts.

1. Extend `settings.ex` with "Provider Accounts" card (status, balance, re-auth)
2. Extend `settings.ex` with "Model Pathways" card (preferred pathway per family)
3. Add event handlers in `ChatLive.SettingsComponent`
4. Add `load_pathway_families/0` to `ChatLive`
5. Persist pathway preferences and `ProviderAccount` settings (cost_profile,
   subscription details) to Settings DB
6. Resolve `[ProviderAccount]` from settings and push into `ctx.metadata` before `Agentic.run/1`

**Estimated effort:** 3-4 days
**Risk:** Medium — UI complexity, event handler wiring.

### Phase 5 — z.ai, Admin Key Polling, External Providers (agentic + worth)

**Goal:** Add z.ai and wire optional admin-API polling for Anthropic / OpenAI.

1. Create `Agentic.LLM.Provider.Zai` — thin variant of OpenAI adapter, base URL
   `https://api.z.ai/api/paas/v4/`, Bearer auth, static GLM model list seeded
   in `Canonical` overrides (no `/models` endpoint), no balance polling
   (dashboard link-out)
2. Add Coding-Plan endpoint variant (`/api/coding/paas/v4/`) gated by
   key-type detection
3. Add `Worth.LLM.AdminKey` settings UI — separate optional flow for
   `sk-ant-admin-...` and `sk-admin-...` keys, distinct from regular API key
   entry, with explicit "read-only billing" disclosure
4. Add `Agentic.LLM.UsageManager` adapters that hit Anthropic
   `/v1/organizations/usage_report/messages` + `/cost_report` and OpenAI
   `/v1/organization/usage/{completions,...}` + `/v1/organization/costs`
   (poll every 5 min when admin key present)
5. SpendTracker reconciliation: when admin-key data arrives, mark matching
   gateway-derived rows as "verified" and headline the admin-API value
6. Add z.ai to SpendTracker (USD-native on global, CNY-native on bigmodel.cn,
   USD display via `Money.to_currency/3`)

**Estimated effort:** 3-4 days (admin-key flows ~1.5 days)
**Risk:** Medium — z.ai is straightforward; admin-key UX needs care to avoid
key confusion.

### Phase 6 — Subscription Dashboard with Amortization (worth)

**Goal:** UI for spend tracking, including effective $/Mtok.

1. Add "Usage" view mode to `ChatLive` (or extend existing `/usage` slash command)
2. Query `SpendTracker.snapshot/0` and `UsageManager.snapshot/0`
3. Render per-provider cards with balance, spend, request count, **effective rate**, **savings vs pay-per-use**
4. Render FX-rate freshness footer ("rates as of X")
5. Add "Refresh balance" buttons

**Estimated effort:** 2-3 days
**Risk:** Low — purely presentational.

### Phase 7 — FX Relay (worth, future)

**Goal:** Replace direct OXR fetches with a Worth-hosted relay so client
installs don't each consume the OXR rate limit.

1. Build `worth.example.com/api/exchange-rates/v1/` — OXR-compatible JSON
   shape, Redis-cached, server-side OXR fetch every N minutes
2. Add `Worth.LLM.ExchangeRates.WorthRelay` (subclass of
   `Money.ExchangeRates.OpenExchangeRates`, base URL override)
3. Switch the default `:ex_money` config to the relay; fall back to direct
   OXR when the relay is unreachable
4. Sunset the bundled OXR app id once the majority of installs are on the
   relay

**Estimated effort:** 2-3 days (server) + 1 day (client wiring)
**Risk:** Low — behind the `Money.ExchangeRates` behaviour.

**Total estimated effort (Phases 1-6):** 16-23 days (3-4.5 weeks)
**Phase 7 (relay):** +3-4 days, deferred to a later milestone.

---

## 8. Open Questions — Resolved & Remaining

### 8.1 Coding Agents

1. **Claude Code `--model` arg format** — ✅ **Resolved.** Accepts both short
   aliases (`sonnet`, `opus`) and dated IDs (`claude-sonnet-4-20250514`).
   `Canonical` overrides cover both forms (§3.6).
2. **Claude Code OAuth token location** — ⚠️ **Partial.** `~/.claude/auth.json`
   verified for Linux/macOS. Windows path unconfirmed; smoke-test during
   Phase 3 (likely `%APPDATA%\claude\auth.json`).
3. **OpenCode model list** — ✅ **Resolved.** `opencode models [provider]`
   command exists. OpenCode pulls from `https://models.dev/api.json` —
   **same source we now use for `Canonical`** (§3.6). No need to shell out to
   `opencode` to discover models; we query models.dev directly.
4. **Codex model list** — ✅ **Resolved (negative result).** No `codex models`
   or `--list-models` command; model identifiers are hardcoded into the binary
   as bare strings (no `provider/` prefix). We hardcode the rolling aliases in
   `Canonical`'s static-override table (§3.6).
5. **ACP model negotiation** — Still open; defer to a future phase.

### 8.2 z.ai

All five questions ✅ **Resolved**:

1. **Base URL:** `https://api.z.ai/api/paas/v4/` (global, USD billing).
   `https://open.bigmodel.cn/api/paas/v4/` (China, CNY billing). Coding-Plan
   keys must use `https://api.z.ai/api/coding/paas/v4/`.
2. **Auth:** OpenAI-compatible `Authorization: Bearer <API_KEY>`. JWT mode
   exists but is optional; skip until needed.
3. **Models endpoint:** **Does not exist.** Treat the model list as static.
   Seed `Canonical` overrides for `glm-4.5`, `glm-4.5-air`, `glm-4.5-flash`,
   `glm-4.5v`, `glm-4.6`, `glm-4.7`, `glm-4.7-flash`, `glm-5`, `glm-5.1`,
   `glm-5-turbo`. Refresh from z.ai docs when new GLM versions ship.
4. **Usage/balance endpoint:** **Does not exist publicly.** Billing is
   dashboard-only (`https://z.ai/manage-apikey/billing`). The Worth UI links
   out; we do not promise a "remaining credits" feature for z.ai.
5. **Pricing & currency:** Pay-per-token in USD on the global endpoint,
   CNY on bigmodel.cn. Subscription tier exists (GLM Coding Plan, ~$3-$18/mo)
   without a per-tier-quota API. Cost can be computed client-side from the
   static price table; `usage.cost` is **not** in the response body (only
   `usage.{prompt_tokens, completion_tokens, total_tokens, prompt_tokens_details: { cached_tokens }}`).

The z.ai adapter is a thin variant of the OpenAI adapter — same wire shape,
different base URL, different model list. It belongs in
`Worth.LLM.Provider.Zai` (or `Agentic.LLM.Provider.Zai` if we want it shared).

### 8.3 Cost Tracking

1. **Anthropic usage API** — ✅ **Resolved.** `GET /v1/organizations/usage_report/messages`
   for tokens, `GET /v1/organizations/cost_report` for USD. Requires a
   separate `sk-ant-admin-...` key (org-tier accounts only; not self-service).
   Wired in §5.4.
2. **OpenAI usage API** — ✅ **Resolved.** `GET /v1/organization/usage/{completions,...}`
   for tokens, `GET /v1/organization/costs` for USD. Requires a separate
   `sk-admin-...` key minted by an org Owner; available on all paid tiers.
   Wired in §5.4.
3. **Gateway accuracy** — Stable understanding: store both `actual_cost`
   (when provider returns it) and `estimated_cost` (catalog-derived) per row.
   Reconcile against admin-API cost reports daily when those keys are
   configured.
4. **Billing window alignment** — UTC by default; per-user override later if
   anyone asks.
5. **Subscription quota signal source** — ❌ **Resolved (negative).** Anthropic
   exposes only per-minute API rate limits via `anthropic-ratelimit-*`
   headers, not the Pro/Max 5-hour or weekly token caps. Those caps are
   visible only in the Anthropic Console. The user enters their plan tier
   manually in Worth settings; we estimate the cap from Anthropic's published
   plan limits and back-fill `ProviderAccount.quotas` from SpendTracker
   accumulation. The `quota_pressure_score` (§3.5) ramps based on our
   estimate, not a server-authoritative number — accept the imprecision.

### 8.4 ex_money / Currency

1. **Exchange rate provider** — ✅ **Resolved (per direction):** v1 ships a
   bundled OXR app id; v2 routes all clients through a Worth-hosted
   OXR-compatible relay (§5.5.1). Initial app id: "d4e4dd0acfd441f2a3e1011ec923a5c1"
2. **`ex_money` v6 RC** — Stable v5.24.2 is fine for now; revisit when v6
   stabilizes.
3. **`ex_money_sql` vs raw columns** — Use `:exqlite` directly with
   `(amount NUMERIC, currency TEXT)` columns. SQLite TEXT affinity preserves
   Decimal precision through `:exqlite`'s type coercion.
4. **Currency coverage for OXR free tier** — OXR free tier supports USD as
   base currency only. To convert CNY→USD we fetch USD-rates and divide. The
   relay (v2) can normalize this server-side.

### 8.5 Security

1. **SpendTracker persistence** — `~/.agentic/spend.sqlite3` is not credential
   data; treat as local app state (filesystem permissions only). Opt-in
   SQLCipher if Worth's settings DB encrypts.
2. **Gateway-injected env vars** — `Gateway.inject_env/2` only fires for
   subprocesses Agentic spawns for LLM purposes (`ClaudeCode`, `OpenCode`,
   `Codex` protocols). Audit: confirm `Worth.Tools.Bash` / generic shell tools
   don't pass through `Agentic.Protocol.CLI` and therefore never receive the
   redirect env vars.
3. **Admin-key handling** — Anthropic and OpenAI admin keys are strictly more
   sensitive than regular keys (read all org usage, manage members). Worth's
   settings UI surfaces them as a **separate, optional** "Connect organization
   for usage reporting" step, with a warning that the key is only used for
   read-only billing endpoints. Stored in the same encrypted vault as other
   credentials.

---

## 9. Appendix: Response Header Reference

### OpenRouter

```
Response body:
  usage.cost                # float, USD
  usage.prompt_tokens
  usage.completion_tokens

Headers:
  x-ratelimit-limit
  x-ratelimit-remaining
  x-ratelimit-reset
```

### Anthropic

```
Response body:
  usage.input_tokens
  usage.output_tokens
  usage.cache_creation_input_tokens
  usage.cache_read_input_tokens

Headers:
  anthropic-ratelimit-requests-limit
  anthropic-ratelimit-requests-remaining
  anthropic-thinking-tokens
  # No cost headers
```

### OpenAI

```
Response body:
  usage.prompt_tokens
  usage.completion_tokens
  usage.total_tokens

Headers:
  x-ratelimit-limit-requests
  x-ratelimit-remaining-requests
  x-ratelimit-limit-tokens
  x-ratelimit-remaining-tokens
  # No cost headers
```

### Groq

```
Response body:
  usage.prompt_tokens
  usage.completion_tokens
  usage.total_tokens

Headers:
  x-ratelimit-remaining-requests
  x-ratelimit-remaining-tokens
  # No cost headers
```

---

## 10. Appendix: CLI Model Selection Reference

### Claude Code

```bash
claude --model opus
claude --model claude-sonnet-4-6
ANTHROPIC_MODEL=claude-opus-4 claude
```

Config files: `.claude/settings.json`, `~/.claude/settings.json`

### OpenCode

```bash
opencode --model anthropic/claude-sonnet-4-5
opencode --model openai/gpt-5.2
```

Config files: `opencode.json`, `~/.config/opencode/opencode.json`

### Codex

```bash
codex --model gpt-5.4
codex -m gpt-5.3-codex
codex --config model=gpt-5.5
```

Config files: `~/.codex/config.toml`, `.codex/config.toml`
In-session: `/model` slash command
