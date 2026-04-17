# Orchestration Research: Strategy Enhancement

**Status:** PROPOSED
**Created:** 2026-04-14
**Source:** `docs/orchestration_reasearch.md` (nature-inspired coordination research)

A cross-repo plan for building a pluggable orchestration research framework into `agentic` and `worth`, enabling systematic experimentation with different multi-agent coordination approaches, with efficient local metrics storage in the Tauri desktop app for later analysis.

## Guiding Principle

**agentic owns the abstraction** (behaviour, registry, metrics, experiment runner). Orchestration is about how the agent loop coordinates — agentic's domain. It already owns profiles, stages, phases, and the context struct. Strategy is the natural layer above profile: a strategy *selects and configures* profiles, decides how multiple agent runs compose, and controls iteration flow.

**worth owns the implementations** — concrete strategies (Stigmergy, Holonic, etc.) that depend on Recollect, workspace context, and the tool router. The Brain dispatches to the active strategy per workspace but doesn't own the abstraction.

The split means orchestration approaches can be tested in agentic with mock callbacks, without Worth at all.

---

## Phase 0: Baseline Telemetry (agentic)

**Goal:** Start collecting per-turn metrics against the current system so we have data to compare against later. No behavior changes.

### Changes in `agentic`

#### 0a. Add strategy tag to Context

`lib/agentic/loop/context.ex` — add field:

```elixir
strategy: :default,  # atom identifying the active strategy
```

Populated in `Agentic.run/1` from a new optional `:strategy` key in opts (default `:default`). Included in all telemetry event metadata so downstream consumers can group by strategy.

#### 0b. Emit structured turn-level telemetry

Add a telemetry event inside `ModeRouter` (after each routing decision) and `ToolExecutor` (after each tool execution). These already emit some events, but we need consistent per-turn aggregates:

```elixir
:telemetry.execute(
  [:agentic, :orchestration, :turn],
  %{duration_ms: elapsed, tokens_in: n, tokens_out: n, tool_calls: n},
  %{strategy: ctx.strategy, mode: ctx.mode, phase: ctx.phase, stop_reason: reason}
)
```

Also emit `[:agentic, :orchestration, :tool_executed]` per tool call with name, duration, success/failure.

These events exist partially today via `[:agentic, :pipeline, :stage, :stop]` but aren't aggregated in a way that makes comparison easy. The new events are strategy-aware from day one.

#### 0c. Telemetry aggregation helper

New module `lib/agentic/telemetry/aggregator.ex` — a GenServer that attaches to the above events and maintains running aggregates per `(strategy, mode)`:

- `turn_count`, `total_duration_ms`, `total_tokens`, `total_cost`
- `tool_call_count`, `tool_success_count`
- `error_count`

Exposes `Aggregator.summary(strategy)` and `Aggregator.summary(strategy, mode)`. Used by the experiment runner later.

#### 0d. Session-level summary event

In `Agentic.run/1` (around line 186-201), add `strategy` to the existing `[:session, :stop]` event metadata. No new event needed — just ensure the tag is present.

### Deliverable
No user-visible change. `Aggregator.summary/1` returns baseline stats for `:default` strategy after any run.

---

## Phase 1: Strategy Abstraction (agentic)

**Goal:** Define the Strategy behaviour and integrate it into `Agentic.run/1` so strategies can control the agent loop without modifying engine internals.

### The Strategy Behaviour

New file: `lib/agentic/strategy.ex`

```elixir
defmodule Agentic.Strategy do
  @type state :: struct()
  @type ctx :: Agentic.Loop.Context.t()
  @type opts :: keyword()

  @doc "Unique atom identifier for this strategy"
  @callback id() :: atom()

  @doc "Human-readable name"
  @callback display_name() :: String.t()

  @doc "One-line description"
  @callback description() :: String.t()

  @doc "Initialize strategy state before the first turn. Receives the full run opts."
  @callback init(opts :: keyword()) :: {:ok, state()} | {:error, term()}

  @doc "Transform run opts before each Agentic.run call. Can modify profile, mode, callbacks, system prompt, tool permissions, etc."
  @callback prepare_run(opts :: keyword(), state :: state()) ::
    {:ok, prepared_opts :: keyword(), new_state :: state()} | {:error, term()}

  @doc "Called after each agent run completes. Can trigger follow-up runs, update state, or signal completion."
  @callback handle_result(
    result :: {:ok, map()} | {:error, term()},
    opts :: keyword(),
    state :: state()
  ) ::
    {:ok, new_state :: state()}
    | {:rerun, new_opts :: keyword(), new_state :: state()}
    | {:done, final_result :: map(), new_state :: state()}
    | {:error, term()}

  @doc "Called when the strategy's agent emits an event. Used for reactive adaptation."
  @callback handle_event(event :: tuple(), state :: state()) ::
    {:ok, new_state :: state()} | {:swap, strategy_id :: atom()} | :ignore

  @doc "Tags included in all telemetry events for this strategy."
  @callback telemetry_tags() :: [{atom(), term()}]

  @optional_callbacks [handle_event: 2, telemetry_tags: 0]
end
```

### Why these callbacks

| Callback | Maps to | Purpose |
|---|---|---|
| `init/1` | Before `Agentic.run/1` | Strategy-specific setup (e.g., initialize pheromone trails, seed population) |
| `prepare_run/2` | Inside `Agentic.run/1`, before building Context | Modify profile, mode, callbacks, system prompt, tool permissions |
| `handle_result/3` | After `Agentic.run/1` returns | Decide whether to run again (multi-turn orchestration), record strategy-specific outcomes |
| `handle_event/2` | Hooked into `Context.emit_event/2` | Reactive adaptation (e.g., deposit pheromone on tool use, detect holon formation) |
| `telemetry_tags/0` | In telemetry events | Strategy-specific dimensions for analysis |

