defmodule Worth.LLM.ProviderTaxonomy do
  @moduledoc """
  Classifies registered LLM providers along two axes the rest of the
  Worth UI cares about:

    * **Source** — `:http_api` vs `:coding_agent_cli`. CLI providers
      are auto-detected by `Worth.CodingAgents.discover/0`; HTTP
      providers are surfaced via the `Agentic.LLM.ProviderRegistry`
      and need an API key.
    * **Default cost profile** — what the user's `ProviderAccount`
      should default to when no setting has been stored. CLI
      providers default to `:subscription_included` because every
      coding-agent CLI currently ships requires an underlying paid
      account (Claude Pro/Max, ChatGPT Plus/Pro, etc.). HTTP
      providers default to `:pay_per_token` since pasting an API
      key implies usage-based billing.

  This module lets `PathwayPreferences` and the settings UI agree on
  a sensible default *without* the user having to flip a switch when
  they install a new CLI.
  """

  # Provider ids whose `Agentic.LLM.Provider.*` wrapper is a thin
  # shell over a coding-agent CLI. These are auto-detected via
  # `System.find_executable/1` in their `availability/1`.
  @cli_providers MapSet.new([:claude_code, :opencode, :codex])

  # Free-tier defaults — Ollama is local, no key needed and no cost.
  @free_providers MapSet.new([:ollama])

  @doc "True if the provider is a coding-agent CLI wrapper."
  @spec cli_provider?(atom()) :: boolean()
  def cli_provider?(provider_id) when is_atom(provider_id) do
    MapSet.member?(@cli_providers, provider_id)
  end

  @doc """
  The default cost profile for a provider when no explicit user
  setting is stored. CLI providers default to subscription-included
  (every supported CLI is subscription-backed); local providers like
  Ollama default to free; everything else defaults to pay-per-token.
  """
  @spec default_cost_profile(atom()) :: Agentic.LLM.ProviderAccount.cost_profile()
  def default_cost_profile(provider_id) when is_atom(provider_id) do
    cond do
      MapSet.member?(@cli_providers, provider_id) -> :subscription_included
      MapSet.member?(@free_providers, provider_id) -> :free
      true -> :pay_per_token
    end
  end

  @doc """
  Source of the provider's configuration:

    * `:coding_agent_cli` — registered in `ProviderRegistry` *and*
      surfaced by `CodingAgents.discover/0`. The user installs the
      CLI and Worth picks it up automatically.
    * `:http_api` — the user configures it by pasting an API key.
  """
  @spec source(atom()) :: :coding_agent_cli | :http_api
  def source(provider_id) when is_atom(provider_id) do
    if cli_provider?(provider_id), do: :coding_agent_cli, else: :http_api
  end

  @doc "List of CLI provider ids (canonical order)."
  def cli_providers, do: MapSet.to_list(@cli_providers)
end
