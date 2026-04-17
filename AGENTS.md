<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- agentic-start -->
## agentic usage
_A composable AI agent runtime_

# Rules for working with Agentic

Agentic is a composable AI agent runtime for Elixir (~> 1.19). Read the source
moduledocs and type specs before attempting to use its features. Do not assume
prior knowledge of the framework or its conventions.

## Critical Conventions

### String Keys Everywhere

All tool schemas, messages, content blocks, and LLM response maps use **string
keys** — not atoms. This is non-negotiable and consistent throughout the entire
chat pipeline.

```elixir
# CORRECT
%{"name" => "read_file", "input_schema" => %{"type" => "object"}}
%{"role" => "user", "content" => "hello"}

# WRONG
%{name: "read_file", input_schema: %{type: "object"}}
%{role: "user", content: "hello"}
```

### Tool Names Are Exact

Use the exact tool names defined in the codebase. Agents frequently hallucinate
tool names. The correct names are:

**File tools**: `read_file`, `write_file`, `edit_file`, `list_files`, `bash`
**Skills**: `skill_list`, `skill_read`, `skill_search`, `skill_info`, `skill_install`, `skill_remove`, `skill_analyze`
**Memory**: `memory_query`, `memory_write`, `memory_note`, `memory_recall`
**Gateway**: `search_tools`, `use_tool`, `get_tool_schema`, `activate_tool`, `deactivate_tool`
**Delegation**: `delegate_task`

There is NO tool called `file_read`, `glob`, `grep`, `task`, `skills_list`, `skills_apply`, or `gateway`.

## Entry Points

### `Agentic.run/1`

Primary entry point. Accepts keyword opts. Required keys: `:prompt`, `:workspace`, `:callbacks` (at minimum `:llm_chat`).

Returns `{:ok, %{text: string, cost: float, tokens: integer, steps: integer}}` or `{:error, reason}`.

### `Agentic.resume/1`

Resume a previous session from its transcript. Required keys: `:session_id`, `:workspace`, `:callbacks`.

### `Agentic.new_workspace/2`

Scaffold a workspace directory with default identity files.

## Profiles

Agentic provides eight built-in profiles. Use `:agentic` as the default unless
you have a specific reason to choose otherwise.

- `:agentic` — Full pipeline, tool use, progress tracking (default)
- `:agentic_planned` — Two-phase: plan then execute with verification
- `:turn_by_turn` — Human-in-the-loop review/execute
- `:conversational` — Call-respond only, no tools
- `:claude_code` — Claude Code CLI via local agent protocol
- `:opencode` — OpenCode CLI via local agent protocol
- `:codex` — Codex CLI via local agent protocol
- `:acp` — Agent Client Protocol (JSON-RPC 2.0 over stdio)

See `usage-rules/loop.md` for pipeline stage lists per profile.

## Phase State Machine

The loop does NOT use a step counter. `ModeRouter` decides loop/terminate/compact
based on the `(mode, phase, stop_reason)` triple. `max_turns` is a safety rail only.

All phase transitions MUST go through `Agentic.Loop.Phase.transition/2` — never
mutate `ctx.phase` directly. Use `transition!/2` in hot paths for compile-time
safety.

Valid phases: `:init`, `:plan`, `:execute`, `:review`, `:verify`, `:done`

See `usage-rules/loop.md` for the full transition map.

## Strategy Layer

Strategies control orchestration: they can modify opts before each run, decide
whether to re-run, and react to results. Implement `Agentic.Strategy` behaviour.

Built-in strategies:
- `:default` — Identity strategy, passes opts through unchanged

Register custom strategies via `Agentic.Strategy.Registry.register/1`.

See `usage-rules/strategies.md` for the full behaviour spec.

## Protocol System

Agent protocols abstract the communication backend (LLM API vs CLI subprocess vs ACP).
Implement `Agentic.AgentProtocol` for custom backends.

Transport types: `:llm`, `:local_agent`, `:acp`

See `usage-rules/protocols.md` for details.

## Callbacks

The `callbacks` map connects Agentic to your LLM provider and external systems.
Only `:llm_chat` is required. See `usage-rules/callbacks.md` for all signatures.

## Model Routing

Two modes:
- `:manual` (default) — caller picks a tier (`:primary`, `:lightweight`, `:any`), router resolves from catalog
- `:auto` — router analyses the request, determines complexity/capabilities, selects best model

Auto mode options: `:model_preference` (`:optimize_price` | `:optimize_speed`), `:model_filter` (`:free_only` | nil)

## Testing

Use `Agentic.TestHelpers` for test setup. See `usage-rules/testing.md`.

## Subtopics

- `usage-rules/loop.md` — Pipeline stages, profiles, context struct, phase machine
- `usage-rules/tools.md` — All tool names, schemas, extension modules
- `usage-rules/callbacks.md` — Complete callback reference
- `usage-rules/protocols.md` — AgentProtocol behaviour and built-in protocols
- `usage-rules/strategies.md` — Strategy behaviour and experiment runner
- `usage-rules/testing.md` — TestHelpers and mock utilities

<!-- agentic-end -->
<!-- agentic:callbacks-start -->
## agentic:callbacks usage
# Callbacks Reference

Callbacks are functions passed in the `callbacks` map to `Agentic.run/1` and
`Agentic.resume/1`. Only `:llm_chat` is required.

## Required

### `:llm_chat`

`(params) -> {:ok, response} | {:error, term}`

Called by `LLMCall` stage. `params` is a string-keyed map with:
- `"messages"` — conversation messages
- `"tools"` — tool definitions
- `"session_id"`, `"user_id"` — identity
- `"model_tier"` — requested tier as string
- `"_route"` — resolved route map (when ModelRouter is used)
- `"cache_control"` — `%{"stable_hash" => ..., "prefix_changed" => bool}`