### The Default Strategy

New file: `lib/agentic/strategy/default.ex`

```elixir
defmodule Agentic.Strategy.Default do
  @behaviour Agentic.Strategy

  @impl true
  def id(), do: :default
  def display_name(), do: "Default"
  def description(), do: "Passes opts through unchanged. Matches current Agentic.run behavior."

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def prepare_run(opts, _state), do: {:ok, opts, nil}

  @impl true
  def handle_result({:ok, result} = ok, _opts, _state), do: {:done, result, nil}
  def handle_result({:error, _} = err, _opts, _state), do: err

  @impl true
  def handle_event(_event, state), do: {:ok, state}
end
```

This is the identity strategy — it does nothing. The current `Agentic.run/1` behavior is preserved exactly when using `:default`.

### Integration into Agentic.run/1

Modify `Agentic.run/1` (`lib/agentic.ex`):

```elixir
def run(opts) do
  strategy_mod = resolve_strategy(opts)
  strategy_opts = Keyword.get(opts, :strategy_opts, [])

  case strategy_mod.init(strategy_opts) do
    {:ok, strategy_state} ->
      run_with_strategy(strategy_mod, strategy_state, opts)

    {:error, reason} ->
      {:error, {:strategy_init, reason}}
  end
end

defp run_with_strategy(mod, state, opts) do
  case mod.prepare_run(opts, state) do
    {:ok, prepared_opts, new_state} ->
      prepared_opts = Keyword.put(prepared_opts, :strategy, mod.id())

      case run_single(prepared_opts) do
        {:ok, result} ->
          handle_strategy_result(mod, {:ok, result}, prepared_opts, new_state)

        {:error, reason} ->
          mod.handle_result({:error, reason}, prepared_opts, new_state)
      end

    {:error, reason} ->
      {:error, {:strategy_prepare, reason}}
  end
end

defp handle_strategy_result(mod, result, opts, state) do
  case mod.handle_result(result, opts, state) do
    {:done, final_result, _final_state} ->
      {:ok, final_result}

    {:rerun, new_opts, new_state} ->
      run_with_strategy(mod, new_state, new_opts)

    {:ok, _new_state} ->
      {:ok, elem(result, 1)}

    {:error, reason} ->
      {:error, reason}
  end
end

defp resolve_strategy(opts) do
  case Keyword.get(opts, :strategy) do
    nil -> Agentic.Strategy.Default
    id when is_atom(id) -> Agentic.Strategy.Registry.fetch!(id)
    mod when is_atom(mod) -> mod  # can pass module directly
  end
end
```

The existing `Agentic.run/1` body becomes `run_single/1` (the same code, minus strategy wrapping). This keeps backward compatibility — callers who don't pass `:strategy` get the exact same behavior.

### Event Hook

In `Context.emit_event/2` (`lib/agentic/loop/context.ex`), after the existing event emission, check if a strategy module is available and call `handle_event/2`:

```elixir
def emit_event(%{strategy: strategy_id, strategy_module: mod, strategy_state: ss} = ctx, event) do
  # existing behavior
  if callback = ctx.callbacks[:on_event], do: callback.(event, ctx)
  send(ctx.caller, {:agentic_event, event})

  # strategy hook
  if mod do
    case mod.handle_event(event, ss) do
      {:ok, new_ss} -> %{ctx | strategy_state: new_ss}
      {:swap, new_id} -> swap_strategy(ctx, new_id)
      :ignore -> ctx
    end
  else
    ctx
  end
end
```

This requires adding `strategy_module` and `strategy_state` to the Context struct.

### Strategy Registry

New file: `lib/agentic/strategy/registry.ex`

```elixir
defmodule Agentic.Strategy.Registry do
  use Agent

  def start_link(_), do: Agent.start_link(fn -> %{default: Agentic.Strategy.Default} end, name: __MODULE__)

  def register(mod) when is_atom(mod) do
    Agent.update(__MODULE__, &Map.put(&1, mod.id(), mod))
  end

  def fetch(id), do: Agent.get(__MODULE__, &Map.get(&1, id))
  def fetch!(id), do: fetch(id) || raise "Strategy not registered: #{id}"
  def all(), do: Agent.get(__MODULE__, & &1)
end
```

Added to `Agentic.Application` supervision tree, before the protocol registry.

### File layout in agentic

```
lib/agentic/
  strategy.ex                    # behaviour definition
  strategy/
    registry.ex                  # process registry for strategies
    default.ex                   # identity strategy
    metrics.ex                   # telemetry helpers + aggregation
```

### Tests

- `test/agentic/strategy/default_test.exs` — verifies Default passes through unchanged
- `test/agentic/strategy/registry_test.exs` — register, fetch, all
- `test/agentic/strategy/integration_test.exs` — full `Agentic.run(strategy: :default)` matches `Agentic.run()` output

### Deliverable
`Agentic.run(strategy: :default, ...)` produces identical results to `Agentic.run(...)`. The abstraction is in place, no existing code breaks.

---

## Phase 2: Experiment Runner (agentic)

**Goal:** A module that can run the same prompt through multiple strategies, collect results, and compute comparison metrics.

### Experiment Definition

New file: `lib/agentic/strategy/experiment.ex`

