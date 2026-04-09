defmodule Worth.Brain do
  use GenServer
  require Logger

  defstruct [
    :ui_pid,
    :current_workspace,
    :workspace_path,
    :session_id,
    :history,
    :config,
    :status,
    :mode,
    :profile,
    :tool_permissions,
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

  def skill_promote(name) do
    GenServer.call(__MODULE__, {:skill_promote, name})
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

  def list_coding_agents do
    Worth.CodingAgents.discover()
  end

  def switch_to_coding_agent(protocol) do
    GenServer.call(__MODULE__, {:switch_to_coding_agent, protocol})
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
          Worth.Workspace.Service.resolve_path(workspace),
      session_id: generate_session_id(),
      history: [],
      config: Worth.Config.get_all(),
      status: :idle,
      mode: mode,
      profile: mode_to_profile(mode),
      tool_permissions: @default_tool_permissions,
      active_tools: []
    }

    tiers = Worth.Workspace.Identity.tier_overrides(state.workspace_path)
    AgentEx.ModelRouter.set_tier_overrides(tiers)

    {:ok, state}
  end

  @impl true
  def handle_call({:set_ui_pid, pid}, _from, state) do
    {:reply, :ok, %{state | ui_pid: pid}}
  end

  def handle_call(:get_status, _from, state) do
    status = %{
      status: state.status,
      cost: Worth.Metrics.session_cost(),
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

  def handle_call({:switch_mode, mode}, _from, state) do
    {:reply, :ok, %{state | mode: mode, profile: mode_to_profile(mode)}}
  end

  def handle_call({:switch_to_coding_agent, protocol}, _from, state) do
    profile = Worth.CodingAgents.profile_for(protocol)

    cond do
      profile == nil ->
        {:reply, {:error, :unknown_protocol}, state}

      not Worth.CodingAgents.available?(protocol) ->
        {:reply, {:error, :not_available}, state}

      true ->
        new_state = %{state | profile: profile, mode: :coding_agent}
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:switch_workspace, name}, _from, state) do
    if state.current_workspace != name do
      flush_working_memory(state.current_workspace)
    end

    path = Worth.Workspace.Service.resolve_path(name)
    new_state = %{state | current_workspace: name, workspace_path: path, history: [], session_id: generate_session_id()}

    tiers = Worth.Workspace.Identity.tier_overrides(path)
    AgentEx.ModelRouter.set_tier_overrides(tiers)
    Worth.Metrics.reset()

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
      Worth.LLM.chat_tier(%{messages: messages}, :lightweight, state.config)
    end

    result = Worth.Skill.Refiner.refine(name, llm_fn: llm_fn)
    {:reply, result, state}
  end

  def handle_call({:skill_promote, name}, _from, state) do
    result = Worth.Skill.Lifecycle.promote(name)

    case result do
      {:ok, :needs_user_approval, target} ->
        case Worth.Skill.Lifecycle.execute_promotion(name, target) do
          {:ok, _} = success -> {:reply, success, state}
          error -> {:reply, error, state}
        end

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:agent_event, event}, state) do
    if state.ui_pid do
      send(state.ui_pid, {:agent_event, event})
    end

    state =
      case event do
        {:status, status} ->
          %{state | status: status}

        {:done, _} ->
          maybe_trigger_proactive_review(state)
          %{state | status: :idle}

        {:tool_call, %{name: name}} ->
          %{state | active_tools: state.active_tools ++ [name]}

        {:tool_trace, name, _input, _output, true = _is_error, _ws}
        when is_binary(name) ->
          maybe_trigger_refinement(name, state)
          state

        _ ->
          state
      end

    {:noreply, state}
  end

  defp execute_agent_loop(text, state) do
    callbacks = build_callbacks(state)

    workspace_path =
      state.workspace_path || Worth.Workspace.Service.resolve_path(state.current_workspace)

    try do
      # Persist user message to transcript
      Worth.Persistence.Transcript.append(
        state.session_id,
        %{role: "user", text: text},
        workspace_path
      )

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
      run_opts = apply_model_routing(run_opts)

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
        content = params[:content]

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
            Worth.LLM.chat_tier(%{messages: messages}, :lightweight, state.config)
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
              Worth.LLM.chat_tier(%{messages: messages}, :lightweight, state.config)
            end
          ]

          Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
            Worth.Memory.FactExtractor.extract_and_store(result_text, extraction_opts)
          end)
        end

        :ok
      end,
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
        result = Worth.Tools.Router.execute(name, args, workspace)
        track_skill_tool_usage(name, args, result)
        result
      end,
      get_tool_schema: fn name ->
        case Worth.Tools.Router.get_schema(name) do
          nil ->
            if String.contains?(name, ":") do
              case Worth.Mcp.ToolIndex.get_schema(name) do
                {:ok, schema} -> {:ok, schema}
                {:error, _} -> {:error, :not_found}
              end
            else
              {:error, :not_found}
            end

          schema ->
            {:ok, schema}
        end
      end
    }
  end

  defp mode_to_profile(:code), do: :agentic
  defp mode_to_profile(:research), do: :conversational
  defp mode_to_profile(:coding_agent), do: :claude_code
  defp mode_to_profile(_), do: :agentic

  defp apply_model_routing(opts) do
    case Application.get_env(:worth, :model_routing) do
      %{mode: "auto", preference: pref, filter: filter} ->
        opts
        |> Keyword.put(:model_selection_mode, :auto)
        |> Keyword.put(:model_preference, String.to_existing_atom(pref))
        |> maybe_put_filter(filter)

      %{mode: "manual", filter: filter} ->
        opts
        |> Keyword.put(:model_selection_mode, :manual)
        |> maybe_put_filter(filter)

      _ ->
        opts
    end
  end

  defp maybe_put_filter(opts, "free_only"), do: Keyword.put(opts, :model_filter, :free_only)
  defp maybe_put_filter(opts, _), do: opts

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
      e ->
        Logger.warning("Failed to flush working memory: #{Exception.message(e)}")
        :ok
    end
  end

  defp track_skill_tool_usage("skill_read", %{"name" => skill_name}, result) do
    success? = match?({:ok, _}, result)

    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      Worth.Skill.Service.record_usage(skill_name, success?)
      maybe_suggest_promotion(skill_name)
    end)
  end

  defp track_skill_tool_usage(_tool, _args, _result), do: :ok

  defp maybe_suggest_promotion(skill_name) do
    case Worth.Skill.Evaluator.should_promote?(skill_name) do
      {:promote, target} ->
        Phoenix.PubSub.broadcast(
          Worth.PubSub,
          "brain:events",
          {:skill_promotion_available, skill_name, target}
        )

      _ ->
        :ok
    end
  end

  defp maybe_trigger_refinement(tool_name, state) do
    skill_name = tool_name |> String.replace_prefix("skill_", "")

    if Worth.Skill.Evaluator.should_refine?(skill_name) do
      llm_fn = fn messages ->
        Worth.LLM.chat_tier(%{messages: messages}, :lightweight, state.config)
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