Response shape: `{:ok, %Agentic.LLM.Response{}}` or `{:ok, response_map}`.
The response must include `stop_reason` (`:end_turn`, `:tool_use`, `:max_tokens`)
and `usage` (`%{input_tokens: _, output_tokens: _, cache_read: _, cache_write: _}`).

## Optional — Execution

### `:execute_tool`

`(name, input, ctx) -> {:ok, out} | {:ok, out, ctx} | {:error, term}`

Custom tool handler. Defaults to `Agentic.Tools.execute/3`. If your callback
returns `{:ok, output, updated_ctx}`, the updated context is threaded forward.

### `:transcript_backend`

Module implementing `Agentic.Persistence.Transcript`. Defaults to `Transcript.Local`.
Set this (or pass `:transcript_backend` opt) to enable session recording and resumption.

## Optional — Events

### `:on_event`

`(event, ctx) -> :ok`

Called for every telemetry-worthy event. Events are tuples like:
`{:tool_use, name, workspace_id}`, `{:turn_intermediate, tool_names, workspace_id}`,
`{:tool_trace, name, input, output, is_error, workspace_id}`,
`{:model_selected, %{model_id: _, provider_name: _, ...}}`, etc.

### `:on_response_facts`

`(ctx, text) -> :ok`

Called after each LLM response with extracted text. Used for custom fact extraction.

### `:on_tool_facts`

`(workspace_id, tool_name, result, turn) -> :ok`

Called after each tool execution with the result.

### `:on_persist_turn`

`(ctx, text) -> :ok`

Called when a turn produces final text (end_turn path).

## Optional — Knowledge Store

### `:knowledge_search`

`(query, opts) -> {:ok, entries} | {:error, term}`

Opts typically include `workspace_id:` and `user_id:`.

### `:knowledge_create`

`(params) -> {:ok, entry} | {:error, term}`

Params: `%{content:, entry_type:, source:, workspace_id:, user_id:, ...}`.

### `:knowledge_recent`

`(scope_id) -> {:ok, entries} | {:error, term}`

## Optional — Tool Gateway

### `:search_tools`

`(query, opts) -> [result]`

Returns list of tool discovery results.

### `:get_tool_schema`

`(name) -> {:ok, schema} | {:error, reason}`

Returns the full schema for an external tool.

### `:execute_external_tool`

`(name, args, ctx) -> {:ok, result} | {:error, reason}`

Executes an external tool via the tool gateway.

## Optional — Secrets

### `:get_secret`

`(service, key) -> {:ok, value} | {:error, reason}`

Resolves API keys or credentials.

## Optional — Human-in-the-Loop

### `:on_human_input`

`(proposal, ctx) -> {:approve, ctx} | {:approve, feedback, ctx} | {:abort, reason}`

Called by `HumanCheckpoint` stage in `:turn_by_turn` mode.
`proposal` is a map with `:thinking`, `:proposed_action`, `:tools_needed`, `:risks`.

### `:on_tool_approval`

`(name, input, ctx) -> :approved | {:approved_with_changes, new_input} | :denied`

Called when a tool has `:approve` permission in `ctx.tool_permissions`.

## Optional — Planning

### `:on_plan_created`

`(plan, ctx) -> {:ok, ctx} | {:revise, feedback, ctx}`

Called after plan parsing in `:agentic_planned` mode.

### `:on_step_complete`

`(step, result, ctx) -> :ok`

Called after each plan step is marked complete.

## Optional — Workspace

### `:on_workspace_snapshot`

`(workspace_path) -> {:ok, snapshot_string} | {:error, reason}`

Called by `WorkspaceSnapshot` stage. Return a custom snapshot string, or let
the stage auto-gather from git/files/instructions.

<!-- agentic:callbacks-end -->
<!-- agentic:loop-start -->
## agentic:loop usage
# Loop Pipeline

## Pipeline Architecture

Each stage wraps the next, receiving `ctx` and a `next` function. Stages can:
- Pass through: call `next.(ctx)`
- Short-circuit: return `{:done, result}`
- Transform: modify ctx before calling `next`
- Loop: call `next` multiple times

All stages implement `Agentic.Loop.Stage` behaviour with `call/2` and optional `model_tier/0`.

## Stage Modules

| Stage | Purpose |
|-------|---------|
| `Stages.ContextGuard` | Checks context window usage, triggers compaction, enforces cost limit |
| `Stages.ProgressInjector` | Injects system reminder after tool calls to prevent context drift |
| `Stages.LLMCall` | Makes LLM API call via callback, stores response in `ctx.last_response` |
| `Stages.ModeRouter` | Routes based on `(mode, phase, stop_reason)` — decides loop/terminate/compact |
| `Stages.TranscriptRecorder` | Records session events to transcript backend for resumption |
| `Stages.ToolExecutor` | Executes pending tool calls, re-enters pipeline |
| `Stages.CommitmentGate` | Intercepts unfulfilled commitments (e.g. "Let me analyze..." without tool use) |
| `Stages.PlanBuilder` | Injects structured plan-request prompt (agentic_planned only) |
| `Stages.PlanTracker` | Tracks plan step completion, transitions to :verify (agentic_planned only) |
| `Stages.VerifyPhase` | Injects verification prompt (agentic_planned only) |
| `Stages.WorkspaceSnapshot` | Gathers git/file/instruction context on first pass |
| `Stages.HumanCheckpoint` | Yields to human for approval (turn_by_turn only) |
| `Stages.CLIExecutor` | Executes via CLI protocol (claude_code/opencode/codex) |
| `Stages.ACPExecutor` | Executes via ACP protocol |

## Profile Stage Lists

### :agentic (default)
```
ContextGuard → ProgressInjector → LLMCall → ModeRouter → TranscriptRecorder → ToolExecutor → CommitmentGate
```

