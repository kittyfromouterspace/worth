defmodule Worth.LLM.SubscriptionPrompt do
  @moduledoc """
  Detects detected-CLI subscription pathways that haven't yet had
  their monthly fee entered. Without a `monthly_fee` we can't compute
  the effective $/Mtok or savings columns in the Subscription
  dashboard, so the user sees zeroes despite having paid for the
  underlying account.

  Returns one prompt per CLI provider that meets all three:

    1. `Worth.LLM.ProviderTaxonomy.cli_provider?/1` — it's a coding-
       agent CLI wrapper.
    2. `availability == :ready` — binary is on PATH.
    3. `cost_profile == :subscription_included` and
       `subscription.monthly_fee` is missing — fee not yet entered.

  Plus a per-provider dismiss flag (stored as a Worth preference)
  so users who deliberately opt out of fee tracking aren't nagged
  forever. Dismiss is recorded via `dismiss/1`.
  """

  alias Worth.LLM.{ProviderAccountResolver, ProviderTaxonomy}
  alias Worth.Settings

  @dismiss_prefix "preference:subscription_prompt_dismissed:"

  @type prompt :: %{
          required(:provider) => atom(),
          required(:label) => String.t(),
          required(:hint) => String.t()
        }

  @doc "Return the list of providers that need a subscription fee entered."
  @spec pending() :: [prompt()]
  def pending do
    ProviderAccountResolver.build_all()
    |> Enum.filter(&needs_prompt?/1)
    |> Enum.map(&to_prompt/1)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc "Mark a provider's subscription prompt as dismissed (sticky)."
  @spec dismiss(atom()) :: :ok | {:error, term()}
  def dismiss(provider) when is_atom(provider) do
    Settings.put("subscription_prompt_dismissed:#{provider}", "true", "preference")
  end

  @doc "True if the user has dismissed the prompt for this provider."
  @spec dismissed?(atom()) :: boolean()
  def dismissed?(provider) when is_atom(provider) do
    Settings.get_preference(@dismiss_prefix <> Atom.to_string(provider)) == "true"
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  # ----- helpers -----

  defp needs_prompt?(account) do
    ProviderTaxonomy.cli_provider?(account.provider) and
      account.availability == :ready and
      account.cost_profile == :subscription_included and
      missing_fee?(account.subscription) and
      not dismissed?(account.provider)
  end

  defp missing_fee?(nil), do: true
  defp missing_fee?(%{monthly_fee: %Money{}}), do: false
  defp missing_fee?(_), do: true

  defp to_prompt(account) do
    %{
      provider: account.provider,
      label: provider_label(account.provider),
      hint: hint_for(account.provider)
    }
  end

  defp provider_label(:claude_code), do: "Claude Code"
  defp provider_label(:opencode), do: "OpenCode"
  defp provider_label(:codex), do: "Codex CLI"
  defp provider_label(:cursor), do: "Cursor"
  defp provider_label(:gemini), do: "Gemini CLI"
  defp provider_label(:goose), do: "Goose"
  defp provider_label(:copilot), do: "GitHub Copilot"
  defp provider_label(:kimi), do: "Kimi Code"
  defp provider_label(:qwen), do: "Qwen Code"
  defp provider_label(other), do: other |> Atom.to_string() |> String.capitalize()

  defp hint_for(:claude_code), do: "Claude Pro / Max — typical: $20/mo or $100/mo"
  defp hint_for(:codex), do: "ChatGPT Plus / Pro / Team — typical: $20/mo or $200/mo"
  defp hint_for(:cursor), do: "Cursor Pro — typical: $20/mo"
  defp hint_for(:copilot), do: "GitHub Copilot — typical: $10/mo (Individual) or $19/mo (Business)"
  defp hint_for(:gemini), do: "Gemini Advanced / Code Assist — typical: $20/mo or free"
  defp hint_for(:goose), do: "Goose itself is free — set to 0 unless backed by a paid provider key"
  defp hint_for(:kimi), do: "Kimi K2 plan — check your Moonshot subscription"
  defp hint_for(:qwen), do: "Qwen plan — check your Alibaba subscription"
  defp hint_for(:opencode), do: "OpenCode is free; cost depends on the provider key it routes through"
  defp hint_for(_), do: "Enter your monthly subscription cost so Worth can compute effective $/Mtok"
end
