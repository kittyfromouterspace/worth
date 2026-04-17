# BEAM Architecture

How worth leverages OTP, BEAM primitives, and established Elixir libraries.

## Supervision Tree

The current docs say "one GenServer" for the brain, but worth needs a proper supervision tree with fault isolation. An MCP server crash should not kill the UI. A memory flush failure should not kill the brain.

```
Worth.Application
│
├── Worth.Repo                          (Ecto)
│
├── Worth.PubSub                        (Phoenix.PubSub)
│   Broadcasts: [:worth, :mcp, ...], [:worth, :skills, ...],
│               [:worth, :memory, ...], [:worth, :cost, ...]
│
├── Worth.Registry                      (Elixir Registry, keys: :unique)
│   Registers: Brain, UI, per-workspace processes
│
├── Worth.TaskSupervisor                (Task.Supervisor)
│   All async work: MCP tool calls, web fetches, memory flush,
│   fact extraction, skill refinement, codebase indexing
│
├── {Worth.Config, :loader}             (Agent, runtime config cache)
│   Resolved config values, :persistent_term for hot reads
│
├── Worth.Telemetry                     (telemetry_metrics reporter)
│   Attaches to [:worth, ...], [:agentic, ...], [:recollect, ...]
│
├── Worth.Brain.Supervisor              (Supervisor, rest_for_one)
│   ├── Worth.Brain                     (GenServer)
│   └── Worth.Memory.WorkingMemory.Supervisor  (DynamicSupervisor)
│       └── [per workspace] Worth.Memory.WorkingMemory (GenServer, owns ETS)
│
├── Worth.Mcp.Supervisor                (Supervisor, one_for_one)
│   ├── Worth.Mcp.Broker                (DynamicSupervisor)
│   │   └── [per server] Worth.Mcp.Connection  (GenServer, owns Hermes.Client)
│   ├── Worth.Mcp.Registry              (Elixir Registry)
│   ├── Worth.Mcp.ToolIndex             (ETS table, public, write_concurrency)
│   └── Worth.Mcp.ConnectionMonitor    (GenServer)
│
├── Worth.Skills.Registry               (ETS + :persistent_term)
│   Skill metadata cache (L1: name+description for system prompt)
│
└── WorthWeb.Endpoint                    (Bandit HTTP server for LiveView)
```

### Why rest_for_one for Brain

The Brain depends on WorkingMemory. If WorkingMemory crashes and restarts, the Brain's references to it are stale. `rest_for_one` restarts the Brain too, which re-establishes references. This is better than letting the Brain hold dead PIDs.

### Why one_for_one for MCP

MCP servers are independent. A GitHub server crash should not affect the Brave server. `one_for_one` provides fault isolation.

### Task.Supervisor

All async operations route through `Worth.TaskSupervisor`:

```elixir
Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
  Worth.Mcp.Connection.call_tool(client, name, args)
end)
```