### :agentic_planned
```
WorkspaceSnapshot → ContextGuard → PlanBuilder → ProgressInjector → LLMCall → ModeRouter → TranscriptRecorder → ToolExecutor → PlanTracker → CommitmentGate
```

### :turn_by_turn
```
WorkspaceSnapshot → ContextGuard → LLMCall → ModeRouter → TranscriptRecorder → HumanCheckpoint → ToolExecutor → CommitmentGate
```

### :conversational
```
ContextGuard → LLMCall → ModeRouter → TranscriptRecorder
```

### :claude_code
```
ContextGuard → ProgressInjector → CLIExecutor → ModeRouter → TranscriptRecorder → ToolExecutor → CommitmentGate
```

### :opencode
Same stages as `:claude_code`.

### :codex
Same stages as `:claude_code`.

### :acp / {:acp, agent}
```
ContextGuard → ProgressInjector → ACPExecutor → ModeRouter → TranscriptRecorder → CommitmentGate
```

## Phase State Machine

### Mode Transitions

| Mode | From | Allowed Transitions |
|------|------|-------------------|
| `:agentic` | `:init` | `:execute` |
| `:agentic` | `:execute` | `:execute`, `:done` |
| `:agentic_planned` | `:init` | `:plan` |
| `:agentic_planned` | `:plan` | `:execute` |
| `:agentic_planned` | `:execute` | `:execute`, `:verify` |
| `:agentic_planned` | `:verify` | `:done` |
| `:turn_by_turn` | `:init` | `:review` |
| `:turn_by_turn` | `:review` | `:review`, `:execute` |
| `:turn_by_turn` | `:execute` | `:review`, `:done` |
| `:conversational` | `:init` | `:execute` |
| `:conversational` | `:execute` | `:done` |

### Initial Phases

- `:agentic` → `:execute`
- `:agentic_planned` → `:plan` (skipped to `:execute` if pre-built plan provided)
- `:turn_by_turn` → `:review`
- `:conversational` → `:execute`

## ModeRouter Routing Table

| Mode | Phase | Stop Reason | Action |
|------|-------|-------------|--------|
| `:agentic` | `:execute` | `end_turn` | Accumulate text → next (CommitmentGate) |
| `:agentic` | `:execute` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:agentic_planned` | `:plan` | `end_turn` | Parse plan → transition to `:execute` → reentry |
| `:agentic_planned` | `:execute` | `end_turn` | Accumulate text → next (CommitmentGate) |
| `:agentic_planned` | `:execute` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:agentic_planned` | `:verify` | `end_turn` | Accumulate verification → done |
| `:turn_by_turn` | `:review` | `end_turn` | Build proposal → next (HumanCheckpoint) |
| `:turn_by_turn` | `:review` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:turn_by_turn` | `:execute` | `end_turn` | Transition to `:review` → reentry |
| `:conversational` | `:execute` | `end_turn` | Accumulate text → done |
| any | any | `max_tokens` | Return what we have → done |

## Context Struct Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | `String.t \| nil` | Session identifier |
| `user_id` | `String.t \| nil` | User identifier |
| `caller` | `pid \| nil` | Pid to receive events |
| `profile` | `atom` | Profile name |
| `mode` | `atom` | Current mode |
| `phase` | `atom` | Current phase |
| `messages` | `[map]` | Conversation history (string-keyed) |
| `tools` | `[map]` | Active tool definitions |
| `core_tools` | `[map]` | Built-in tool definitions |
| `last_response` | `LLM.Response \| nil` | Most recent LLM response |
| `pending_tool_calls` | `[map]` | Tool calls awaiting execution |
| `accumulated_text` | `String.t` | Concatenated response text |
| `turns_used` | `non_neg_integer` | Turn counter |
| `total_cost` | `float` | Session cost in USD |
| `total_tokens` | `non_neg_integer` | Total tokens used |
| `plan` | `map \| nil` | Current plan (agentic_planned) |
| `config` | `map` | Profile config |
| `callbacks` | `map` | Callback functions |
| `metadata` | `map` | Workspace path, workspace_id, allowed_roots |
| `model_tier` | `atom` | `:primary`, `:lightweight`, `:any` |
| `model_selection_mode` | `atom` | `:manual` or `:auto` |
| `strategy` | `atom` | Strategy id |
| `reentry_pipeline` | `fun \| nil` | Cached pipeline for re-entry |
| `activation` | `map` | Tool activation state |
| `tool_permissions` | `map` | Per-tool permissions (`:auto`, `:approve`, `:deny`) |
| `subagent_depth` | `non_neg_integer` | Current subagent nesting depth |

## Profile Config Defaults

| Profile | max_turns | compaction_at_pct | progress_injection |
|---------|-----------|-------------------|-------------------|
| `:agentic` | 50 | 0.80 | `:system_reminder` |
| `:agentic_planned` | 100 | 0.80 | `:system_reminder` |
| `:turn_by_turn` | 200 | 0.80 | `:none` |
| `:conversational` | 100 | 0.80 | `:none` |
| CLI profiles | 50 | 0.80 | `:system_reminder` |

<!-- agentic:loop-end -->
<!-- agentic:protocols-start -->
## agentic:protocols usage
# Agent Protocols

## Transport Types

Defined in `Agentic.Protocol`:

- `:llm` — Stateless LLM API calls (OpenAI, Anthropic, etc.)
- `:local_agent` — Stateful CLI-based local agents (Claude Code, OpenCode, Codex)
- `:acp` — Agent Client Protocol (JSON-RPC 2.0 over stdio)

## AgentProtocol Behaviour

Defined in `Agentic.AgentProtocol`. Implement for custom backends.

### Required Callbacks

| Callback | Signature | Description |
|----------|-----------|-------------|
| `start/2` | `(backend_config, ctx) -> {:ok, session_id} \| {:error, term}` | Start a new session |
| `send/3` | `(session_id, messages, ctx) -> {:ok, response} \| {:error, term}` | Send messages, get response |
| `resume/3` | `(session_id, messages, ctx) -> {:ok, session_id, response} \| {:error, term}` | Resume existing session |
| `stop/1` | `(session_id) -> :ok \| {:error, term}` | Stop and cleanup session |
| `parse_stream/1` | `(chunk) -> {:message, map} \| :partial \| :eof \| {:error, term}` | Parse streaming chunk |
| `format_messages/2` | `(messages, ctx) -> iodata()` | Format messages for wire protocol |
| `transport_type/0` | `() -> transport_type()` | Return transport type |

### Optional Callbacks (with defaults)

| Callback | Default | Description |
|----------|---------|-------------|
| `estimate_cost/1` | `0.0` | Estimate cost for a response |
| `get_usage/1` | `nil` | Get current usage stats for a session |
| `available?/0` | `true` | Check if protocol is available |
| `stream_message/3` | `:ok` | Stream a chunk to the client |

### Protocol Response Shape

```elixir
%{
  content: String.t() | nil,
  tool_calls: [map()] | nil,
  usage: %{input: non_neg_integer(), output: non_neg_integer()} | nil,
  stop_reason: String.t() | nil,
  metadata: map() | nil
}
```

## Built-in Protocols

### `Agentic.Protocol.LLM`

Wraps existing callback-based LLM calls. Transport: `:llm`. Sessionless.

### `Agentic.Protocol.ClaudeCode`

Claude Code CLI via subprocess. Transport: `:local_agent`. Session-based.
Checks `System.find_executable("claude")` for availability.

CLI args: `-p --output-format stream-json --include-partial-messages --verbose --permission-mode bypassPermissions`

### `Agentic.Protocol.OpenCode`

OpenCode CLI via subprocess. Transport: `:local_agent`. Session-based.
Checks `System.find_executable("opencode")` for availability.

CLI args: `--mode agent`

### `Agentic.Protocol.Codex`

Codex CLI via subprocess. Transport: `:local_agent`. Session-based.
Checks `System.find_executable("codex")` for availability.

CLI args: `--json`

### `Agentic.Protocol.ACP`

Agent Client Protocol (JSON-RPC 2.0 over stdio). Transport: `:acp`. Session-based.
Used for `:acp` and `{:acp, agent_name}` profiles.

## Protocol Registry

Protocols are registered at application startup in `Agentic.Application`.
CLI protocols are only registered if their binary is found on the system.

ACP agents can be configured via:

```elixir
config :agentic,
  acp_agents: [
    [name: "my-agent", command: "my-agent-cli"]
  ]
