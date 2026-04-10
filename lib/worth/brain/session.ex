defmodule Worth.Brain.Session do
  def resume(session_id, workspace_path, workspace, config) do
    callbacks = build_resume_callbacks(workspace, workspace_path, config)

    opts = [
      session_id: session_id,
      workspace: workspace_path,
      callbacks: callbacks,
      profile: :agentic,
      mode: :agentic,
      caller: self(),
      cost_limit: config[:cost_limit] || 5.0,
      transcript_backend: Worth.Persistence.Transcript
    ]

    AgentEx.resume(opts)
  end

  def list_sessions(workspace_path) do
    Worth.Persistence.Transcript.list_sessions(workspace_path, [])
  end

  defp build_resume_callbacks(workspace, workspace_path, config) do
    %{
      llm_chat: fn params ->
        Worth.LLM.chat(params, config)
      end,
      on_event: fn event, _ctx ->
        Phoenix.PubSub.broadcast(Worth.PubSub, "workspace:#{workspace}", {:agent_event, event})
        :ok
      end,
      on_tool_approval: fn _name, _input, _ctx -> :approved end,
      knowledge_search: fn query, opts ->
        Worth.Memory.Manager.search(query, Keyword.merge([workspace: workspace], opts))
      end,
      knowledge_create: fn params ->
        content = params[:content]
        Worth.Memory.Manager.remember(content, workspace: workspace, entry_type: params[:entry_type] || "fact")
      end,
      knowledge_recent: fn _scope_id ->
        Worth.Memory.Manager.recent(workspace: workspace)
      end,
      on_persist_turn: fn ctx, text ->
        Worth.Persistence.Transcript.append(
          ctx.session_id,
          %{role: "assistant", text: text},
          workspace_path
        )

        :ok
      end,
      on_response_facts: fn _ctx, _text -> :ok end,
      on_tool_facts: fn _ws_id, _name, _result, _turn -> :ok end,
      search_tools: fn query, _opts ->
        Worth.Tools.Router.all_definitions()
        |> Enum.filter(fn d ->
          name = d[:name] || d["name"] || ""
          desc = d[:description] || d["description"] || ""
          String.contains?(name, query) or String.contains?(String.downcase(desc), String.downcase(query))
        end)
        |> Enum.map(fn d -> d[:name] || d["name"] end)
      end,
      execute_external_tool: fn name, args, _ctx ->
        Worth.Tools.Router.execute(name, args, workspace)
      end,
      get_tool_schema: fn name ->
        case Worth.Tools.Router.get_schema(name) do
          nil -> {:error, :not_found}
          schema -> {:ok, schema}
        end
      end
    }
  end
end
