# Codebase Cleanup Plan

Comprehensive refactoring plan covering everything outside the skills consolidation
(see `skills-consolidation.md` for that).

## 1. Critical Bugs

### 1.1 Broken exponential backoff in MCP ConnectionMonitor

**File:** `lib/worth/mcp/connection_monitor.ex:73`

```elixir
# BUG: Empty map means Map.get always returns 0, backoff is always 1ms
backoff = min(:math.pow(2, Map.get(%{}, server_name, 0)), 30_000)
```

**Fix:** Track attempt counts in the monitor's state:

```elixir
# In state, add: retry_counts: %{}
attempts = Map.get(state.retry_counts, server_name, 0)
backoff = min(trunc(:math.pow(2, attempts)) * 1_000, 30_000)
# After scheduling reconnect:
retry_counts = Map.update(state.retry_counts, server_name, 1, &(&1 + 1))
# On successful connect:
retry_counts = Map.delete(state.retry_counts, server_name)
```

### 1.2 Unsafe pattern match in MCP Gateway

**File:** `lib/worth/mcp/gateway.ex:15`

```elixir
# CRASH: Will crash if get_schema returns {:error, _}
{:ok, schema} = Worth.Mcp.ToolIndex.get_schema(tool_name)
```

**Fix:** Use `case` or `with`:

```elixir
with {:ok, schema} <- Worth.Mcp.ToolIndex.get_schema(tool_name) do
  # proceed
else
  {:error, reason} -> {:error, "Tool schema not found: #{reason}"}
end
```

### 1.3 No-op expression in Brain

**File:** `lib/worth/brain.ex:370`

```elixir
# BUG: Same expression on both sides of ||
content = params[:content] || params[:content]
```

**Also in:** `lib/worth/brain/session.ex:37`

**Fix:** Remove the redundant `||`:

```elixir
content = params[:content]
```

### 1.4 Test logic error

**File:** `test/worth/memory/fact_extractor_test.exs:88`

Test named "extracts and stores facts when enabled" passes `enabled: false`.

**Fix:** Change to `enabled: true` or rename the test.

---

## 2. Extract Worth.Tools.Router

**Problem:** Tool dispatch logic (prefix-matching cond block) is duplicated in:
- `Brain.build_callbacks/1` → `execute_external_tool` (6 branches)
- `Brain.Session.build_resume_callbacks/3` → `execute_external_tool` (3 branches)

Plus tool definition aggregation is duplicated in 3 places (search_tools,
get_tool_schema in Brain, and Session).

### New module: `lib/worth/tools/router.ex`

```elixir
defmodule Worth.Tools.Router do
  @moduledoc """
  Routes tool calls to the appropriate Worth tool module based on name prefix.
  """

  @tool_modules [
    {"memory_", Worth.Tools.Memory},
    {"skill_", Worth.Tools.Skills},
    {"mcp_", Worth.Tools.Mcp},
    {"kit_", Worth.Tools.Kits}
  ]

  def all_definitions do
    Enum.flat_map(@tool_modules, fn {_prefix, mod} -> mod.definitions() end)
  end

  def execute(name, args, workspace) do
    case find_module(name) do
      {:ok, mod} -> mod.execute(name, args, workspace)
      :not_found ->
        if String.contains?(name, ":") do
          Worth.Mcp.Gateway.execute(name, args)
        else
          {:error, "External tool '#{name}' not configured"}
        end
    end
  end

  def get_schema(name) do
    all_definitions()
    |> Enum.find(&(&1["name"] == name || &1[:name] == name))
  end

  defp find_module(name) do
    case Enum.find(@tool_modules, fn {prefix, _} -> String.starts_with?(name, prefix) end) do
      {_, mod} -> {:ok, mod}
      nil -> :not_found
    end
  end
end
```

Then Brain callbacks simplify to:

```elixir
execute_external_tool: fn name, args, ctx ->
  Worth.Tools.Router.execute(name, args, ctx.metadata[:workspace])
end,

search_tools: fn query, _opts ->
  Worth.Tools.Router.all_definitions()
  |> Enum.filter(& String.contains?(&1["name"] || &1[:name] || "", query))
end,

get_tool_schema: fn name ->
  case Worth.Tools.Router.get_schema(name) do
    nil -> {:error, :not_found}
    schema -> {:ok, schema}
  end
end
```

### Files changed

| File | Change |
|------|--------|
| **New:** `lib/worth/tools/router.ex` | Tool routing + definition aggregation |
| `lib/worth/brain.ex` | Replace inline dispatch with Router calls |
| `lib/worth/brain/session.ex` | Replace inline dispatch with Router calls |

