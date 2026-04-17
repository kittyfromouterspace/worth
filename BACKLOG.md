# Worth Backlog

## Remove `test/support/recollect_embedding_mock.ex` shim

**Added:** 2026-04-17 (during v0.2.1-alpha.10 release)

Recollect v0.5.1 moved `Recollect.Embedding.Mock` from `lib/` to `test/support/`, which means the module isn't available when Recollect is consumed as a git dependency (`test/support` is not packaged). `config/test.exs` still references `Recollect.Embedding.Mock` as the embedding provider, so the v0.2.1-alpha.10 release added a local copy at `test/support/recollect_embedding_mock.ex` to unblock the prod-mode test step in the release SOP.

Once Recollect ships the mock under `lib/` again (tracked in `recollect/BACKLOG.md`), delete the local shim and bump the recollect git dep tag in `mix.exs`. Keeping both will fire a module-redefinition warning at compile time.



Open items, cleanup, and refinement work identified during the LLM
provider abstraction phases. Grouped by category, not by priority —
each item should be evaluated against current goals before pulling
it in. Items reference the phase that surfaced them so the original
context is recoverable from `docs/llm-provider-abstraction-plan.md`.

## Dead code / safe deletes

_All items in this section were addressed in the Phase 6 cleanup
commit. Kept for historical reference._

- ~~`worth/lib/worth/llm/{anthropic,openai,openrouter,shim,adapter,cost}.ex`~~ — **deleted**.
- ~~`worth/lib/worth/brain.ex` `state.cost_total` field + dead `{:cost, amount}` handler~~ — **deleted**. UI consumers now read from `Worth.Metrics.session_cost/0`.
- ~~`agentic/lib/agentic/model_router/free.ex`~~ — **deleted** along with its supervision tree entry.

## Worth.LLM projection layer retirement

_Resolved: projection layer deleted, all consumers migrated to struct field access._

- ~~**`Worth.LLM.project_result/1` / `project_block/1`**~~ — **deleted** from `worth/lib/worth/llm.ex`. The 4 dispatch paths (`chat_with_route`, `chat_with_configured`, `stream_chat_with_route`, `stream_chat_with_configured`) now return `%Agentic.LLM.Response{}` directly.
- ~~Every place that did `response["stop_reason"]` / `response["content"]` / `response["usage"]`~~ — **migrated** to struct field access (`response.stop_reason`, `response.content`, `response.usage`). Scope: `agentic/lib/agentic/loop/stages/{mode_router,llm_call,transcript_recorder,plan_tracker,commitment_gate}.ex`, `agentic/lib/agentic/loop/{helpers,context}.ex`, `agentic/lib/agentic/loop/stages/cli_executor.ex`, `agentic/lib/agentic/model_router/analyzer.ex`, `agentic/lib/agentic/memory/{memory_manager,fact_extractor}.ex`.
- **`Agentic.LLM.Response` struct** gained a `cost: nil` field so `LLMCall` can set cost without mutating a map.
- **`Context.last_response`** typed as `Response.t() | nil` (was `map() | nil`).
- **`Helpers.extract_text/1` and `extract_tool_calls/1`** now use atom keys (`&1.type == :text`) instead of string keys (`&1["type"] == "text"`).
- **15 test files** updated to use `%Agentic.LLM.Response{}` fixtures instead of string-keyed maps. All 428 tests pass.

## Embedding cost telemetry

Phase 5 ships with `[:agentic, :llm, :embed, :stop]` events but `cost_usd` is hardcoded to `0.0`. Real embedding cost requires:

1. **Parse usage out of each transport's embedding response.** OpenAI returns `usage.total_tokens` in the `/embeddings` response. Ollama's `/api/embed` doesn't return token counts. The `parse_embedding_response/3` callback should return `{:ok, vectors, usage_map}` with token counts when available.
2. **Extend `Model.cost` for embedding models.** Chat-style `%{input:, output:}` doesn't fit — embeddings have a single per-token rate. Either add `cost.embedding` or use `cost.input` for the per-1M-token rate (current OpenAI provider already does this).
3. **Wire `compute_embedding_cost/2` into `Agentic.LLM.execute_embed/3`** mirroring the chat-side `compute_cost/2`.