```elixir
defmodule Agentic.Strategy.Experiment do
  defstruct [
    :id,                  # unique atom or UUID
    :name,                # human name
    :description,         # what's being tested
    :strategies,          # list of strategy ids or modules
    :prompts,             # list of prompt strings or {prompt, workspace} tuples
    :repetitions,         # how many times to run each (prompt, strategy) pair
    :base_opts,           # shared opts for all runs (callbacks, workspace, etc.)
    :results,             # accumulated results
    :status               # :pending | :running | :complete | :error
  ]

  def run(experiment) do
    results = for prompt <- experiment.prompts,
                  strategy <- experiment.strategies,
                  rep <- 1..experiment.repetitions do
      opts = experiment.base_opts
        |> Keyword.put(:prompt, prompt)
        |> Keyword.put(:strategy, strategy)

      start = System.monotonic_time(:millisecond)
      result = Agentic.run(opts)
      elapsed = System.monotonic_time(:millisecond) - start

      %{
        strategy: strategy,
        prompt: prompt,
        repetition: rep,
        result: result,
        duration_ms: elapsed
      }
    end

    %{experiment | results: results, status: :complete}
  end

  def compare(experiment) do
    for strategy <- experiment.strategies do
      strategy_results = Enum.filter(experiment.results, &(&1.strategy == strategy))
      successes = Enum.filter(strategy_results, fn r -> match?({:ok, _}, r.result) end)

      %{
        strategy: strategy,
        run_count: length(strategy_results),
        success_count: length(successes),
        success_rate: length(successes) / max(length(strategy_results), 1),
        avg_duration_ms: avg(strategy_results, & &1.duration_ms),
        avg_cost: avg(successes, fn r -> elem(r.result, 1).cost end),
        avg_tokens: avg(successes, fn r -> elem(r.result, 1).tokens end),
        avg_tool_calls: avg(successes, fn r -> elem(r.result, 1).steps end)
      }
    end
  end

  defp avg(list, extractor) when length(list) > 0 do
    list |> Enum.map(extractor) |> Enum.sum() |> Kernel./(length(list))
  end
  defp avg([], _), do: 0
end
```

### What This Enables

```elixir
experiment = %Experiment{
  id: :single_agent_comparison,
  name: "Default vs Stigmergy on task decomposition",
  strategies: [:default, :stigmergy],
  prompts: [
    "Refactor the auth module to use OAuth2",
    "Add pagination to the API endpoints",
    "Extract shared validation logic into a behaviour"
  ],
  repetitions: 3,
  base_opts: [workspace: "/tmp/test_workspace", callbacks: my_callbacks]
}

results = Experiment.run(experiment)
comparison = Experiment.compare(results)
```

### File layout addition

```
lib/agentic/strategy/
  experiment.ex            # experiment definition + runner + comparison
```

### Deliverable
Can run head-to-head strategy comparisons with statistical aggregation, entirely within agentic, using mock callbacks.

---

## Phase 3: Brain Integration (worth)

**Goal:** Wire the strategy system into Worth's Brain so strategies can be selected per workspace and switched at runtime.

### Changes to Brain State

`lib/worth/brain.ex` — add to struct:

```elixir
strategy: :default,              # current strategy id
strategy_state: nil,             # strategy-specific state
strategy_opts: []                # extra opts passed to strategy init
```

### Changes to execute_agent_loop/3

The key change. Currently (line 416-443):

```elixir
defp execute_agent_loop(text, state, brain_pid) do
  callbacks = build_callbacks(state, brain_pid)
  run_opts = build_run_opts(text, state, brain_pid, workspace_path, callbacks, system_prompt)
  Agentic.run(run_opts)
end
```

Becomes:

```elixir
defp execute_agent_loop(text, state, brain_pid) do
  callbacks = build_callbacks(state, brain_pid)
  base_opts = build_run_opts(text, state, brain_pid, workspace_path, callbacks, system_prompt)

  opts = base_opts
    |> Keyword.put(:strategy, state.strategy)
    |> Keyword.put(:strategy_opts, state.strategy_opts)

  Agentic.run(opts)
end
```

Everything else (build_callbacks, build_run_opts, system prompt assembly) stays the same. The strategy's `prepare_run/2` callback can override any of these opts if it wants to.

### Strategy Switching

New API on Brain:

```elixir
def switch_strategy(workspace, strategy_id, opts \\ []) do
  GenServer.call(via(workspace), {:switch_strategy, strategy_id, opts})
end
```

Handler:

```elixir
def handle_call({:switch_strategy, strategy_id, opts}, _from, state) do
  case Agentic.Strategy.Registry.fetch(strategy_id) do
    nil ->
      {:reply, {:error, :unknown_strategy}, state}

    mod ->
      case mod.init(opts) do
        {:ok, strategy_state} ->
          new_state = %{state |
            strategy: strategy_id,
            strategy_state: strategy_state,
            strategy_opts: opts
          }
          {:reply, :ok, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
  end
end
```

### CLI Flag

`lib/worth/cli.ex` — add `--strategy` flag:

```bash
mix run --no-halt -- --strategy stigmergy
```

Parsed alongside `--workspace` and `--mode`, passed to `Brain.switch_strategy/3` after boot.

### LiveView Command

`lib/worth/ui/commands.ex` — add `/strategy <name>` command. Dispatched to `Brain.switch_strategy/2`. The LiveView can display the active strategy in the status bar.

### Deliverable
Worth runs with any registered strategy. `/strategy default` switches back to baseline. No strategies beyond Default exist yet.

---

## Phase 4: Stigmergy Strategy (worth)

**Goal:** Implement the first research strategy using pheromone-based coordination via Recollect.

