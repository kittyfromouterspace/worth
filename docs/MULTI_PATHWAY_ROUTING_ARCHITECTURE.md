# Multi-Pathway Model Routing Architecture

> **Status:** This is the short-form summary. The full proposal — with
> `ProviderAccount` separation, per-pathway capabilities, graded availability,
> quota-pressure scoring, `ex_money`-based currency handling, SQLite-backed
> SpendTracker, and subscription amortization — lives in
> [`IMPLEMENTATION_PROPOSAL_MULTI_PATHWAY_ROUTING.md`](IMPLEMENTATION_PROPOSAL_MULTI_PATHWAY_ROUTING.md)
> (rev 2). This file is kept in sync with the headline shape of that proposal.

## Problem

The same underlying model (e.g. Claude Sonnet 4) can be reached through multiple
providers with wildly different economics:

| Pathway | Provider | Cost Model | Requires |
|---------|----------|------------|----------|
| Anthropic API | `:anthropic` | Subscription / included | API key |
| Claude Code CLI | `:claude_code` | Subscription / included | `claude` binary + OAuth |
| OpenRouter | `:openrouter` | Pay-per-token | API key |
| OpenCode CLI | `:opencode` | Subscription / included | `opencode` binary |

Today Agentic treats each provider as a silo. There is no concept of "Claude
Sonnet 4 reached via Anthropic direct vs OpenRouter." The Catalog keys models
by `{provider, model_id}` and the ModelRouter picks one model. We need to
**group by canonical model** and **score pathways**.

---

## Proposed Architecture

### 1. Add `canonical_id` and per-pathway capabilities to the Model struct

```elixir
defstruct Agentic.LLM.Model do
  # ... existing fields ...
  canonical_id: nil,       # "claude-sonnet-4" — provider-agnostic
  capabilities: MapSet.new()  # PER-PATHWAY (Anthropic direct ≠ Claude Code)
end
```

- **OpenRouter** uses `provider/model` IDs → strip the org prefix to get the canonical (e.g. `anthropic/claude-sonnet-4` → `claude-sonnet-4`).
- **Anthropic direct** uses `claude-sonnet-4-20250514` → map to `claude-sonnet-4`.
- **Claude Code** serves the same weights → same canonical.

A central static module `Agentic.LLM.Canonical` owns the (provider, model_id) →
canonical_id table; providers consult it instead of hardcoding their own.

Per-pathway capabilities matter: Anthropic direct supports 1M context, extended
thinking, prompt caching, vision; Claude Code via CLI may not surface all of
that. `Catalog.find/1` accepts `requires: [capability]` so the router rejects
under-capable pathways before scoring.

### 2. Cost Profiles live on the user-account, not the model

The same model is `:pay_per_token` for someone with a raw API key and
`:subscription_included` for someone on Pro. Cost profile lives on
`Agentic.LLM.ProviderAccount`, resolved from settings at session start:

```elixir
defmodule Agentic.LLM.ProviderAccount do
  defstruct [
    :provider, :cost_profile, :subscription, :credentials_status,
    :availability, :quotas
  ]
end

@type cost_profile ::
  :free              # Ollama, OpenRouter :free tier
  | :subscription_included   # Flat fee, unmetered (Claude Code, z.ai)
  | :subscription_metered    # Flat fee + overage (Anthropic Pro with weekly caps)
  | :pay_per_token           # Pure usage-based (OpenRouter paid)
```

The `Model.cost` map remains the static per-token catalog price — used for
estimated-cost telemetry on pay-per-token paths and for subscription
amortization math (effective $/Mtok) on subscription paths.

### 3. ModelRouter groups by canonical, then scores pathways

Current flow:
```
Catalog.find(tier: :primary) → [Model, Model, ...] → sort by priority → routes
```

New flow:
```
Catalog.find(tier: :primary) → [Model, Model, ...]
  → group by canonical_id
  → for each canonical, score all pathways
  → pick best pathway
  → sort canonical groups
  → return routes
```

Scoring (lower = better):
```
base + source_bonus + free_penalty + verified_bonus + failure_penalty
  + cost_profile_score(account, preference)
  + quota_pressure_score(account)
  + availability_score(account)
```

`cost_profile_score/2`:

| Profile | `:optimize_price` | `:optimize_speed` |
|---------|-------------------|-------------------|
| `:free` | −10 | 0 |
| `:subscription_included` | −5 | −2 |
| `:subscription_metered` | 0 | −1 |
| `:pay_per_token` | `log(avg_cost+1)*5` | tier-based |

`quota_pressure_score/1` ramps from 0 below 70% subscription utilization to a
sharp cliff above 90% — so Pro plans automatically taper toward pay-per-token
fallbacks as the weekly cap approaches, instead of hard-failing mid-session.

### 4. Graded availability filtering

Availability is **not binary**. Provider behaviour gains:

```elixir
@callback availability(account) ::
  :ready | :degraded | {:rate_limited, until} | :unavailable
```

| State | Meaning | Routing effect |
|-------|---------|----------------|
| `:ready` | Credentials valid, no rate limit, quota healthy | Score normally |
| `:degraded` | Reachable but suboptimal (e.g. expired Claude Code OAuth — CLI re-auths lazily) | +2 penalty + UI warning |
| `{:rate_limited, until}` | Provider returned 429 recently | +8 penalty until `until` |
| `:unavailable` | No creds, no binary, or creds invalid | Hard-filter out |

Worth resolves `[ProviderAccount]` from settings at session start and pushes
them into `ctx.metadata` so the router has all the per-user state it needs
without knowing about Worth's vault directly.