---

## 3. Standardize Tool Definition Schema Keys

**Problem:** Tool definitions use 3 different key formats:

| Modules | Key format |
|---------|------------|
| `Memory`, `Skills` | `parameters:` (atom) |
| `Mcp`, `Kits` | `input_schema:` (atom) |
| `Git`, `Web`, `Workspace` | `"input_schema"` (string) |

**Target:** Use string keys with `"input_schema"` everywhere, matching agent_ex's
format (`%{"name" => ..., "input_schema" => ...}`).

**Files to update:**
- `lib/worth/tools/memory.ex` — change `parameters:` to `"input_schema"`
- `lib/worth/tools/skills.ex` — change `parameters:` to `"input_schema"`
- `lib/worth/tools/mcp.ex` — change `input_schema:` to `"input_schema"`
- `lib/worth/tools/kits.ex` — change `input_schema:` to `"input_schema"`

After this, `Tools.Router.get_schema/1` can use consistent key access.

---

## 4. Extract Worth.Workspace.resolve_path/1

**Problem:** Workspace path resolution duplicated in 3 places:
- `Brain.init` (line 122-127)
- `Brain.execute_agent_loop` (line 284-289)
- `CLI.main` (line 46)

All do:
```elixir
Path.expand("workspaces/#{workspace}", Worth.Config.Store.home_directory())
```

### Solution

Add to existing `Worth.Workspace.Service` or a new function:

```elixir
# In lib/worth/workspace/service.ex (or a new Worth.Workspace module)
def resolve_path(workspace_name) do
  Path.expand("workspaces/#{workspace_name}", Worth.Config.Store.home_directory())
end
```

Replace all 3 call sites.

---

## 5. Fix MCP Module Issues

### 5.1 Redundant cleanup in ToolIndex.unregister_server

**File:** `lib/worth/mcp/tool_index.ex:25-35`

```elixir
def unregister_server(server_name) do
  server = to_string(server_name)
  :ets.match_delete(@table, {:"$1", server, :_, :_})
  # BUG: This second pass is redundant — match_delete already removed everything
  :ets.tab2list(@table)
  |> Enum.filter(fn {_key, srv, _, _} -> srv == server end)
  |> Enum.each(fn {key, _, _, _} -> :ets.delete(@table, key) end)
  :ok
end
```

**Fix:** Remove the second pass. If `match_delete` pattern is wrong, fix the
pattern instead of adding a fallback scan.

### 5.2 Unused parameters in MCP Config

**File:** `lib/worth/mcp/config.ex`

- `add_server(name, config, _persist)` — `_persist` never used
- `save_global(_servers)` — `_servers` never used, `_config_content` assigned but discarded

**Fix:** Either implement the persist/save logic or remove the parameters.

### 5.3 Bare rescue in Client Supervisor

**File:** `lib/worth/mcp/client/supervisor.ex:30`

```elixir
rescue
  _ ->
```

**Fix:** Catch specific exceptions, log what was caught.

---

## 6. Refactor CommandHandler

**Problem:** `WorthWeb.CommandHandler.handle/3` is 480 lines with 40+ pattern-match
clauses covering every slash command.

### Solution: Split into per-namespace modules

```
lib/worth_web/live/
  command_handler.ex          # Router — dispatches to namespace modules
  commands/
    memory_commands.ex        # /memory *
    skill_commands.ex         # /skill *
    provider_commands.ex      # /provider *, /model *
    workspace_commands.ex     # /workspace *, /mode *
    mcp_commands.ex           # /mcp *
    session_commands.ex       # /session *
    system_commands.ex        # /clear, /help, /status, /setup
```

Each module implements:
```elixir
defmodule WorthWeb.Commands.MemoryCommands do
  def handle({:memory, :query, query}, socket), do: ...
  def handle({:memory, :write, text}, socket), do: ...
  def handle({:memory, :reembed}, socket), do: ...
end
```

Router becomes:
```elixir
defmodule WorthWeb.CommandHandler do
  @dispatchers %{
    memory: WorthWeb.Commands.MemoryCommands,
    skill: WorthWeb.Commands.SkillCommands,
    # ...
  }

  def handle({namespace, _action} = cmd, socket) when is_map_key(@dispatchers, namespace) do
    @dispatchers[namespace].handle(cmd, socket)
  end

  def handle({namespace, _action, _arg} = cmd, socket) when is_map_key(@dispatchers, namespace) do
    @dispatchers[namespace].handle(cmd, socket)
  end
end
```

