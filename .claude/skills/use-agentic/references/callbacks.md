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