### 5. Route struct additions

```elixir
%{
  canonical_model_id: "claude-sonnet-4",
  provider_name: "anthropic",
  model_id: "claude-sonnet-4-20250514",
  account_id: "anthropic-pro",                # which ProviderAccount matched
  cost_profile: :subscription_included,       # resolved from the account
  # ...existing fields...
}
```

### 6. Worth UI: Provider Pathways

Extend the existing settings panel with a **"Model Pathways"** card:

```
┌─ Model Pathways ─────────────────────────────────────┐
│ Choose how to reach each model family.                │
│                                                       │
│ Claude models                                         │
│   [● Anthropic direct]  [○ Claude Code]  [○ OpenRouter]│
│   subscription          subscription       pay-per-use │
│                                                       │
│ GLM models                                            │
│   [○ z.ai]  [○ OpenCode]  [● OpenRouter]             │
│   subscription  subscription  pay-per-use            │
│                                                       │
│ GPT models                                            │
│   [● OpenAI]  [○ OpenRouter]                         │
│   subscription  pay-per-use                          │
└───────────────────────────────────────────────────────┘
```

- Green dot = pathway is available (key configured / CLI installed)
- Grey dot = pathway unavailable (no key / CLI not found)
- Clicking selects the preferred pathway; router uses it as a tie-breaker
  within the canonical group.

---

## Implementation Phases

See [`IMPLEMENTATION_PROPOSAL_MULTI_PATHWAY_ROUTING.md` §7](IMPLEMENTATION_PROPOSAL_MULTI_PATHWAY_ROUTING.md#7-implementation-phases)
for the full phase breakdown. Headline order:

1. **Foundation** — `Canonical` module, `ProviderAccount`, capability-aware
   `Catalog.find/1`, `Preference.score/4`, route grouping.
2. **Gateway cost tracking & SpendTracker** — augment existing `:stop` event
   with `actual_cost`/`estimated_cost` (Money), persist to SQLite. The Gateway
   already auto-injects `ANTHROPIC_BASE_URL`/`OPENAI_BASE_URL` into all CLI
   subprocesses (`Gateway.inject_env/2`), so CLI turns are covered automatically.
3. **CLI provider wrappers** — `Provider.ClaudeCode`, `OpenCode`, `Codex` with
   `availability/1`. CLI macro injects `--model` from `route.model_id` directly
   (no per-protocol alias tables — `Canonical` is the single source).
4. **Provider management UI** — Provider Accounts + Model Pathways cards.
5. **z.ai & external providers** — CNY-native rows, USD display via `Money.to_currency/3`.
6. **Subscription dashboard with amortization** — effective $/Mtok, savings vs
   pay-per-use.

---

## Resolved & Open Questions

**Resolved during rev 2:**
- ✅ Claude Code OAuth → graded `availability/1` returns `:degraded` if
  `~/.claude/auth.json` is expired (CLI re-auths lazily); `:unavailable` if
  binary missing.
- ✅ CLI subprocess cost capture → already covered by Gateway proxy auto-injection
  via `Gateway.inject_env/2`. The same `:stop` telemetry event fires whether
  the call originated in-process or from a subprocess CLI.
- ✅ Currency normalization → `ex_money` (Hex `:ex_money` v5.24.x or v6 RC) for
  `Money.t()` values; `Money.ExchangeRates` for FX. Persisted to SQLite as
  `(amount NUMERIC, currency TEXT)` pairs.
- ✅ Sticky route migration → none needed; no users yet.

**Resolved during rev 3 (research):**
- ✅ Canonical mapping → `Agentic.LLM.Canonical` is now a GenServer that
  **fetches and caches [models.dev](https://models.dev/api.json)** (the same
  catalog OpenCode uses, ~50+ providers, free no-auth) and merges with a small
  static-override table for things models.dev doesn't list (Codex aliases,
  z.ai GLM family, Claude Code short aliases). Snapshots to
  `~/.agentic/models_dev.json`.
- ✅ z.ai API — `https://api.z.ai/api/paas/v4/` (USD) or `bigmodel.cn` (CNY),
  OpenAI-compatible Bearer auth, **no `/models` endpoint, no balance endpoint**
  (link to z.ai dashboard). Treat as static-list provider.
- ✅ OpenCode / Codex — OpenCode has `opencode models` and uses models.dev
  (we share the source). Codex has no list command; rolling aliases hardcoded
  in `Canonical` overrides.
- ✅ Anthropic Admin API — `GET /v1/organizations/usage_report/messages` and
  `/cost_report` confirmed; require separate `sk-ant-admin-...` org-admin key.
- ✅ OpenAI Admin API — `GET /v1/organization/usage/{completions,...}` and
  `/v1/organization/costs`; require separate `sk-admin-...` key.
- ❌ Anthropic Pro weekly cap header — does **not** exist. Plan caps are
  Console-only; we estimate from published plan limits and back-fill
  `ProviderAccount.quotas` from SpendTracker accumulation.
- ✅ OXR distribution — v1 bundles a Worth-owned OXR app id; v2 routes clients
  through a Worth-hosted OXR-compatible relay (transparent migration behind
  `Money.ExchangeRates` behaviour).

**Still open:**
1. **Claude Code OAuth path on Windows** — likely `%APPDATA%\claude\auth.json`,
   confirm in Phase 3 smoke-test.
2. **ACP model negotiation** — Defer to a future phase; not load-bearing for
   the current scope.
