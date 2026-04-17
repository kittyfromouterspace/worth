# Brain Implementation

## Worth.Brain GenServer

The brain is a per-workspace GenServer that owns the agent loop. It is the integration point between the Phoenix LiveView web UI (events in, PubSub out) and agentic (execution).

```elixir
defmodule Worth.Brain do
  use GenServer

  defstruct [
    :ui_pid,
    :current_workspace,
    :workspace_path,
    :session_id,
    :history,
    :model_routes,
    :config,
    :cost_total,
    :status             # :idle | :running | :error
  ]
end
```

## Agentic Callbacks

The brain bridges Agentic's callback system to worth's subsystems:

```elixir
callbacks = %{
  llm_chat: fn params ->
    Worth.LLM.chat(params, brain.config)
  end,

  on_event: fn event, ctx ->
    Phoenix.PubSub.broadcast(Worth.PubSub, "worth:brain:#{ctx.workspace}", {:agent_event, event})
  end,

  # Global memory (unified model)
  knowledge_search: fn query, opts ->
    Recollect.search(query, Keyword.put(opts, :scope_id, "worth"))
  end,

  knowledge_create: fn params ->
    Recollect.remember(params.content, %{
      scope_id: "worth",
      content: params.content,
      entry_type: params[:entry_type] || "fact",
      metadata: Map.put(params[:metadata] || %{}, :workspace, brain.workspace_path)
    })
  end,

  knowledge_recent: fn _scope_id ->
    Recollect.Knowledge.recent("worth")
  end,

  get_tool_schema: fn name ->
    Worth.Tools.resolve_schema(name)
  end,

  execute_external_tool: fn name, args, ctx ->
    Worth.Tools.execute_external(name, args, ctx)
  end,

  get_secret: fn service, key ->
    Worth.Secrets.get(service, key)
  end,

  on_tool_approval: fn name, input, ctx ->
    Worth.Web.ApprovalHandler.request_approval(ctx.workspace, name, input)
  end,

  on_human_input: fn proposal, ctx ->
    Worth.Web.ApprovalHandler.request_human_input(ctx.workspace, proposal)
  end,

  on_persist_turn: fn ctx, text ->
    Worth.Persistence.append_turn(ctx.session_id, text)
  end,

  on_response_facts: fn ctx, text ->
    Worth.Memory.extract_facts(ctx, text)
  end,

  on_tool_facts: fn ws_id, name, result, turn ->
    Worth.Memory.extract_tool_facts(ws_id, name, result, turn)
  end
}
```

## System Prompt Assembly

The brain assembles the system prompt from global + overlay layers:

```
Priority order (highest to lowest):
1. Worth system prompt (core behavior, tool usage guidelines)          [global]
2. IDENTITY.md (workspace personality)                                     [overlay]
3. AGENTS.md (project-specific instructions)                                    [overlay]
4. Always-loaded skills (agent-tools, human-agency, tool-discovery)                [overlay]
5. On-demand skill listings (names only)                                        [overlay]
6. Memory context (from global Recollect search + ContextKeeper)                   [global + overlay boost]
7. Workspace snapshot (file tree, key files)                                [overlay]
```

Budget: 25% of context window for system prompt (min 32k chars). Memory/knowledge split: 60/40.

## LLM Provider Routing

Worth uses agentic's ModelRouter for smart model selection:

```elixir
routes = %{
  primary: [
    %{provider_name: "anthropic", model_id: "claude-sonnet-4-20250514", api_type: :anthropic_messages}
  ],
  lightweight: [
    %{provider_name: "anthropic", model_id: "claude-haiku-4-20250414", api_type: :anthropic_messages}
  ]
}
Agentic.ModelRouter.set_routes(:primary, routes.primary)
Agentic.ModelRouter.set_routes(:lightweight, routes.lightweight)
```

The Worth.LLM module wraps provider adapters (Anthropic, OpenAI, OpenRouter) and normalizes responses to agentic's expected format:

```elixir
%{
  "content" => [%{"type" => "text", "text" => "..."} | tool_use_blocks],
  "stop_reason" => "end_turn" | "tool_use" | "max_tokens",
  "usage" => %{"input_tokens" => N, "output_tokens" => N},
  "cost" => calculated_cost
}
```

## Event Flow

```
User types message in browser
    │
    ▼
Phoenix LiveView handle_event → Worth.Brain.send_message(text, workspace)
    │
    ▼
Worth.Brain (GenServer) → Agentic.run/1
    │
    │  Agentic emits events via :on_event callback:
    │  - {:text_chunk, "I'll read..."}
    │  - {:tool_call, %{name: "read_file", input: %{...}}}
    │  - {:tool_result, %{name: "read_file", output: "..."}}
    │  - {:thinking_chunk, "..."}
    │  - {:status, :idle | :running | :error}
    │  - {:done, %{text: "...", cost: 0.042, tokens: %{...}}}
    │
    ▼
Brain broadcasts to PubSub → ChatLive.handle_info({:agent_event, event})
    │
    ▼
LiveView updates assigns, Phoenix pushes diff to browser
```

The Brain and UI communicate via:
- **UI → Brain**: `GenServer.call(Worth.Brain.via(workspace), {:send_message, text})` (synchronous)
- **Brain → UI**: `Phoenix.PubSub.broadcast(Worth.PubSub, ...)` (async streaming via PubSub)
