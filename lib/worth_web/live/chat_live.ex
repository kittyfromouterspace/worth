defmodule WorthWeb.ChatLive do
  use WorthWeb, :live_view

  import WorthWeb.ChatComponents
  import WorthWeb.SettingsComponents

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    workspace = Application.get_env(:worth, :current_workspace, "personal")
    mode = Application.get_env(:worth, :current_mode, :code)

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
       turn: 0,
       streaming_text: "",
       sidebar_visible: true,
       selected_tab: :status,
       active_agents: [],
       workspace_files: [],
       input_history: [],
       history_index: -1,
       view: :chat,
       has_history: prior_messages != [],
       settings_form: default_settings_form(),
       theme_module: Worth.Theme.Registry.resolve(),
       workspaces: list_workspaces(),
       memory_stats: fetch_memory_stats(workspace)
     )}
  end

  # ── Agent events ────────────────────────────────────────────────

  @impl true
  def handle_info({:agent_event, event}, socket) do
    Logger.info("[ChatLive.handle_info] RECEIVED agent_event: #{inspect(event)}")
    Logger.info("[ChatLive.handle_info] Processing event type: #{elem(event, 0)}")
    {:noreply, process_event(event, socket)}
  end

  def handle_info(:agents_updated, socket) do
    agents =
      Worth.Agent.Tracker.list_active()
      |> Enum.filter(&(&1.workspace == socket.assigns.workspace))

    {:noreply, assign(socket, active_agents: agents)}
  end

  def handle_info({:global_event, :agents_updated}, socket) do
    agents =
      Worth.Agent.Tracker.list_active()
      |> Enum.filter(&(&1.workspace == socket.assigns.workspace))

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
    files = Worth.Workspace.FileBrowser.scan(socket.assigns.workspace)
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
      case Worth.Workspace.Learning.analyze(workspace) do
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
      if socket.assigns.streaming_text != "" do
        socket
        |> stream_insert(:messages, %{
          id: msg_id(),
          type: :assistant,
          content: socket.assigns.streaming_text <> "\n\n*[stopped]*"
        })
        |> assign(streaming_text: "")
      else
        socket
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
        {:ok, summary} = Worth.Workspace.Learning.ingest(workspace)

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
    Worth.Learning.Permissions.grant(agent)

    {:noreply,
     append_system_message(socket, "Granted access to #{agent} data. It will be included in the next learning run.")}
  end

  def handle_event("deny_agent_permission", %{"agent" => agent_str}, socket) do
    agent = String.to_existing_atom(agent_str)
    Worth.Learning.Permissions.deny(agent)
    {:noreply, append_system_message(socket, "Denied access to #{agent} data.")}
  end

  def handle_event("grant_all_agents", _params, socket) do
    unasked = Worth.Learning.Permissions.unasked_agents()
    Enum.each(unasked, &Worth.Learning.Permissions.grant(&1.agent))
    names = unasked |> Enum.map(& &1.agent) |> Enum.join(", ")
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
        Worth.Learning.ProjectMapping.set(workspace, agent, projects)
        {:noreply, append_system_message(socket, "Mapped #{length(projects)} projects for #{agent}.")}

      _ ->
        {:noreply, append_system_message(socket, "Invalid project selection.")}
    end
  end

  def handle_event("map_all_projects", %{"workspace" => workspace}, socket) do
    discovered = Worth.Learning.ProjectMapping.discover()
    Worth.Learning.ProjectMapping.set_all(workspace, discovered)
    total = discovered |> Map.values() |> List.flatten() |> length()
    {:noreply, append_system_message(socket, "Mapped all #{total} discovered projects.")}
  end

  def handle_event("memory_query", %{"workspace" => workspace}, socket) do
    msg =
      case Worth.Memory.Manager.recent(workspace: workspace, limit: 5) do
        {:ok, entries} when entries != [] ->
          items = Enum.map(entries, &"  - #{truncate_memory(&1)}") |> Enum.join("\n")
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
      case Worth.Memory.Manager.working_flush(workspace: workspace) do
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

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  # ── Settings events ────────────────────────────────────────────

  def handle_event("settings_setup_password", %{"password" => password}, socket) do
    case Worth.Settings.setup_password(password) do
      :ok ->
        Worth.Settings.import_from_config_store()
        socket = load_settings_form(socket)
        {:noreply, append_system_message(socket, "Master password set and vault unlocked.")}

      {:error, :already_set} ->
        {:noreply, append_system_message(socket, "Master password already exists. Use unlock.")}

      {:error, :empty_password} ->
        {:noreply, append_system_message(socket, "Password cannot be empty.")}

      {:error, _} ->
        {:noreply, append_system_message(socket, "Failed to set password.")}
    end
  end

  def handle_event("settings_unlock", %{"password" => password}, socket) do
    case Worth.Settings.unlock(password) do
      :ok ->
        export_secrets_to_env()
        socket = load_settings_form(socket)
        {:noreply, append_system_message(socket, "Vault unlocked.")}

      {:error, :invalid_password} ->
        {:noreply, append_system_message(socket, "Invalid password.")}

      {:error, :no_password_set} ->
        {:noreply, append_system_message(socket, "No master password set yet.")}
    end
  end

  def handle_event("settings_lock", _params, socket) do
    Worth.Settings.lock()
    {:noreply, socket |> assign(settings_form: default_settings_form())}
  end

  def handle_event("settings_save", params, socket) do
    saved =
      params
      |> Map.drop(["_target", "_csrf_token"])
      |> Enum.reject(fn {_k, v} -> v == "" end)
      |> Enum.map(fn {key, value} ->
        category =
          if String.contains?(key, "API_KEY") or String.contains?(key, "SECRET"), do: "secret", else: "preference"

        Worth.Settings.put(key, value, category)
        key
      end)

    if saved != [] do
      export_secrets_to_env()
      socket = load_settings_form(socket)
      {:noreply, append_system_message(socket, "Saved: #{Enum.join(saved, ", ")}")}
    else
      {:noreply, socket}
    end
  end

  def handle_event("settings_save_key", %{"env_var" => env_var, "api_key" => key}, socket) when key != "" do
    Worth.Settings.put(env_var, key, "secret")
    System.put_env(env_var, key)
    export_secrets_to_env()
    socket = load_settings_form(socket)
    {:noreply, append_system_message(socket, "Saved #{env_var}.")}
  end

  def handle_event("settings_save_key", _params, socket), do: {:noreply, socket}

  def handle_event("settings_delete", %{"key" => key}, socket) do
    Worth.Settings.delete(key)
    socket = load_settings_form(socket)
    {:noreply, append_system_message(socket, "Deleted: #{key}")}
  end

  def handle_event("settings_change_password", params, socket) do
    current = params["current_password"] || ""
    new_pw = params["new_password"] || ""

    case Worth.Settings.change_password(current, new_pw) do
      :ok ->
        {:noreply, append_system_message(socket, "Master password changed.")}

      {:error, :invalid_password} ->
        {:noreply, append_system_message(socket, "Current password is incorrect.")}

      {:error, :empty_password} ->
        {:noreply, append_system_message(socket, "New password cannot be empty.")}

      {:error, _} ->
        {:noreply, append_system_message(socket, "Failed to change password.")}
    end
  end

  def handle_event("settings_set_theme", %{"theme" => theme_name}, socket) do
    case Worth.Theme.Registry.get(theme_name) do
      {:ok, theme_mod} ->
        Application.put_env(:worth, :theme, theme_name)

        try do
          if function_exported?(Worth.Settings, :put, 3) do
            Worth.Settings.put("theme", theme_name, "preference")
          end
        rescue
          _ -> nil
        end

        socket =
          socket
          |> assign(theme_module: theme_mod)
          |> load_settings_form()
          |> push_event("apply_theme", %{
            bg_class: theme_mod.colors()[:background] || "",
            css: theme_mod.css()
          })

        {:noreply, append_system_message(socket, "Theme changed to #{theme_name}.")}

      {:error, _} ->
        {:noreply, append_system_message(socket, "Unknown theme: #{theme_name}")}
    end
  end

  def handle_event("settings_set_routing", %{"mode" => mode} = params, socket) do
    preference = params["preference"] || "optimize_price"
    filter = params["filter"] || ""

    routing = %{
      mode: mode,
      preference: preference,
      filter: if(filter == "free_only", do: "free_only", else: "")
    }

    Application.put_env(:worth, :model_routing, routing)

    try do
      Worth.Settings.put("model_routing_mode", mode, "preference")
      Worth.Settings.put("model_routing_preference", preference, "preference")
      Worth.Settings.put("model_routing_filter", routing.filter, "preference")
    rescue
      _ -> nil
    end

    socket = load_settings_form(socket)
    label = routing_label(mode, preference, routing.filter)
    {:noreply, append_system_message(socket, "Model routing: #{label}")}
  end

  def handle_event("settings_save_limits", params, socket) do
    cost = parse_float(params["cost_limit"], 5.0)
    turns = parse_int(params["max_turns"], 50)

    Application.put_env(:worth, :cost_limit, cost)
    Application.put_env(:worth, :max_turns, turns)

    persist_preference("cost_limit", to_string(cost))
    persist_preference("max_turns", to_string(turns))

    socket = load_settings_form(socket)
    {:noreply, append_system_message(socket, "Agent limits: $#{cost}/session, #{turns} max turns")}
  end

  def handle_event("settings_toggle_memory", _params, socket) do
    current = Worth.Config.get([:memory, :enabled], true)
    new_val = !current

    Worth.Config.put_setting([:memory, :enabled], new_val)
    persist_preference("memory_enabled", to_string(new_val))

    socket = load_settings_form(socket)
    {:noreply, append_system_message(socket, "Memory #{if new_val, do: "enabled", else: "disabled"}")}
  end

  def handle_event("settings_save_memory", params, socket) do
    decay = parse_int(params["decay_days"], 90)

    Worth.Config.put_setting([:memory, :decay_days], decay)
    persist_preference("memory_decay_days", to_string(decay))

    socket = load_settings_form(socket)
    {:noreply, append_system_message(socket, "Memory decay: #{decay} days")}
  end

  def handle_event("settings_save_base_dir", %{"home_directory" => path}, socket) do
    expanded = Path.expand(path)

    if File.dir?(expanded) or File.mkdir_p(expanded) == :ok do
      old_home = Worth.Config.Store.home_directory()

      Worth.Config.put_setting([:home_directory], expanded)
      persist_preference("home_directory", expanded)

      if old_home != expanded do
        migrate_skills_if_needed(old_home, expanded)
      end

      socket = load_settings_form(socket)

      {:noreply,
       append_system_message(socket, "Base directory set to #{expanded}. Skills and workspaces will use this location.")}
    else
      {:noreply, append_system_message(socket, "Cannot create directory: #{expanded}")}
    end
  end

  def handle_event("settings_back", _params, socket) do
    {:noreply, assign(socket, view: :chat)}
  end

  defp routing_label("auto", pref, "free_only"), do: "Auto (#{pref}, free only)"
  defp routing_label("auto", pref, _), do: "Auto (#{pref})"
  defp routing_label("manual", _, "free_only"), do: "Manual (free only)"
  defp routing_label("manual", _, _), do: "Manual (tier-based)"
  defp routing_label(m, _, _), do: m

  defp migrate_skills_if_needed(old_home, new_home) do
    old_skills = Path.join(old_home, "skills")
    new_skills = Path.join(new_home, "skills")

    if File.dir?(old_skills) and old_skills != new_skills do
      # Ensure new directory exists
      File.mkdir_p!(new_home)

      # Copy skills to new location
      case File.cp_r(old_skills, new_skills) do
        {:ok, _} ->
          # Refresh registry to pick up new location
          Worth.Skill.Registry.refresh()
          :ok

        {:error, reason, _} ->
          require Logger
          Logger.warning("Failed to migrate skills: #{inspect(reason)}")
          :error
      end
    else
      :ok
    end
  end

  defp persist_preference(key, value) do
    try do
      Worth.Settings.put(key, value, "preference")
    rescue
      _ -> nil
    end
  end

  defp parse_float(nil, default), do: default

  defp parse_float(val, default) when is_binary(val) do
    case Float.parse(val) do
      {f, _} when f > 0 -> f
      _ -> default
    end
  end

  defp parse_float(_, default), do: default

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} when i > 0 -> i
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  # ── Event processing (ported from Worth.UI.Events) ──────────────

  defp process_event(event, socket) do
    Logger.info("[ChatLive.process_event] Processing event: #{inspect(event)}")
    socket = assign(socket, cost: Worth.Metrics.session_cost())

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
          if socket.assigns.streaming_text != "",
            do: socket.assigns.streaming_text,
            else: text || ""

        final = strip_eom_tokens(final) |> String.trim()

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
          if report.unasked_agents != [] do
            prompt = build_permission_prompt(report.unasked_agents)

            stream_insert(socket, :messages, %{
              id: msg_id(),
              type: :system,
              content: prompt,
              permission_agents: report.unasked_agents
            })
          else
            socket
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
    workspace = socket.assigns.workspace

    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      Worth.Brain.send_message(text, workspace)
    end)

    assign(socket, status: :running, streaming_text: "")
  end

  defp poll_resolved_model(socket) do
    try do
      primary = AgentEx.ModelRouter.resolve(:primary)
      lightweight = AgentEx.ModelRouter.resolve(:lightweight)

      models = %{
        primary: format_model_slot(primary),
        lightweight: format_model_slot(lightweight)
      }

      assign(socket, models: models)
    rescue
      _ -> socket
    end
  end

  defp format_model_slot(nil), do: %{label: nil, source: nil}
  defp format_model_slot({:ok, resolved}) when is_map(resolved), do: format_model_slot(resolved)
  defp format_model_slot({:error, _}), do: %{label: nil, source: nil}

  defp format_model_slot(resolved) when is_map(resolved) do
    provider = Map.get(resolved, :provider_name, "")
    source = Map.get(resolved, :source, "")

    %{
      label: Map.get(resolved, :label) || Map.get(resolved, :model_id),
      source: if(provider != "", do: "#{source}/#{provider}", else: to_string(source)),
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
    history = [text | socket.assigns.input_history] |> Enum.take(50)
    assign(socket, input_history: history, history_index: -1)
  end

  defp msg_id, do: System.unique_integer([:positive]) |> to_string()

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
      base_dir: Worth.Config.Store.home_directory()
    }
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
          Worth.Settings.all_by_category("preference")
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
        base_dir: Worth.Config.Store.home_directory()
      }
    )
  end

  defp theme_list do
    Worth.Theme.Registry.list()
    |> Enum.map(fn mod -> %{name: mod.name(), display_name: mod.display_name(), description: mod.description()} end)
  end

  defp list_workspaces do
    try do
      Worth.Workspace.Service.list()
    rescue
      _ -> []
    end
  end

  defp current_theme_name do
    theme = Worth.Theme.Registry.resolve()
    theme.name()
  end

  defp provider_list do
    # Get stored keys from the vault
    stored_keys =
      Worth.Settings.all_by_category("secret")
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
    try do
      AgentEx.LLM.Catalog.for_provider(provider_id) |> length()
    rescue
      _ -> 0
    catch
      :exit, _ -> 0
    end
  end

  defp current_agent_limits do
    config = Application.get_env(:worth, :agent, [])

    %{
      cost_limit: config[:cost_limit] || Application.get_env(:worth, :cost_limit, 5.0),
      max_turns: config[:max_turns] || Application.get_env(:worth, :max_turns, 50)
    }
  end

  defp current_memory_settings do
    %{
      enabled: Worth.Config.get([:memory, :enabled], true),
      decay_days: Worth.Config.get([:memory, :decay_days], 90)
    }
  end

  defp current_routing do
    case Application.get_env(:worth, :model_routing) do
      %{mode: mode, preference: pref, filter: filter} ->
        %{mode: mode, preference: pref, filter: filter}

      _ ->
        %{mode: "manual", preference: "optimize_price", filter: ""}
    end
  end

  defp load_last_session_messages(workspace) do
    workspace_path = Worth.Workspace.Service.resolve_path(workspace)

    with {:ok, sessions} <- Worth.Persistence.Transcript.list_sessions(workspace_path),
         last when not is_nil(last) <- List.last(sessions),
         {:ok, entries} <- Worth.Persistence.Transcript.load(last, workspace_path) do
      entries
      |> Enum.map(fn entry ->
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
    try do
      Worth.CodingAgents.discover()
    rescue
      _ -> []
    catch
      :exit, _ -> []
    end
  end

  defp export_secrets_to_env do
    Worth.Config.export_vault_secrets()

    # Trigger catalog refresh so providers pick up new keys
    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      AgentEx.LLM.Catalog.refresh()
    end)
  end

  @eom_tokens ~w(<|eom|> <|eot_id|> <|end|> <|endoftext|>)
  defp strip_eom_tokens(text) do
    Enum.reduce(@eom_tokens, text, fn token, acc -> String.replace(acc, token, "") end)
  end

  defp build_learning_prompt(report) do
    type_list =
      report.opportunities
      |> Enum.map(fn opp ->
        "- #{opp.description}: #{opp.item_count} items (#{format_bytes(opp.total_bytes)})"
      end)
      |> Enum.join("\n")

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
      agents
      |> Enum.map(fn a ->
        paths = Enum.join(a.data_paths, ", ")
        "- **#{a.agent}** (reads from #{paths})"
      end)
      |> Enum.join("\n")

    """
    The following coding agents have data on this machine that Worth can learn from:

    #{agent_list}

    These directories may contain session transcripts, project preferences, and other potentially sensitive data. Worth will only read data needed for learning — never credentials or settings files.

    Grant access to include their data in future learning runs.
    """
  end

  defp build_project_mapping_prompt(workspace, discovered) do
    agent_sections =
      discovered
      |> Enum.map(fn {agent, projects} ->
        project_list = Enum.map_join(projects, "\n", &"    - #{&1}")
        "**#{format_agent_display(agent)}** (#{length(projects)} projects):\n#{project_list}"
      end)
      |> Enum.join("\n\n")

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
    names = Enum.map(sources, &inspect/1) |> Enum.join(", ")
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
    case Earmark.as_html(text, compact_output: true) do
      {:ok, html, _} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end

  defp fetch_memory_stats(workspace) do
    try do
      {:ok, working} = Worth.Memory.Manager.working_read(workspace: workspace)
      {:ok, recent} = Worth.Memory.Manager.recent(limit: 100)

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
  end

  defp truncate_memory(entry) do
    content = Map.get(entry, :content, "")
    if String.length(content) > 80, do: String.slice(content, 0, 80) <> "...", else: content
  end
end