---

## 7. Remove Dead Code

### 7.1 Delete `Worth.Telemetry`

**File:** `lib/worth/telemetry.ex`

Agent-based span tracker. Started in supervision tree but `span/3` is never called.
The Agent always returns `%{}`. Remove from supervision tree and delete file.

Note: `WorthWeb.Telemetry` (the Phoenix telemetry module) stays — it's a different
module. But its `periodic_measurements/0` stub should either be implemented or
cleaned up (remove commented-out example).

### 7.2 Remove unused Brain pass-throughs

**File:** `lib/worth/brain.ex`

Remove these functions that just delegate to Mcp modules with no added value:
- `mcp_connect/1` → callers should use `Worth.Mcp.Broker.connect/1` directly
- `mcp_disconnect/1` → callers should use `Worth.Mcp.Broker.disconnect/1`
- `mcp_list/0` → callers should use `Worth.Mcp.Broker.list/0`
- `mcp_tools/1` → callers should use `Worth.Mcp.ToolIndex.tools_for/1`

### 7.3 Remove unused ChatLive assigns

**File:** `lib/worth_web/live/chat_live.ex`

Remove from mount:
- `input_history: []` — initialized but never read or updated
- `history_index: -1` — initialized but never read or updated

### 7.4 Clean up duplicate render_streaming

**File:** `lib/worth_web/live/chat_live.ex:257-262`

`render_streaming/1` is defined here but should either be in ChatComponents or
called from the template — not both. Consolidate to one location.

---

## 8. Replace Broad Rescue Clauses

These locations silently swallow all exceptions:

| File | Location | Current | Fix |
|------|----------|---------|-----|
| `brain.ex` | `flush_working_memory` | `rescue _ -> :ok` | Log warning |
| `workspace/file_browser.ex` | line 22-24 | `rescue _ -> []` | Log warning |
| `workspace/identity.ex` | `parse_yaml` | `rescue _ -> nil` | Log warning, return `{:error, reason}` |
| `mcp/client/supervisor.ex` | line 30 | `rescue _ ->` | Catch specific, log |
| `chat_components.ex` | 5 `tab_content` clauses | `rescue _ ->` | Catch specific, show error in tab |

**Pattern:** Replace bare rescues with:
```elixir
rescue
  e ->
    Logger.warning("Context: #{Exception.message(e)}")
    fallback_value
end
```

---

## 9. Fix Persistence.Transcript

### 9.1 load_since/3 ignores timestamp

**File:** `lib/worth/persistence/transcript.ex`

```elixir
def load_since(session_id, _timestamp, workspace_path) do
  {:ok, entries} = load(session_id, workspace_path)
  {:ok, entries}
end
```

**Fix:** Filter entries by timestamp:
```elixir
def load_since(session_id, timestamp, workspace_path) do
  {:ok, entries} = load(session_id, workspace_path)
  filtered = Enum.filter(entries, &(&1["timestamp"] >= timestamp))
  {:ok, filtered}
end
```

### 9.2 Jason.decode! can crash on corrupt lines

**Fix:** Use `Jason.decode/1` with error handling per line, skip corrupt entries
with a warning log.

---

## 10. Implement Tool Approval Flow

**Status:** Backlog — blocked on architecture decision

**Problem:** The `on_tool_approval` callback in Brain always returns `:approved`.
With the PubSub refactor (replacing `ui_pid` direct sends), PubSub is fire-and-forget
and cannot carry a reply, so the approval flow needs a dedicated mechanism.

### Current state (post-PubSub refactor)

- `on_tool_approval` broadcasts `{:tool_approval_request, name, input}` to the
  workspace PubSub topic for informational purposes, then returns `:approved`
- No UI for approval prompts exists yet
- `pending_approval` field was removed from Brain state (dead code cleanup)

### Implementation approach

The `on_tool_approval` callback runs inside the AgentEx agent loop Task, so it can
block. The approval flow should:

1. Brain's `on_tool_approval` callback broadcasts the request to PubSub
2. Callback blocks on a `receive` waiting for `{:tool_decision, tool_name, decision}`
3. LiveView shows an approval dialog and sends the decision to the blocking Task
   via `send(task_pid, {:tool_decision, ...})` — task PID is included in the PubSub
   broadcast
4. Callback returns `:approved` or `:denied` based on the received message
5. Timeout (e.g., 60s) auto-denies

