defmodule Worth.LLM.ProviderAccountResolver do
  @moduledoc """
  Bridges Worth's settings → `Agentic.LLM.ProviderAccount` structs that
  the multi-pathway router consumes via `ctx.metadata[:provider_accounts]`.

  Worth holds the user-facing state (which providers are configured, what
  cost_profile each one has, whether the corresponding CLI binary is
  installed). Agentic stays oblivious to settings — it just reads
  `ctx.metadata[:provider_accounts]` at session start.
  """

  alias Agentic.LLM.{ProviderAccount, ProviderRegistry}
  alias Worth.LLM.PathwayPreferences

  @doc """
  Build the full list of `ProviderAccount` structs for every registered
  provider. Each carries the user's `cost_profile`/`subscription` from
  preferences and a real-time `availability` derived from credential
  presence (HTTP providers) or `availability/1` (CLI providers).
  """
  @spec build_all() :: [ProviderAccount.t()]
  def build_all do
    ProviderRegistry.list()
    |> Enum.map(&build_for_provider/1)
  end

  @doc "Build a `ProviderAccount` for a single registered provider."
  @spec build_for_provider(map() | atom()) :: ProviderAccount.t()
  def build_for_provider(provider_id) when is_atom(provider_id) do
    case Enum.find(ProviderRegistry.list(), &(&1.id == provider_id)) do
      nil -> ProviderAccount.default(provider_id)
      entry -> build_for_provider(entry)
    end
  end

  def build_for_provider(%{id: provider_id, module: mod}) do
    pref = PathwayPreferences.account_for(provider_id)
    avail = resolve_availability(provider_id, mod)
    creds_status = resolve_credentials_status(mod, avail)

    %ProviderAccount{
      provider: provider_id,
      account_id: Atom.to_string(provider_id),
      cost_profile: pref.cost_profile,
      subscription: pref.subscription,
      credentials_status: creds_status,
      availability: avail,
      quotas: nil
    }
  end

  # ----- availability -----

  defp resolve_availability(_provider_id, mod) do
    cond do
      function_exported?(mod, :availability, 1) ->
        mod.availability(nil)

      function_exported?(mod, :availability, 0) ->
        mod.availability()

      true ->
        case has_creds?(mod) do
          true -> :ready
          false -> :unavailable
        end
    end
  rescue
    _ -> :unavailable
  catch
    :exit, _ -> :unavailable
  end

  defp resolve_credentials_status(_mod, :unavailable), do: :missing
  defp resolve_credentials_status(_mod, _), do: :ready

  defp has_creds?(mod) do
    case Agentic.LLM.Credentials.resolve(mod) do
      {:ok, _} -> true
      _ -> false
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end
end
