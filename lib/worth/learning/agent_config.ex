defmodule Worth.Learning.AgentConfig do
  @moduledoc """
  Bridges Agentic's agent registry with Recollect's coding agent providers.

  Reads agent metadata (including `cache_dirs`) from
  `Agentic.Protocol.ACP.Discovery` and builds config maps that
  Recollect providers accept, avoiding a circular dependency between
  the two libraries.
  """

  @doc """
  Build a provider configs map for Recollect, keyed by recollect agent name.

  Returns `%{agent_name => %{data_paths: [String.t()]}}` suitable for
  passing as `:agent_configs` to `Recollect.Learner.CodingAgent` functions.
  """
  def build_provider_configs do
    Agentic.Protocol.ACP.Discovery.known_agents()
    |> Enum.filter(fn entry -> Map.get(entry, :cache_dirs, []) != [] end)
    |> Enum.map(fn entry ->
      recollect_name = resolve_recollect_name(entry)
      {recollect_name, %{data_paths: entry.cache_dirs}}
    end)
    |> Enum.reject(fn {name, _} -> is_nil(name) end)
    |> Map.new()
  end

  @doc """
  Return enriched agent info for all agents that have learnable cache dirs.

  Each entry: `%{agent: atom, display: String.t(), data_paths: [String.t()], available: boolean}`.
  """
  def learnable_agents do
    Agentic.Protocol.ACP.Discovery.known_agents()
    |> Enum.filter(fn entry -> Map.get(entry, :cache_dirs, []) != [] end)
    |> Enum.map(fn entry ->
      %{
        agent: resolve_recollect_name(entry) || entry.name,
        display: entry.display,
        data_paths: entry.cache_dirs,
        available: cache_dir_exists?(entry.cache_dirs)
      }
    end)
  end

  @doc """
  Build `[{provider_module, config}]` tuples ready for Recollect calls.

  Delegates to `Recollect.Learner.CodingAgent.provider_configs/1` with
  overrides from the agentic registry.
  """
  def provider_configs_for_recollect do
    Recollect.Learner.CodingAgent.provider_configs(build_provider_configs())
  end

  # Map agentic canonical names to recollect provider names.
  # Uses the entry's aliases to find matches.
  defp resolve_recollect_name(entry) do
    recollect_providers = Recollect.Learner.CodingAgent.providers()
    recollect_names = Enum.map(recollect_providers, & &1.agent_name())
    all_names = [entry.name | Map.get(entry, :aliases, [])]

    Enum.find(recollect_names, fn recollect_name ->
      recollect_name in all_names
    end)
  end

  defp cache_dir_exists?(dirs) do
    Enum.any?(dirs, fn dir ->
      dir |> Path.expand() |> File.dir?()
    end)
  end
end
