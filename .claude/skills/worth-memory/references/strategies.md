# Strategies

## Strategy Behaviour

Defined in `Agentic.Strategy`. Controls how the agent loop runs.

### Required Callbacks

| Callback | Signature | Description |
|----------|-----------|-------------|
| `id/0` | `() -> atom()` | Unique strategy identifier |
| `display_name/0` | `() -> String.t()` | Human-readable name |
| `description/0` | `() -> String.t()` | Short description |
| `init/1` | `(opts) -> {:ok, state} \| {:error, term}` | Strategy-specific setup |
| `prepare_run/2` | `(opts, state) -> {:ok, prepared_opts, new_state} \| {:error, term}` | Modify opts before each run |
| `handle_result/3` | `(result, opts, state) -> return` | Decide what to do after a run |

### `handle_result/3` Return Values

| Return | Meaning |
|--------|---------|
| `{:done, final_result, state}` | All done, return the result |
| `{:rerun, new_opts, state}` | Re-run with modified opts |
| `{:ok, state}` | Accept result, no further action |
| `{:error, reason}` | Error |

### Optional Callbacks

| Callback | Signature | Description |
|----------|-----------|-------------|
| `telemetry_tags/0` | `() -> [{atom, term}]` | Strategy-specific telemetry dimensions |

## Built-in Strategies

### `Agentic.Strategy.Default`

Identity strategy. Passes opts through unchanged. This is the default when no
strategy is specified. Matches the existing `Agentic.run/1` behavior exactly.

## Strategy Registry

Strategies are registered by their `id/0` callback via `Agentic.Strategy.Registry`.

```elixir
# Register a custom strategy
Agentic.Strategy.Registry.register(MyApp.CustomStrategy)

# Fetch by id
Agentic.Strategy.Registry.fetch(:my_strategy)  # => module or nil

# List all
Agentic.Strategy.Registry.all()  # => %{id => module}
```

The `:default` strategy is always pre-registered.

## Experiment Runner

`Agentic.Strategy.Experiment` provides head-to-head strategy comparison.

```elixir
experiment = %Agentic.Strategy.Experiment{
  strategies: [:default, :my_strategy],
  prompts: ["Refactor this module", "Fix this bug"],
  repetitions: 3,
  base_opts: [workspace: "/path", callbacks: callbacks]
}

results = Agentic.Strategy.Experiment.run(experiment)
comparison = Agentic.Strategy.Experiment.compare(results)
```

Comparison metrics per strategy: `success_rate`, `avg_duration_ms`, `avg_cost`, `avg_tokens`, `avg_tool_calls`.
