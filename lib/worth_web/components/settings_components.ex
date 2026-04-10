defmodule WorthWeb.SettingsComponents do
  @moduledoc """
  Function components for the settings panel, rendered in the center pane.
  """
  use Phoenix.Component

  @known_preferences [
    {"embedding_model", "Embedding Model"}
  ]

  attr :settings_form, :map, required: true

  def settings_panel(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto p-6">
      <div class="max-w-2xl mx-auto space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-bold text-ctp-text">Settings</h1>
          <button phx-click="settings_back" class="text-xs text-ctp-overlay0 hover:text-ctp-text cursor-pointer">
            ← back to chat
          </button>
        </div>

        <%= if not @settings_form.has_password do %>
          <.setup_password_form />
        <% else %>
          <%= if @settings_form.locked do %>
            <.unlock_form />
          <% else %>
            <.vault_status />
            <.providers_section providers={@settings_form.providers} />
            <.preferences_section preferences={@settings_form.preferences} />
            <.change_password_section />
          <% end %>
        <% end %>

        <%!-- These don't need the vault --%>
        <.routing_section routing={@settings_form.routing} />
        <.agent_limits_section limits={@settings_form.agent_limits} />
        <.memory_section memory={@settings_form.memory} />
        <.base_directory_section base_dir={@settings_form.base_dir} />
        <.coding_agents_section agents={@settings_form.coding_agents} />
        <.theme_section
          themes={@settings_form.themes}
          current_theme={@settings_form.current_theme}
        />
      </div>
    </div>
    """
  end

  # ── Password forms ─────────────────────────────────────────────

  defp setup_password_form(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Create Master Password
      </h2>
      <p class="text-xs text-ctp-subtext0 mb-4">
        Choose a master password to encrypt your secrets. You'll need this password each time you start Worth.
      </p>
      <form phx-submit="settings_setup_password" class="flex gap-3">
        <input
          type="password"
          name="password"
          placeholder="Master password"
          autocomplete="new-password"
          required
          class="flex-1 bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
        />
        <button
          type="submit"
          class="px-4 py-2 rounded text-xs font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer"
        >
          Set Password
        </button>
      </form>
    </div>
    """
  end

  defp unlock_form(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Unlock Vault
      </h2>
      <p class="text-xs text-ctp-subtext0 mb-4">
        Enter your master password to decrypt secrets.
      </p>
      <form phx-submit="settings_unlock" class="flex gap-3">
        <input
          type="password"
          name="password"
          placeholder="Master password"
          autocomplete="current-password"
          required
          class="flex-1 bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
        />
        <button
          type="submit"
          class="px-4 py-2 rounded text-xs font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer"
        >
          Unlock
        </button>
      </form>
    </div>
    """
  end

  defp vault_status(assigns) do
    ~H"""
    <div class="flex items-center justify-between rounded-lg border border-ctp-green/30 bg-ctp-green/5 px-4 py-2">
      <span class="text-xs text-ctp-green font-semibold">Vault unlocked</span>
      <button
        phx-click="settings_lock"
        class="text-xs text-ctp-overlay0 hover:text-ctp-red cursor-pointer"
      >
        Lock
      </button>
    </div>
    """
  end

  defp change_password_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Change Password
      </h2>
      <form phx-submit="settings_change_password" class="space-y-3">
        <div class="space-y-1">
          <label class="text-xs text-ctp-subtext0 font-medium">Current Password</label>
          <input
            type="password"
            name="current_password"
            placeholder="Current password"
            autocomplete="current-password"
            required
            class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
          />
        </div>
        <div class="space-y-1">
          <label class="text-xs text-ctp-subtext0 font-medium">New Password</label>
          <input
            type="password"
            name="new_password"
            placeholder="New password"
            autocomplete="new-password"
            required
            class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
          />
        </div>
        <button
          type="submit"
          class="px-4 py-2 rounded text-xs font-semibold bg-ctp-yellow text-ctp-base hover:bg-ctp-peach cursor-pointer"
        >
          Change Password
        </button>
      </form>
    </div>
    """
  end

  # ── Providers (API Keys) ───────────────────────────────────────

  defp providers_section(assigns) do
    configured = Enum.filter(assigns.providers, & &1.has_key)
    unconfigured = Enum.reject(assigns.providers, & &1.has_key)
    assigns = assign(assigns, configured: configured, unconfigured: unconfigured)

    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Providers
      </h2>

      <%!-- Configured providers --%>
      <div :if={@configured != []} class="space-y-3 mb-4">
        <div :for={provider <- @configured} class="rounded-lg border border-ctp-surface1 p-3">
          <div class="flex items-center justify-between mb-2">
            <div class="flex items-center gap-2">
              <span class="text-ctp-green text-xs">●</span>
              <span class="text-sm font-medium text-ctp-text">{provider.label}</span>
              <span class="text-xs text-ctp-overlay0">({provider.model_count} models)</span>
            </div>
            <span class="text-xs text-ctp-overlay0 font-mono">{provider.key_hint}</span>
          </div>
          <form phx-submit="settings_save_key" class="flex gap-2">
            <input type="hidden" name="env_var" value={provider.env_var} />
            <input
              type="password"
              name="api_key"
              placeholder={"●●●●●●●● #{provider.key_hint}"}
              class="flex-1 bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-1.5 text-xs text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
            />
            <button
              type="submit"
              class="px-3 py-1.5 rounded text-xs font-semibold bg-ctp-surface2 text-ctp-text hover:bg-ctp-blue hover:text-ctp-base cursor-pointer transition-colors"
            >
              Update
            </button>
            <button
              type="button"
              phx-click="settings_delete"
              phx-value-key={provider.env_var}
              class="px-2 py-1.5 text-xs text-ctp-overlay0 hover:text-ctp-red cursor-pointer"
              title="Remove key"
            >
              ×
            </button>
          </form>
        </div>
      </div>

      <div :if={@configured == []} class="text-xs text-ctp-overlay0 mb-4">
        No API keys configured yet.
      </div>

      <%!-- Add new key --%>
      <div :if={@unconfigured != []} class="border-t border-ctp-surface0 pt-3">
        <div class="text-xs text-ctp-subtext0 font-medium mb-2">Add Provider</div>
        <form phx-submit="settings_save_key" class="flex gap-2">
          <select
            name="env_var"
            class="bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-1.5 text-xs text-ctp-text focus:outline-none focus:border-ctp-blue cursor-pointer"
          >
            <option :for={provider <- @unconfigured} value={provider.env_var}>
              {provider.label}
            </option>
          </select>
          <input
            type="password"
            name="api_key"
            placeholder="API key"
            required
            class="flex-1 bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-1.5 text-xs text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
          />
          <button
            type="submit"
            class="px-3 py-1.5 rounded text-xs font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer"
          >
            Add
          </button>
        </form>
      </div>
    </div>
    """
  end

  # ── Model Routing ───────────────────────────────────────────────

  @routing_modes [
    %{
      id: "manual",
      label: "Manual",
      description: "Tier-based selection — uses primary/lightweight model tiers"
    },
    %{
      id: "auto",
      label: "Auto",
      description: "Complexity-optimized — analyzes each request and picks the best model"
    }
  ]

  @routing_preferences [
    %{id: "optimize_price", label: "Optimize Cost", description: "Prefer cheaper models, upgrade when needed"},
    %{id: "optimize_speed", label: "Optimize Speed", description: "Prefer faster models"}
  ]

  defp routing_section(assigns) do
    assigns = assign(assigns,
      modes: @routing_modes,
      preferences: @routing_preferences
    )

    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Model Routing
      </h2>

      <%!-- Mode selector --%>
      <div class="space-y-2 mb-4">
        <div class="text-xs text-ctp-subtext0 font-medium mb-1">Selection Mode</div>
        <div
          :for={mode <- @modes}
          class={[
            "flex items-center justify-between p-3 rounded-lg border cursor-pointer transition-colors",
            mode.id == @routing.mode && "border-ctp-blue bg-ctp-blue/10",
            mode.id != @routing.mode && "border-ctp-surface1 hover:border-ctp-surface2 hover:bg-ctp-surface0/50"
          ]}
          phx-click="settings_set_routing"
          phx-value-mode={mode.id}
          phx-value-preference={@routing.preference}
          phx-value-filter={@routing.filter}
        >
          <div>
            <div class={[
              "text-sm font-medium",
              mode.id == @routing.mode && "text-ctp-blue",
              mode.id != @routing.mode && "text-ctp-text"
            ]}>
              {mode.label}
            </div>
            <div class="text-xs text-ctp-overlay0">{mode.description}</div>
          </div>
          <span :if={mode.id == @routing.mode} class="text-ctp-blue text-xs font-semibold">
            Active
          </span>
        </div>
      </div>

      <%!-- Preference (only relevant for auto mode) --%>
      <div :if={@routing.mode == "auto"} class="mb-4">
        <div class="text-xs text-ctp-subtext0 font-medium mb-1">Optimization</div>
        <div class="flex gap-2">
          <button
            :for={pref <- @preferences}
            phx-click="settings_set_routing"
            phx-value-mode={@routing.mode}
            phx-value-preference={pref.id}
            phx-value-filter={@routing.filter}
            class={[
              "flex-1 p-2 rounded-lg border text-xs text-center cursor-pointer transition-colors",
              pref.id == @routing.preference && "border-ctp-blue bg-ctp-blue/10 text-ctp-blue font-semibold",
              pref.id != @routing.preference && "border-ctp-surface1 text-ctp-subtext0 hover:border-ctp-surface2"
            ]}
            title={pref.description}
          >
            {pref.label}
          </button>
        </div>
      </div>

      <%!-- Free-only filter --%>
      <div class="flex items-center gap-2">
        <button
          phx-click="settings_set_routing"
          phx-value-mode={@routing.mode}
          phx-value-preference={@routing.preference}
          phx-value-filter={if @routing.filter == "free_only", do: "", else: "free_only"}
          class={[
            "flex items-center gap-2 px-3 py-1.5 rounded-lg border text-xs cursor-pointer transition-colors",
            @routing.filter == "free_only" && "border-ctp-green bg-ctp-green/10 text-ctp-green font-semibold",
            @routing.filter != "free_only" && "border-ctp-surface1 text-ctp-subtext0 hover:border-ctp-surface2"
          ]}
        >
          <span>{if @routing.filter == "free_only", do: "●", else: "○"}</span>
          Free models only
        </button>
      </div>
    </div>
    """
  end

  # ── Agent Limits ──────────────────────────────────────────────

  defp agent_limits_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Agent Limits
      </h2>
      <form phx-submit="settings_save_limits" class="space-y-3">
        <div class="space-y-1">
          <label class="text-xs text-ctp-subtext0 font-medium">Cost Limit ($ per session)</label>
          <input
            type="number"
            name="cost_limit"
            value={@limits.cost_limit}
            step="0.5"
            min="0.5"
            class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
          />
          <div class="text-xs text-ctp-overlay0">Agent stops when session cost reaches this limit</div>
        </div>
        <div class="space-y-1">
          <label class="text-xs text-ctp-subtext0 font-medium">Max Turns</label>
          <input
            type="number"
            name="max_turns"
            value={@limits.max_turns}
            step="1"
            min="1"
            max="500"
            class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
          />
          <div class="text-xs text-ctp-overlay0">Maximum LLM turns per agent run (safety limit)</div>
        </div>
        <button
          type="submit"
          class="px-4 py-2 rounded text-xs font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer"
        >
          Save Limits
        </button>
      </form>
    </div>
    """
  end

  # ── Memory ──────────────────────────────────────────────────

  defp memory_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Memory
      </h2>
      <form phx-submit="settings_save_memory" class="space-y-3">
        <div class="flex items-center justify-between">
          <div>
            <div class="text-sm font-medium text-ctp-text">Enabled</div>
            <div class="text-xs text-ctp-overlay0">Store and recall facts across sessions</div>
          </div>
          <button
            type="button"
            phx-click="settings_toggle_memory"
            class={[
              "relative inline-flex h-6 w-11 items-center rounded-full cursor-pointer transition-colors",
              @memory.enabled && "bg-ctp-blue",
              not @memory.enabled && "bg-ctp-surface2"
            ]}
          >
            <span class={[
              "inline-block h-4 w-4 rounded-full bg-white transition-transform",
              @memory.enabled && "translate-x-6",
              not @memory.enabled && "translate-x-1"
            ]} />
          </button>
        </div>
        <div class="space-y-1">
          <label class="text-xs text-ctp-subtext0 font-medium">Memory Decay (days)</label>
          <input
            type="number"
            name="decay_days"
            value={@memory.decay_days}
            step="1"
            min="7"
            max="365"
            class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
          />
          <div class="text-xs text-ctp-overlay0">Facts older than this lose confidence over time</div>
        </div>
        <button
          type="submit"
          class="px-4 py-2 rounded text-xs font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer"
        >
          Save Memory Settings
        </button>
      </form>
    </div>
    """
  end

  # ── Base Directory ──────────────────────────────────────────

  defp base_directory_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Base Directory
      </h2>
      <form phx-submit="settings_save_base_dir" class="space-y-3">
        <div class="space-y-1">
          <label class="text-xs text-ctp-subtext0 font-medium">Home Directory</label>
          <input
            type="text"
            name="home_directory"
            value={@base_dir}
            placeholder="~/.worth"
            class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
          />
          <div class="text-xs text-ctp-overlay0">
            Root directory for config, workspaces, skills, and logs. Requires restart.
          </div>
        </div>
        <button
          type="submit"
          class="px-4 py-2 rounded text-xs font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer"
        >
          Save
        </button>
      </form>
    </div>
    """
  end

  # ── Coding Agents ──────────────────────────────────────────────

  defp coding_agents_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Coding Agents
      </h2>
      <div :if={@agents == []} class="text-xs text-ctp-overlay0">
        No coding agents detected. Install Claude Code or OpenCode to use agent delegation.
      </div>
      <div :if={@agents != []} class="space-y-2">
        <div
          :for={agent <- @agents}
          class="flex items-center justify-between p-3 rounded-lg border border-ctp-surface1"
        >
          <div class="flex items-center gap-2">
            <span class={if agent.available, do: "text-ctp-green", else: "text-ctp-overlay0"}>
              {if agent.available, do: "●", else: "○"}
            </span>
            <span class="text-sm font-medium text-ctp-text">{agent.display_name}</span>
            <span class="text-xs text-ctp-overlay0 font-mono">{agent.cli_name}</span>
          </div>
          <span class={[
            "text-xs font-semibold",
            agent.available && "text-ctp-green",
            not agent.available && "text-ctp-overlay0"
          ]}>
            {if agent.available, do: "Installed", else: "Not found"}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # ── Theme ──────────────────────────────────────────────────────

  attr :themes, :list, required: true
  attr :current_theme, :string, required: true

  defp theme_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Theme
      </h2>
      <div class="space-y-2">
        <div
          :for={theme <- @themes}
          class={[
            "flex items-center justify-between p-3 rounded-lg border cursor-pointer transition-colors",
            theme.name == @current_theme && "border-ctp-blue bg-ctp-blue/10",
            theme.name != @current_theme && "border-ctp-surface1 hover:border-ctp-surface2 hover:bg-ctp-surface0/50"
          ]}
          phx-click="settings_set_theme"
          phx-value-theme={theme.name}
        >
          <div>
            <div class={[
              "text-sm font-medium",
              theme.name == @current_theme && "text-ctp-blue",
              theme.name != @current_theme && "text-ctp-text"
            ]}>
              {theme.display_name}
            </div>
            <div class="text-xs text-ctp-overlay0">{theme.description}</div>
          </div>
          <span :if={theme.name == @current_theme} class="text-ctp-blue text-xs font-semibold">
            Active
          </span>
        </div>
      </div>
    </div>
    """
  end

  # ── Preferences ────────────────────────────────────────────────

  defp preferences_section(assigns) do
    all_prefs =
      Enum.map(@known_preferences, fn {key, label} ->
        value = Enum.find_value(assigns.preferences, "", fn s -> if s.key == key, do: s.value end)
        %{key: key, label: label, value: value}
      end)

    assigns = assign(assigns, all_prefs: all_prefs)

    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Preferences
      </h2>
      <form phx-submit="settings_save" class="space-y-3">
        <div :for={pref <- @all_prefs} class="space-y-1">
          <label class="text-xs text-ctp-subtext0 font-medium">{pref.label}</label>
          <input
            type="text"
            name={pref.key}
            value={pref.value}
            placeholder={"Enter #{pref.label}"}
            class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
          />
        </div>
        <button
          type="submit"
          class="px-4 py-2 rounded text-xs font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer"
        >
          Save Preferences
        </button>
      </form>
    </div>
    """
  end
end