## Async ownership warnings in Recollect.Pipeline.Embedder

`embed_entry_async` spawns a `Task.Supervisor` task to write embeddings, but in test environments the spawned task can't see the test's Ecto sandbox connection. Result: a `DBConnection.OwnershipError` is logged on every call, the embedding is dropped, and tests pass anyway because the warnings are non-fatal. Pre-existed Phase 4 — Phase 4's added column made the failing UPDATE more visible but didn't introduce the bug.

**Fix:** when running under sandbox mode, pass the test's owner pid via `Task.Supervisor.start_child(supervisor, fun, caller: pid)` and call `Ecto.Adapters.SQL.Sandbox.allow/3` on the spawned task. Or expose a `:caller_pid` opt on `embed_entry_async` and let tests pass it explicitly.

## Reembed performance

`Recollect.Maintenance.Reembed.run/1` is now sync-within-transaction, walking rows one at a time through `embedding_fn`. Fine for typical memory store sizes; pathological for large stores.

- **Batched COPY upserts** would be faster: build the (id, embedding, model_id) tuples in memory, then `COPY ... FROM STDIN` in one round trip.
- **The HTTP call to the embedding provider dominates anyway** — batching has to happen at the embedding API call level (e.g., `OpenAI.generate(texts)` with N=100) before COPY upserts matter.
- The async version was simpler but broke tests via sandbox ownership. If we ever want async back, fix the ownership issue first (see above) and then revisit.

## Catalog hardening

- ~~**Atomic catalog persistence.**~~ — **resolved** (already uses tmp+rename in `Agentic.LLM.Catalog.save_to_disk/1`).
- **Schema versioning** is at `v1`. Bump to `v2` whenever the `Model` struct gains/changes a field, and drop the cache on mismatch (already wired, just remember to do it).
- **Catalog merge conflict logging.** When a user override claims a model has different capabilities than discovery says, log a warning. Currently silent — user wins without comment.

## Reembed progress reporting

`/memory reembed` is fire-and-forget: it prints "Re-embedding memories in the background..." and that's the last the user hears unless they `tail -f` the log. The plan's "things to refine" section calls out wiring `progress_callback` into a `:reembed_progress` agent event so the UI can render a progress bar.

- New agent event: `{:reembed_progress, %{table:, processed:, total:}}`
- `Worth.UI.Events.drain/1` consumes it and updates a sidebar progress bar
- `Worth.Tools.Memory.Reembed.run/1` passes the callback through

## UsageManager refinements

- **Live config reload.** The 5-minute poll interval is read once at boot. Changing `:agentic, :usage, :refresh_interval_ms` requires a restart. Acceptable for an observability cache, fixable with a `set_interval/1` GenServer call.
- **Anthropic fetch_usage.** Currently `:not_supported` because the `/v1/organizations/<id>/usage` endpoint requires OAuth admin credentials. Wire when OAuth lands (see future iterations).
- **OpenRouter rate-limit windows.** OpenRouter exposes `data.rate_limit.{requests, interval}` (the *limit*) but no `used` counter. Sidebar shows `?/<limit>` until either OpenRouter ships a `used` field or we track it locally via successful-call counters keyed off telemetry events.
- **Per-provider usage error display.** `%Usage{error: ...}` exists in the struct but the sidebar doesn't render it — failed fetches are silently dropped. Show a `(stale)` or `(error)` marker next to the provider label.

## UI / TUI polish

_The TermUI TUI was replaced by Phoenix LiveView. Items referencing `lib/worth/ui/root.ex` are resolved._

- ~~**`:usage` sidebar tab is unreachable via number key.**~~ — **resolved** (TUI removed, replaced by LiveView).
- ~~**`lib/worth/ui/root.ex` debug `IO.puts`**~~ — **resolved** (file deleted).
- ~~**`lib/worth/ui/root.ex` unused `e` variable warning**~~ — **resolved** (file deleted).
- **`/provider list` output format.** Currently a brief one-liner per provider. The "things to refine" plan section suggests `name | enabled | model count | last refresh | usage status`. Grow when needed.

## Test infrastructure

