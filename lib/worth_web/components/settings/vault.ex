defmodule WorthWeb.Components.Settings.Vault do
  @moduledoc """
  Vault-related settings components (password, unlock, change password).
  """
  use Phoenix.Component

  attr :settings_form, :map, required: true
  attr :target, :any, required: true

  def vault_forms(assigns) do
    ~H"""
    <%= if not @settings_form.has_password do %>
      <.setup_password_form target={@target} />
    <% else %>
      <%= if @settings_form.locked do %>
        <.unlock_form target={@target} />
      <% else %>
        <.vault_status target={@target} />
        <.change_password_section target={@target} />
      <% end %>
    <% end %>
    """
  end

  attr :target, :any, required: true

  defp setup_password_form(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Create Master Password
      </h2>
      <p class="text-xs text-ctp-subtext0 mb-4">
        Choose a master password to encrypt your secrets. You'll need this password each time you start Worth.
      </p>
      <form phx-target={@target} phx-submit="settings_setup_password" class="flex gap-3">
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

  attr :target, :any, required: true

  defp unlock_form(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Unlock Vault
      </h2>
      <p class="text-xs text-ctp-subtext0 mb-4">
        Enter your master password to decrypt secrets.
      </p>
      <form phx-target={@target} phx-submit="settings_unlock" class="flex gap-3">
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

  attr :target, :any, required: true

  defp vault_status(assigns) do
    ~H"""
    <div class="flex items-center justify-between rounded-lg border border-ctp-green/30 bg-ctp-green/5 px-4 py-2">
      <span class="text-xs text-ctp-green font-semibold">Vault unlocked</span>
      <button
        phx-target={@target}
        phx-click="settings_lock"
        class="text-xs text-ctp-overlay0 hover:text-ctp-red cursor-pointer"
      >
        Lock
      </button>
    </div>
    """
  end

  attr :target, :any, required: true

  defp change_password_section(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
      <h2 class="text-sm font-semibold text-ctp-lavender uppercase tracking-wider mb-3">
        Change Password
      </h2>
      <form phx-target={@target} phx-submit="settings_change_password" class="space-y-3">
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
end