### Strategy Module

New file: `lib/worth/orchestration/strategies/stigmergy.ex`

```elixir
defmodule Worth.Orchestration.Strategies.Stigmergy do
  @behaviour Agentic.Strategy

  defstruct [
    :workspace,
    active_trails: [],
    deposited_pheromones: [],
    trail_decay: 0.95,
    max_trails: 10
  ]

  @impl true
  def id(), do: :stigmergy
  def display_name(), do: "Stigmergy (Ant Colony)"
  def description(), do: "Coordinates through environmental signals deposited in the knowledge store"

  @impl true
  def init(opts) do
    workspace = Keyword.fetch!(opts, :workspace)
    {:ok, %__MODULE__{workspace: workspace}}
  end

  @impl true
  def prepare_run(opts, state) do
    pheromones = fetch_pheromones(state.workspace, state.max_trails)

    system_prompt = Keyword.get(opts, :system_prompt, "")
    overlay = build_pheromone_overlay(pheromones)

    opts = opts
      |> Keyword.put(:system_prompt, system_prompt <> overlay)
      |> Keyword.put(:strategy_opts, [pheromone_context: pheromones])

    {:ok, opts, %{state | active_trails: pheromones}}
  end

  @impl true
  def handle_result({:ok, result}, opts, state) do
    pheromone = deposit_completion_pheromone(result, state.workspace)
    new_state = %{state |
      deposited_pheromones: [pheromone | state.deposited_pheromones] |> Enum.take(50)
    }
    {:done, result, new_state}
  end

  def handle_result({:error, reason}, _opts, state) do
    deposit_failure_pheromone(reason, state.workspace)
    {:error, reason}
  end

  @impl true
  def handle_event({:tool_call, %{name: name}}, state) do
    deposit_intention_pheromone(name, state.workspace)
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}

  # --- Private ---

  defp fetch_pheromones(workspace, limit) do
    Recollect.search("pheromone type:intention scope:#{workspace}",
      limit: limit,
      scope_id: "worth:stigmergy:#{workspace}"
    )
  end

  defp deposit_completion_pheromone(result, workspace) do
    Recollect.remember("pheromone completion: #{binary.part(result.text, 0, min(byte_size(result.text), 200))}", %{
      scope_id: "worth:stigmergy:#{workspace}",
      entry_type: "pheromone_completion",
      metadata: %{signal: :completion, cost: result.cost, workspace: workspace}
    })
  end

  defp deposit_failure_pheromone(reason, workspace) do
    Recollect.remember("pheromone failure: #{inspect(reason)}", %{
      scope_id: "worth:stigmergy:#{workspace}",
      entry_type: "pheromone_failure",
      metadata: %{signal: :failure, workspace: workspace}
    })
  end

  defp deposit_intention_pheromone(tool_name, workspace) do
    Recollect.remember("pheromone intention: #{tool_name}", %{
      scope_id: "worth:stigmergy:#{workspace}",
      entry_type: "pheromone_intention",
      metadata: %{signal: :intention, tool: tool_name, workspace: workspace}
    })
  end

  defp build_pheromone_overlay([]), do: ""
  defp build_pheromone_overlay(pheromones) do
    trails = Enum.map_join(pheromones, "\n", fn p ->
      "- #{p.metadata[:signal]}: #{p.content}"
    end)
    "\n\n## Active Pheromone Trails\nOther agents have left these coordination signals:\n#{trails}\nConsider these trails when choosing your approach."
  end
end
```

### Registration at Boot

In `Worth.Application`, after skill init:

```elixir
Agentic.Strategy.Registry.register(Worth.Orchestration.Strategies.Stigmergy)
```

### What This Tests

Stigmergy's hypothesis: *deposited environmental signals help the next agent turn converge faster on the right approach*. We can measure:

- Does the agent take fewer turns when pheromone trails are present?
- Does tool call sequencing change (more focused, less exploration)?
- Does cost go down because less backtracking?

Run the experiment:
```elixir
experiment = %Experiment{
  strategies: [:default, :stigmergy],
  prompts: standard_benchmark_prompts(),
  repetitions: 5,
  base_opts: [workspace: test_workspace, callbacks: test_callbacks]
}
```

### File layout in worth

```
lib/worth/orchestration/
  strategies/
    stigmergy.ex
```

### Deliverable
First research strategy, measurable against baseline. Real data on whether pheromone-based coordination helps.

---

## Phase 5: Additional Strategies (worth)

**Goal:** Implement the remaining strategies from the research doc, each as a self-contained module.

### 5a. Holonic Strategy

`lib/worth/orchestration/strategies/holonic.ex`

Recursive agent composition. The strategy configures `delegate_task` with specific subagent limits and captures holon formation events.

```elixir
defmodule Worth.Orchestration.Strategies.Holonic do
  @behaviour Agentic.Strategy

  defstruct [:workspace, holon_capacity: 3, active_holons: 0, holon_history: []]

  # Key idea: prepare_run injects a system prompt overlay that instructs
  # the agent to decompose work into holon-forming subtasks.
  # handle_event tracks holon formation when delegate_task is called.
  # handle_result checks holon success rates and adjusts capacity.
end
```

### 5b. Evolutionary Strategy

`lib/worth/orchestration/strategies/evolutionary.ex`

Maintains a population of solution candidates. Uses `{:rerun, opts, state}` return from `handle_result/3` to run multiple candidates.