- **Provider smoke test harness.** Every provider module should have a `live_test` that hits `Credentials.resolve/1` and `fetch_catalog/1` against the real service when an env-var-gated `LIVE_TESTS=1` is set. Catches "did this provider ever actually work" regressions.
- **Phase 4 `agentic/test/agentic/llm_test.exs`** has only minimal coverage — extend it once `embed_tier/3` resolution stabilizes.
- **No worth-side tests for `Worth.Metrics`, `Worth.Memory.Embeddings.Adapter`, or `Worth.Memory.Embeddings.StaleCheck`.** Each is small and well-scoped; add unit tests when there's bandwidth.
- **No worth-side tests for the new `:usage` sidebar tab or the `/usage` slash command.** The existing `test/worth/ui/sidebar_test.exs` (untracked since session start) is the natural home.

## Pre-Phase 6 prep (Anthropic prompt caching)

The telemetry path already reads `cache_read`/`cache_write` defensively, so Phase 6 mostly needs transport changes:

1. **`Agentic.LLM.Transport.AnthropicMessages.build_chat_request/2`** must add `cache_control: %{type: "ephemeral"}` to the last block of the stable prefix when `params["cache_control"]["prefix_changed"] == false`. The `stable_hash`/`prefix_changed` already flow through `LLMCall` (see `base_params["cache_control"]`).
2. **`parse_chat_response/3`** must extract `usage.cache_creation_input_tokens` and `usage.cache_read_input_tokens` and put them on `Response.usage` (under `:cache_write` and `:cache_read` keys to match what `LLMCall.compute_cost/2` already reads).
3. **Cost computation already uses `cost.cache_read`/`cost.cache_write`** from `Model.cost`. Anthropic provider's `default_models/0` already populates these fields. Phase 6 just needs to make sure the values flow.
4. **`Worth.Metrics`** already accumulates `cache_read`/`cache_write` totals — sidebar and `/usage` will start showing real numbers once the transport populates them.
5. **Sidebar cache hit/miss display.** Add a "cache hit ratio" line under the session metrics in the `:usage` tab once the values are non-zero.

## Documentation

- **`docs/llm-provider-abstraction-plan.md`** has accumulated 6 phase progress entries and is approaching 1500 lines. Consider splitting the progress log into a separate `docs/llm-provider-abstraction-progress.md` file once Phase 6 lands.
- **README.md** doesn't mention any of the new slash commands (`/provider list/enable/disable`, `/catalog refresh`, `/memory reembed`, `/usage`, `/usage refresh`). Either drop them in or wait for the user-facing docs sweep.
- **`Worth.Memory.Embeddings.Adapter` moduledoc** describes the tier resolution logic but the actual logic lives in `Agentic.LLM.embed_tier/3`. Cross-reference.
- **`agentic/lib/agentic/llm/usage_manager.ex` config block.** The `:agentic, :usage, :refresh_interval_ms` key isn't documented in `Agentic.Config`'s `nimble_options` schema. Add it.

## libSQL Migration Test Fixes (Phase 1-2 Post-Implementation)

Discovered during the PostgreSQL → libSQL migration implementation. These are pre-existing test issues that became visible during migration testing but are unrelated to the database backend changes.

### 1. Brain API Function Signature Mismatches

**Status:** ~~Fixed~~. Tests updated to pass `workspace` argument to all Brain API calls.

**Affected Tests:**
- `test/worth/brain_test.exs:5` - `Worth.Brain.get_status()`
- `test/worth/brain_test.exs:13` - `Worth.Brain.switch_mode(:research)`
- `test/worth/brain_test.exs:21` - `Worth.Brain.switch_workspace("personal")`

**Fix:** Update test calls to match actual function signatures:
```elixir
# Before (wrong):
status = Worth.Brain.get_status()
:ok = Worth.Brain.switch_mode(:research)
:ok = Worth.Brain.switch_workspace("personal")

# After (correct):
status = Worth.Brain.get_status(session_id)
:ok = Worth.Brain.switch_mode(session_id, :research)
:ok = Worth.Brain.switch_workspace(session_id, "personal")
```

### 2. Missing Repo.query/2 in Worth.Repo

