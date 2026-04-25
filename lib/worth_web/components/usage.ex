defmodule WorthWeb.Components.Usage do
  @moduledoc """
  Subscription & Usage dashboard. Renders SpendTracker windows with
  per-provider amortization (effective $/Mtok) for subscription
  accounts, and pre-paid balance / today / month-to-date spend for
  pay-per-token accounts.

  Phase 6 of the multi-pathway routing plan — read-only view
  consuming `Agentic.LLM.SpendTracker.snapshot/0` and the
  `ProviderAccount` shape.
  """

  use Phoenix.Component

  attr :usage, :map, required: true
  attr :target, :any, required: true

  def usage_panel(assigns) do
    ~H"""
    <div class="flex-1 overflow-y-auto p-6">
      <div class="max-w-3xl mx-auto space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-bold text-ctp-text">Subscription &amp; Usage</h1>
          <button
            phx-click="usage_back"
            class="text-xs text-ctp-overlay0 hover:text-ctp-text cursor-pointer"
          >
            ← back to chat
          </button>
        </div>

        <p class="text-xs text-ctp-overlay0">
          Aggregated from the Gateway proxy across every workspace. Subscription accounts
          show effective $/Mtok (subscription cost ÷ tokens consumed); pay-per-token
          accounts show actual cost when the provider returns it, otherwise our
          catalog-derived estimate. {fx_blurb(@usage.fx_updated_at)}
        </p>

        <div :if={@usage.cards == []} class="text-xs text-ctp-overlay0 italic">
          No spend events yet. Run an agent and check back.
        </div>

        <div :for={card <- @usage.cards} class="rounded-lg border border-ctp-surface0 bg-ctp-mantle p-4">
          <div class="flex items-center justify-between mb-3">
            <div>
              <div class="text-sm font-semibold text-ctp-text">
                {card.label}
                <span :if={card.subscription} class="text-xs text-ctp-overlay0 ml-2 font-normal">
                  — {card.subscription.plan} ({card.subscription.fee_display}/mo)
                </span>
              </div>
              <div class="text-xs text-ctp-overlay0">
                {card.cost_profile_label} · {card.availability_label}
              </div>
            </div>
            <button
              type="button"
              phx-click="usage_refresh_provider"
              phx-value-provider={card.provider}
              class="text-xs px-3 py-1 rounded border border-ctp-surface1 text-ctp-subtext0 hover:border-ctp-blue hover:text-ctp-blue cursor-pointer"
            >
              Refresh
            </button>
          </div>

          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <.metric label="Today" value={card.today_display} />
            <.metric label="Month" value={card.month_display} />
            <.metric label="Tokens (mo)" value={card.token_display} />
            <.metric :if={card.effective_rate_display} label="Effective $/Mtok" value={card.effective_rate_display} />
            <.metric :if={card.balance_display} label="Balance" value={card.balance_display} />
            <.metric :if={card.savings_display} label="Subscription savings" value={card.savings_display} />
          </div>

          <div :if={card.note} class="mt-3 text-xs text-ctp-overlay0 italic">
            {card.note}
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  defp metric(assigns) do
    ~H"""
    <div class="rounded-lg border border-ctp-surface1 p-2">
      <div class="text-xs text-ctp-overlay0">{@label}</div>
      <div class="text-sm font-medium text-ctp-text font-mono">{@value}</div>
    </div>
    """
  end

  defp fx_blurb(nil), do: ""
  defp fx_blurb(%DateTime{} = dt), do: "FX rates as of #{DateTime.to_iso8601(dt)}."
  defp fx_blurb(_), do: ""
end
