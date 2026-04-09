defmodule WorthWeb.ChatLive do
  use WorthWeb, :live_view

  import WorthWeb.ChatComponents
  import WorthWeb.SettingsComponents

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Worth.Brain.set_ui_pid(self())
      Phoenix.PubSub.subscribe(Worth.PubSub, "agents:updates")
      send(self(), :refresh_model)
      send(self(), :scan_files)
    end

    workspace = Application.get_env(:worth, :current_workspace, "personal")
    mode = Application.get_env(:worth, :current_mode, :code)

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
       theme_module: Worth.Theme.Registry.resolve()
     )}
  end

  # ── Agent events ────────────────────────────────────────────────

  @impl true
  def handle_info({:agent_event, event}, socket) do
    {:noreply, process_event(event, socket)}
  end

  def handle_info(:agents_updated, socket) do
    {:noreply, assign(socket, active_agents: Worth.Agent.Tracker.list_active())}
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

  def handle_info({:reembed_done, result}, socket) do
    msg =
      case result do
        {:ok, count} -> "Re-embedding complete: #{count} memories processed."
        {:error, reason} -> "Re-embedding failed: #{inspect(reason)}"
      end

    {:noreply, append_system_message(socket, msg)}
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

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, update(socket, :sidebar_visible, &(!&1))}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, selected_tab: String.to_existing_atom(tab))}
  end

  def handle_event("keydown", %{"key" => "Tab"}, socket) do
    {:noreply, update(socket, :sidebar_visible, &(!&1))}
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

  defp routing_label("auto", pref, "free_only"), do: "Auto (#{pref}, free only)"
  defp routing_label("auto", pref, _), do: "Auto (#{pref})"
  defp routing_label("manual", _, "free_only"), do: "Manual (free only)"
  defp routing_label("manual", _, _), do: "Manual (tier-based)"
  defp routing_label(m, _, _), do: m

  def handle_event("settings_back", _params, socket) do
    {:noreply, assign(socket, view: :chat)}
  end

  # ── Event processing (ported from Worth.UI.Events) ──────────────

  defp process_event(event, socket) do
    socket = assign(socket, cost: Worth.Metrics.session_cost())

    case event do
      {:text_chunk, chunk} ->
        update(socket, :streaming_text, &(&1 <> chunk))

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
        final =
          if socket.assigns.streaming_text != "",
            do: socket.assigns.streaming_text,
            else: text || ""

        socket
        |> stream_insert(:messages, %{id: msg_id(), type: :assistant, content: final})
        |> assign(streaming_text: "", status: :idle)
        |> push_event("scroll_to_bottom", %{})

      {:error, reason} ->
        reason_str = if is_binary(reason), do: reason, else: inspect(reason)

        socket
        |> stream_insert(:messages, %{id: msg_id(), type: :error, content: "Error: #{reason_str}"})
        |> assign(status: :idle, streaming_text: "")

      _ ->
        socket
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp send_to_brain(text, socket) do
    ui_pid = self()

    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      case Worth.Brain.send_message(text) do
        {:ok, response} ->
          send(ui_pid, {:agent_event, {:done, response}})

        {:error, reason} ->
          send(ui_pid, {:agent_event, {:error, reason}})
      end
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
      routing: current_routing()
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
        routing: current_routing()
      }
    )
  end

  defp theme_list do
    Worth.Theme.Registry.list()
    |> Enum.map(fn mod -> %{name: mod.name(), display_name: mod.display_name(), description: mod.description()} end)
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

  defp render_streaming(text) do
    case Earmark.as_html(text, compact_output: true) do
      {:ok, html, _} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end
end
