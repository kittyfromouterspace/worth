defmodule Worth.LLM.UsageSummary do
  @moduledoc """
  Builds the data shape consumed by `WorthWeb.Components.Usage` from
  the agentic SpendTracker + UsageManager snapshots and the user's
  ProviderAccount settings.

  One card per provider that has either:
    * any spend event in the SpendTracker, OR
    * a configured account economics (cost_profile / subscription)

  Per card we compute:
    * today / month USD totals
    * monthly token total
    * effective $/Mtok (subscription cost ÷ tokens) when subscription
    * subscription savings vs catalog list price
    * pre-paid balance for OpenRouter
  """

  alias Agentic.LLM.SpendTracker
  alias Worth.LLM.{PathwayPreferences, ProviderAccountResolver}

  def build do
    accounts = safe_call(fn -> ProviderAccountResolver.build_all() end, [])
    daily_windows = safe_call(fn -> SpendTracker.snapshot(period: :daily) end, [])
    monthly_windows = safe_call(fn -> SpendTracker.snapshot(period: :monthly) end, [])
    today_iso = Date.utc_today() |> Date.to_iso8601()
    month_iso = month_start_iso()
    balances = safe_call(fn -> Agentic.LLM.UsageManager.snapshot() end, [])

    cards =
      accounts
      |> Enum.map(fn account ->
        provider = account.provider

        today_total =
          daily_windows
          |> Enum.filter(&(&1.provider == provider and &1.period_start == today_iso))
          |> sum_costs()

        month_total =
          monthly_windows
          |> Enum.filter(&(&1.provider == provider and &1.period_start == month_iso))
          |> sum_costs()

        month_tokens =
          monthly_windows
          |> Enum.filter(&(&1.provider == provider and &1.period_start == month_iso))
          |> Enum.reduce(0, fn w, acc -> acc + (w.input_tokens || 0) + (w.output_tokens || 0) end)

        balance =
          Enum.find_value(balances, nil, fn b ->
            if b.provider == provider, do: balance_money(b)
          end)

        subscription = account.subscription
        effective_rate = effective_rate(subscription, month_tokens)
        savings = subscription_savings(subscription, monthly_windows, provider, month_iso)

        %{
          provider: Atom.to_string(provider),
          label: provider_label(provider),
          cost_profile_label: cost_profile_label(account.cost_profile),
          availability_label: availability_label(account.availability),
          subscription: subscription_blurb(subscription),
          today_display: format_money(today_total),
          month_display: format_money(month_total),
          token_display: format_int(month_tokens),
          effective_rate_display: effective_rate && format_money(effective_rate),
          balance_display: balance && format_money(balance),
          savings_display: savings && format_money(savings),
          note: build_note(account, balance)
        }
      end)
      |> Enum.filter(fn card ->
        card.today_display != "—" or card.month_display != "—" or card.subscription != nil or
          card.balance_display
      end)
      |> Enum.sort_by(& &1.label)

    %{
      cards: cards,
      fx_updated_at: nil,
      pathway_preferences: PathwayPreferences.all_pathway_preferences()
    }
  end

  # ----- card helpers -----

  defp sum_costs(windows) do
    actual_total =
      windows
      |> Enum.map(& &1.actual_cost)
      |> sum_money()

    estimated_total =
      windows
      |> Enum.map(& &1.estimated_cost)
      |> sum_money()

    # Prefer actual when at least one window reported it, else fall
    # back to estimated so we still show a number.
    actual_total || estimated_total
  end

  # Sum a list of `Money.t()` values, normalising every entry to the
  # display currency (default USD) before adding so we can mix CNY z.ai
  # spend with USD OpenRouter spend in one rollup. Conversion uses the
  # live exchange-rate cache the host configured (`Money.ExchangeRates`);
  # currencies the cache can't resolve are dropped from the sum and a
  # debug log is emitted.
  #
  # When the cache hasn't fetched any rates yet (common in dev where
  # `auto_start_exchange_rate_service` is `false`), we fall back to
  # adding only the entries that already share the display currency
  # rather than refusing to produce a number.
  defp sum_money(monies) do
    display = display_currency()

    monies
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_display_currency(&1, display))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] ->
        nil

      [first | rest] ->
        Enum.reduce(rest, first, fn m, acc ->
          case Money.add(acc, m) do
            {:ok, total} -> total
            # Should be impossible after normalisation, but stay
            # defensive — fall back to whatever we have so far.
            _ -> acc
          end
        end)
    end
  end

  defp display_currency do
    case Application.get_env(:worth, :usage_display_currency) do
      nil -> :USD
      atom when is_atom(atom) -> atom
      str when is_binary(str) -> str |> String.upcase() |> String.to_atom()
    end
  end

  defp to_display_currency(%Money{currency: c} = m, c), do: m

  defp to_display_currency(%Money{} = m, display) do
    case Money.to_currency(m, display) do
      {:ok, converted} ->
        converted

      _ ->
        # FX rates not loaded or currency unknown — drop this entry
        # rather than poison the sum. The dashboard already surfaces
        # the FX-freshness footer, so users can tell when conversion
        # is best-effort.
        nil
    end
  rescue
    _ -> nil
  end

  # effective $/Mtok = monthly fee ÷ million-tokens-consumed
  defp effective_rate(nil, _tokens), do: nil
  defp effective_rate(_, tokens) when tokens == 0, do: nil

  defp effective_rate(%{monthly_fee: %Money{} = fee}, tokens) do
    Money.div!(fee, max(tokens / 1_000_000, 0.0001))
  rescue
    _ -> nil
  end

  defp effective_rate(_, _), do: nil

  # Subscription savings: estimated_cost (catalog list price) -
  # actual subscription monthly fee. Positive means the subscription
  # is paying off; negative means OpenRouter would be cheaper.
  defp subscription_savings(nil, _windows, _provider, _month_iso), do: nil

  defp subscription_savings(
         %{monthly_fee: %Money{} = fee},
         windows,
         provider,
         month_iso
       ) do
    list_total =
      windows
      |> Enum.filter(&(&1.provider == provider and &1.period_start == month_iso))
      |> Enum.map(& &1.estimated_cost)
      |> sum_money()

    case list_total do
      nil ->
        nil

      %Money{} = list ->
        case Money.sub(list, fee) do
          {:ok, %Money{amount: amount} = savings} ->
            if Decimal.compare(amount, Decimal.new(0)) == :gt, do: savings, else: nil

          _ ->
            nil
        end
    end
  end

  defp subscription_savings(_, _, _, _), do: nil

  defp subscription_blurb(nil), do: nil

  defp subscription_blurb(%{plan: plan, monthly_fee: %Money{} = fee}) do
    %{plan: plan, fee_display: format_money(fee)}
  end

  defp subscription_blurb(_), do: nil

  defp balance_money(usage) do
    case usage do
      %{balance: %Money{} = m} -> m
      %{balance_usd: n} when is_number(n) -> Money.from_float(:USD, n)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp build_note(_account, %Money{}), do: nil

  defp build_note(%{cost_profile: :subscription_included}, _), do: nil
  defp build_note(%{cost_profile: :subscription_metered}, _), do: nil
  defp build_note(%{provider: :ollama}, _), do: "Local — no spend tracking."

  defp build_note(%{provider: :zai}, _) do
    "z.ai has no balance/usage API. Check https://z.ai/manage-apikey/billing for org-level totals."
  end

  defp build_note(_, _), do: nil

  defp provider_label(:anthropic), do: "Anthropic API"
  defp provider_label(:openai), do: "OpenAI API"
  defp provider_label(:openrouter), do: "OpenRouter"
  defp provider_label(:groq), do: "Groq"
  defp provider_label(:ollama), do: "Ollama (local)"
  defp provider_label(:zai), do: "z.ai"
  defp provider_label(:claude_code), do: "Claude Code (CLI)"
  defp provider_label(:opencode), do: "OpenCode (CLI)"
  defp provider_label(:codex), do: "Codex (CLI)"
  defp provider_label(other), do: other |> Atom.to_string() |> String.capitalize()

  defp cost_profile_label(:free), do: "Free tier"
  defp cost_profile_label(:subscription_included), do: "Subscription (included)"
  defp cost_profile_label(:subscription_metered), do: "Subscription (metered)"
  defp cost_profile_label(:pay_per_token), do: "Pay per token"
  defp cost_profile_label(_), do: "—"

  defp availability_label(:ready), do: "ready"
  defp availability_label(:degraded), do: "degraded"
  defp availability_label({:rate_limited, _}), do: "rate-limited"
  defp availability_label(:unavailable), do: "not configured"
  defp availability_label(_), do: ""

  defp format_money(nil), do: "—"

  defp format_money(%Money{} = m) do
    case Money.to_string(m, fractional_digits: 2) do
      {:ok, formatted} -> formatted
      _ -> Money.to_string!(m)
    end
  rescue
    _ -> Money.to_string!(m)
  end

  defp format_int(0), do: "—"
  defp format_int(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 2)}M"
  defp format_int(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}k"
  defp format_int(n), do: Integer.to_string(n)

  defp month_start_iso do
    today = Date.utc_today()
    "#{today.year}-#{String.pad_leading(Integer.to_string(today.month), 2, "0")}-01"
  end

  defp safe_call(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end
end