```elixir
defmodule Worth.Orchestration.Strategies.Evolutionary do
  @behaviour Agentic.Strategy

  defstruct [
    :workspace,
    population_size: 5,
    generation: 0,
    max_generations: 3,
    population: [],
    current_candidate: 0
  ]

  # Key idea: init seeds the population with mutated prompt variants.
  # prepare_run selects a candidate and sets its prompt.
  # handle_result evaluates fitness, moves to next candidate.
  # After all candidates run, selects top N and mutates for next generation.
  # Returns {:rerun, opts, state} to continue, or {:done, best, state} when done.
end
```

### 5c. Swarm Strategy

`lib/worth/orchestration/strategies/swarm.ex`

Particle Swarm Optimization. Multiple concurrent agent runs adjust toward personal and neighborhood bests.

```elixir
defmodule Worth.Orchestration.Strategies.Swarm do
  @behaviour Agentic.Strategy

  defstruct [
    :workspace,
    particles: [],
    personal_bests: [],
    global_best: nil,
    inertia: 0.7,
    cognitive_weight: 1.5,
    social_weight: 1.5
  ]

  # Key idea: each "particle" is an agent run with slightly different
  # system prompt or tool permissions. Results update personal/global bests.
  # Prompt variations converge toward the global best over iterations.
end
```

### 5d. Ecosystem Strategy

`lib/worth/orchestration/strategies/ecosystem.ex`

Niche specialization with predator-prey error detection. Two agent roles: builder and critic.

```elixir
defmodule Worth.Orchestration.Strategies.Ecosystem do
  @behaviour Agentic.Strategy

  defstruct [
    :workspace,
    niches: [],
    carrying_capacity: 3,
    builder_results: [],
    predator_findings: []
  ]

  # Key idea: first run is "builder" (agentic profile).
  # handle_result triggers a "predator" run (conversational profile with
  # error-hunting system prompt) on the builder's output.
  # predator findings feed back into the next builder run's system prompt.
end
```

### Registration

All registered in `Worth.Application`:

```elixir
strategies = [
  Worth.Orchestration.Strategies.Stigmergy,
  Worth.Orchestration.Strategies.Holonic,
  Worth.Orchestration.Strategies.Evolutionary,
  Worth.Orchestration.Strategies.Swarm,
  Worth.Orchestration.Strategies.Ecosystem
]
Enum.each(strategies, &Agentic.Strategy.Registry.register/1)
```

### Deliverable
Five research strategies, all measurable against each other and against baseline via the experiment runner.

---

## Phase 6: Experiment Dashboard (worth)

**Goal:** UI for running experiments and comparing results in the LiveView.

### New LiveView Route

`/experiments` — lists experiments, their status, and comparison tables.

### Experiment Storage

Persist experiment definitions and results to PostgreSQL. Schema:

```elixir
create table(:orchestration_experiments) do
  add :name, :string, null: false
  add :description, :text
  add :strategies, {:array, :string}, null: false
  add :prompts, {:array, :text}, null: false
  add :repetitions, :integer, default: 1
  add :base_opts, :map
  add :results, :map
  add :comparison, :map
  add :status, :string, default: "pending"
  timestamps()
end
```

### LiveView Features

- Create experiment: pick strategies, enter prompts, set repetitions
- Run experiment: executes in background Task, streams progress
- Compare: table view of metrics per strategy, sparklines for trends
- History: all past experiments with sortable results

### CLI Support

```bash
mix worth --experiment "Stigmergy vs Default" --strategies default,stigmergy --prompts-file prompts.json
mix worth --compare <experiment_id>
```

### Deliverable
Full experiment lifecycle from creation to comparison, accessible via UI and CLI.

---

## Summary: Cross-Repo File Layout

### agentic (new files)

```
lib/agentic/
  strategy.ex                           # behaviour
  strategy/
    registry.ex                         # process registry
    default.ex                          # identity strategy
    experiment.ex                       # experiment runner + comparison
    metrics.ex                          # telemetry aggregation
test/agentic/strategy/
  default_test.exs
  registry_test.exs
  integration_test.exs
  experiment_test.exs
```

### worth (new files)

```
lib/worth/orchestration/
  strategies/
    stigmergy.ex
    holonic.ex
    evolutionary.ex
    swarm.ex
    ecosystem.ex
  experiment.ex                         # Worth-specific experiment config + persistence
  experiment_live.ex                    # LiveView for experiment dashboard
priv/repo/migrations/
  <timestamp>_create_orchestration_experiments.exs
```

### Modified files

| Repo | File | Change |
|---|---|---|
| agentic | `lib/agentic.ex` | Strategy wrapping around `run/1`, extract body to `run_single/1` |
| agentic | `lib/agentic/loop/context.ex` | Add `strategy`, `strategy_module`, `strategy_state` fields |
| agentic | `lib/agentic/loop/context.ex` | `emit_event/2` hooks into strategy `handle_event/2` |
| agentic | `lib/agentic/application.ex` | Add `Strategy.Registry` to supervision tree |
| agentic | `lib/agentic/loop/stages/mode_router.ex` | Add strategy-aware telemetry events |
| agentic | `lib/agentic/loop/stages/tool_executor.ex` | Add strategy-aware telemetry events |
| worth | `lib/worth/brain.ex` | Add strategy fields to struct, pass strategy to `Agentic.run`, `switch_strategy/3` |
| worth | `lib/worth/cli.ex` | `--strategy` flag |
| worth | `lib/worth/ui/commands.ex` | `/strategy` command |
| worth | `lib/worth/application.ex` | Register Worth strategies |

---

## Dependency Order