**Issue:** Several modules call `Worth.Repo.query/2` directly, but this function is not defined in `Worth.Repo`. The query functions are provided by `Ecto.Adapters.SQL` and need to be imported or required.

**Affected Modules:**
- `lib/recollect/search/vector.ex` - Line 204: `repo.query(sql, params)`
- `lib/recollect/pipeline/embedder.ex` - Line 143: `repo.query("UPDATE...", [...])`
- Various test modules calling `Worth.Repo.query/2`

**Fix:** Add `require Ecto.Adapters.SQL` to modules that need raw query access:
```elixir
# In Worth.Repo:
defmodule Worth.Repo do
  use Ecto.Repo, @repo_opts
  require Ecto.Adapters.SQL
  
  # Now Repo.query/2 is available
end

# Or in calling modules:
defmodule Recollect.Search.Vector do
  import Ecto.Adapters.SQL, only: [query: 3]
  
  # Then use query(repo, sql, params)
end
```

### 3. Application Startup in Test Environment

**Issue:** Test `test worth application starts` fails because `Worth.Brain` process is not running at test time. The test expects `Process.whereis(Worth.Brain)` to return a pid, but it returns `nil`.

**Affected Test:**
- `test/worth_test.exs:4` - `assert Process.whereis(Worth.Brain) != nil`

**Fix Options:**
1. **Start Brain in test setup:**
```elixir
# test/test_helper.exs or test setup
{:ok, _pid} = Worth.Brain.start_link([])
```

2. **Start full supervision tree in tests:**
```elixir
# In test setup
{:ok, _} = Application.ensure_all_started(:worth)
```

3. **Make test conditional:** Skip this test when Brain isn't started (if that's the expected test behavior).

### 4. LLM Config Validation Warnings

**Status:** ~~Fixed~~. Changed `type: {:map, :string}` to `type: :map` in `Worth.Workspace.Identity` NimbleOptions schema.
```
Failed to validate LLM config: invalid NimbleOptions schema. 
Reason: invalid value for :type option: unknown type {:map, :string}.
```

**Location:** Likely in `Worth.Config` or `Agentic.Config` schema definitions.

**Fix:** Update the NimbleOptions schema to use valid type definitions:
```elixir
# Invalid:
type: {:map, :string}

# Valid alternatives:
type: :map
type: {:map, :string, :string}  # if supported
# Or define a custom type
```

### 5. Recollect Pipeline Embedder Async Sandbox Issues

**Related to existing backlog item above** - `embed_entry_async` spawns tasks that can't access the Ecto sandbox connection in tests. This causes `DBConnection.OwnershipError` warnings and embeddings are dropped.

**Location:** `Recollect.Pipeline.Embedder.embed_entry_async/1`

**Status:** Already documented in backlog under "Async ownership warnings in Recollect.Pipeline.Embedder" - fix that item and this will be resolved.

## Future iterations (deferred from the plan)

These are explicitly out of scope for the current iteration but documented here so they don't get forgotten:

- **Auth profiles + secure key storage + config UI.** `~/.worth/credentials.toml` encrypted via OS keyring, `/auth login <provider>` slash command, in-TUI form for pasting keys. Prerequisite for multi-profile auth.
- **Multi-profile auth per provider.** work-anthropic vs personal-anthropic. Builds on the credentials store above.
- **OAuth flows.** Anthropic web auth, OpenAI Codex CLI reuse, Google Gemini CLI reuse. Each is its own provider auth method. Unblocks Anthropic `fetch_usage`.
- **Streaming chat.** `Transport.stream_chat/2` callback returning a `Stream.t()` of canonical events.
- **Bedrock / Vertex / Azure-OpenAI Responses transports.** When someone needs them.
- **Long-term metrics history.** Persist `Worth.Metrics` snapshots to disk so users can see "you spent $X this week".
- **Per-workspace credential overrides.** Pin `OPENROUTER_API_KEY` for a specific repo without polluting the global env. Probably via `IDENTITY.md` frontmatter.
- **Tool schema normalization pipeline.** Only if a future provider needs per-call schema rewrites the transport can't express.
- **Reasoning level mapping across providers.** `/think low|medium|high` mapped to provider-specific reasoning controls.
