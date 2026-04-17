# Testing

## TestHelpers

Defined in `test/support/test_helpers.ex`. Included via `elixirc_paths(:test)` in `mix.exs`.

### `mock_callbacks/1`

Builds a callbacks map with default mock LLM and tool responses. Pass overrides to customize.

```elixir
# Default: end_turn response + mock tool execution
callbacks = Agentic.TestHelpers.mock_callbacks()

# Override LLM to return tool_use
callbacks = Agentic.TestHelpers.mock_callbacks(
  llm_chat: &Agentic.TestHelpers.mock_llm_tool_use/1
)

# Override with custom LLM
callbacks = Agentic.TestHelpers.mock_callbacks(
  llm_chat: fn params -> {:ok, my_response} end
)
```

### `build_ctx/1`

Creates a minimal `Agentic.Loop.Context` with sensible defaults and activated tools.

```elixir
ctx = Agentic.TestHelpers.build_ctx()

# With overrides
ctx = Agentic.TestHelpers.build_ctx(
  mode: :agentic_planned,
  phase: :plan,
  metadata: %{workspace: "/my/project", workspace_id: "my-ws"}
)
```

Defaults:
- `session_id`: `"test-session"`
- `caller`: `self()`
- `metadata`: `%{workspace: "/tmp/test", workspace_id: "ws-test"}`
- `messages`: `[%{"role" => "system", "content" => "You are a test agent."}]`
- `callbacks`: result of `mock_callbacks()`
- Tool activation initialized via `Agentic.Tools.Activation.init/1`

### `build_planned_ctx/1`

Shortcut for `build_ctx` with `mode: :agentic_planned, phase: :plan`.

### `build_turn_by_turn_ctx/1`

Shortcut for `build_ctx` with `mode: :turn_by_turn, phase: :review` and a mock
`on_human_input` callback that auto-approves.

### `create_test_workspace/0`

Creates a temp directory and registers cleanup via `on_exit`.

```elixir
workspace = Agentic.TestHelpers.create_test_workspace()
# workspace is cleaned up automatically after the test
```

### Mock LLM Functions

| Function | Description |
|----------|-------------|
| `mock_llm_end_turn/1` | Returns `%LLM.Response{stop_reason: :end_turn}` with text |
| `mock_llm_tool_use/1` | Returns `%LLM.Response{stop_reason: :tool_use}` calling `read_file` |
| `mock_llm_plan_response/1` | Takes step list, returns end_turn with plan text |

### `mock_human_callback/1`

Creates a mock `on_human_input` callback that returns a sequence of responses.

```elixir
# Auto-approve all
callback = Agentic.TestHelpers.mock_human_callback([{:approve, "ok"}])

# Approve with feedback then approve
callback = Agentic.TestHelpers.mock_human_callback([
  {:approve, "Looks good", "ctx"},
  {:approve, "ok"}
])

# Abort after two approvals
callback = Agentic.TestHelpers.mock_human_callback([
  {:approve, "ok"},
  {:approve, "ok"},
  {:abort, "stopping"}
])
```

### `mock_tool_execute/3`

Default mock tool handler. Returns `"Mock result from #{name}"`.

## Running Tests

```bash
mix test                                          # all tests
mix test test/agentic/loop/engine_test.exs        # single file
mix test test/agentic/loop/engine_test.exs:42     # single test by line
```

`mix test` is aliased to run `ecto.create --quiet` + `ecto.migrate --quiet` before tests.
No Ecto Repo module exists yet, so these are no-ops.
