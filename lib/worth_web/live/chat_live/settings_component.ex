defmodule WorthWeb.ChatLive.SettingsComponent do
  @moduledoc """
  LiveComponent for the Settings panel.
  Handles all settings-related events and communicates with the parent ChatLive
  via sent messages.
  """
  use Phoenix.LiveComponent

  import WorthWeb.Components.Settings

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, settings_form: assigns.settings_form)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.settings_panel settings_form={@settings_form} target={@myself} />
    </div>
    """
  end

  @impl true
  def handle_event("settings_back", _params, socket) do
    send(self(), {:set_view, :chat})
    {:noreply, socket}
  end

  def handle_event("settings_setup_password", %{"password" => password}, socket) do
    case Worth.Settings.setup_password(password) do
      :ok ->
        Worth.Settings.import_from_config_store()
        send(self(), {:refresh_settings_form})
        send(self(), {:append_system_message, "Master password set and vault unlocked."})
        {:noreply, socket}

      {:error, :already_set} ->
        send(self(), {:append_system_message, "Master password already exists. Use unlock."})
        {:noreply, socket}

      {:error, :empty_password} ->
        send(self(), {:append_system_message, "Password cannot be empty."})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:append_system_message, "Failed to set password."})
        {:noreply, socket}
    end
  end

  def handle_event("settings_unlock", %{"password" => password}, socket) do
    case Worth.Settings.unlock(password) do
      :ok ->
        send(self(), {:export_secrets_to_env})
        send(self(), {:refresh_settings_form})
        send(self(), {:append_system_message, "Vault unlocked."})
        {:noreply, socket}

      {:error, :invalid_password} ->
        send(self(), {:append_system_message, "Invalid password."})
        {:noreply, socket}

      {:error, :no_password_set} ->
        send(self(), {:append_system_message, "No master password set yet."})
        {:noreply, socket}
    end
  end

  def handle_event("settings_lock", _params, socket) do
    Worth.Settings.lock()
    send(self(), {:lock_settings_form})
    {:noreply, socket}
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
      send(self(), {:export_secrets_to_env})
      send(self(), {:refresh_settings_form})
      send(self(), {:append_system_message, "Saved: #{Enum.join(saved, ", ")}"})
    end

    {:noreply, socket}
  end

  def handle_event("settings_save_key", %{"env_var" => env_var, "api_key" => key}, socket) when key != "" do
    Worth.Settings.put(env_var, key, "secret")
    send(self(), {:export_secrets_to_env})
    send(self(), {:refresh_settings_form})
    send(self(), {:append_system_message, "Saved #{env_var}."})
    {:noreply, socket}
  end

  def handle_event("settings_save_key", _params, socket), do: {:noreply, socket}

  def handle_event("settings_delete", %{"key" => key}, socket) do
    Worth.Settings.delete(key)
    send(self(), {:refresh_settings_form})
    send(self(), {:append_system_message, "Deleted: #{key}"})
    {:noreply, socket}
  end

  def handle_event("settings_change_password", params, socket) do
    current = params["current_password"] || ""
    new_pw = params["new_password"] || ""

    case Worth.Settings.change_password(current, new_pw) do
      :ok ->
        send(self(), {:append_system_message, "Master password changed."})
        {:noreply, socket}

      {:error, :invalid_password} ->
        send(self(), {:append_system_message, "Current password is incorrect."})
        {:noreply, socket}

      {:error, :empty_password} ->
        send(self(), {:append_system_message, "New password cannot be empty."})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:append_system_message, "Failed to change password."})
        {:noreply, socket}
    end
  end

  def handle_event("settings_set_theme", %{"theme" => theme_name}, socket) do
    case Worth.Theme.Registry.get(theme_name) do
      {:ok, theme_mod} ->
        Worth.Config.put(:theme, theme_name)
        persist_preference("theme", theme_name)

        send(self(), {:apply_theme, theme_mod.colors()[:background] || "", theme_mod.css()})
        send(self(), {:refresh_settings_form})
        send(self(), {:append_system_message, "Theme changed to #{theme_name}."})
        {:noreply, socket}

      {:error, _} ->
        send(self(), {:append_system_message, "Unknown theme: #{theme_name}"})
        {:noreply, socket}
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

    Worth.Config.put([:model_routing], routing)
    persist_preference("model_routing_mode", mode)
    persist_preference("model_routing_preference", preference)
    persist_preference("model_routing_filter", routing.filter)

    send(self(), {:refresh_settings_form})
    label = routing_label(mode, preference, routing.filter)
    send(self(), {:append_system_message, "Model routing: #{label}"})
    {:noreply, socket}
  end

  def handle_event("settings_save_limits", params, socket) do
    cost = parse_float(params["cost_limit"], 5.0)
    turns = parse_int(params["max_turns"], 50)

    Worth.Config.put(:cost_limit, cost)
    Worth.Config.put(:max_turns, turns)
    persist_preference("cost_limit", to_string(cost))
    persist_preference("max_turns", to_string(turns))

    send(self(), {:refresh_settings_form})
    send(self(), {:append_system_message, "Agent limits: $#{cost}/session, #{turns} max turns"})
    {:noreply, socket}
  end

  def handle_event("settings_toggle_memory", _params, socket) do
    current = Worth.Config.get([:memory, :enabled], true)
    new_val = !current

    Worth.Config.put_setting([:memory, :enabled], new_val)

    send(self(), {:refresh_settings_form})
    send(self(), {:append_system_message, "Memory #{if new_val, do: "enabled", else: "disabled"}"})
    {:noreply, socket}
  end

  def handle_event("settings_save_memory", params, socket) do
    decay = parse_int(params["decay_days"], 90)

    Worth.Config.put_setting([:memory, :decay_days], decay)

    send(self(), {:refresh_settings_form})
    send(self(), {:append_system_message, "Memory decay: #{decay} days"})
    {:noreply, socket}
  end

  def handle_event("settings_save_base_dir", %{"workspace_directory" => path}, socket) do
    expanded = Path.expand(path)

    if File.dir?(expanded) or File.mkdir_p(expanded) == :ok do
      Worth.Config.put_setting([:workspace_directory], expanded)

      send(self(), {:refresh_settings_form})
      send(self(), {:append_system_message, "Workspace directory set to #{expanded}."})
      {:noreply, socket}
    else
      send(self(), {:append_system_message, "Cannot create directory: #{expanded}"})
      {:noreply, socket}
    end
  end

  defp routing_label("auto", pref, "free_only"), do: "Auto (#{pref}, free only)"
  defp routing_label("auto", pref, _), do: "Auto (#{pref})"
  defp routing_label("manual", _, "free_only"), do: "Manual (free only)"
  defp routing_label("manual", _, _), do: "Manual (tier-based)"
  defp routing_label(m, _, _), do: m

  defp persist_preference(key, value) do
    Worth.Settings.put(key, value, "preference")
  rescue
    _ -> nil
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
end
