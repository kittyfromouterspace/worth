defmodule Worth.LLM.AdminKeys do
  @moduledoc """
  Storage helpers for organization-tier admin keys (Anthropic
  `sk-ant-admin-...`, OpenAI `sk-admin-...`).

  These are kept **separate** from the regular API keys used for
  inference: they're strictly more sensitive (read all org usage,
  manage members, list keys) and have a distinct UX surface. Stored
  in the same encrypted vault as regular secrets — the vault must be
  unlocked to read them.

  Used by the Worth-side admin polling adapter that wraps
  `Agentic.LLM.AdminUsage` to feed the SpendTracker reconciliation
  loop.
  """

  alias Worth.Settings

  @anthropic_key "ANTHROPIC_ADMIN_API_KEY"
  @openai_key "OPENAI_ADMIN_API_KEY"

  @spec has?(:anthropic | :openai) :: boolean()
  def has?(:anthropic), do: present?(@anthropic_key)
  def has?(:openai), do: present?(@openai_key)

  @spec get(:anthropic | :openai) :: String.t() | nil
  def get(:anthropic), do: Settings.get(@anthropic_key)
  def get(:openai), do: Settings.get(@openai_key)

  @spec put(:anthropic | :openai, String.t()) ::
          {:ok, Worth.Settings.Setting.t()} | {:error, term()}
  def put(:anthropic, key) when is_binary(key) and key != "",
    do: Settings.put(@anthropic_key, key, "secret")

  def put(:openai, key) when is_binary(key) and key != "",
    do: Settings.put(@openai_key, key, "secret")

  def put(_, _), do: {:error, :empty}

  @spec delete(:anthropic | :openai) ::
          {:ok, Worth.Settings.Setting.t()} | {:error, term()}
  def delete(:anthropic), do: Settings.delete(@anthropic_key)
  def delete(:openai), do: Settings.delete(@openai_key)

  defp present?(key) do
    case Settings.get(key) do
      nil -> false
      "" -> false
      _ -> true
    end
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end
end
