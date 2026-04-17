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