```
Phase 0 (telemetry) ──► Phase 1 (abstraction) ──► Phase 2 (experiment runner)
                                                        │
                                                        ▼
                                                 Phase 3 (brain integration)
                                                        │
                                                        ▼
                                                 Phase 4 (stigmergy) ──► Phase 5 (all strategies)
                                                        │
                                                        ▼
                                                 Phase 6 (dashboard)
```

Phases 0-2 are agentic only. Phase 3 is the bridge. Phases 4-6 are worth only. Each phase is independently mergeable and doesn't break existing behavior.

---

## Phase 7: Local Metrics Storage (Tauri)

**Goal:** Store orchestration metrics efficiently in the Tauri desktop app context — no active server component required — so that strategy effectiveness can be analyzed over time.

### Why This Needs Its Own Phase

Worth's desktop app bundles the BEAM VM inside Tauri. The Phoenix LiveView frontend loads via `localhost:4090`. Metrics must be written on every agent turn and tool call (high-frequency), then queried for analysis and comparison (low-frequency). This is a classic OLTP writes / OLAP reads pattern inside a desktop app.

### Storage Decision: SQLite with WAL Mode

Evaluated 6 options:

| Option | Fit | Why |
|---|---|---|
| **SQLite + WAL** | **9.5/10** | Full SQL aggregation, WAL mode for concurrent read/write, ~1MB binary overhead, industry standard for desktop apps |
| DuckDB | 7/10 | Superior analytics but C++ dependency complicates Tauri bundling, Windows build risk, overkill for single-user volumes |
| Arrow + Parquet | 5/10 | Best compression but immutable file format requires buffer/flush/compact lifecycle — too complex |
| JSONL files | 4/10 | Good for debug/export sidecar, no query capability as primary store |
| Sled / redb | 3/10 | Fast writes but KV model means building your own aggregation engine |
| Tauri plugin-store | 1/10 | Designed for preferences, not metrics — JSON serialization on every write |

**Why SQLite wins:** Every major desktop app (VS Code, Slack, Notion, Linear) uses SQLite for structured local data. For single-user volumes (thousands to tens of thousands of metric rows), SQLite with proper indexes handles aggregations in microseconds. WAL mode lets the LiveView frontend query while the agent is actively writing. The `.db` file is universally exportable (pandas, DuckDB, Jupyter) for later analysis.

### Where Metrics Live

Two parallel paths, both writing to the same SQLite database:

```
┌─────────────────────────────────────────────────────┐
│  Tauri Desktop App                                   │
│                                                      │
│  ┌──────────┐    telemetry events    ┌────────────┐  │
│  │ BEAM VM   │ ────(Rust TCP bridge)──>│ Rust       │  │
│  │ Agentic   │                        │ Metrics    │  │
│  │ Brain     │                        │ Writer     │  │
│  └──────────┘                         └─────┬──────┘  │
│                                              │         │
│                                       batch tx│WAL     │
│                                              ▼         │
│                                       ┌────────────┐  │
│                                       │ SQLite DB  │  │
│                                       │ ~/.worth/  │  │
│                                       │ metrics.db │  │
│                                       └─────┬──────┘  │
│                                              │         │
│  ┌──────────┐         SQL queries      ┌─────▼──────┐  │
│  │ LiveView  │ ◄─────────────────────── │ Tauri      │  │
│  │ Frontend  │                          │ Command    │  │
│  │           │ ◄── JSON result ──────── │ (query)    │  │
│  └──────────┘                          └────────────┘  │
└─────────────────────────────────────────────────────┘
```

The Rust side receives telemetry events from the BEAM VM via the existing TCP bridge (`rel/desktop/src-tauri/src/main.rs`), buffers them, and batch-writes to SQLite. The LiveView frontend queries via a Tauri command exposed through the webview's `window.__TAURI__` API.

### SQLite Schema

```sql
-- One row per agent session (maps to a single Agentic.run call)
CREATE TABLE session_metrics (
    id              INTEGER PRIMARY KEY,
    session_id      TEXT NOT NULL UNIQUE,
    run_id          TEXT,                           -- experiment run UUID (nullable = not part of an experiment)
    strategy        TEXT NOT NULL DEFAULT 'default',
    mode            TEXT NOT NULL,
    workspace       TEXT NOT NULL,
    started_at      TEXT NOT NULL,                  -- ISO 8601
    completed_at    TEXT,
    status          TEXT NOT NULL DEFAULT 'running', -- running | completed | failed | errored
    total_cost_usd  REAL DEFAULT 0,
    total_tokens_in  INTEGER DEFAULT 0,
    total_tokens_out INTEGER DEFAULT 0,
    total_turns     INTEGER DEFAULT 0,
    total_tool_calls INTEGER DEFAULT 0,
    prompt_hash     TEXT,                           -- SHA256 of prompt for grouping identical prompts
    model_id        TEXT                            -- resolved model used
);

-- One row per agent turn within a session
CREATE TABLE turn_metrics (
    id              INTEGER PRIMARY KEY,
    session_id      TEXT NOT NULL REFERENCES session_metrics(session_id),
    turn_number     INTEGER NOT NULL,
    started_at      TEXT NOT NULL,
    duration_ms     INTEGER,
    cost_usd        REAL DEFAULT 0,
    tokens_in       INTEGER DEFAULT 0,
    tokens_out      INTEGER DEFAULT 0,
    stop_reason     TEXT,                           -- end_turn | tool_use | max_tokens
    model_id        TEXT,
    phase           TEXT                            -- execute | plan | verify | review
);

-- One row per tool invocation
CREATE TABLE tool_call_metrics (
    id              INTEGER PRIMARY KEY,
    session_id      TEXT NOT NULL REFERENCES session_metrics(session_id),
    turn_number     INTEGER NOT NULL,
    tool_name       TEXT NOT NULL,
    called_at       TEXT NOT NULL,
    duration_ms     INTEGER,
    success         INTEGER NOT NULL DEFAULT 1,     -- 0/1
    error_type      TEXT,                           -- permission_denied | timeout | execution_error | circuit_open
    result_size_bytes INTEGER
);

-- Strategy-specific custom metrics (flexible key-value pairs)
CREATE TABLE strategy_metrics (
    id              INTEGER PRIMARY KEY,
    session_id      TEXT NOT NULL REFERENCES session_metrics(session_id),
    metric_key      TEXT NOT NULL,
    metric_value    REAL NOT NULL,
    recorded_at     TEXT NOT NULL,
    metadata        TEXT                            -- JSON blob for extra context
);

-- Indexes for common aggregation queries
CREATE INDEX idx_session_strategy_time ON session_metrics(strategy, started_at);
CREATE INDEX idx_session_run_id ON session_metrics(run_id);
CREATE INDEX idx_session_prompt_hash ON session_metrics(prompt_hash);
CREATE INDEX idx_turn_session ON turn_metrics(session_id);
CREATE INDEX idx_toolcall_session ON tool_call_metrics(session_id);
CREATE INDEX idx_toolcall_name ON tool_call_metrics(tool_name);
CREATE INDEX idx_strategy_metrics_key ON strategy_metrics(metric_key);
```