```

## Errors

- `Agentic.Protocol.Error.NotFound` — Protocol not registered
- `Agentic.Protocol.Error.Unavailable` — CLI binary not found
- `Agentic.Protocol.Error.SessionError` — Session-level error

<!-- agentic:protocols-end -->
<!-- agentic:strategies-start -->
## agentic:strategies usage
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

<!-- agentic:strategies-end -->
<!-- agentic:testing-start -->
## agentic:testing usage
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

<!-- agentic:testing-end -->
<!-- agentic:tools-start -->
## agentic:tools usage
# Tools Reference

## File Tools

Defined in `Agentic.Tools`. All paths are relative to the workspace root.

### `read_file`

```json
{
  "name": "read_file",
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {"type": "string"},
      "offset": {"type": "integer", "description": "Starting line number (1-based)"},
      "limit": {"type": "integer", "description": "Number of lines to read"}
    },
    "required": ["path"]
  }
}
```

Returns file content with line numbers. Use `offset` and `limit` for large files.

### `write_file`

```json
{
  "name": "write_file",
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {"type": "string"},
      "content": {"type": "string"}
    },
    "required": ["path", "content"]
  }
}
```

Creates or overwrites a file. Parent directories are created automatically.

### `edit_file`

```json
{
  "name": "edit_file",
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {"type": "string"},
      "old_text": {"type": "string", "description": "Exact text to find and replace"},
      "new_text": {"type": "string", "description": "Replacement text"}
    },
    "required": ["path", "old_text", "new_text"]
  }
}
```

Surgical edit. `old_text` must match exactly (including whitespace). Errors if
`old_text` matches multiple locations — provide more context to make it unique.

### `list_files`

```json
{
  "name": "list_files",
  "input_schema": {
    "type": "object",
    "properties": {
      "pattern": {"type": "string", "description": "Glob pattern (default: '**/*')"}
    }
  }
}
```

Lists files matching a glob pattern. Searches all allowed roots.

### `bash`

```json
{
  "name": "bash",
  "input_schema": {
    "type": "object",
    "properties": {
      "command": {"type": "string"},
      "timeout": {"type": "integer", "description": "Timeout in seconds (default 60, max 300)"}
    },
    "required": ["command"]
  }
}
```

Executes shell commands in the workspace directory. Commands are sandboxed
via `Agentic.Sandbox.Runner`. Output truncated at 1MB.

## Delegation Tool

### `delegate_task`

Defined in `Agentic.Subagent.DelegateTask`.

```json
{
  "name": "delegate_task",
  "input_schema": {
    "type": "object",
    "properties": {
      "task": {"type": "string", "description": "Task description for the subagent"},
      "max_turns": {"type": "integer", "description": "Max turns (default 20, max 50)"}
    },
    "required": ["task"]
  }
}
```

Spawns a bounded subagent that runs `Agentic.run/1` with its own context.
Maximum nesting depth: 3. Subagent inherits workspace and callbacks.

## Skill Tools

Defined in `Agentic.Tools.Skill`.

| Tool | Required Input | Description |
|------|---------------|-------------|
| `skill_list` | (none) | Lists all installed skills |
| `skill_read` | `skill_name` | Reads full SKILL.md instructions |
| `skill_search` | `query` | Searches public registries |
| `skill_info` | `repo` | Fetches info before installing |
| `skill_install` | `repo` | Installs from GitHub (`owner/repo/skill-name`) |
| `skill_remove` | `skill_name` | Removes installed skill |
| `skill_analyze` | `skill_name` | Analyzes model tier requirements |

## Memory Tools

Defined in `Agentic.Tools.Memory`.

| Tool | Required Input | Description |
|------|---------------|-------------|
| `memory_query` | (none) | Searches knowledge store. Optional `query` and `entry_type` |
| `memory_write` | `content` | Persists to knowledge store. Optional `entry_type`, `summary` |
| `memory_note` | `key`, `value` | In-process working memory with optional `ttl` and `priority` |
| `memory_recall` | `query` | Searches in-process working memory |

## Tool Gateway

Defined in `Agentic.Tools.Gateway`.

| Tool | Required Input | Description |
|------|---------------|-------------|
| `search_tools` | `query` | Discovers external tools. Optional `category` filter |
| `use_tool` | `tool_name` | Executes external tool (MCP, OpenAPI). Optional `arguments` |
| `get_tool_schema` | `tool_name` | Gets full input schema for an external tool |
| `activate_tool` | `tool_name` | Promotes external tool to first-class (appears in tool list) |
| `deactivate_tool` | `tool_name` | Removes activated tool, frees budget slot |

### Tool Activation

External tools start as "discovered" (only accessible via `use_tool`). Activating
a tool promotes it to first-class status — it appears as a direct tool in the LLM
request. Budget-limited (default 10 slots). LRU eviction when exceeded.

State is in `ctx.activation`, not a separate process.

## Extension Modules

Tool execution dispatches to three extension modules in order:
1. `Agentic.Tools.Skill` — skill-related tools
2. `Agentic.Tools.Gateway` — tool discovery and external execution
3. `Agentic.Tools.Memory` — memory and knowledge store tools

If no extension handles the tool, falls back to core file tools and `delegate_task`.

<!-- agentic:tools-end -->
<!-- recollect-start -->
## recollect usage
_Pluggable memory engine with vector search, knowledge graphs, and LLM extraction. Supports PostgreSQL (pgvector), SQLite (sqlite-vec), and libSQL._

# Rules for working with Recollect

Recollect is a pluggable memory engine for Elixir applications (~> 1.17). It
provides three tiers: working memory (session-scoped), lightweight knowledge
(store-embed-search), and a full document pipeline (chunk, embed, extract,
graph). Read the source moduledocs and type specs before attempting to use its
features. Do not assume prior knowledge of the framework or its conventions.

## Critical Conventions

### No Top-Level Recollect Module

There is no `Recollect.remember/2` or `Recollect.search/2`. All public API
lives on submodules. Use the correct module paths:

```elixir
# CORRECT
Recollect.Knowledge.remember(content, opts)
Recollect.Search.search(query, opts)
Recollect.Search.ContextFormatter.format(context_pack)
Recollect.Pipeline.Ingester.ingest(title, content, opts)
Recollect.Pipeline.process(document, opts)
Recollect.Maintenance.Decay.run(opts)
Recollect.Maintenance.Reembed.run(opts)
Recollect.Consolidation.run(opts)
Recollect.Invalidation.invalidate(scope_id, pattern, opts)

