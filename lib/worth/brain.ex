defmodule Worth.Brain do
  @moduledoc """
  Per-workspace GenServer that owns one agent session at a time.

  Each workspace gets its own Brain process, registered via
  `{:via, Registry, {Worth.Registry, {:brain, workspace}}}`.
  Processes are started on demand by `Worth.Brain.Supervisor.ensure_started/2`.
  """
  use GenServer

  alias Worth.Agent.Tracker
  alias Worth.Brain.Session
  alias Worth.Mcp.Broker
  alias Worth.Mcp.ToolIndex
  alias Worth.Memory.FactExtractor
  alias Worth.Memory.Manager
  alias Worth.Persistence.Transcript
  alias Worth.Skill.Evaluator
  alias Worth.Skill.Lifecycle
  alias Worth.Skill.Refiner
  alias Worth.Skill.Versioner
  alias Worth.Tools.Router
  alias Worth.Workspace.Service

  require Logger

  defstruct [
    :current_workspace,
    :workspace_path,
    :session_id,
    :history,
    :config,
    :status,
    :mode,
    :profile,
    :tool_permissions,
    :active_tools,
    :task_pid,
    :task_from,
    strategy: :default,
    strategy_state: nil,
    strategy_opts: []
  ]

  @type t :: %__MODULE__{}

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

  # ── Registry helpers ──────────────────────────────────────────

  @doc "Returns the via-tuple for a workspace Brain process."
  def via(workspace), do: {:via, Registry, {Worth.Registry, {:brain, workspace}}}

  @doc "Look up the PID of the Brain for `workspace`, or nil."
  def whereis(workspace) do
    case Registry.lookup(Worth.Registry, {:brain, workspace}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Returns the PID of the Brain for `workspace`, starting one if needed.
  """
  def ensure(workspace) do
    Worth.Brain.Supervisor.ensure_started(workspace)
  end

  # ── Public API ────────────────────────────────────────────────

  def child_spec(opts) do
    workspace = Keyword.get(opts, :workspace, "personal")

    %{
      id: {:brain, workspace},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts \\ []) do
    workspace = Keyword.get(opts, :workspace, "personal")
    GenServer.start_link(__MODULE__, opts, name: via(workspace))
  end

  def send_message(text, workspace) do
    Logger.info(
      "[Brain.External] send_message called: text=#{String.slice(text, 0, 30)}, workspace=#{inspect(workspace)}"
    )

    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, {:send_message, text}, :infinity)
  end

  @doc """
  Fire-and-forget version of send_message — results arrive via PubSub.
  Use this from LiveView instead of wrapping send_message in a Task.
  """
  def cast_message(text, workspace) do
    Logger.info(
      "[Brain.External] cast_message called: text=#{String.slice(text, 0, 30)}, workspace=#{inspect(workspace)}"
    )

    {:ok, pid} = ensure(workspace)
    GenServer.cast(pid, {:send_message, text})
  end

  def stop(workspace) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, :stop)
  end

  def get_status(workspace) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, :get_status)
  end

  def switch_mode(workspace, mode) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, {:switch_mode, mode})
  end

  def switch_strategy(workspace, strategy_id, opts \\ []) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, {:switch_strategy, strategy_id, opts})
  end

  def resume_session(workspace, session_id) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, {:resume_session, session_id})
  end

  def list_sessions(workspace) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, :list_sessions)
  end

  def skill_history(workspace, name) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, {:skill_history, name})
  end

  def skill_rollback(workspace, name, version) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, {:skill_rollback, name, version})
  end

  def skill_refine(workspace, name) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, {:skill_refine, name})
  end

  def skill_promote(workspace, name) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, {:skill_promote, name})
  end

  def switch_to_coding_agent(workspace, protocol) do
    {:ok, pid} = ensure(workspace)
    GenServer.call(pid, {:switch_to_coding_agent, protocol})
  end

  # These don't need a workspace — they're global services
  def mcp_connect(name, config), do: Broker.connect(name, config)
  def mcp_disconnect(name), do: Broker.disconnect(name)
  def mcp_list, do: Broker.list_connections()
  def mcp_tools(server_name), do: ToolIndex.tools_for_server(server_name)
  def list_coding_agents, do: Worth.CodingAgents.discover()

  # ── GenServer callbacks ───────────────────────────────────────

  @impl true
  def init(opts) do
    workspace = Keyword.get(opts, :workspace, "personal")
    mode = Keyword.get(opts, :mode, :code)

    state = %__MODULE__{
      current_workspace: workspace,
      workspace_path:
        Keyword.get(opts, :workspace_path) ||
          Service.resolve_path(workspace),
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

    Logger.info("[Brain] Started for workspace=#{workspace}, pid=#{inspect(self())}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      status: state.status,
      cost: Worth.Metrics.session_cost(),
      workspace: state.current_workspace,
      mode: state.mode,
      profile: state.profile,
      session_id: state.session_id,
      active_tools: state.active_tools,
      strategy: state.strategy
    }

    {:reply, status, state}
  end

  def handle_call({:send_message, text}, from, state) do
    state = start_agent_task(text, state, from)
    {:noreply, state}
  end

  def handle_call(:stop, _from, %{status: :running, task_pid: pid} = state) when is_pid(pid) do
    if Process.alive?(pid) do
      Process.unlink(pid)
      Process.exit(pid, :kill)
    end

    Tracker.unregister(state.session_id)
    if state.task_from, do: GenServer.reply(state.task_from, {:error, :stopped})

    Logger.info("[Brain] Agent execution stopped by user")
    {:reply, :ok, %{state | status: :idle, task_pid: nil, task_from: nil}}
  end

  def handle_call(:stop, _from, state) do
    {:reply, :ok, %{state | status: :idle, task_pid: nil, task_from: nil}}
  end

  def handle_call({:switch_mode, mode}, _from, state) do
    {:reply, :ok, %{state | mode: mode, profile: mode_to_profile(mode)}}
  end

  def handle_call({:switch_strategy, strategy_id, opts}, _from, state) do
    case AgentEx.Strategy.Registry.fetch(strategy_id) do
      nil ->
        {:reply, {:error, :unknown_strategy}, state}

      mod ->
        case mod.init(opts) do
          {:ok, strategy_state} ->
            new_state = %{
              state
              | strategy: strategy_id,
                strategy_state: strategy_state,
                strategy_opts: opts
            }

            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
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

  def handle_call({:resume_session, session_id}, _from, state) do
    workspace = state.current_workspace

    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      result = Session.resume(session_id, state.workspace_path, workspace, state.config)
      broadcast_workspace(workspace, {:agent_event, {:session_resumed, result}})
    end)

    {:reply, :ok, %{state | status: :running}}
  end

  def handle_call(:list_sessions, _from, state) do
    sessions = Session.list_sessions(state.workspace_path)
    {:reply, sessions, state}
  end

  def handle_call({:skill_history, name}, _from, state) do
    result = Versioner.list_versions(name)
    {:reply, result, state}
  end

  def handle_call({:skill_rollback, name, version}, _from, state) do
    result = Versioner.rollback(name, version)
    {:reply, result, state}
  end

  def handle_call({:skill_refine, name}, _from, state) do
    llm_fn = fn messages ->
      Worth.LLM.chat_tier(%{messages: messages}, :lightweight, state.config)
    end

    result = Refiner.refine(name, llm_fn: llm_fn)
    {:reply, result, state}
  end

  def handle_call({:skill_promote, name}, _from, state) do
    result = Lifecycle.promote(name)

    case result do
      {:ok, :needs_user_approval, target} ->
        case Lifecycle.execute_promotion(name, target) do
          {:ok, _} = success -> {:reply, success, state}
          error -> {:reply, error, state}
        end

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_cast({:send_message, text}, state) do
    state = start_agent_task(text, state, nil)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{task_pid: pid} = state) do
    Logger.warning("[Brain] Agent task #{inspect(pid)} exited: #{inspect(reason)}")
    Tracker.unregister(state.session_id)

    if reason != :normal do
      if state.task_from, do: GenServer.reply(state.task_from, {:error, reason})

      broadcast_workspace(
        state.current_workspace,
        {:agent_event, {:error, "Agent task crashed: #{inspect(reason)}"}}
      )
    end

    {:noreply, %{state | status: :idle, task_pid: nil, task_from: nil}}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:agent_event_internal, event}, state) do
    state =
      case event do
        {:status, status} ->
          %{state | status: status}

        {:done, _} ->
          maybe_trigger_proactive_review(state)
          %{state | status: :idle, task_pid: nil, task_from: nil}

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

  def handle_info({:model_selected, _model_info}, state) do
    # AgentEx ModelRouter broadcasts model selection events; ignore in Brain
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ── Agent task dispatch ──────────────────────────────────────

  defp start_agent_task(text, state, from) do
    workspace = state.current_workspace
    brain_pid = self()

    Tracker.register(state.session_id,
      workspace: workspace,
      mode: state.profile,
      label: "main agent"
    )

    {:ok, pid} =
      Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
        result = execute_agent_loop(text, state, brain_pid)

        done_event =
          case result do
            {:ok, response} -> {:done, response}
            {:error, reason} -> {:error, reason}
          end

        broadcast_workspace(workspace, {:agent_event, done_event})
        send(brain_pid, {:agent_event_internal, done_event})
        if from, do: GenServer.reply(from, result)
      end)

    Process.monitor(pid)
    %{state | status: :running, task_pid: pid, task_from: from}
  end

  # ── Agent loop ────────────────────────────────────────────────

  defp execute_agent_loop(text, state, brain_pid) do
    callbacks = build_callbacks(state, brain_pid)

    workspace_path =
      state.workspace_path || Service.resolve_path(state.current_workspace)

    Transcript.append(
      state.session_id,
      %{role: "user", text: text},
      workspace_path
    )

    context_opts = [workspace: state.current_workspace, user_message: text]

    Logger.info("[Brain] Building system prompt...")

    system_prompt =
      case Worth.Workspace.Context.build_system_prompt(workspace_path, context_opts) do
        {:ok, prompt} when is_binary(prompt) and prompt != "" -> prompt
        _ -> nil
      end

    Logger.info("[Brain] System prompt ready (#{if system_prompt, do: byte_size(system_prompt), else: 0} bytes)")

    Manager.working_push(text,
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
      caller: brain_pid,
      cost_limit: state.config[:cost_limit] || 5.0,
      history: state.history,
      tool_permissions: state.tool_permissions,
      strategy: state.strategy,
      strategy_opts: state.strategy_opts
    ]

    run_opts = if system_prompt, do: Keyword.put(run_opts, :system_prompt, system_prompt), else: run_opts
    run_opts = apply_model_routing(run_opts)

    Tracker.register(state.session_id,
      mode: state.mode,
      workspace: state.current_workspace,
      label: "main agent"
    )

    Logger.info("[Brain] Calling AgentEx.run (profile=#{state.profile})")

    case AgentEx.run(run_opts) do
      {:ok, response} ->
        store_outcome_feedback(response)
        {:ok, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_outcome_feedback(%{text: text}) when is_binary(text) and text != "" do
    Manager.outcome_good()
  end

  defp store_outcome_feedback(_), do: :ok

  defp build_callbacks(state, brain_pid) do
    workspace = state.current_workspace
    workspace_path = state.workspace_path
    memory_opts = [workspace: workspace]

    %{
      llm_chat: fn params ->
        # Internal calls (e.g., model router classification) should not stream to UI
        if params["internal"] do
          params = maybe_inject_manual_model(params)
          Worth.LLM.stream_chat(params, state.config, fn _chunk -> :ok end)
        else
          on_chunk = fn text_delta ->
            broadcast_workspace(workspace, {:agent_event, {:text_chunk, text_delta}})
          end

          params = maybe_inject_manual_model(params)
          Worth.LLM.stream_chat(params, state.config, on_chunk)
        end
      end,
      on_event: fn event, _ctx ->
        broadcast_workspace(workspace, {:agent_event, event})
        send(brain_pid, {:agent_event_internal, event})
        :ok
      end,
      on_tool_approval: fn name, input, _ctx ->
        broadcast_workspace(workspace, {:agent_event, {:tool_approval_request, name, input}})
        :approved
      end,
      knowledge_search: fn query, opts ->
        merged_opts = Keyword.merge(memory_opts, opts)
        Manager.search(query, merged_opts)
      end,
      knowledge_create: fn params ->
        content = params[:content]

        create_opts =
          Keyword.merge(memory_opts,
            entry_type: params[:entry_type] || "fact",
            source: params[:source] || "agent",
            metadata: Map.put(params[:metadata] || %{}, :workspace, workspace)
          )

        Manager.remember(content, create_opts)
      end,
      knowledge_recent: fn _scope_id ->
        Manager.recent(memory_opts)
      end,
      on_persist_turn: fn ctx, text ->
        Transcript.append(
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
          FactExtractor.extract_and_store(text, extraction_opts)
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
            FactExtractor.extract_and_store(result_text, extraction_opts)
          end)
        end

        :ok
      end,
      search_tools: fn query, _opts ->
        Router.all_definitions()
        |> Enum.filter(fn d ->
          name = d[:name] || d["name"] || ""
          desc = d[:description] || d["description"] || ""
          String.contains?(name, query) or String.contains?(String.downcase(desc), String.downcase(query))
        end)
        |> Enum.map(fn d -> d[:name] || d["name"] end)
      end,
      execute_external_tool: fn name, args, _ctx ->
        result = Router.execute(name, args, workspace)
        track_skill_tool_usage(name, args, result)
        result
      end,
      get_tool_schema: fn name ->
        case Router.get_schema(name) do
          nil ->
            if String.contains?(name, ":") do
              case ToolIndex.get_schema(name) do
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

  # ── Helpers ───────────────────────────────────────────────────

  defp mode_to_profile(:code), do: :agentic
  defp mode_to_profile(:research), do: :conversational
  defp mode_to_profile(:coding_agent), do: :claude_code
  defp mode_to_profile(_), do: :agentic

  defp apply_model_routing(opts) do
    case Worth.Config.get([:model_routing]) do
      %{mode: "auto", preference: pref, filter: filter} ->
        opts
        |> Keyword.put(:model_selection_mode, :auto)
        |> Keyword.put(:model_preference, safe_to_existing_atom(pref))
        |> maybe_put_filter(filter)

      %{mode: "manual", filter: filter} ->
        opts
        |> Keyword.put(:model_selection_mode, :manual)
        |> maybe_put_filter(filter)

      _ ->
        opts
    end
  end

  defp safe_to_existing_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> :optimize_price
  end

  defp safe_to_existing_atom(other), do: other

  defp maybe_put_filter(opts, "free_only"), do: Keyword.put(opts, :model_filter, :free_only)
  defp maybe_put_filter(opts, _), do: opts

  defp maybe_inject_manual_model(params) when is_map(params) do
    case Worth.Config.get([:model_routing]) do
      %{mode: "manual", manual_model: %{provider: p, model_id: m}} ->
        Map.put(params, "_route", %{provider_name: p, model_id: m})

      _ ->
        params
    end
  end

  defp maybe_inject_manual_model(params), do: params

  defp mode_to_agent_mode(:code), do: :agentic
  defp mode_to_agent_mode(:research), do: :conversational
  defp mode_to_agent_mode(:planned), do: :agentic_planned
  defp mode_to_agent_mode(:turn_by_turn), do: :turn_by_turn
  defp mode_to_agent_mode(_), do: :agentic

  defp generate_session_id do
    "worth-#{1_000_000 |> :rand.uniform() |> Integer.to_string() |> String.pad_leading(6, "0")}"
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
    case Evaluator.should_promote?(skill_name) do
      {:promote, target} ->
        Phoenix.PubSub.broadcast(
          Worth.PubSub,
          "worth:global",
          {:global_event, {:skill_promotion_available, skill_name, target}}
        )

      _ ->
        :ok
    end
  end

  defp broadcast_workspace(workspace, message) do
    Logger.debug("[Brain] broadcasting to workspace:#{workspace}: #{inspect(elem(message, 0))}")
    Phoenix.PubSub.broadcast(Worth.PubSub, "workspace:#{workspace}", message)
  end

  defp maybe_trigger_refinement(tool_name, state) do
    skill_name = String.replace_prefix(tool_name, "skill_", "")

    if Evaluator.should_refine?(skill_name) do
      llm_fn = fn messages ->
        Worth.LLM.chat_tier(%{messages: messages}, :lightweight, state.config)
      end

      Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
        Refiner.refine(skill_name, llm_fn: llm_fn)
      end)
    end
  end

  defp maybe_trigger_proactive_review(state) do
    workspace = state.current_workspace

    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      Worth.Skill.Registry.all()
      |> Enum.filter(&(&1.trust_level == :learned))
      |> Enum.each(fn skill ->
        case Refiner.proactive_review(skill.name) do
          {:ok, :review_needed, info} ->
            broadcast_workspace(
              workspace,
              {:agent_event,
               {:system,
                "Skill '#{skill.name}' may need review (#{info.success_rate}% success, #{info.usage_count} uses)"}}
            )

          _ ->
            :ok
        end
      end)
    end)
  end
end