### Rust Metrics Writer

New file: `rel/desktop/src-tauri/src/metrics.rs`

```rust
use rusqlite::{Connection, params};
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::Manager;

pub struct MetricsDb(pub Mutex<Connection>);

impl MetricsDb {
    pub fn init(app_data_dir: &PathBuf) -> Result<Self, Box<dyn std::error::Error>> {
        let db_path = app_data_dir.join("metrics.db");
        let conn = Connection::open(&db_path)?;
        conn.execute_batch("
            PRAGMA journal_mode=WAL;
            PRAGMA synchronous=NORMAL;
            PRAGMA cache_size=-64000;  -- 64MB cache
        ")?;
        Self::run_migrations(&conn)?;
        Ok(Self(Mutex::new(conn)))
    }

    fn run_migrations(conn: &Connection) -> Result<(), rusqlite::Error> {
        conn.execute_batch(SCHEMA);  // the CREATE TABLE statements above
        Ok(())
    }
}

// Buffer metrics in a channel, flush every 50 events or 5 seconds
pub struct MetricsWriter {
    tx: std::sync::mpsc::Sender<MetricEvent>,
}

enum MetricEvent {
    SessionStart { session_id: String, strategy: String, mode: String, workspace: String },
    TurnComplete { session_id: String, turn_number: u32, duration_ms: u64, cost_usd: f64, tokens_in: u32, tokens_out: u32, stop_reason: String },
    ToolCall { session_id: String, turn_number: u32, tool_name: String, duration_ms: u64, success: bool, error_type: Option<String> },
    SessionComplete { session_id: String, total_cost_usd: f64, total_tokens: u64, total_turns: u32, status: String },
    Flush,
}

impl MetricsWriter {
    pub fn spawn(db: MetricsDb) -> Self {
        let (tx, rx) = std::sync::mpsc::channel::<MetricEvent>();
        std::thread::spawn(move || {
            let conn = db.0.lock().unwrap();
            let mut buffer = Vec::with_capacity(50);
            loop {
                match rx.recv_timeout(std::time::Duration::from_secs(5)) {
                    Ok(event) => {
                        buffer.push(event);
                        if buffer.len() >= 50 {
                            Self::flush(&conn, &mut buffer);
                        }
                    }
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                        Self::flush(&conn, &mut buffer);
                    }
                    Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                        Self::flush(&conn, &mut buffer);
                        break;
                    }
                }
            }
        });
        Self { tx }
    }

    fn flush(conn: &Connection, buffer: &mut Vec<MetricEvent>) {
        if buffer.is_empty() { return; }
        let tx = conn.unchecked_transaction().unwrap();
        for event in buffer.drain(..) {
            match event {
                MetricEvent::SessionStart { session_id, strategy, mode, workspace } => { /* INSERT */ }
                MetricEvent::TurnComplete { session_id, turn_number, duration_ms, cost_usd, tokens_in, tokens_out, stop_reason } => { /* INSERT */ }
                MetricEvent::ToolCall { session_id, turn_number, tool_name, duration_ms, success, error_type } => { /* INSERT */ }
                MetricEvent::SessionComplete { session_id, total_cost_usd, total_tokens, total_turns, status } => { /* UPDATE session_metrics */ }
                MetricEvent::Flush => {}
            }
        }
        tx.commit().unwrap();
    }
}
```

### Tauri Query Command

Expose a query interface to the LiveView frontend:

```rust
#[tauri::command]
fn query_metrics(
    db: tauri::State<'_, MetricsDb>,
    query_type: String,
    params: Option<serde_json::Value>,
) -> Result<serde_json::Value, String> {
    let conn = db.0.lock().map_err(|e| e.to_string())?;
    match query_type.as_str() {
        "strategy_comparison" => {
            // SELECT strategy, COUNT(*), AVG(total_cost_usd), ...
            // FROM session_metrics WHERE status='completed' GROUP BY strategy
        }
        "strategy_trend" => {
            // SELECT strategy, strftime('%Y-%m-%d', started_at) as day, AVG(total_cost_usd)
            // FROM session_metrics GROUP BY strategy, day ORDER BY day
        }
        "tool_analysis" => {
            // SELECT tool_name, COUNT(*), AVG(duration_ms),
            // SUM(CASE WHEN success=0 THEN 1 ELSE 0 END) as failures
            // FROM tool_call_metrics GROUP BY tool_name
        }
        "prompt_comparison" => {
            // For experiments: compare strategies on same prompt_hash
        }
        "recent_sessions" => {
            // Last N sessions with summary stats
        }
        _ => Err(format!("Unknown query type: {}", query_type)),
    }
}
```

