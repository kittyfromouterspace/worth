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
    <div class="flex-1 flex flex-col overflow-hidden">
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
        send(self(), {:populate_credentials})
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
        send(self(), {:populate_credentials})
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
    locked = safe_vault_locked?()

    {saved, blocked} =
      params
      |> Map.drop(["_target", "_csrf_token"])
      |> Enum.reject(fn {_k, v} -> v == "" end)
      |> Enum.reduce({[], []}, fn {key, value}, {ok, blocked} ->
        is_secret = String.contains?(key, "API_KEY") or String.contains?(key, "SECRET")

        if is_secret and locked do
          {ok, [key | blocked]}
        else
          Worth.Settings.put(key, value, if(is_secret, do: "secret", else: "preference"))
          {[key | ok], blocked}
        end
      end)

    if saved != [] do
      send(self(), {:populate_credentials})
      send(self(), {:refresh_settings_form})
      send(self(), {:append_system_message, "Saved: #{Enum.join(saved, ", ")}"})
    end

    if blocked != [] do
      send(
        self(),
        {:append_system_message,
         "Cannot save secrets while vault is locked: #{Enum.join(blocked, ", ")}. Unlock first."}
      )
    end

    {:noreply, socket}
  end

  def handle_event("settings_save_key", %{"env_var" => env_var, "api_key" => key}, socket) when key != "" do
    if safe_vault_locked?() do
      send(self(), {:append_system_message, "Cannot save #{env_var} — vault is locked. Unlock first."})
    else
      Worth.Settings.put(env_var, key, "secret")
      send(self(), {:populate_credentials})
      send(self(), {:refresh_settings_form})
      send(self(), {:append_system_message, "Saved #{env_var}."})
    end

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

    Worth.Config.save_routing(routing)

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

  # ── Provider account economics ─────────────────────────────────

  def handle_event("settings_set_account", _params, socket) do
    # phx-change handler — fired when the cost_profile dropdown
    # changes. We don't persist on every keystroke; the form-submit
    # handler does that. This handler exists so the
    # subscription-fields show/hide reactively in re-render.
    send(self(), {:refresh_settings_form})
    {:noreply, socket}
  end

  def handle_event("settings_save_account", params, socket) do
    case params["provider"] do
      provider when is_binary(provider) and provider != "" ->
        attrs = %{
          cost_profile: params["cost_profile"],
          plan: params["plan"],
          monthly_fee: build_monthly_fee(params["monthly_fee_amount"], params["monthly_fee_currency"])
        }

        Worth.LLM.PathwayPreferences.put_account(String.to_atom(provider), attrs)
        send(self(), {:refresh_settings_form})

        send(
          self(),
          {:append_system_message,
           "Provider account saved: #{provider} → #{params["cost_profile"]}"}
        )

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  defp build_monthly_fee(amount, currency)
       when is_binary(amount) and amount != "" and is_binary(currency) and currency != "" do
    case Money.new(String.to_atom(String.upcase(currency)), amount) do
      %Money{} = m -> m
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp build_monthly_fee(_, _), do: nil

  # ── Admin keys ─────────────────────────────────────────────────

  def handle_event("settings_save_admin_key", %{"provider" => provider, "key" => key}, socket)
      when key != "" do
    if safe_vault_locked?() do
      send(self(), {:append_system_message, "Cannot save admin key — vault is locked. Unlock first."})
      {:noreply, socket}
    else
      case Worth.LLM.AdminKeys.put(String.to_atom(provider), key) do
        {:ok, _} ->
          send(self(), {:refresh_settings_form})
          send(self(), {:append_system_message, "Admin key saved for #{provider}."})

        {:error, reason} ->
          send(self(), {:append_system_message, "Failed to save admin key: #{inspect(reason)}"})
      end

      {:noreply, socket}
    end
  end

  def handle_event("settings_save_admin_key", _params, socket), do: {:noreply, socket}

  def handle_event("settings_delete_admin_key", %{"provider" => provider}, socket) do
    Worth.LLM.AdminKeys.delete(String.to_atom(provider))
    send(self(), {:refresh_settings_form})
    send(self(), {:append_system_message, "Admin key removed for #{provider}."})
    {:noreply, socket}
  end

  # ── Pathway preferences ───────────────────────────────────────

  def handle_event(
        "settings_set_pathway",
        %{"canonical" => canonical, "provider" => provider},
        socket
      ) do
    Worth.LLM.PathwayPreferences.put_preferred_pathway(canonical, String.to_atom(provider))
    send(self(), {:refresh_settings_form})

    send(
      self(),
      {:append_system_message, "Preferred pathway: #{canonical} → #{provider}"}
    )

    {:noreply, socket}
  end

  def handle_event("settings_clear_pathway", %{"canonical" => canonical}, socket) do
    Worth.LLM.PathwayPreferences.clear_preferred_pathway(canonical)
    send(self(), {:refresh_settings_form})
    send(self(), {:append_system_message, "Pathway preference cleared for #{canonical}."})
    {:noreply, socket}
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

  defp safe_vault_locked? do
    Worth.Settings.locked?()
  rescue
    _ -> true
  catch
    :exit, _ -> true
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
