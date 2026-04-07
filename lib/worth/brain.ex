defmodule Worth.Brain do
  use GenServer

  defstruct [
    :ui_pid,
    :current_workspace,
    :workspace_path,
    :session_id,
    :history,
    :config,
    :cost_total,
    :status,
    :mode,
    :profile,
    :tool_permissions,
    :pending_approval,
    :active_tools
  ]

  @default_tool_permissions %{
    "bash" => :approve,
    "write_file" => :approve,
    "edit_file" => :auto,
    "read_file" => :auto,
    "list_files" => :auto,
    "skill_list" => :auto,
    "skill_read" => :auto,
    "memory_query" => :auto,
    "memory_write" => :auto,
    "memory_note" => :auto,
    "memory_recall" => :auto,
    "search_tools" => :auto,
    "use_tool" => :auto,
    "get_tool_schema" => :auto,
    "activate_tool" => :auto,
    "deactivate_tool" => :auto
  }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def send_message(text) do
    GenServer.call(__MODULE__, {:send_message, text}, :infinity)
  end

  def set_ui_pid(pid) do
    GenServer.call(__MODULE__, {:set_ui_pid, pid})
  end

  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  def approve_tool(tool_call_id) do
    GenServer.call(__MODULE__, {:approve_tool, tool_call_id})
  end

  def deny_tool(tool_call_id) do
    GenServer.call(__MODULE__, {:deny_tool, tool_call_id})
  end

  def switch_mode(mode) do
    GenServer.call(__MODULE__, {:switch_mode, mode})
  end

  def switch_workspace(name) do
    GenServer.call(__MODULE__, {:switch_workspace, name})
  end

  def resume_session(session_id) do
    GenServer.call(__MODULE__, {:resume_session, session_id})
  end

  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  def skill_history(name) do
    GenServer.call(__MODULE__, {:skill_history, name})
  end

  def skill_rollback(name, version) do
    GenServer.call(__MODULE__, {:skill_rollback, name, version})
  end

  def skill_refine(name) do
    GenServer.call(__MODULE__, {:skill_refine, name})
  end

  def mcp_connect(name, config) do
    Worth.Mcp.Broker.connect(name, config)
  end

  def mcp_disconnect(name) do
    Worth.Mcp.Broker.disconnect(name)
  end

  def mcp_list do
    Worth.Mcp.Broker.list_connections()
  end

  def mcp_tools(server_name) do
    Worth.Mcp.ToolIndex.tools_for_server(server_name)
  end

  @impl true
  def init(opts) do
    workspace = Keyword.get(opts, :workspace, "personal")
    mode = Keyword.get(opts, :mode, :code)

    state = %__MODULE__{
      ui_pid: Keyword.get(opts, :ui_pid),
      current_workspace: workspace,
      workspace_path:
        Keyword.get(opts, :workspace_path) ||
          Path.expand("~/.worth/workspaces/#{workspace}"),
      session_id: generate_session_id(),
      history: [],
      config: Worth.Config.get_all(),
      cost_total: 0.0,
      status: :idle,
      mode: mode,
      profile: mode_to_profile(mode),
      tool_permissions: @default_tool_permissions,
      pending_approval: nil,
      active_tools: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:set_ui_pid, pid}, _from, state) do
    {:reply, :ok, %{state | ui_pid: pid}}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      status: state.status,
      cost: state.cost_total,
      workspace: state.current_workspace,
      mode: state.mode,
      profile: state.profile,
      session_id: state.session_id,
      active_tools: state.active_tools
    }

    {:reply, status, state}
  end

  def handle_call({:send_message, text}, from, state) do
    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      result = execute_agent_loop(text, state)
      GenServer.reply(from, result)
    end)

    {:noreply, %{state | status: :running}}
  end

  def handle_call({:approve_tool, _tool_call_id}, _from, state) do
    {:reply, :ok, state}
  end

  def handle_call({:deny_tool, _tool_call_id}, _from, state) do
    {:reply, :denied, state}
  end

  def handle_call({:switch_mode, mode}, _from, state) do
    {:reply, :ok, %{state | mode: mode, profile: mode_to_profile(mode)}}
  end

  def handle_call({:switch_workspace, name}, _from, state) do
    if state.current_workspace != name do
      flush_working_memory(state.current_workspace)
    end

    path = Worth.Workspace.Service.resolve_path(name)
    new_state = %{state | current_workspace: name, workspace_path: path, history: [], session_id: generate_session_id()}
    {:reply, :ok, new_state}
  end

  def handle_call({:resume_session, session_id}, _from, state) do
    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      result = Worth.Brain.Session.resume(session_id, state.workspace_path, state.current_workspace, state.config)
      send(self(), {:agent_event, {:session_resumed, result}})
    end)

    {:reply, :ok, %{state | status: :running}}
  end

  def handle_call(:list_sessions, _from, state) do
    sessions = Worth.Brain.Session.list_sessions(state.workspace_path)
    {:reply, sessions, state}
  end

  def handle_call({:skill_history, name}, _from, state) do
    result = Worth.Skill.Versioner.list_versions(name)
    {:reply, result, state}
  end

  def handle_call({:skill_rollback, name, version}, _from, state) do
    result = Worth.Skill.Versioner.rollback(name, version)
    {:reply, result, state}
  end

  def handle_call({:skill_refine, name}, _from, state) do
    llm_fn = fn messages ->
      Worth.LLM.chat(%{messages: messages}, state.config)
    end

    result = Worth.Skill.Refiner.refine(name, llm_fn: llm_fn)
    {:reply, result, state}
  end

  @impl true
  def handle_info({:agent_event, event}, state) do
    if state.ui_pid do
      send(state.ui_pid, {:agent_event, event})
    end

    state =
      case event do
        {:cost, amount} ->
          new_cost = state.cost_total + amount
          limit = state.config[:cost_limit] || 5.0

          if new_cost > limit do
            if state.ui_pid,
              do:
                send(
                  state.ui_pid,
                  {:agent_event,
                   {:error, "Cost limit exceeded ($#{Float.round(new_cost, 3)} / $#{Float.round(limit, 3)})"}}
                )
          end

          %{state | cost_total: new_cost}

        {:status, status} ->
          %{state | status: status}

        {:done, %{cost: cost}} ->
          maybe_trigger_proactive_review(state)
          %{state | status: :idle, cost_total: state.cost_total + (cost || 0.0)}

        {:tool_call, %{name: name}} ->
          %{state | active_tools: state.active_tools ++ [name]}

        {:tool_result, %{name: name, success: false}} ->
          if String.starts_with?(name, "skill_") do
            maybe_trigger_refinement(name, state)
          end

          state

        _ ->
          state
      end

    {:noreply, state}
  end

  defp execute_agent_loop(text, state) do
    callbacks = build_callbacks(state)

    workspace_path =
      state.workspace_path ||
        Path.expand("~/.worth/workspaces/#{state.current_workspace}")

    try do
      context_opts = [workspace: state.current_workspace, user_message: text]

      system_prompt =
        case Worth.Workspace.Context.build_system_prompt(workspace_path, context_opts) do
          {:ok, prompt} when is_binary(prompt) and prompt != "" -> prompt
          _ -> nil
        end

      Worth.Memory.Manager.working_push(text,
        workspace: state.current_workspace,
        importance: 0.3,
        metadata: %{entry_type: "conversation_turn", role: "user"}
      )

      run_opts = [
        prompt: text,
        workspace: workspace_path,
        callbacks: callbacks,
        profile: state.profile,
        mode: mode_to_agent_mode(state.mode),
        session_id: state.session_id,
        caller: self(),
        cost_limit: state.config[:cost_limit] || 5.0,
        history: state.history,
        tool_permissions: state.tool_permissions
      ]

      run_opts = if system_prompt, do: Keyword.put(run_opts, :system_prompt, system_prompt), else: run_opts

      result = AgentEx.run(run_opts)

      case result do
        {:ok, response} ->
          store_outcome_feedback(response)
          {:ok, response}

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        {:error, Exception.message(e)}
    end
  end

  defp store_outcome_feedback(%{text: text}) when is_binary(text) and text != "" do
    Worth.Memory.Manager.outcome_good()
  end

  defp store_outcome_feedback(_), do: :ok

  defp build_callbacks(state) do
    ui_pid = state.ui_pid
    workspace = state.current_workspace
    workspace_path = state.workspace_path
    memory_opts = [workspace: workspace]

    %{
      llm_chat: fn params ->
        Worth.LLM.chat(params, state.config)
      end,
      on_event: fn event, _ctx ->
        send(self(), {:agent_event, event})
        if ui_pid, do: send(ui_pid, {:agent_event, event})
        :ok
      end,
      on_tool_approval: fn name, input, _ctx ->
        if ui_pid do
          send(ui_pid, {:agent_event, {:tool_approval_request, name, input}})
        end

        :approved
      end,
      knowledge_search: fn query, opts ->
        merged_opts = Keyword.merge(memory_opts, opts)
        Worth.Memory.Manager.search(query, merged_opts)
      end,
      knowledge_create: fn params ->
        content = params[:content] || params[:content]

        create_opts =
          Keyword.merge(memory_opts,
            entry_type: params[:entry_type] || "fact",
            source: params[:source] || "agent",
            metadata: Map.put(params[:metadata] || %{}, :workspace, workspace)
          )

        Worth.Memory.Manager.remember(content, create_opts)
      end,
      knowledge_recent: fn _scope_id ->
        Worth.Memory.Manager.recent(memory_opts)
      end,
      on_persist_turn: fn ctx, text ->
        Worth.Persistence.Transcript.append(
          ctx.session_id || state.session_id,
          %{role: "assistant", text: text},
          workspace_path
        )

        :ok
      end,
      on_response_facts: fn _ctx, text ->
        extraction_opts = [
          workspace: workspace,
          source_type: "response",
          llm_fn: fn messages ->
            Worth.LLM.chat(%{messages: messages}, state.config)
          end
        ]

        Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
          Worth.Memory.FactExtractor.extract_and_store(text, extraction_opts)
        end)

        :ok
      end,
      on_tool_facts: fn _ws_id, name, result, turn ->
        result_text = if is_binary(result), do: result, else: inspect(result)

        if String.length(result_text) > 20 do
          extraction_opts = [
            workspace: workspace,
            source_type: "tool:#{name}",
            turn: turn,
            llm_fn: fn messages ->
              Worth.LLM.chat(%{messages: messages}, state.config)
            end
          ]

          Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
            Worth.Memory.FactExtractor.extract_and_store(result_text, extraction_opts)
          end)
        end

        :ok
      end,
      search_tools: fn query, _opts ->
        memory = Worth.Tools.Memory.definitions()
        skills = Worth.Tools.Skills.definitions()
        mcp = Worth.Tools.Mcp.definitions()
        kits = Worth.Tools.Kits.definitions()

        (memory ++ skills ++ mcp ++ kits)
        |> Enum.filter(fn d ->
          String.contains?(d.name, query) or
            String.contains?(String.downcase(d.description), String.downcase(query))
        end)
        |> Enum.map(& &1.name)
      end,
      execute_external_tool: fn name, args, _ctx ->
        cond do
          String.starts_with?(name, "memory_") ->
            case Worth.Tools.Memory.execute(name, args, workspace) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, reason}
            end

          String.starts_with?(name, "skill_") ->
            case Worth.Tools.Skills.execute(name, args, workspace) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, reason}
            end

          String.starts_with?(name, "mcp_") ->
            case Worth.Tools.Mcp.execute(name, args, workspace) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, reason}
            end

          String.starts_with?(name, "kit_") ->
            case Worth.Tools.Kits.execute(name, args, workspace) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, reason}
            end

          String.contains?(name, ":") ->
            case Worth.Mcp.Gateway.execute(name, args) do
              {:ok, result} -> {:ok, result}
              {:error, reason} -> {:error, reason}
            end

          true ->
            {:error, "External tool '#{name}' not configured"}
        end
      end,
      get_tool_schema: fn name ->
        all_defs =
          Worth.Tools.Memory.definitions() ++
            Worth.Tools.Skills.definitions() ++
            Worth.Tools.Mcp.definitions() ++ Worth.Tools.Kits.definitions()

        definition =
          all_defs
          |> Enum.find(&(&1.name == name))

        cond do
          definition ->
            {:ok, definition}

          String.contains?(name, ":") ->
            case Worth.Mcp.ToolIndex.get_schema(name) do
              {:ok, schema} -> {:ok, schema}
              {:error, _} -> {:error, :not_found}
            end

          true ->
            {:error, :not_found}
        end
      end
    }
  end

  defp mode_to_profile(:code), do: :agentic
  defp mode_to_profile(:research), do: :conversational
  defp mode_to_profile(_), do: :agentic

  defp mode_to_agent_mode(:code), do: :agentic
  defp mode_to_agent_mode(:research), do: :conversational
  defp mode_to_agent_mode(:planned), do: :agentic_planned
  defp mode_to_agent_mode(:turn_by_turn), do: :turn_by_turn
  defp mode_to_agent_mode(_), do: :agentic

  defp generate_session_id do
    "worth-#{:rand.uniform(1_000_000) |> Integer.to_string() |> String.pad_leading(6, "0")}"
  end

  defp flush_working_memory(workspace) do
    try do
      Worth.Memory.Manager.working_flush(workspace: workspace)
    rescue
      _ -> :ok
    end
  end

  defp maybe_trigger_refinement(tool_name, state) do
    skill_name = tool_name |> String.replace_prefix("skill_", "")

    if Worth.Skill.Evaluator.should_refine?(skill_name) do
      llm_fn = fn messages ->
        Worth.LLM.chat(%{messages: messages}, state.config)
      end

      Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
        Worth.Skill.Refiner.refine(skill_name, llm_fn: llm_fn)
      end)
    end
  end

  defp maybe_trigger_proactive_review(state) do
    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      Worth.Skill.Registry.all()
      |> Enum.filter(&(&1.trust_level == :learned))
      |> Enum.each(fn skill ->
        case Worth.Skill.Refiner.proactive_review(skill.name) do
          {:ok, :review_needed, info} ->
            if state.ui_pid do
              send(
                state.ui_pid,
                {:agent_event,
                 {:system,
                  "Skill '#{skill.name}' may need review (#{info.success_rate}% success, #{info.usage_count} uses)"}}
              )
            end

          _ ->
            :ok
        end
      end)
    end)
  end
end