### Elixir → Rust Bridge (Telemetry Forwarding)

The existing `Worth.Desktop.Bridge` (`lib/worth/desktop/bridge.ex`) already communicates with the Rust side via TCP. Add metric event forwarding:

```elixir
# In the :telemetry handler attached in Worth.Application
def handle_event([:agentic, :orchestration, :turn], measurements, metadata, _config) do
  if desktop_mode?() do
    Worth.Desktop.Bridge.send_metric(%{
      type: "turn_complete",
      session_id: metadata.session_id,
      strategy: metadata.strategy,
      duration_ms: measurements.duration_ms,
      cost_usd: measurements.cost,
      tokens_in: measurements.tokens_in,
      tokens_out: measurements.tokens_out
    })
  end
end
```

The Rust TCP listener (`src/lib.rs`) parses these frames and pushes them into the `MetricsWriter` channel.

### Alternative: Direct Elixir Writes

If the TCP bridge approach adds too much complexity, an alternative is to have the BEAM VM write directly to the same SQLite database using `exqlite` (Ecto's SQLite adapter, already used by Worth's main database). The `metrics.db` file lives at `~/.worth/metrics.db` alongside `worth.db`.

Pros: No Rust-side changes, uses existing Ecto infrastructure.
Cons: Two processes (BEAM + Rust) writing to the same SQLite file requires careful WAL configuration to avoid lock contention.

**Recommendation:** Start with the direct Elixir approach (simpler, uses existing infra). The `strategy_metrics` Ecto schema lives in Worth. If contention becomes an issue at scale, switch to the Rust-writer bridge.

### Analysis Queries (Examples)

```sql
-- Strategy effectiveness: cost, speed, success rate
SELECT strategy,
       COUNT(*) as runs,
       ROUND(AVG(total_cost_usd), 4) as avg_cost,
       ROUND(AVG(total_turns), 1) as avg_turns,
       ROUND(AVG(total_tokens_in + total_tokens_out), 0) as avg_tokens,
       ROUND(100.0 * SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) / COUNT(*), 1) as success_pct
FROM session_metrics
WHERE started_at > datetime('now', '-30 days')
GROUP BY strategy
ORDER BY avg_cost;

-- Same prompt, different strategies (experiment results)
SELECT prompt_hash,
       strategy,
       ROUND(AVG(total_cost_usd), 4) as avg_cost,
       ROUND(AVG(total_turns), 1) as avg_turns,
       COUNT(*) as n
FROM session_metrics
WHERE run_id IS NOT NULL
GROUP BY prompt_hash, strategy
ORDER BY prompt_hash, avg_cost;

-- Tool usage patterns by strategy
SELECT m.strategy,
       t.tool_name,
       COUNT(*) as calls,
       ROUND(AVG(t.duration_ms), 0) as avg_ms,
       ROUND(100.0 * SUM(CASE WHEN t.success=0 THEN 1 ELSE 0 END) / COUNT(*), 1) as failure_pct
FROM session_metrics m
JOIN tool_call_metrics t ON t.session_id = m.session_id
GROUP BY m.strategy, t.tool_name
ORDER BY m.strategy, calls DESC;

-- Strategy improvement over time (weekly)
SELECT strategy,
       strftime('%Y-W%W', started_at) as week,
       ROUND(AVG(total_cost_usd), 4) as avg_cost,
       ROUND(AVG(total_turns), 1) as avg_turns
FROM session_metrics
WHERE status = 'completed'
GROUP BY strategy, week
ORDER BY week;
```

### Export for External Analysis

SQLite files are directly readable by:
- **pandas**: `pd.read_sql("SELECT ...", sqlite3.connect("metrics.db"))`
- **DuckDB**: `duckdb.query("SELECT * FROM sqlite_scan('metrics.db', 'session_metrics')")`
- **Jupyter**: via either of the above
- **Observable / R / etc.**: universal SQLite support

This means the research workflow can be:
1. Run experiments in Worth (desktop app writes to `metrics.db`)
2. Open `metrics.db` in Jupyter/Python for statistical analysis
3. Visualize with matplotlib, Observable, or similar

### File Layout Additions

```
rel/desktop/src-tauri/src/
  metrics.rs                           # MetricsDb, MetricsWriter, Tauri commands
  main.rs                              # Modified: init MetricsDb, register command

lib/worth/metrics/
  schema.ex                            # Ecto schema for session_metrics, turn_metrics, etc.
  writer.ex                            # Telemetry handler that writes to SQLite
  queries.ex                           # Pre-built analysis queries for LiveView

priv/repo/migrations/
  <timestamp>_create_metrics_tables.exs

lib/worth_web/live/
  metrics_live.ex                      # LiveView for metrics dashboard / analysis
```

### Dependency Addition

`Cargo.toml`:
```toml
[dependencies]
rusqlite = { version = "0.31", features = ["bundled"] }
```

Adds ~1-1.5MB to the final binary.

### Deliverable

Metrics are written on every agent turn and tool call, queryable from the LiveView, and exportable to external analysis tools. Strategy comparisons are available in real-time during experiments.
