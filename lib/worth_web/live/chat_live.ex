defmodule WorthWeb.ChatLive do
  @moduledoc false
  use WorthWeb, :live_view

  import WorthWeb.Components.Chat
  import WorthWeb.Components.Chat.Messages
  import WorthWeb.Components.Settings

  alias AgentEx.LLM.Catalog
  alias Worth.Agent.Tracker
  alias Worth.Config.Setup
  alias Worth.Learning.Permissions
  alias Worth.Learning.ProjectMapping
  alias Worth.Memory.Manager
  alias Worth.Persistence.Transcript
  alias Worth.Workspace.Learning
  alias Worth.Workspace.Service

  require Logger

  @impl true
  def terminate(reason, _socket) do
    Logger.error("[ChatLive] TERMINATED: #{inspect(reason, limit: :infinity, printable_limit: :infinity)}")

    Worth.LogBuffer.push(%{
      level: :error,
      text: "[ChatLive] TERMINATED: #{inspect(reason, limit: :infinity)}",
      ts: System.system_time(:millisecond)
    })
  end

  @impl true
  def mount(_params, _session, socket) do
    workspace = Worth.Config.get(:current_workspace, "personal")
    mode = Worth.Config.get(:current_mode, :code)

    if connected?(socket) do
      topic = "workspace:#{workspace}"
      Logger.info("[ChatLive] mounting: workspace=#{workspace}, self=#{inspect(self())}")
      Logger.info("[ChatLive] subscribing to #{topic}")
      :ok = Phoenix.PubSub.subscribe(Worth.PubSub, topic)
      Logger.info("[ChatLive] subscribed to #{topic}")
      Phoenix.PubSub.subscribe(Worth.PubSub, "worth:global")
      Logger.info("[ChatLive] subscribed to worth:global")
      send(self(), :refresh_model)
      send(self(), :scan_files)
      send(self(), {:check_learning, workspace})
      send(self(), :refresh_memory_stats)
    else
      Logger.info("[ChatLive] not connected yet")
    end

    prior_messages = load_last_session_messages(workspace)

    {:ok,
     socket
     |> stream(:messages, prior_messages)
     |> assign(
       page_title: "Worth",
       input_text: "",
       status: :idle,
       cost: 0.0,
       workspace: workspace,
       mode: mode,
       models: %{primary: %{label: nil, source: nil}, lightweight: %{label: nil, source: nil}},
       model_routing: current_routing(),
       turn: 0,
       streaming_text: "",
       sidebar_visible: true,
       selected_tab: :status,
       active_agents: [],
       workspace_files: [],
       input_history: [],
       history_index: -1,
       view: initial_view(),
       onboarding_step: 1,
       unlock_error: nil,
       has_history: prior_messages != [],
       settings_form: default_settings_form(),
       theme_module: Worth.Theme.Registry.resolve(),
       workspaces: list_workspaces(),
       memory_stats: fetch_memory_stats(workspace),
       strategy: :default,
       desktop_mode: System.get_env("WORTH_DESKTOP") == "1"
     )}
  end

  # ── Agent events ────────────────────────────────────────────────

  @impl true
  def handle_info({:agent_event, event}, socket) do
    {:noreply, process_event(event, socket)}
  end

  def handle_info(:agents_updated, socket) do
    agents = Enum.filter(Tracker.list_active(), &(&1.workspace == socket.assigns.workspace))

    {:noreply, assign(socket, active_agents: agents)}
  end

  def handle_info({:global_event, :agents_updated}, socket) do
    agents = Enum.filter(Tracker.list_active(), &(&1.workspace == socket.assigns.workspace))

    {:noreply, assign(socket, active_agents: agents)}
  end

  def handle_info({:global_event, _event}, socket) do
    {:noreply, socket}
  end

  def handle_info(:refresh_model, socket) do
    socket = poll_resolved_model(socket)
    if connected?(socket), do: Process.send_after(self(), :refresh_model, 2_000)
    {:noreply, socket}
  end

  def handle_info(:scan_files, socket) do
    files =
      try do
        Worth.Workspace.FileBrowser.scan(socket.assigns.workspace)
      rescue
        _ -> socket.assigns.workspace_files
      end

    if connected?(socket), do: Process.send_after(self(), :scan_files, 5_000)
    {:noreply, assign(socket, workspace_files: files)}
  end

  def handle_info(:refresh_memory_stats, socket) do
    stats = fetch_memory_stats(socket.assigns.workspace)
    if connected?(socket), do: Process.send_after(self(), :refresh_memory_stats, 10_000)
    {:noreply, assign(socket, memory_stats: stats)}
  end

  def handle_info({:reembed_done, result}, socket) do
    msg =
      case result do
        {:ok, count} -> "Re-embedding complete: #{count} memories processed."
        {:error, reason} -> "Re-embedding failed: #{inspect(reason)}"
      end

    {:noreply, append_system_message(socket, msg)}
  end

  def handle_info({:check_learning, workspace}, socket) do
    # Check for learning opportunities in the background
    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      case Learning.analyze(workspace) do
        {:ok, report} when report.has_learning_opportunity ->
          Phoenix.PubSub.broadcast(
            Worth.PubSub,
            "workspace:#{workspace}",
            {:agent_event, {:learning_opportunity, report}}
          )

        _ ->
          :ok
      end
    end)

    {:noreply, socket}
  end

  # ── SettingsComponent bridge messages ───────────────────────────

  def handle_info({:set_view, view}, socket) do
    {:noreply, assign(socket, view: view)}
  end

  def handle_info({:append_system_message, msg}, socket) do
    {:noreply, append_system_message(socket, msg)}
  end

  def handle_info({:apply_theme, bg_class, css}, socket) do
    {:noreply, push_event(socket, "apply_theme", %{bg_class: bg_class, css: css})}
  end

  def handle_info({:refresh_settings_form}, socket) do
    {:noreply, load_settings_form(socket)}
  end

  def handle_info({:lock_settings_form}, socket) do
    {:noreply, assign(socket, settings_form: default_settings_form())}
  end

  def handle_info({:export_secrets_to_env}, socket) do
    export_secrets_to_env()
    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── User events ─────────────────────────────────────────────────

  @impl true
  def handle_event("submit", %{"text" => text}, socket) when text != "" do
    socket =
      socket
      |> update(:turn, &(&1 + 1))
      |> push_input_history(text)
      |> stream_insert(:messages, %{id: msg_id(), type: :user, content: text})
      |> push_event("clear_input", %{})
      |> push_event("scroll_to_bottom", %{})

    case Worth.UI.Commands.parse(text) do
      :message ->
        {:noreply, send_to_brain(text, socket)}

      {:command, cmd} ->
        {:noreply, WorthWeb.CommandHandler.handle(cmd, text, socket)}
    end
  end

  def handle_event("submit", _params, socket), do: {:noreply, socket}

  def handle_event("stop", _params, socket) do
    Worth.Brain.stop(socket.assigns.workspace)

    # Promote any in-flight streaming text to a complete message
    socket =
      if socket.assigns.streaming_text == "" do
        socket
      else
        socket
        |> stream_insert(:messages, %{
          id: msg_id(),
          type: :assistant,
          content: socket.assigns.streaming_text <> "\n\n*[stopped]*"
        })
        |> assign(streaming_text: "")
      end

    socket =
      socket
      |> assign(status: :idle, active_agents: [])
      |> push_event("scroll_to_bottom", %{})

    {:noreply, socket}
  end

  def handle_event("switch_workspace", %{"name" => name}, socket) do
    old_workspace = socket.assigns.workspace

    Phoenix.PubSub.unsubscribe(Worth.PubSub, "workspace:#{old_workspace}")
    Phoenix.PubSub.subscribe(Worth.PubSub, "workspace:#{name}")

    socket =
      socket
      |> assign(workspace: name, workspaces: list_workspaces(), memory_stats: fetch_memory_stats(name))
      |> stream(:messages, [], reset: true)

    # Check for learning opportunities in the new workspace
    send(self(), {:check_learning, name})

    {:noreply, append_system_message(socket, "Switched to workspace: #{name}")}
  end

  def handle_event("approve_learning", %{"workspace" => workspace}, socket) do
    # Start the learning ingestion process
    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      try do
        {:ok, summary} = Learning.ingest(workspace)

        Phoenix.PubSub.broadcast(
          Worth.PubSub,
          "workspace:#{workspace}",
          {:agent_event, {:learning_complete, summary}}
        )
      rescue
        e ->
          Phoenix.PubSub.broadcast(
            Worth.PubSub,
            "workspace:#{workspace}",
            {:agent_event, {:learning_error, Exception.message(e)}}
          )
      end
    end)

    {:noreply, append_system_message(socket, "Starting learning process for #{workspace}...")}
  end

  def handle_event("decline_learning", %{"workspace" => _workspace}, socket) do
    {:noreply, append_system_message(socket, "Learning declined. You can start it later with /learn")}
  end

  def handle_event("grant_agent_permission", %{"agent" => agent_str}, socket) do
    agent = String.to_existing_atom(agent_str)
    Permissions.grant(agent)

    {:noreply,
     append_system_message(socket, "Granted access to #{agent} data. It will be included in the next learning run.")}
  end

  def handle_event("deny_agent_permission", %{"agent" => agent_str}, socket) do
    agent = String.to_existing_atom(agent_str)
    Permissions.deny(agent)
    {:noreply, append_system_message(socket, "Denied access to #{agent} data.")}
  end

  def handle_event("grant_all_agents", _params, socket) do
    unasked = Permissions.unasked_agents()
    Enum.each(unasked, &Permissions.grant(&1.agent))
    names = Enum.map_join(unasked, ", ", & &1.agent)
    {:noreply, append_system_message(socket, "Granted access to: #{names}")}
  end

  def handle_event(
        "map_projects",
        %{"workspace" => workspace, "agent" => agent_str, "projects" => projects_json},
        socket
      ) do
    agent = String.to_existing_atom(agent_str)

    case Jason.decode(projects_json) do
      {:ok, projects} when is_list(projects) ->
        ProjectMapping.set(workspace, agent, projects)
        {:noreply, append_system_message(socket, "Mapped #{length(projects)} projects for #{agent}.")}

      _ ->
        {:noreply, append_system_message(socket, "Invalid project selection.")}
    end
  end

  def handle_event("map_all_projects", %{"workspace" => workspace}, socket) do
    discovered = ProjectMapping.discover()
    ProjectMapping.set_all(workspace, discovered)
    total = discovered |> Map.values() |> List.flatten() |> length()
    {:noreply, append_system_message(socket, "Mapped all #{total} discovered projects.")}
  end

  def handle_event("memory_query", %{"workspace" => workspace}, socket) do
    msg =
      case Manager.recent(workspace: workspace, limit: 5) do
        {:ok, entries} when entries != [] ->
          items = Enum.map_join(entries, "\n", &"  - #{truncate_memory(&1)}")
          "Recent memories:\n#{items}"

        {:ok, []} ->
          "No stored memories yet."

        {:error, reason} ->
          "Memory query failed: #{inspect(reason)}"
      end

    {:noreply, append_system_message(socket, msg)}
  end

  def handle_event("memory_flush", %{"workspace" => workspace}, socket) do
    msg =
      case Manager.working_flush(workspace: workspace) do
        {:ok, count} ->
          "Flushed #{count} working memories to long-term storage."

        {:error, reason} ->
          "Flush failed: #{inspect(reason)}"
      end

    socket =
      socket
      |> assign(memory_stats: fetch_memory_stats(workspace))
      |> append_system_message(msg)

    {:noreply, socket}
  end

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, update(socket, :sidebar_visible, &(!&1))}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, selected_tab: String.to_existing_atom(tab))}
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    if socket.assigns.view == :settings do
      {:noreply, assign(socket, view: :chat)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("quit_app", _params, socket) do
    System.stop(0)
    {:noreply, socket}
  end

  # ── Onboarding events ──────────────────────────────────────────

  def handle_event("onboarding_save_dir", %{"workspace_directory" => path}, socket) do
    case Setup.set_workspace_directory(path) do
      :ok ->
        {:noreply, assign(socket, onboarding_step: 2)}

      {:error, _} ->
        {:noreply, assign(socket, onboarding_step: 1)}
    end
  end

  def handle_event("onboarding_save_password", params, socket) do
    password = params["password"] || ""
    confirmation = params["password_confirmation"] || ""

    cond do
      String.length(password) < 4 ->
        {:noreply, socket}

      password != confirmation ->
        {:noreply, socket}

      true ->
        case Worth.Settings.setup_password(password) do
          :ok ->
            # Migrate any secrets stored on disk during earlier onboarding steps
            Worth.Settings.import_from_config_store()
            {:noreply, assign(socket, onboarding_step: 3)}

          {:error, :already_set} ->
            # Password exists (e.g. page was refreshed mid-onboarding) — unlock instead
            case Worth.Settings.unlock(password) do
              :ok -> {:noreply, assign(socket, onboarding_step: 3)}
              {:error, _} -> {:noreply, socket}
            end

          {:error, _} ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("onboarding_save_key", %{"api_key" => key}, socket) do
    case Setup.set_openrouter_key(key) do
      :ok ->
        {:noreply, assign(socket, onboarding_step: 4)}

      {:error, _} ->
        {:noreply, assign(socket, onboarding_step: 3)}
    end
  end

  def handle_event("onboarding_save_profile", params, socket) do
    profile = %{
      name: String.trim(params["user_name"] || ""),
      role: String.trim(params["user_role"] || ""),
      goals: String.trim(params["user_goals"] || "")
    }

    finish_onboarding(socket, profile)
  end

  def handle_event("onboarding_skip_profile", _params, socket) do
    finish_onboarding(socket, %{name: "", role: "", goals: ""})
  end

  def handle_event("vault_unlock", %{"password" => password}, socket) do
    case Worth.Settings.unlock(password) do
      :ok ->
        export_secrets_to_env()

        {:noreply,
         socket
         |> assign(view: :chat, unlock_error: nil)
         |> load_settings_form()
         |> append_system_message("Vault unlocked. Welcome back!")}

      {:error, :invalid_password} ->
        {:noreply, assign(socket, unlock_error: "Invalid password. Please try again.")}

      {:error, _} ->
        {:noreply, assign(socket, unlock_error: "Failed to unlock vault.")}
    end
  end

  # ── Settings events ────────────────────────────────────────────

  # ── Event processing ──────────────────────────────────────────

  defp process_event(event, socket) do
    cost =
      try do
        Worth.Metrics.session_cost()
      rescue
        _ -> socket.assigns.cost
      end

    socket = assign(socket, cost: cost)

    case event do
      {:text_chunk, chunk} ->
        clean = strip_eom_tokens(chunk)
        if clean == "", do: socket, else: update(socket, :streaming_text, &(&1 <> clean))

      {:status, status} ->
        assign(socket, status: status)

      {:model_selected, info} ->
        tier = Map.get(info, :tier, :primary)
        label = Map.get(info, :label) || Map.get(info, :model_id) || "?"
        provider = Map.get(info, :provider_name, "?")
        source = Map.get(info, :source, :unknown)
        slot = %{label: label, source: "#{source}/#{provider}"}
        models = Map.put(socket.assigns.models, tier, slot)
        assign(socket, models: models)

      {:tool_use, name, _ws} when is_binary(name) ->
        stream_insert(socket, :messages, %{
          id: msg_id(),
          type: :tool_call,
          content: %{name: name, input: %{}, status: :running}
        })

      {:tool_use, nil, _ws} ->
        socket

      {:tool_trace, name, _input, output, is_error, _ws} ->
        status = if is_error, do: :failed, else: :success
        output_str = if is_binary(output), do: output, else: inspect(output)

        stream_insert(socket, :messages, %{
          id: msg_id(),
          type: :tool_result,
          content: %{name: name, output: output_str, status: status}
        })

      {:tool_call, %{name: name, input: input}} ->
        stream_insert(socket, :messages, %{
          id: msg_id(),
          type: :tool_call,
          content: %{name: name, input: input}
        })

      {:tool_result, %{name: name, output: output}} ->
        stream_insert(socket, :messages, %{
          id: msg_id(),
          type: :tool_result,
          content: %{name: name, output: output}
        })

      {:agent_reasoning, text, _tool_names, _ws} ->
        stream_insert(socket, :messages, %{id: msg_id(), type: :thinking, content: text})

      {:thinking_chunk, text} ->
        stream_insert(socket, :messages, %{id: msg_id(), type: :thinking, content: text})

      {:done, %{text: text}} ->
        Logger.info("[ChatLive] RECEIVED :done event with text: #{inspect(text)}")

        final =
          if socket.assigns.streaming_text == "",
            do: text || "",
            else: socket.assigns.streaming_text

        final = final |> strip_eom_tokens() |> String.trim()

        socket
        |> stream_insert(:messages, %{id: msg_id(), type: :assistant, content: final})
        |> assign(streaming_text: "", status: :idle)
        |> push_event("scroll_to_bottom", %{})

      {:error, :stopped} ->
        Logger.info("[ChatLive.process_event] Received :stopped error")
        # Already handled by the stop event handler — ignore
        socket

      {:error, reason} ->
        Logger.info("[ChatLive.process_event] Received error: #{inspect(reason)}")
        reason_str = if is_binary(reason), do: reason, else: inspect(reason)

        socket
        |> stream_insert(:messages, %{id: msg_id(), type: :error, content: "Error: #{reason_str}"})
        |> assign(status: :idle, streaming_text: "")

      {:learning_opportunity, report} ->
        Logger.info("[ChatLive] Received learning opportunity for #{report.workspace}")

        socket =
          if report.unasked_agents == [] do
            socket
          else
            prompt = build_permission_prompt(report.unasked_agents)

            stream_insert(socket, :messages, %{
              id: msg_id(),
              type: :system,
              content: prompt,
              permission_agents: report.unasked_agents
            })
          end

        socket =
          if report[:needs_project_mapping] and report[:discovered_projects] != %{} do
            prompt = build_project_mapping_prompt(report.workspace, report.discovered_projects)

            stream_insert(socket, :messages, %{
              id: msg_id(),
              type: :system,
              content: prompt,
              project_mapping: report.discovered_projects,
              mapping_workspace: report.workspace
            })
          else
            socket
          end

        prompt = build_learning_prompt(report)
        stream_insert(socket, :messages, %{id: msg_id(), type: :system, content: prompt, learning_report: report})

      {:learning_progress, details} ->
        msg = format_learning_progress(details)
        stream_insert(socket, :messages, %{id: msg_id(), type: :system, content: msg})

      {:learning_complete, summary} ->
        msg = "Learning complete! Ingested #{summary.ingested} items into memory."
        stream_insert(socket, :messages, %{id: msg_id(), type: :system, content: msg})

      {:learning_error, reason} ->
        msg = "Learning failed: #{inspect(reason)}"
        stream_insert(socket, :messages, %{id: msg_id(), type: :error, content: msg})

      _ ->
        Logger.info("[ChatLive.process_event] Unhandled event: #{inspect(event)}")
        socket
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp send_to_brain(text, socket) do
    Worth.Brain.cast_message(text, socket.assigns.workspace)
    assign(socket, status: :running, streaming_text: "")
  end

  defp poll_resolved_model(socket) do
    primary = AgentEx.ModelRouter.resolve(:primary)
    lightweight = AgentEx.ModelRouter.resolve(:lightweight)

    models = %{
      primary: format_model_slot(primary),
      lightweight: format_model_slot(lightweight)
    }

    routing = current_routing()

    assign(socket, models: models, model_routing: routing)
  rescue
    _ -> socket
  end

  defp format_model_slot(nil), do: %{label: nil, source: nil}
  defp format_model_slot({:ok, resolved}) when is_map(resolved), do: format_model_slot(resolved)
  defp format_model_slot({:error, _}), do: %{label: nil, source: nil}

  defp format_model_slot(resolved) when is_map(resolved) do
    provider = Map.get(resolved, :provider_name, "")
    source = Map.get(resolved, :source, "")

    %{
      label: Map.get(resolved, :label) || Map.get(resolved, :model_id),
      source: if(provider == "", do: to_string(source), else: "#{source}/#{provider}"),
      context_window: Map.get(resolved, :context_window)
    }
  end

  defp format_model_slot(_), do: %{label: nil, source: nil}

  def append_system_message(socket, msg) do
    socket
    |> stream_insert(:messages, %{id: msg_id(), type: :system, content: msg})
    |> push_event("scroll_to_bottom", %{})
  end

  defp push_input_history(socket, text) do
    history = Enum.take([text | socket.assigns.input_history], 50)
    assign(socket, input_history: history, history_index: -1)
  end

  defp msg_id, do: [:positive] |> System.unique_integer() |> to_string()

  defp default_settings_form do
    %{
      locked: safe_vault_call(fn -> Worth.Settings.locked?() end, true),
      has_password: safe_vault_call(fn -> Worth.Settings.has_password?() end, false),
      providers: [],
      preferences: [],
      themes: theme_list(),
      current_theme: current_theme_name(),
      coding_agents: coding_agents_list(),
      routing: current_routing(),
      agent_limits: current_agent_limits(),
      memory: current_memory_settings(),
      base_dir: Worth.Paths.workspace_dir()
    }
  end

  defp finish_onboarding(socket, profile) when is_map(profile) do
    # Set routing defaults
    routing = %{mode: "auto", preference: "optimize_price", filter: "free_only"}
    Worth.Config.put([:model_routing], routing)

    export_secrets_to_env()

    # Create the personal workspace
    {:ok, _path} = Service.create_personal(profile)

    # Set personal as the current workspace
    workspace = "personal"
    Worth.Config.put(:current_workspace, workspace)
    Worth.Config.put(:current_mode, :code)

    # Start the Brain for this workspace
    Worth.Brain.ensure(workspace)

    # Seed memory with user profile (async, non-blocking)
    seed_user_memory(workspace, profile)

    # Build personalized welcome
    message = build_welcome_message(profile)

    {:noreply,
     socket
     |> assign(
       view: :chat,
       onboarding_step: 1,
       workspace: workspace,
       mode: :code,
       workspaces: list_workspaces()
     )
     |> load_settings_form()
     |> append_system_message(message)}
  end

  defp seed_user_memory(workspace, profile) do
    name = Map.get(profile, :name, "")
    role = Map.get(profile, :role, "")
    goals = Map.get(profile, :goals, "")

    if name != "" or role != "" or goals != "" do
      parts = []
      parts = if name == "", do: parts, else: parts ++ ["User's name is #{name}."]
      parts = if role == "", do: parts, else: parts ++ ["Role: #{role}."]
      parts = if goals == "", do: parts, else: parts ++ ["Goals: #{goals}"]

      text = Enum.join(parts, " ")
      scope_id = Learning.workspace_scope_id(workspace)

      Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
        try do
          Mneme.remember(text,
            scope_id: scope_id,
            entry_type: "identity"
          )
        rescue
          e -> Logger.warning("[Onboarding] Failed to seed memory: #{Exception.message(e)}")
        end
      end)
    end
  end

  defp build_welcome_message(profile) do
    name = Map.get(profile, :name, "")

    if name == "" do
      "Your personal workspace is ready. What would you like to work on?"
    else
      "Hey #{name}! Your personal workspace is ready. What would you like to work on?"
    end
  end

  defp initial_view do
    cond do
      Setup.needs_setup?() -> :onboarding
      safe_vault_call(fn -> Worth.Settings.has_password?() and Worth.Settings.locked?() end, false) -> :unlock
      true -> :chat
    end
  end

  defp safe_vault_call(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end

  def refresh_settings_form(socket), do: load_settings_form(socket)

  defp load_settings_form(socket) do
    locked = safe_vault_call(fn -> Worth.Settings.locked?() end, true)

    {providers, preferences} =
      if locked do
        {[], []}
      else
        prefs =
          "preference"
          |> Worth.Settings.all_by_category()
          |> Enum.map(fn s -> %{key: s.key, value: s.encrypted_value} end)

        {provider_list(), prefs}
      end

    assign(socket,
      settings_form: %{
        locked: locked,
        has_password: safe_vault_call(fn -> Worth.Settings.has_password?() end, false),
        providers: providers,
        preferences: preferences,
        themes: theme_list(),
        current_theme: current_theme_name(),
        coding_agents: coding_agents_list(),
        routing: current_routing(),
        agent_limits: current_agent_limits(),
        memory: current_memory_settings(),
        base_dir: Worth.Paths.workspace_dir()
      }
    )
  end

  defp theme_list do
    Enum.map(Worth.Theme.Registry.list(), fn mod ->
      %{name: mod.name(), display_name: mod.display_name(), description: mod.description()}
    end)
  end

  defp list_workspaces do
    Service.list()
  rescue
    _ -> []
  end

  defp current_theme_name do
    theme = Worth.Theme.Registry.resolve()
    theme.name()
  end

  defp provider_list do
    # Get stored keys from the vault
    stored_keys =
      "secret"
      |> Worth.Settings.all_by_category()
      |> Map.new(fn s -> {s.key, s.encrypted_value} end)

    AgentEx.LLM.ProviderRegistry.list()
    |> Enum.map(fn entry ->
      mod = entry.module
      env_var = List.first(mod.env_vars()) || ""
      has_key = has_provider_key?(env_var, stored_keys)
      model_count = provider_model_count(entry.id)

      %{
        id: entry.id,
        label: mod.label(),
        env_var: env_var,
        has_key: has_key,
        key_hint: key_hint(env_var, stored_keys),
        model_count: model_count
      }
    end)
    |> Enum.sort_by(fn p -> {!p.has_key, p.label} end)
  end

  defp has_provider_key?(env_var, stored_keys) when env_var != "" do
    Map.has_key?(stored_keys, env_var) or (System.get_env(env_var) || "") != ""
  end

  defp has_provider_key?(_, _), do: false

  defp key_hint(env_var, stored_keys) when env_var != "" do
    value = Map.get(stored_keys, env_var) || System.get_env(env_var) || ""

    if String.length(value) > 8 do
      "#{String.slice(value, 0, 8)}..."
    else
      ""
    end
  end

  defp key_hint(_, _), do: ""

  defp provider_model_count(provider_id) do
    provider_id |> Catalog.for_provider() |> length()
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  defp current_agent_limits do
    %{
      cost_limit: Worth.Config.get(:cost_limit, 5.0),
      max_turns: Worth.Config.get(:max_turns, 50)
    }
  end

  defp current_memory_settings do
    %{
      enabled: Worth.Config.get([:memory, :enabled], true),
      decay_days: Worth.Config.get([:memory, :decay_days], 90)
    }
  end

  defp current_routing do
    case Worth.Config.get([:model_routing]) do
      %{mode: mode, preference: pref, filter: filter} ->
        %{mode: mode, preference: pref, filter: filter}

      _ ->
        %{mode: "auto", preference: "optimize_price", filter: "free_only"}
    end
  end

  defp load_last_session_messages(workspace) do
    workspace_path = Service.resolve_path(workspace)

    with {:ok, sessions} <- Transcript.list_sessions(workspace_path),
         last when not is_nil(last) <- List.last(sessions),
         {:ok, entries} <- Transcript.load(last, workspace_path) do
      Enum.map(entries, fn entry ->
        event = entry["event"] || %{}
        role = event["role"]
        text = event["text"] || ""

        type =
          case role do
            "user" -> :user
            "assistant" -> :assistant
            _ -> :system
          end

        %{id: msg_id(), type: type, content: text}
      end)
    else
      _ -> []
    end
  rescue
    _ -> []
  end

  defp coding_agents_list do
    Worth.CodingAgents.discover()
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp export_secrets_to_env do
    # Migrate any plaintext secrets to encrypted vault storage
    Worth.Config.export_vault_secrets()

    # Refresh catalog so provider availability is up to date
    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      Catalog.refresh()
    end)
  end

  @eom_tokens ~w(<|eom|> <|eot_id|> <|end|> <|endoftext|>)
  defp strip_eom_tokens(text) do
    Enum.reduce(@eom_tokens, text, fn token, acc -> String.replace(acc, token, "") end)
  end

  defp build_learning_prompt(report) do
    type_list =
      Enum.map_join(report.opportunities, "\n", fn opp ->
        "- #{opp.description}: #{opp.item_count} items (#{format_bytes(opp.total_bytes)})"
      end)

    total_bytes = report.total_new_bytes + report.total_modified_bytes

    """
    #{report.recommendation}

    Found the following content to learn from:
    #{type_list}

    Total: #{report.total_items} items (#{format_bytes(total_bytes)})

    Would you like to ingest this content into memory?
    """
  end

  defp build_permission_prompt(agents) do
    agent_list =
      Enum.map_join(agents, "\n", fn a ->
        paths = Enum.join(a.data_paths, ", ")
        "- **#{a.agent}** (reads from #{paths})"
      end)

    """
    The following coding agents have data on this machine that Worth can learn from:

    #{agent_list}

    These directories may contain session transcripts, project preferences, and other potentially sensitive data. Worth will only read data needed for learning — never credentials or settings files.

    Grant access to include their data in future learning runs.
    """
  end

  defp build_project_mapping_prompt(workspace, discovered) do
    agent_sections =
      Enum.map_join(discovered, "\n\n", fn {agent, projects} ->
        project_list = Enum.map_join(projects, "\n", &"    - #{&1}")
        "**#{format_agent_display(agent)}** (#{length(projects)} projects):\n#{project_list}"
      end)

    """
    The following coding agent projects were discovered. Select which ones are relevant to workspace "#{workspace}":

    #{agent_sections}

    Only data from selected projects will be imported during learning.
    """
  end

  defp format_agent_display(:claude_code), do: "Claude Code"
  defp format_agent_display(:codex), do: "Codex"
  defp format_agent_display(:gemini), do: "Gemini"
  defp format_agent_display(:opencode), do: "OpenCode"
  defp format_agent_display(name), do: to_string(name)

  defp format_learning_progress(%{phase: :start} = details) do
    sources = details[:sources] || []
    names = Enum.map_join(sources, ", ", &inspect/1)
    "[learning] Starting pipeline: #{names}"
  end

  defp format_learning_progress(%{phase: :source_complete} = details) do
    source = details[:source] || "unknown"
    fetched = details[:fetched] || 0
    learned = details[:learned] || 0
    "[learning] #{source}: fetched #{fetched}, learned #{learned}"
  end

  defp format_learning_progress(%{phase: :agents_fetched} = details) do
    count = details[:events_found] || 0
    "[learning] Coding agents: found #{count} events"
  end

  defp format_learning_progress(%{phase: :agent_fetched} = details) do
    agent = details[:agent] || "unknown"
    "[learning] #{agent}: fetch complete (#{details[:duration_ms] || 0}ms)"
  end

  defp format_learning_progress(%{phase: :complete} = details) do
    learned = details[:total_learned] || 0
    fetched = details[:total_fetched] || 0
    duration = details[:duration_ms] || 0
    "[learning] Complete: #{learned} learned from #{fetched} fetched (#{div(duration, 1000)}s)"
  end

  defp format_learning_progress(details) do
    "[learning] #{inspect(details)}"
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp format_bytes(bytes), do: "#{div(bytes, 1024 * 1024)} MB"

  defp render_streaming(text) do
    case MDEx.to_html(text) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end

  defp fetch_memory_stats(workspace) do
    {:ok, working} = Manager.working_read(workspace: workspace)
    {:ok, recent} = Manager.recent(limit: 100)

    %{
      working_count: length(working),
      recent_count: length(recent),
      enabled: Worth.Config.get([:memory, :enabled], true)
    }
  rescue
    _ -> %{working_count: 0, recent_count: 0, enabled: true}
  catch
    :exit, _ -> %{working_count: 0, recent_count: 0, enabled: true}
  end

  defp truncate_memory(entry) do
    content = Map.get(entry, :content, "")
    if String.length(content) > 80, do: String.slice(content, 0, 80) <> "...", else: content
  end
end