### Prerequisites

- AgentEx must pass the tool approval callback result through to the agent loop
  (verify this is implemented)
- LiveView needs an approval dialog component
- Need to decide on per-tool permission granularity (current `@default_tool_permissions`
  map in Brain)

---

## 11. LLM Module Cleanup

### 11.1 Duplicate provider mapping

**File:** `lib/worth/llm.ex`

`provider_for_route/1` and `provider_module_for/1` both map provider strings to
modules. Consolidate:

```elixir
@providers %{
  "anthropic" => AgentEx.LLM.Provider.Anthropic,
  "openai" => AgentEx.LLM.Provider.OpenAI,
  "openrouter" => AgentEx.LLM.Provider.OpenRouter,
  "groq" => AgentEx.LLM.Provider.Groq
}

defp provider_module(name), do: Map.get(@providers, name)
```

### 11.2 Complex classify_error/1

8 clauses with multiple `String.contains?` chains. Extract patterns:

```elixir
@rate_limit_patterns ["429", "rate", "too many"]
@auth_patterns ["401", "403", "auth", "key", "permission"]

defp classify_error(reason) when is_binary(reason) do
  cond do
    matches_any?(reason, @rate_limit_patterns) -> :rate_limit
    matches_any?(reason, @auth_patterns) -> :auth
    # ...
  end
end
```

---

## 12. Inconsistent Tool Execute Context

**Problem:** The third parameter to `execute/3` varies across tool modules:
- `Memory` → `workspace` (string)
- `Git` → `ctx` (map with `.metadata`)
- Others → `_workspace` or `_ctx`

**Fix:** Standardize to always pass a context map. Tools that need workspace
extract it:

```elixir
# All tool execute functions receive:
def execute(name, args, ctx) do
  workspace = ctx[:workspace] || ctx["workspace"]
  # ...
end
```

Update `Worth.Tools.Router.execute/3` to always pass a consistent context map.

---

## 13. Versioner /tmp Fallback

**File:** `lib/worth/skills/versioner.ex:84`

```elixir
nil -> Path.join("/tmp", "worth-skill-history-#{skill_name}")
```

Falls back to ephemeral `/tmp` when skill dir can't be resolved. Version history
silently lost on reboot.

**Fix:** Return `{:error, :skill_not_found}` instead. Callers should handle the
error explicitly.

---

## 14. Test Infrastructure

### 14.1 Coverage gaps

50% of modules (37 of ~74) have no tests. Priority additions:

**Critical (blocks confident refactoring):**
- `Worth.Brain.Session` — session resume logic
- `Worth.LLM` — routing, retry, fallback
- `Worth.Skill.Service` — after refactoring, needs full coverage
- `Worth.Mcp.Gateway` — tool resolution + execution

**Important:**
- `Worth.Persistence.Transcript`
- `Worth.Workspace.Context`
- `Worth.Mcp.ConnectionMonitor` (especially the backoff fix)

### 14.2 Duplicated test setup

`test/worth/workspace/identity_test.exs` has 3 near-identical `setup do` blocks
creating temp directories. Extract to `test/support/`:

```elixir
defmodule Worth.TestHelpers do
  def tmp_dir(prefix) do
    dir = Path.join(System.tmp_dir!(), "#{prefix}_#{:rand.uniform(999_999)}")
    File.mkdir_p!(dir)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
```

### 14.3 Async test audit

9 of 14 test files use `async: false`. Audit each to determine if they truly need
serial execution or if test isolation can be improved.

---

## Execution Priority

| Priority | Items | Impact | Risk |
|----------|-------|--------|------|
| **P0** | 1.1-1.4 (bugs) | Correctness | Low |
| **P1** | 2 (Tools.Router) | Removes biggest duplication | Low |
| **P1** | 7 (dead code removal) | Reduces confusion | Low |
| **P2** | 3 (schema keys) | Consistency | Low |
| **P2** | 4 (workspace path) | Small DRY win | Low |
| **P2** | 5 (MCP fixes) | Correctness | Low |
| **P2** | 8 (rescue clauses) | Debuggability | Low |
| **P3** | 6 (CommandHandler split) | Maintainability | Medium |
| **P3** | 9 (Transcript fixes) | Correctness | Low |
| **P3** | 10 (approval flow) | Feature gap | Medium |
| **P3** | 11 (LLM cleanup) | DRY | Low |
| **P3** | 12 (tool context) | Consistency | Medium |
| **P4** | 14 (tests) | Confidence | Low |