# WRONG
Recollect.remember(content, opts)
Recollect.search(query, opts)
Recollect.build_context(results)
Recollect.ingest(title, content, opts)
Recollect.process(document)
Recollect.decay()
Recollect.reembed()
```

### Owner and Scope on Every Schema

All schemas carry both `owner_id` and `scope_id` (UUID columns). Your app
decides what they map to. `owner_id` is the user; `scope_id` is the
workspace/project. Pass them in opts, never hardcode.

### Tuple Returns

All API functions return `{:ok, result}` or `{:error, reason}` tuples. Never
raise on expected error paths. Pattern match on the return value.

### Embedding Providers

Only two providers exist. Do not invent others:

- `Recollect.Embedding.Local` — Default. Uses Bumblebee with
  `all-MiniLM-L6-v2` (384 dims). No API key needed.
- `Recollect.Embedding.OpenRouter` — API-based. Default model is
  `openai/text-embedding-3-small` (1536 dims).

There is no `Recollect.Embedding.OpenAI` or `Recollect.Embedding.Ollama`.

### Database Adapters

Three adapters exist. Configure via `config :recollect, :database_adapter`:

- `Recollect.DatabaseAdapter.Postgres` — Default. Requires pgvector.
- `Recollect.DatabaseAdapter.SQLiteVec` — SQLite3 + sqlite-vec.
- `Recollect.DatabaseAdapter.LibSQL` — libSQL with native vector support.

### Source Field Validation

Entry `source` field must be one of: `"agent"`, `"system"`, `"user"`.

### Entry Type Constants

Use these exact strings for `entry_type`:

`outcome`, `event`, `decision`, `observation`, `hypothesis`, `note`,
`session_summary`, `conversation_turn`, `preference`, `milestone`, `problem`,
`emotional`, `archived`

### Entity and Relation Types

Entity types: `concept`, `person`, `goal`, `obstacle`, `domain`, `strategy`,
`emotion`, `place`, `event`, `tool`

Relation types: `supports`, `blocks`, `causes`, `relates_to`, `part_of`,
`depends_on`, `precedes`, `contradicts`

Edge relation types: `leads_to`, `supports`, `contradicts`, `derived_from`,
`supersedes`, `related_to`

## Configuration

All config is via `config :recollect, ...` in the host application. Recollect
never starts its own Repo, never stores API keys, and never makes assumptions
about the host app's secret management.

Required: `:repo`. Everything else has defaults.

Embedding credentials use a `:credentials_fn` callback that returns a map or
`:disabled`. Never pass raw API keys as static config in production.

## Tier Quick Reference

- **Tier 0** (`Recollect.WorkingMemory`) — Session-scoped, no embeddings,
  importance-based eviction
- **Tier 1** (`Recollect.Pipeline`) — Document ingestion: chunk, embed,
  extract entities, graph
- **Tier 2** (`Recollect.Knowledge`) — Simple remember/forget/search with
  edges

## Subtopics

- `usage-rules/knowledge.md` — Knowledge API (Tier 2): remember, forget,
  connect, search, contradiction detection
- `usage-rules/pipeline.md` — Full pipeline (Tier 1): ingest, process,
  chunking, extraction
- `usage-rules/search.md` — Search, context formatting, LLM completion
- `usage-rules/embedding.md` — Embedding providers, dimensions, credentials
- `usage-rules/maintenance.md` — Decay, reembed, consolidation, invalidation
- `usage-rules/extension-points.md` — Behaviours: EmbeddingProvider,
  ExtractionProvider, GraphStore, DatabaseAdapter, Learner

<!-- recollect-end -->
<!-- recollect:embedding-start -->
## recollect:embedding usage
# Embedding

## Providers

### `Recollect.Embedding.Local` (default)

Uses Bumblebee with `sentence-transformers/all-MiniLM-L6-v2`. 384 dimensions.
No API key needed. Model weights downloaded from HuggingFace Hub on first use.

Requires `{:bumblebee, "~> 0.6.0"}` in deps. The `Nx.Serving` process is
started by `Recollect.Application` at boot.

Config:

```elixir
config :recollect, :local_embedding,
  model: "sentence-transformers/all-MiniLM-L6-v2",
  compile: [batch_size: 32, sequence_length: 128]
