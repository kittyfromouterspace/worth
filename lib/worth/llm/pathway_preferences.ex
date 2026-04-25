defmodule Worth.LLM.PathwayPreferences do
  @moduledoc """
  Persisted user preferences that feed `Agentic.LLM.ProviderAccount`
  resolution. Two distinct kinds of preference live here:

    1. **Per-provider account economics** — for each provider id we
       store the user's `cost_profile` and (optionally) their
       `subscription` plan and monthly fee. Worth surfaces this as
       part of the Provider Accounts settings card.

    2. **Per-canonical preferred pathway** — for each `canonical_id`
       (e.g. `claude-sonnet-4`) we store which provider should be
       picked first when multiple pathways are available. Surfaced as
       the Model Pathways settings card.

  Stored as plaintext preference rows in `Worth.Settings`:

      preference:account:<provider>:cost_profile
      preference:account:<provider>:plan
      preference:account:<provider>:monthly_fee_amount
      preference:account:<provider>:monthly_fee_currency
      preference:pathway:<canonical_id>
  """

  alias Worth.LLM.ProviderTaxonomy
  alias Worth.Settings

  @cost_profiles ~w(free subscription_included subscription_metered pay_per_token)a
  @default_currency "USD"

  @type provider_id :: atom()
  @type canonical_id :: String.t()

  @type account_pref :: %{
          required(:cost_profile) => Agentic.LLM.ProviderAccount.cost_profile(),
          optional(:subscription) => map() | nil
        }

  # ----- Account economics -----

  @doc """
  Fetch the stored economics for `provider`, or fall back to a sensible
  default. CLI providers (auto-detected from `System.find_executable`)
  default to `:subscription_included` — every supported coding-agent
  CLI is subscription-backed, so the user shouldn't have to tell us so
  manually. HTTP API providers default to `:pay_per_token`. Always
  returns a map (never nil).
  """
  @spec account_for(provider_id()) :: account_pref()
  def account_for(provider) when is_atom(provider) do
    stored_profile = get("account:#{provider}:cost_profile")

    profile =
      case stored_profile do
        nil -> ProviderTaxonomy.default_cost_profile(provider)
        s when is_binary(s) -> parse_cost_profile(s)
      end

    plan = get("account:#{provider}:plan")
    fee_amount = get("account:#{provider}:monthly_fee_amount")
    fee_currency = get("account:#{provider}:monthly_fee_currency") || @default_currency

    %{
      cost_profile: profile,
      subscription: build_subscription(plan, fee_amount, fee_currency)
    }
  end

  @doc "Save the economics for `provider`. `cost_profile` is required; others optional."
  def put_account(provider, attrs) when is_atom(provider) and is_map(attrs) do
    if profile = attrs[:cost_profile] || attrs["cost_profile"] do
      put("account:#{provider}:cost_profile", to_string(profile))
    end

    if plan = attrs[:plan] || attrs["plan"] do
      put("account:#{provider}:plan", to_string(plan))
    end

    if fee = attrs[:monthly_fee] || attrs["monthly_fee"] do
      {amount, currency} = decompose_money(fee)
      put("account:#{provider}:monthly_fee_amount", amount)
      put("account:#{provider}:monthly_fee_currency", currency)
    end

    :ok
  end

  @doc "List provider ids that have any saved account economics."
  @spec configured_providers() :: [provider_id()]
  def configured_providers do
    # Stored keys look like "preference:account:<provider>:<field>"
    # because `put/2` always adds the "preference:" prefix.
    "preference"
    |> Settings.all_by_category()
    |> Enum.flat_map(fn s ->
      case String.split(s.key, ":", parts: 4) do
        ["preference", "account", provider, _field] -> [String.to_atom(provider)]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  # ----- Pathway preference -----

  @doc "Return the preferred provider atom for a canonical id, or nil."
  @spec preferred_pathway(canonical_id()) :: provider_id() | nil
  def preferred_pathway(canonical_id) when is_binary(canonical_id) do
    case get("pathway:#{canonical_id}") do
      nil -> nil
      "" -> nil
      provider_str -> String.to_atom(provider_str)
    end
  end

  @doc "Persist a preferred pathway for a canonical id."
  def put_preferred_pathway(canonical_id, provider) when is_binary(canonical_id) and is_atom(provider) do
    put("pathway:#{canonical_id}", to_string(provider))
  end

  @doc "Clear a preferred pathway."
  def clear_preferred_pathway(canonical_id) when is_binary(canonical_id) do
    Settings.delete("preference:pathway:#{canonical_id}")
  end

  @doc "Return all stored canonical → provider preferences as a map."
  def all_pathway_preferences do
    # Stored row keys look like "preference:pathway:<canonical_id>"
    # because `put/2` namespaces every preference with a literal
    # "preference:" prefix. The original implementation split on `:`
    # parts=2 which lopped off the prefix and never matched
    # "pathway", silently returning an empty map.
    "preference"
    |> Settings.all_by_category()
    |> Enum.flat_map(fn s ->
      case String.split(s.key, ":", parts: 3) do
        ["preference", "pathway", canonical] when is_binary(s.value) and s.value != "" ->
          [{canonical, String.to_atom(s.value)}]

        _ ->
          []
      end
    end)
    |> Map.new()
  end

  # ----- helpers -----

  # Caller (`account_for/1`) handles the nil case directly so it can
  # delegate to `ProviderTaxonomy.default_cost_profile/1`. This clause
  # only ever sees a stored binary.
  defp parse_cost_profile(s) when is_binary(s) do
    atom = String.to_atom(s)
    if atom in @cost_profiles, do: atom, else: :pay_per_token
  end

  defp build_subscription(nil, _, _), do: nil
  defp build_subscription(_, nil, _), do: nil

  defp build_subscription(plan, amount, currency) when is_binary(amount) do
    case Money.new(currency_atom(currency), amount) do
      %Money{} = fee -> %{plan: plan, monthly_fee: fee}
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp currency_atom(s) when is_binary(s), do: s |> String.upcase() |> String.to_atom()
  defp currency_atom(a) when is_atom(a), do: a

  defp decompose_money(%Money{amount: amount, currency: currency}) do
    {Decimal.to_string(amount), Atom.to_string(currency)}
  end

  defp decompose_money(s) when is_binary(s), do: {s, @default_currency}

  defp get(key), do: Settings.get_preference("preference:" <> key)

  defp put(key, value) when is_binary(value),
    do: Settings.put("preference:" <> key, value, "preference")
end
