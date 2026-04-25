defmodule WorthWeb.Components.Settings do
  @moduledoc """
  Function components for the settings panel, rendered in the center pane.
  """
  use Phoenix.Component

  import WorthWeb.Components.Brand, only: [worth_wordmark: 1]
  import WorthWeb.Components.Settings.Vault, only: [vault_forms: 1]

  @known_preferences [
    {"embedding_model", "Embedding Model"}
  ]

  attr :settings_form, :map, required: true
  attr :target, :any, required: true

  def settings_panel(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto p-6">
      <div class="max-w-2xl mx-auto space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-bold text-ctp-text">Settings</h1>
          <button
            phx-target={@target}
            phx-click="settings_back"
            class="text-xs text-ctp-overlay0 hover:text-ctp-text cursor-pointer"
          >
            ← back to chat
          </button>
        </div>

        <.vault_forms settings_form={@settings_form} target={@target} />

        <%= if @settings_form.has_password and not @settings_form.locked do %>
          <.providers_section providers={@settings_form.providers} target={@target} />
          <.provider_accounts_section accounts={@settings_form.provider_accounts} target={@target} />
          <.admin_keys_section admin_keys={@settings_form.admin_keys} target={@target} />
          <.model_pathways_section pathways={@settings_form.model_pathways} target={@target} />
          <.preferences_section preferences={@settings_form.preferences} target={@target} />
        <% end %>

        <.routing_section routing={@settings_form.routing} target={@target} />
        <.agent_limits_section limits={@settings_form.agent_limits} target={@target} />
        <.memory_section memory={@settings_form.memory} target={@target} />
        <.base_directory_section base_dir={@settings_form.base_dir} target={@target} />
        <.coding_agents_section agents={@settings_form.coding_agents} />
        <.theme_section
          themes={@settings_form.themes}
          current_theme={@settings_form.current_theme}
          target={@target}
        />
      </div>
    </div>
    """
  end

  # ── Providers (API Keys) ───────────────────────────────────────

  attr :target, :any, required: true
  attr :providers, :list, required: true

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
          <form phx-target={@target} phx-submit="settings_save_key" class="flex gap-2">
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
              phx-target={@target}
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
        <form phx-target={@target} phx-submit="settings_save_key" class="flex gap-2">
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

  attr :target, :any, required: true
  attr :routing, :map, required: true

  defp routing_section(assigns) do
    assigns =
      assign(assigns,
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
          phx-target={@target}
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
            phx-target={@target}
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
          phx-target={@target}
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
          <span>{if @routing.filter == "free_only", do: "●", else: "○"}</span> Free models only
        </button>
      </div>
    </div>
    """
  end

  # ── Agent Limits ──────────────────────────────────────────────

  attr :target, :any, required: true
  attr :limits, :map, required: true

  defp agent_limits_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Agent Limits
      </h2>
      <form phx-target={@target} phx-submit="settings_save_limits" class="space-y-3">
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

  attr :target, :any, required: true
  attr :memory, :map, required: true

  defp memory_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Memory
      </h2>
      <form phx-target={@target} phx-submit="settings_save_memory" class="space-y-3">
        <div class="flex items-center justify-between">
          <div>
            <div class="text-sm font-medium text-ctp-text">Enabled</div>
            <div class="text-xs text-ctp-overlay0">Store and recall facts across sessions</div>
          </div>
          <button
            type="button"
            phx-target={@target}
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

  attr :target, :any, required: true

  attr :base_dir, :string, required: true

  defp base_directory_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Directories
      </h2>
      <div class="space-y-3">
        <div class="space-y-1">
          <label class="text-xs text-ctp-subtext0 font-medium">Data Directory</label>
          <div class="w-full bg-ctp-surface0/50 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-overlay1 font-mono">
            {Worth.Paths.data_dir()}
          </div>
          <div class="text-xs text-ctp-overlay0">
            Internal files (database, config, logs). Auto-detected from OS conventions.
          </div>
        </div>
        <form phx-target={@target} phx-submit="settings_save_base_dir" class="space-y-3">
          <div class="space-y-1">
            <label class="text-xs text-ctp-subtext0 font-medium">Workspace Directory</label>
            <input
              type="text"
              name="workspace_directory"
              value={@base_dir}
              placeholder="~/work"
              class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
            />
            <div class="text-xs text-ctp-overlay0">
              Root directory for your workspaces. Each workspace is a subdirectory here.
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

  attr :target, :any, required: true

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
          phx-target={@target}
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

  # ── Onboarding ────────────────────────────────────────────────

  attr :step, :integer, required: true

  def onboarding(assigns) do
    ~H"""
    <div class="flex-1 flex items-center justify-center p-8">
      <div class="max-w-lg w-full space-y-6">
        <%!-- Logo --%>
        <div class="text-center mb-8">
          <.worth_wordmark size={:xl} show_tagline={true} />
        </div>

        <%!-- Step indicator --%>
        <div class="flex items-center justify-center gap-2 mb-6">
          <%= for i <- 1..4 do %>
            <div class={[
              "w-2 h-2 rounded-full",
              @step == i && "bg-ctp-blue",
              @step != i && "bg-ctp-surface2"
            ]} />
          <% end %>
        </div>

        <%!-- Step 1: Workspace directory --%>
        <div :if={@step == 1} class="space-y-4">
          <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-6">
            <h2 class="text-lg font-semibold text-ctp-text mb-2">Welcome to Worth</h2>
            <p class="text-sm text-ctp-subtext0 mb-4">
              Let's set up a few things. First, choose where Worth should store your workspaces — each workspace is a project folder with its own skills, agents, and files.
            </p>
            <form phx-submit="onboarding_save_dir" class="space-y-4">
              <div class="space-y-1">
                <label class="text-xs text-ctp-subtext0 font-medium">Workspace Directory</label>
                <input
                  type="text"
                  name="workspace_directory"
                  value="~/work"
                  placeholder="~/work"
                  class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
                />
                <div class="text-xs text-ctp-overlay0">
                  Each workspace will be a subdirectory here (e.g. <span class="font-mono">~/work/personal</span>).
                  Internal data (database, config) is stored separately in your OS data directory.
                </div>
              </div>
              <button
                type="submit"
                class="w-full px-4 py-2.5 rounded text-sm font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer transition-colors"
              >
                Continue
              </button>
            </form>
          </div>
        </div>

        <%!-- Step 2: Master password --%>
        <div :if={@step == 2} class="space-y-4">
          <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-6">
            <h2 class="text-lg font-semibold text-ctp-text mb-2">Secure Your Secrets</h2>
            <p class="text-sm text-ctp-subtext0 mb-4">
              Worth encrypts sensitive data like API keys on your machine.
              Choose a password to lock and unlock this vault — you'll need it each time you start Worth.
            </p>

            <div class="rounded-lg border border-ctp-surface1 bg-ctp-surface0/50 p-4 mb-4 space-y-2">
              <div class="text-xs font-semibold text-ctp-lavender uppercase tracking-wider">Why a password?</div>
              <p class="text-sm text-ctp-subtext0">
                Your API keys and other secrets are stored in an encrypted database on your machine.
                The password derives the encryption key — without it, the secrets can't be read, even if someone accesses your files.
              </p>
            </div>

            <form phx-submit="onboarding_save_password" class="space-y-4">
              <div class="space-y-1">
                <label class="text-xs text-ctp-subtext0 font-medium">Master Password</label>
                <input
                  type="password"
                  name="password"
                  placeholder="Choose a password"
                  autocomplete="new-password"
                  required
                  class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
                />
              </div>
              <div class="space-y-1">
                <label class="text-xs text-ctp-subtext0 font-medium">Confirm Password</label>
                <input
                  type="password"
                  name="password_confirmation"
                  placeholder="Re-enter your password"
                  autocomplete="new-password"
                  required
                  class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
                />
              </div>
              <button
                type="submit"
                class="w-full px-4 py-2.5 rounded text-sm font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer transition-colors"
              >
                Continue
              </button>
            </form>
          </div>
        </div>

        <%!-- Step 3: OpenRouter API key --%>
        <div :if={@step == 3} class="space-y-4">
          <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-6">
            <h2 class="text-lg font-semibold text-ctp-text mb-2">Connect to OpenRouter</h2>
            <p class="text-sm text-ctp-subtext0 mb-4">
              Worth uses <span class="font-semibold text-ctp-text">OpenRouter</span> to access AI models.
              A <span class="font-semibold text-ctp-green">free account</span> is all you need — no credit card required.
              Worth defaults to free models, so you won't be charged.
            </p>

            <div class="rounded-lg border border-ctp-surface1 bg-ctp-surface0/50 p-4 mb-4 space-y-3">
              <div class="text-xs font-semibold text-ctp-lavender uppercase tracking-wider">
                How to get your free API key
              </div>
              <ol class="text-sm text-ctp-subtext0 space-y-2 list-decimal list-inside">
                <li>
                  Go to <span class="text-ctp-blue font-mono text-xs">openrouter.ai</span>
                  and create a <span class="text-ctp-green font-semibold">free account</span>
                </li>
                <li>
                  Navigate to <span class="text-ctp-blue font-mono text-xs">openrouter.ai/keys</span>
                </li>
                <li>Click <span class="font-semibold text-ctp-text">"Create Key"</span></li>
                <li>Copy the key (starts with <span class="font-mono text-ctp-text">sk-or-...</span>)</li>
              </ol>
            </div>

            <form phx-submit="onboarding_save_key" class="space-y-4">
              <div class="space-y-1">
                <label class="text-xs text-ctp-subtext0 font-medium">OpenRouter API Key</label>
                <input
                  type="password"
                  name="api_key"
                  placeholder="sk-or-..."
                  autocomplete="off"
                  required
                  class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
                />
              </div>
              <button
                type="submit"
                class="w-full px-4 py-2.5 rounded text-sm font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer transition-colors"
              >
                Continue
              </button>
            </form>
          </div>
        </div>

        <%!-- Step 4: User profile --%>
        <div :if={@step == 4} class="space-y-4">
          <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-6">
            <h2 class="text-lg font-semibold text-ctp-text mb-2">Your profile</h2>
            <p class="text-sm text-ctp-subtext0 mb-4">
              A few details so Worth has context. This also creates your
              <span class="font-semibold text-ctp-text">personal workspace</span> — the default.
            </p>

            <form phx-submit="onboarding_save_profile" class="space-y-4">
              <div class="space-y-1">
                <label class="text-xs text-ctp-subtext0 font-medium">Your Name</label>
                <input
                  type="text"
                  name="user_name"
                  placeholder="e.g. Alex"
                  autocomplete="name"
                  class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
                />
              </div>
              <div class="space-y-1">
                <label class="text-xs text-ctp-subtext0 font-medium">What Do You Do?</label>
                <input
                  type="text"
                  name="user_role"
                  placeholder="e.g. senior engineer, student, indie hacker"
                  class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
                />
              </div>
              <div class="space-y-1">
                <label class="text-xs text-ctp-subtext0 font-medium">What Should Worth Help You With?</label>
                <textarea
                  name="user_goals"
                  placeholder="e.g. Help me prototype ideas, review code, plan architecture..."
                  rows="3"
                  class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue resize-none"
                />
              </div>
              <button
                type="submit"
                class="w-full px-4 py-2.5 rounded text-sm font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer transition-colors"
              >
                Create My Workspace
              </button>
            </form>
            <button
              phx-click="onboarding_skip_profile"
              class="w-full mt-2 px-4 py-2 rounded text-xs text-ctp-overlay0 hover:text-ctp-text cursor-pointer transition-colors"
            >
              Skip — I'll set this up later
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # ── Vault unlock screen ──────────────────────────────────────

  attr :error, :string, default: nil

  def vault_unlock_screen(assigns) do
    ~H"""
    <div class="flex-1 flex items-center justify-center p-8">
      <div class="max-w-lg w-full space-y-6">
        <div class="text-center mb-8">
          <.worth_wordmark size={:xl} show_tagline={true} />
        </div>

        <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-6">
          <h2 class="text-lg font-semibold text-ctp-text mb-2">Unlock Vault</h2>
          <p class="text-sm text-ctp-subtext0 mb-4">
            Enter your master password to decrypt your API keys and secrets.
          </p>

          <form phx-submit="vault_unlock" class="space-y-4">
            <div class="space-y-1">
              <label class="text-xs text-ctp-subtext0 font-medium">Master Password</label>
              <input
                type="password"
                name="password"
                placeholder="Enter your password"
                autocomplete="current-password"
                autofocus
                required
                class="w-full bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-2 text-sm text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
              />
            </div>
            <div :if={@error} class="text-xs text-ctp-red">
              {@error}
            </div>
            <button
              type="submit"
              class="w-full px-4 py-2.5 rounded text-sm font-semibold bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer transition-colors"
            >
              Unlock
            </button>
          </form>
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
      <form phx-target={@target} phx-submit="settings_save" class="space-y-3">
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

  # ── Provider Accounts (cost_profile + subscription) ─────────────

  @cost_profiles [
    {"pay_per_token", "Pay per token", "Charged per request — OpenRouter, raw API keys"},
    {"subscription_included", "Subscription (included)", "Flat fee, treated as no marginal cost"},
    {"subscription_metered", "Subscription (metered)", "Flat fee + overages — Anthropic Pro"},
    {"free", "Free tier", "Zero cost, rate-limited — Ollama, OpenRouter free models"}
  ]

  attr :target, :any, required: true
  attr :accounts, :list, required: true

  defp provider_accounts_section(assigns) do
    assigns = assign(assigns, profiles: @cost_profiles)

    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-1">
        Provider Accounts
      </h2>
      <p class="text-xs text-ctp-overlay0 mb-3">
        Tell the router how each provider bills you. Subscriptions get a strong score bonus over pay-per-token alternatives, and quota pressure tapers them when caps approach.
      </p>

      <div class="space-y-3">
        <div :for={account <- @accounts} class="rounded-lg border border-ctp-surface1 p-3">
          <div class="flex items-center justify-between mb-2">
            <div class="flex items-center gap-2">
              <span class={availability_dot_class(account.availability)}>●</span>
              <span class="text-sm font-medium text-ctp-text">{account.label}</span>
              <span class="text-xs text-ctp-overlay0">{availability_label(account.availability)}</span>
            </div>
          </div>

          <form
            phx-target={@target}
            phx-change="settings_set_account"
            phx-submit="settings_save_account"
            class="space-y-2"
          >
            <input type="hidden" name="provider" value={account.provider} />

            <div class="flex gap-2">
              <select
                name="cost_profile"
                class="flex-1 bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-1.5 text-xs text-ctp-text focus:outline-none focus:border-ctp-blue cursor-pointer"
              >
                <option
                  :for={{value, label, _hint} <- @profiles}
                  value={value}
                  selected={value == to_string(account.cost_profile)}
                >
                  {label}
                </option>
              </select>
            </div>

            <div :if={String.starts_with?(to_string(account.cost_profile), "subscription")} class="flex gap-2">
              <input
                type="text"
                name="plan"
                placeholder="Plan name (e.g. Pro)"
                value={account.plan}
                class="flex-1 bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-1.5 text-xs text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue"
              />
              <input
                type="number"
                name="monthly_fee_amount"
                step="0.01"
                min="0"
                placeholder="20.00"
                value={account.monthly_fee_amount}
                class="w-24 bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-1.5 text-xs text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
              />
              <select
                name="monthly_fee_currency"
                class="w-20 bg-ctp-surface0 border border-ctp-surface1 rounded px-2 py-1.5 text-xs text-ctp-text focus:outline-none focus:border-ctp-blue cursor-pointer"
              >
                <option :for={c <- ~w(USD EUR GBP CNY JPY)} value={c} selected={c == account.monthly_fee_currency}>
                  {c}
                </option>
              </select>
            </div>

            <div class="flex justify-end">
              <button
                type="submit"
                class="px-3 py-1 rounded text-xs font-semibold bg-ctp-surface2 text-ctp-text hover:bg-ctp-blue hover:text-ctp-base cursor-pointer transition-colors"
              >
                Save
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp availability_dot_class(:ready), do: "text-ctp-green text-xs"
  defp availability_dot_class(:degraded), do: "text-ctp-yellow text-xs"
  defp availability_dot_class({:rate_limited, _}), do: "text-ctp-peach text-xs"
  defp availability_dot_class(:unavailable), do: "text-ctp-overlay0 text-xs"
  defp availability_dot_class(_), do: "text-ctp-overlay0 text-xs"

  defp availability_label(:ready), do: "ready"
  defp availability_label(:degraded), do: "degraded — re-auth recommended"
  defp availability_label({:rate_limited, _}), do: "rate-limited"
  defp availability_label(:unavailable), do: "not configured"
  defp availability_label(_), do: ""

  # ── Admin Keys (org-level usage reporting) ──────────────────────

  attr :target, :any, required: true
  attr :admin_keys, :map, required: true

  defp admin_keys_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-1">
        Org Admin Keys (optional)
      </h2>
      <p class="text-xs text-ctp-overlay0 mb-3">
        Connect organization-level admin keys for read-only usage and cost reporting.
        Strictly more sensitive than regular API keys — store only if you want
        Worth to reconcile spend against the provider's billing source of truth.
      </p>

      <div class="space-y-3">
        <div class="rounded-lg border border-ctp-surface1 p-3">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm font-medium text-ctp-text">Anthropic admin (sk-ant-admin-…)</span>
            <span :if={@admin_keys.anthropic_present} class="text-xs text-ctp-green">connected</span>
            <span :if={!@admin_keys.anthropic_present} class="text-xs text-ctp-overlay0">not set</span>
          </div>
          <form phx-target={@target} phx-submit="settings_save_admin_key" class="flex gap-2">
            <input type="hidden" name="provider" value="anthropic" />
            <input
              type="password"
              name="key"
              placeholder="sk-ant-admin-…"
              class="flex-1 bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-1.5 text-xs text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
            />
            <button
              type="submit"
              class="px-3 py-1.5 rounded text-xs font-semibold bg-ctp-surface2 text-ctp-text hover:bg-ctp-blue hover:text-ctp-base cursor-pointer transition-colors"
            >
              {if @admin_keys.anthropic_present, do: "Update", else: "Add"}
            </button>
            <button
              :if={@admin_keys.anthropic_present}
              type="button"
              phx-target={@target}
              phx-click="settings_delete_admin_key"
              phx-value-provider="anthropic"
              class="px-2 py-1.5 text-xs text-ctp-overlay0 hover:text-ctp-red cursor-pointer"
              title="Disconnect"
            >
              ×
            </button>
          </form>
        </div>

        <div class="rounded-lg border border-ctp-surface1 p-3">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm font-medium text-ctp-text">OpenAI admin (sk-admin-…)</span>
            <span :if={@admin_keys.openai_present} class="text-xs text-ctp-green">connected</span>
            <span :if={!@admin_keys.openai_present} class="text-xs text-ctp-overlay0">not set</span>
          </div>
          <form phx-target={@target} phx-submit="settings_save_admin_key" class="flex gap-2">
            <input type="hidden" name="provider" value="openai" />
            <input
              type="password"
              name="key"
              placeholder="sk-admin-…"
              class="flex-1 bg-ctp-surface0 border border-ctp-surface1 rounded px-3 py-1.5 text-xs text-ctp-text placeholder-ctp-overlay0 focus:outline-none focus:border-ctp-blue font-mono"
            />
            <button
              type="submit"
              class="px-3 py-1.5 rounded text-xs font-semibold bg-ctp-surface2 text-ctp-text hover:bg-ctp-blue hover:text-ctp-base cursor-pointer transition-colors"
            >
              {if @admin_keys.openai_present, do: "Update", else: "Add"}
            </button>
            <button
              :if={@admin_keys.openai_present}
              type="button"
              phx-target={@target}
              phx-click="settings_delete_admin_key"
              phx-value-provider="openai"
              class="px-2 py-1.5 text-xs text-ctp-overlay0 hover:text-ctp-red cursor-pointer"
              title="Disconnect"
            >
              ×
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # ── Model Pathways (preferred provider per canonical model) ─────

  attr :target, :any, required: true
  attr :pathways, :list, required: true

  defp model_pathways_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-1">
        Model Pathways
      </h2>
      <p class="text-xs text-ctp-overlay0 mb-3">
        For each canonical model, choose the preferred provider. Without a preference, the router picks the highest-scoring pathway based on your account economics.
      </p>

      <div :if={@pathways == []} class="text-xs text-ctp-overlay0">
        No multi-pathway groups detected yet. The catalog refreshes from models.dev every 24h.
      </div>

      <div class="space-y-3">
        <div :for={pathway <- @pathways} class="rounded-lg border border-ctp-surface1 p-3">
          <div class="flex items-center justify-between mb-2">
            <span class="text-sm font-medium text-ctp-text font-mono">{pathway.canonical_id}</span>
            <span class="text-xs text-ctp-overlay0">{length(pathway.providers)} pathways</span>
          </div>

          <div class="flex flex-wrap gap-2">
            <button
              :for={provider <- pathway.providers}
              type="button"
              phx-target={@target}
              phx-click="settings_set_pathway"
              phx-value-canonical={pathway.canonical_id}
              phx-value-provider={provider.id}
              class={[
                "px-3 py-1.5 rounded-lg text-xs cursor-pointer transition-colors",
                provider.preferred && "border border-ctp-blue bg-ctp-blue/10 text-ctp-blue font-semibold",
                !provider.preferred && "border border-ctp-surface1 text-ctp-subtext0 hover:border-ctp-surface2",
                provider.unavailable && "opacity-40"
              ]}
              title={"#{provider.cost_profile} • #{provider.availability_label}"}
            >
              {provider.label}
              <span :if={provider.cost_profile == "subscription_included"} class="text-ctp-green ml-1">★</span>
            </button>
            <button
              :if={Enum.any?(pathway.providers, & &1.preferred)}
              type="button"
              phx-target={@target}
              phx-click="settings_clear_pathway"
              phx-value-canonical={pathway.canonical_id}
              class="px-3 py-1.5 rounded-lg text-xs cursor-pointer text-ctp-overlay0 hover:text-ctp-text"
              title="Clear preference (auto-pick)"
            >
              auto
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