```

If Bumblebee is not installed, the provider returns `{:error, ...}` gracefully.

### `Recollect.Embedding.OpenRouter`

Uses OpenRouter's `/api/v1/embeddings` endpoint (OpenAI-compatible). Default
model: `openai/text-embedding-3-small` (1536 dimensions).

Config:

```elixir
config :recollect,
  embedding: [
    provider: Recollect.Embedding.OpenRouter,
    credentials_fn: fn ->
      %{
        api_key: System.get_env("OPENROUTER_API_KEY"),
        model: "openai/text-embedding-3-small",
        dimensions: 1536
      }
    end
  ]
```

## Credentials

API credentials are resolved at runtime via `:credentials_fn`. The function
returns a map with `:api_key` (required) and optional `:model`, `:dimensions`,
`:base_url`. Return `:disabled` if no credentials available.

Static config (`api_key: "..."`) works but is not recommended for production.

## Dimensions

Must be consistent across your entire deployment. Set via:
1. `:dimensions` in the credentials map
2. `:dimensions` in the embedding config
3. Provider default (384 for Local, 1536 for OpenRouter)

The migration generator `mix recollect.gen.migration --dimensions N` creates
tables with the specified vector size. This must match your embedding model.

<!-- recollect:embedding-end -->
<!-- recollect:extension-points-start -->
## recollect:extension-points usage
# Extension Points

## `Recollect.EmbeddingProvider`

Behaviour for embedding backends. Callbacks:

- `dimensions(opts)` — Number of embedding dimensions (required)
- `generate(texts, opts)` — Batch embed, returns `{:ok, [[float()]]}` (required)
- `embed(text, opts)` — Single embed, returns `{:ok, [float()]}` (optional)
- `model_id(opts)` — Model identifier for provenance (optional)

## `Recollect.ExtractionProvider`

Behaviour for entity/relation extraction. Callbacks:

- `extract(text, opts)` — Returns `{:ok, %{entities: [...], relations: [...]}}`

## `Recollect.GraphStore`

Behaviour for graph backends (default: `Recollect.Graph.PostgresGraph`).
Callbacks:

- `get_neighbors(owner_id, entity_id, hops)` — Returns `{:ok, [entity]}`
- `get_relations(owner_id, entity_id)` — Returns `{:ok, [relation]}`

## `Recollect.DatabaseAdapter`

Behaviour for database-specific implementations. Key callbacks:

- `vector_type(dimensions)` — SQL type for vector column
- `vector_ecto_type()` — Ecto type atom for embedding fields
- `format_embedding(list)` — Format embedding for insertion
- `vector_index_sql(table, column, opts)` — SQL for creating vector index
- `vector_distance_sql(column, query_ref)` — Cosine distance SQL
- `vector_similarity_sql(column, query_ref)` — Cosine similarity SQL
- `create_vector_extension_sql()` — SQL for vector extension (or nil)
- `uuid_type()` — `:binary_id` or `:uuid`
- `format_uuid(uuid)` — Format UUID for insertion
- `dialect()` — `:postgres | :sqlite | :libsql`
- `placeholder(n)` — `$1` or `?`
- `requires_pgvector?()` — Boolean
- `repo_adapter()` — Ecto adapter module
- `parse_embedding(data)` — DB format to list (optional)
- `top_k_sql(table, index, query, k)` — Approximate search (optional)
- `supports_recursive_ctes?()` — Boolean
- `supports_vector_index?()` — Boolean

## `Recollect.Learner`

Behaviour for learning sources. Callbacks:

- `source()` — Atom identifying the source
- `fetch_since(since, scope_id)` — Returns `{:ok, [events]}`
- `extract(event)` — Returns `{:ok, %{content:, entry_type:, ...}}` or `{:skip, reason}`
- `detect_patterns(events)` — Returns pattern list (can return `[]`)

Built-in learners: `Recollect.Learner.Git`, `Recollect.Learner.ClaudeCode`,
`Recollect.Learner.OpenCode`.

## Working Memory

`Recollect.WorkingMemory` is a GenServer-per-scope bounded buffer. No
behaviour to implement — it's used directly.

Config: `config :recollect, :working_memory, max_entries_per_scope: 20`

## Handoff

`Recollect.Handoff` stores session context in the `recollect_handoffs` table.
No behaviour — used directly.

## Export / Import

`Recollect.Export` and `Recollect.Import` handle JSONL portability. No
behaviour — used directly.

## Telemetry

All operations emit `:telemetry` events. Attach handlers to monitor:
`[:recollect, :remember, :start/:stop]`, `[:recollect, :search, :start/:stop]`,
`[:recollect, :pipeline, :start/:stop]`, `[:recollect, :embed, :stop]`,
`[:recollect, :decay, :stop]`, `[:recollect, :learning, :start/:stop]`,
`[:recollect, :consolidation, :stop]`, `[:recollect, :invalidation, :start/:stop]`,
`[:recollect, :completion, :start/:stop]`, `[:recollect, :handoff, ...]`,
`[:recollect, :mipmap, :generate, :stop]`.

All `:stop` events include `%{duration: native_time}`.

<!-- recollect:extension-points-end -->
<!-- recollect:knowledge-start -->
## recollect:knowledge usage
# Knowledge API (Tier 2)

## `Recollect.Knowledge.remember/2`

Store a knowledge entry with auto-embedding.

```elixir
{:ok, entry} = Recollect.Knowledge.remember(content,
  scope_id: scope_id,       # required
  owner_id: owner_id,       # required
  entry_type: "note",       # default: "note"
  auto_classify: false,     # LLM-free pattern matching
  tags: [],                 # list of strings
  summary: nil,             # optional summary
  source: "system",         # "agent" | "system" | "user"
  source_id: nil,           # external reference
  metadata: %{},            # arbitrary map
  confidence: 1.0,          # 0.0-1.0
  half_life_days: 7.0,      # decay rate
  pinned: false             # exempt from decay
)
```

`auto_classify: true` uses `Recollect.Classification.classify/2` (LLM-free
pattern matching) to detect the entry type automatically.

Context is auto-captured via `Recollect.Context.Detector.detect/0` unless
`context_hints` is provided in opts.

## `Recollect.Knowledge.forget/1`

Delete a knowledge entry by ID. Returns `{:ok, entry}` or `{:error, :not_found}`.

## `Recollect.Knowledge.connect/4`

Create an edge between two entries.

```elixir
{:ok, edge} = Recollect.Knowledge.connect(source_id, target_id, relation, weight: 1.0)
```

`relation` must be one of the edge relation types: `leads_to`, `supports`,
`contradicts`, `derived_from`, `supersedes`, `related_to`.

## `Recollect.Knowledge.recent/2`

Get recent entries for a scope.

```elixir
entries = Recollect.Knowledge.recent(scope_id, limit: 20)
```

## `Recollect.Knowledge.check_contradiction/3`

Check if content contradicts existing knowledge in a scope.

```elixir
:ok                                  # no conflicts
{:conflict, [%{existing: "...", type: :attribution_conflict, claim: ...}]}
{:conflict, [%{existing: "...", type: :status_conflict, claim: ...}]}
```

Uses `Recollect.Classification.extract_claims/1` to extract entity claims
and checks against entries with `confidence > 0.3`.

## `Recollect.Knowledge.supersede/4`

Demote old entries matching an entity+relation pattern by setting confidence
to 0.1.

```elixir
Recollect.Knowledge.supersede(scope_id, "webpack", "build tool", "vite")
```

## Memory Lifecycle Fields

Entries have several fields that drive the memory lifecycle:

- `confidence` (0.0-1.0) — Overall confidence, decayed by `half_life_days`
- `half_life_days` — Exponential decay rate. Default 7.0. Adjusted by
  `Recollect.SchemaFit` on creation.
- `access_count` / `last_accessed_at` — Bumped on retrieval via search
- `pinned` — If true, exempt from decay and consolidation removal
- `emotional_valence` — `"neutral"`, `"positive"`, `"negative"`, `"critical"`.
  Inferred via `Recollect.Valence.infer/1`.
- `schema_fit` (0.0-1.0) — How well content fits existing patterns.
  Computed by `Recollect.SchemaFit.compute/3`.
- `confidence_state` — `"active"`, `"stale"`, `"verified"`. Updated by
  outcome feedback.
- `outcome_score` — Set by `Recollect.Outcome.apply/2` feedback.

<!-- recollect:knowledge-end -->
<!-- recollect:maintenance-start -->
## recollect:maintenance usage
# Maintenance

## Decay

### `Recollect.Maintenance.Decay.run/1`

Archives stale entries. Entries not accessed in N days with fewer than M
accesses are archived (entry_type set to `"archived"`).

```elixir
{:ok, count} = Recollect.Maintenance.Decay.run(
  max_age_days: 90,     # default: 90
  min_access_count: 3   # default: 3
)
```

Pinned entries are never archived.

## Reembed

### `Recollect.Maintenance.Reembed.run/1`

Re-embed rows using the configured embedding provider. Tracks provenance via
`embedding_model_id`.

```elixir
{:ok, count} = Recollect.Maintenance.Reembed.run(
  batch_size: 100,       # default: 100
  concurrency: 2,        # default: 2
  tables: ["recollect_chunks", "recollect_entries", "recollect_entities"],
  scope: :nil_only       # :nil_only | :all | {:stale_model, "model_id"}
)
```

## Consolidation

### `Recollect.Consolidation.run/1`

Multi-pass consolidation cycle: decay -> merge overlapping -> detect conflicts
-> rebuild schema index -> persist.

```elixir
{:ok, result} = Recollect.Consolidation.run(
  scope_id: scope_id,          # required
  decay_threshold: 0.05,       # minimum strength to survive
  merge_threshold: 0.35,       # text overlap for merging
  min_cluster: 3,              # minimum entries to form a cluster
  dry_run: false               # preview without persisting
)
```

Returns `%{decayed: n, removed: n, merged: n, semantic_created: n,
conflicts_detected: n, duration_ms: n}`.

### `Recollect.Consolidation.dry_run/1`

Preview consolidation without persisting changes.

## Invalidation

### `Recollect.Invalidation.run_from_git/1`

Scans recent git commits for migration patterns and weakens related memories.

```elixir
{:ok, result} = Recollect.Invalidation.run_from_git(
  scope_id: scope_id,  # required
  days: 7              # default: 7
)
```

Detects patterns like "migrated from X to Y", "refactor: X -> Y",
"replaced X with Y", "BREAKING CHANGE:".

### `Recollect.Invalidation.invalidate/3`

Manually weaken memories matching a pattern.

```elixir
{:ok, result} = Recollect.Invalidation.invalidate(scope_id, "webpack",
  reason: "migrated to vite",
  replacement: "We now use Vite for bundling",
  weaken_factor: 0.1     # multiply half_life by this
)
```

## Outcome Feedback

### `Recollect.Outcome.good/1` and `Recollect.Outcome.bad/1`

Signal whether the last-retrieved entries were helpful. Adjusts `half_life_days`
and sets `confidence_state` to `"verified"`.

```elixir
Recollect.Outcome.good(scope_id)   # +5 days to half_life
Recollect.Outcome.bad(scope_id)    # -3 days to half_life
Recollect.Outcome.apply([id1, id2], :good)
```

Values are configurable via `config :recollect, :outcome_feedback,
positive_half_life_delta: 5, negative_half_life_delta: 3`.

<!-- recollect:maintenance-end -->
<!-- recollect:pipeline-start -->
## recollect:pipeline usage
# Full Pipeline (Tier 1)

## Ingest

### `Recollect.Pipeline.Ingester.ingest/3`

Ingest text content as a document with content-hash deduplication.

```elixir
{:ok, document} = Recollect.Pipeline.Ingester.ingest(title, content,
  owner_id: owner_id,           # required
  scope_id: scope_id,           # optional
  collection_name: "default",   # default: "default"
  source_type: "manual",        # "artifact" | "conversation" | "manual"
  source_id: nil,               # external ID for dedup
  metadata: %{}                 # arbitrary map
)
```

Returns:
- `{:ok, document}` — created or updated
- `{:ok, :unchanged}` — content hash matches existing (no re-processing)
- `{:error, reason}`

A `Recollect.Schema.Collection` is auto-created if it doesn't exist.

### Document Status Lifecycle

`pending` -> `processing` -> `ready` | `failed`

If re-ingested with changed content, status resets to `pending`.

## Process

### `Recollect.Pipeline.process/2`

Run the full pipeline synchronously on a document.

```elixir
{:ok, run} = Recollect.Pipeline.process(document, opts)
```

Pipeline stages: chunk -> embed chunks -> extract entities/relations ->
embed entities -> complete.

Returns `{:ok, pipeline_run}` with `run.status` and `run.step_details`.

### `Recollect.Pipeline.process_async/2`

Fire-and-forget. Delegates to `Recollect.Pipeline.process/2` via the
configured `TaskSupervisor`.

## Chunking

The `Recollect.Pipeline.Chunker` splits content into markdown-aware chunks
preserving section hierarchy and paragraph boundaries. Chunks are created as
`Recollect.Schema.Chunk` records with sequence numbers, token counts, and
heading context in metadata.

On re-processing, existing chunks are deleted before creating new ones.

## Extraction

The `Recollect.Pipeline.Extractor` uses the configured
`Recollect.ExtractionProvider` (default: `Recollect.Extraction.LlmJson`) to
extract entities and relations from each chunk.

Entities are persisted as `Recollect.Schema.Entity` records. Relations are
persisted as `Recollect.Schema.Relation` records. Entity embedding is done
asynchronously after extraction.

Extraction failure for a single chunk logs a warning and continues — it does
not fail the entire pipeline.

<!-- recollect:pipeline-end -->
<!-- recollect:search-start -->
## recollect:search usage
# Search

## `Recollect.Search.search/2`

Hybrid search combining vector similarity and graph traversal.

```elixir
{:ok, context_pack} = Recollect.Search.search(query, opts)
```

Options:
- `:tier` — `:both` (default), `:full` (Tier 1 only), `:lightweight` (Tier 2 only)
- `:hops` — Graph expansion depth (default: `1`)
- `:limit` — Max results (default varies by implementation)
- `:owner_id` — Owner UUID (required for graph expansion)
- `:scope_id` — Scope UUID
- `:filters` — Map with `entry_type`, `temporal` (`:recent` = last 30 days), `confidence_min`

Returns a context pack map:

```elixir
%{
  chunks: [...],          # Tier 1 chunk results with similarity scores
  entries: [...],         # Tier 2 entry results with similarity scores
  related_entries: [...],  # Entries found via edge traversal
  entities: [...],        # Extracted entities from knowledge graph
  relations: [...],       # Graph relations between entities
  query: "..."
}
```

Each result is a map with string keys: `id`, `content`, `score`, `entry_type`,
etc.

## `Recollect.Search.ContextFormatter.format/1`

Format a context pack into readable text for LLM system prompt injection.

```elixir
context_text = Recollect.Search.ContextFormatter.format(context_pack)
```

Produces sections: `## Relevant Memory Chunks`, `## Relevant Knowledge`,
`## Related Knowledge`, `## Known Entities`, `## Known Relationships`.

Returns an empty string if the context pack has no results.

## `Recollect.Search.Completion.complete/2`

LLM-augmented retrieval that combines search with LLM reasoning.

```elixir
{:ok, %{answer: answer, context: context_pack}} =
  Recollect.Search.Completion.complete(question,
    owner_id: user_id,
    scope_id: scope_id,
    llm_fn: fn messages -> {:ok, "answer"} end,
    system_prompt: nil,   # optional override
    limit: 10,
    hops: 2               # overrides default 1
  )
```

`llm_fn` is required. Recollect never calls LLMs directly for completion.

<!-- recollect:search-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