This means:
- Tasks are supervised (crash doesn't cascade)
- Tasks can be shut down on workspace switch (`Task.Supervisor.children/2` + `Task.shutdown/1`)
- No orphaned processes

## Storage Strategy

| Data | Storage | Why |
|------|---------|-----|
| Skill metadata (L1) | `:persistent_term` | Read every turn, written rarely. Zero-copy reads. |
| Skill full content (L2) | Filesystem (read on demand) | Large, read occasionally. OS page cache is sufficient. |
| MCP tool index | ETS (`:set`, `write_concurrency: true`) | Updated on connect/disconnect, read on every tool call. |
| Working memory facts | ETS (owned by GenServer) | Concurrent reads from brain, bounded writes. |
| Circuit breaker state | ETS (already in agentic) | Lock-free, no GenServer bottleneck. |
| Cost tracking | ETS (`:set`, `read_concurrency: true`) | Updated every turn, read by UI at 60fps. |
| Resolved config | Agent + `:persistent_term` | Rarely changes after startup. |
| Global knowledge | PostgreSQL (via Recollect) | Durable, queryable, vector search. |
| Session transcripts | JSONL files | Append-only, simple, no DB overhead. |
| Skill evolution stats | PostgreSQL (via Recollect) | Recollect entries tagged with skill provenance. |

### :persistent_term for Skill Metadata

Skill metadata (name + description) is injected into every system prompt. With 20+ skills, this happens every turn. `:persistent_term` gives nanosecond reads without copying:

```elixir
# On skill install/remove/refine:
Worth.Skills.Registry.refresh_metadata()
# → Rebuilds the metadata list and puts it in :persistent_term

# On every turn (system prompt assembly):
metadata = :persistent_term.get({:worth, :skill_metadata})
# → Returns the full list of {name, description, loading} tuples
```

### ETS for MCP Tool Index

The tool index maps `server_name:tool_name` to `{server_name, client_pid}`. Updated on connect/disconnect, queried on every tool call:

```elixir
:ets.new(:worth_mcp_tool_index, [
  :set, :public, :named_table,
  read_concurrency: true, write_concurrency: true
])
```

### ETS for Cost Tracking

Cost accumulates every turn but the LiveView reads it on each render. A GenServer would be a bottleneck. ETS with `:read_concurrency` lets the UI read without contending with writes:

```elixir
:ets.update_counter(:worth_cost, :total_usd, current_cost)
# UI reads via :ets.lookup(:worth_cost, :total_usd)
```

## Telemetry & Observability

Both agentic and recollect emit telemetry events. Worth extends this with its own events and wires up a metrics reporter.

### Event Hierarchy

```
[:recollect, :search, :stop]                    # from recollect
[:recollect, :remember, :stop]                  # from recollect
[:agentic, :llm_call, :stop]               # from agentic
[:agentic, :tool, :stop]                   # from agentic
[:worth, :brain, :turn, :start | :stop]     # from worth
[:worth, :brain, :turn, :exception]         # from worth
[:worth, :mcp, :connect, :start | :stop]    # from worth
[:worth, :mcp, :tool, :start | :stop]       # from worth
[:worth, :mcp, :tool, :exception]           # from worth
[:worth, :skills, :install]                 # from worth
[:worth, :skills, :refine]                  # from worth
[:worth, :memory, :flush, :start | :stop]   # from worth
[:worth, :cost, :turn]                      # from worth
[:worth, :ui, :render, :stop]               # from worth
```

### Worth.Telemetry Module

```elixir
defmodule Worth.Telemetry do
  def span(event_prefix, metadata \\ %{}, fun)

  def execute(:brain_turn, ctx, fun) do
    start = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start

    :telemetry.execute(
      [:worth, :brain, :turn, :stop],
      %{duration: duration},
      Map.merge(ctx, %{
        workspace: ctx.workspace_path,
        model: ctx.model_id,
        tokens_in: ctx.usage.input_tokens,
        tokens_out: ctx.usage.output_tokens
      })
    )

    result
  end
end
```

### Metrics Reporter

Uses `telemetry_metrics` + a console reporter for the web UI:

```elixir
# In Worth.Application
Worth.Telemetry.attach_default_handler()

# Reports aggregated metrics:
# - worth_brain_turn_duration (histogram)
# - worth_brain_turn_tokens (last value)
# - worth_mcp_tool_call_duration (histogram)
# - worth_mcp_connection_status (last value per server)
# - worth_cost_session_total (sum)
```

### Why Telemetry Matters

Without telemetry, we're flying blind. The `[:agentic, :llm_call, :stop]` event already carries `duration`, `tokens`, and `cost`. Worth just needs to attach handlers. The LiveView status display (cost, turn count, model) reads from telemetry, not from polling the brain.

## PubSub

Agentic uses direct PID messaging (`send/2`). Recollect uses none. But worth needs cross-component events:

| Event | Publisher | Subscribers |
|-------|-----------|-------------|
| MCP server connected | `Worth.Mcp.ConnectionMonitor` | UI (status tab), ToolIndex |
| MCP server disconnected | `Worth.Mcp.ConnectionMonitor` | UI, ToolIndex |
| MCP tools changed | `Worth.Mcp.Connection` | ToolIndex, Brain (tool activation) |
| Skill installed | `Worth.Skills.Service` | Skills.Registry, UI |
| Skill refined | `Worth.Skills.Lifecycle` | Skills.Registry, UI |
| Memory flushed | `Worth.Memory.WorkingMemory` | Brain |
| Cost updated | Brain (`:on_event`) | UI (status bar) |
| Turn completed | Brain | UI, Memory (fact extraction) |

Using `Phoenix.PubSub` (the standalone library, not Phoenix itself -- it has no web framework dependency):

```elixir
# Worth.PubSub is started in the supervision tree
Phoenix.PubSub.subscribe(Worth.PubSub, "worth:mcp")

# Publisher
Phoenix.PubSub.broadcast(Worth.PubSub, "worth:mcp", {:mcp_connected, server_name: :github})

# Subscriber (e.g., in UI process)
def handle_info({:mcp_connected, server_name: name}, state) do
  {:ok, update_mcp_status(state, name, :connected)}
end
```

Phoenix.PubSub is the standard Elixir solution for this. It's lightweight (no Phoenix dependency), handles process down cleanup automatically, and supports topic-based routing.

## Error Handling Conventions

Both agentic and recollect use `{:ok, value} | {:error, reason}` tuples. Worth follows the same convention and adds structure:

```elixir
defmodule Worth.Error do
  @type t :: %{
    __exception__: true,
    reason: atom(),
    message: String.t(),
    context: map()
  }

  defexception [:reason, :message, :context]

  def new(reason, message, context \\ %{}) do
    %__MODULE__{reason: reason, message: message, context: context}
  end
end
```

### Error Flow Pattern

```elixir
with {:ok, skill} <- Worth.Skills.Parser.parse(raw),
     {:ok, _} <- Worth.Skills.Validator.validate(skill),
     {:ok, _} <- Worth.Skills.Service.install(skill, workspace) do
  {:ok, skill}
else
  {:error, %Worth.Error{reason: :invalid_format} = e} ->
    Logger.warning("Skill parse failed: #{e.message}")
    {:error, e}

  {:error, %Worth.Error{reason: :trust_violation} = e} ->
    Logger.warning("Skill trust check failed: #{e.message}")
    {:error, e}

  {:error, reason} when is_atom(reason) ->
    {:error, Worth.Error.new(reason, inspect(reason))}
end
```

### Boundary Error Handling

At system boundaries (LLM calls, MCP calls, file I/O, HTTP), wrap in `try/rescue`:

```elixir
def execute_mcp_tool(client, name, args) do
  :telemetry.span([:worth, :mcp, :tool], %{server: client.server_name, tool: name}, fn ->
    result = try do
      Hermes.Client.Base.call_tool(client.pid, name, args)
    rescue
      e -> {:error, Worth.Error.new(:mcp_call_failed, Exception.message(e))}
    end

    {result, %{success: match?({:ok, _}, result)}}
  end)
end
```

This is the same pattern agentic and recollect use internally. Wrapping boundaries in try/rescue and converting exceptions to error tuples prevents crashes from propagating up the supervision tree.

## Configuration Strategy

### Runtime Config Resolution

The `{:env, "KEY"}` pattern in config.exs is resolved at application start. Worth adds a `Worth.Config` module:

```elixir
defmodule Worth.Config do
  use Agent

  def start_link(_opts) do
    initial = resolve_config(Application.get_all_env(:worth))
    Agent.start_link(fn -> initial end, name: __MODULE__)
  end

  def get(key, default \\ nil) do
    Agent.get(__MODULE__, &Map.get(&1, key, default))
  end

  defp resolve_config(config) do
    config
    |> resolve_env_values()
    |> validate!()
  end

  defp resolve_env_values(config) when is_map(config) do
    Map.new(config, fn {k, v} -> {k, resolve_env_values(v)} end)
  end

  defp resolve_env_values({:env, var}) do
    System.get_env(var) || raise "Missing env var: #{var}"
  end

  defp resolve_env_values(other), do: other

  defp validate!(config) do
    NimbleOptions.validate!(config, Worth.Config.Schema.schema())
    config
  end
end
```

### nimble_options for Validation

```elixir
defmodule Worth.Config.Schema do
  @schema NimbleOptions.new!(
    llm: [
      type: :keyword_list,
      required: true,
      keys: [
        default_provider: [type: :atom, required: true],
        providers: [type: :map, required: true]
      ]
    ],
    memory: [
      type: :keyword_list,
      default: [enabled: true, extraction: :llm, auto_flush: true, decay_days: 90]
    ],
    cost_limit: [type: :float, default: 5.0],
    max_turns: [type: :pos_integer, default: 50],
    mcp: [type: :keyword_list, default: [servers: %{}]],
    workspaces: [type: :keyword_list, default: [default: "personal", directory: "~/.worth/workspaces"]]
  )

  def schema, do: @schema
end
```

### Config for Workspace Overrides

Workspace config files (`mcp.json`, `skills.json`) use Jason for JSON parsing. Worth merges them at workspace activation time, not at app startup:

```elixir
defmodule Worth.Workspace.Config do
  def resolve(workspace_path) do
    global = Worth.Config.get(:mcp)

    workspace =
      workspace_path
      |> Path.join("mcp.json")
      |> File.read()
      |> case do
        {:ok, json} -> Jason.decode!(json)
        {:error, :enoent} -> %{}
      end

    merge_mcp_configs(global, workspace)
  end
end
```

## Library Additions

| Library | Purpose | Why |
|---------|---------|-----|
| `telemetry` | Event emission | Already a transitive dep (recollect). Worth emits its own events. |
| `telemetry_metrics` | Metrics aggregation | Standard Elixir metrics library. Powers cost/tokens/latency tracking. |
| `phoenix_pubsub` | Cross-component events | Lightweight (no Phoenix dependency). Process-down cleanup. Topic routing. |
| `nimble_options` | Config validation | Established pattern (used by LiveView, Oban, etc.). Compile-time schema. |
| `owl` | Rich CLI output | For `worth init`, `worth --help`, error messages outside the TUI. |
| `yamerl` | YAML parsing | Already a transitive dep (agentic uses yaml_elixir). For SKILL.md frontmatter. |

### Already Available (transitive)

| Library | Via | Used By |
|---------|-----|---------|
| `telemetry` | recollect | Recollect.Telemetry, agentic inline events |
| `jason` | recollect, hermes_mcp | JSON parsing everywhere |
| `req` | recollect | HTTP calls (LLM, embedding, GitHub) |
| `finch` | hermes_mcp | Streamable HTTP transport for MCP |
| `yaml_elixir` | agentic | Config parsing |
| `ecto_sql` + `postgrex` | recollect | Database |
| `pgvector` | recollect | Vector search |
| `peri` | hermes_mcp | JSON Schema validation (for MCP tool schemas) |

### Explicitly NOT Added

| Library | Why Not |
|---------|---------|
| `oban` | Overkill for v1. Background jobs handled by Task.Supervisor + Process.send_after. Add in Phase 7 if needed. |
| `broadway` | Overkill for v1. Codebase indexing uses Task.async_stream. Add when indexing becomes a bottleneck. |
| `redix` | No Redis. PostgreSQL handles all persistence. |
| `libcluster` | Single-node app. No distribution. |

## Graceful Shutdown

Worth must clean up on exit (Ctrl+C, SIGTERM, `/quit`):

```elixir
defmodule Worth.Application do
  def start(_type, _args) do
    Process.flag(:trap_exit, true)
    # ... start supervision tree
  end

  def stop(state) do
    Worth.Telemetry.stop_reporter()

    Worth.Memory.WorkingMemory.flush_all()
    Worth.Persistence.Transcript.close_current()

    :ok
  end
end
```

The `Process.flag(:trap_exit, true)` ensures the application process receives EXIT signals and can perform cleanup before the BEAM shuts down.

## Process Discovery

Worth uses `Worth.Registry` (Elixir Registry) for named process lookup instead of passing PIDs through function arguments. The Brain is registered per-workspace via `{:via, Registry, {Worth.Registry, {:brain, workspace}}}`.

For the Brain itself:

```elixir
# Any module can find the brain:
case Registry.lookup(Worth.Registry, Worth.Brain) do
  [{pid, _}] -> GenServer.call(pid, {:send_message, text})
  [] -> {:error, :brain_not_running}
end
```

## Concurrency Patterns

### Parallel Tool Execution

When the LLM requests multiple tool calls in one turn, execute them concurrently via Task.Supervisor:

```elixir
tool_calls
|> Task.async_stream(
  fn call ->
    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      Worth.Tools.execute(call.name, call.input)
    end)
  end,
  max_concurrency: 4,
  timeout: 30_000,
  on_timeout: :kill_task
)
|> Enum.map(fn {:ok, result} -> result end)
```

### Non-Blocking MCP Calls

MCP tool calls run in Task.Supervised tasks, not in the Brain GenServer process:

```elixir
# Brain GenServer delegates to Task.Supervisor:
def handle_call({:execute_tool, name, args}, from, state) do
  Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
    result = Worth.Mcp.Gateway.execute(name, args)
    GenServer.reply(from, result)
  end)

  {:noreply, state}
end
```

This keeps the Brain responsive while MCP servers respond (some take seconds).

### Debounced Telemetry for UI

The LiveView receives PubSub events from the Brain. Telemetry events fire on every text chunk. The LiveView processes them via `handle_info/2` and pushes diffs to the browser.

## Brain Architecture (Revised)

The Brain is no longer a single monolithic GenServer. It delegates:

```
Worth.Brain (GenServer)
├── Owns: current workspace, session state, agent loop reference
├── Delegates to:
│   ├── Worth.Memory.Manager (module, no process) → Recollect calls
│   ├── Worth.Memory.WorkingMemory (per-workspace GenServer) → ETS reads/writes
│   ├── Worth.Skills.Registry (module + :persistent_term) → metadata reads
│   ├── Worth.Mcp.Gateway (module + ETS) → tool routing
│   ├── Worth.LLM (module) → HTTP calls via Task.Supervisor
│   └── Worth.Workspace.Context (module) → system prompt assembly
└── Subscribes to:
    ├── Worth.PubSub "worth:mcp" → tool availability changes
    └── Worth.PubSub "worth:cost" → cost limit warnings
```

The Brain coordinates but doesn't own all the data. This is the key architectural change. The current docs imply the Brain holds everything in its state. In reality, most state lives in specialized stores (ETS, :persistent_term, PostgreSQL) and the Brain just orchestrates access.
