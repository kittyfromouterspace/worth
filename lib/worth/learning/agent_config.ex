defmodule Worth.Learning.AgentConfig do
  @moduledoc """
  Bridges AgentEx's agent registry with Mneme's coding agent providers.

  Reads agent metadata (including `cache_dirs`) from
  `AgentEx.Protocol.ACP.Discovery` and builds config maps that
  Mneme providers accept, avoiding a circular dependency between
  the two libraries.
  """

  @doc """
  Build a provider configs map for Mneme, keyed by mneme agent name.

  Returns `%{agent_name => %{data_paths: [String.t()]}}` suitable for
  passing as `:agent_configs` to `Mneme.Learner.CodingAgent` functions.
  """
  def build_provider_configs do
    AgentEx.Protocol.ACP.Discovery.known_agents()
    |> Enum.filter(fn entry -> Map.get(entry, :cache_dirs, []) != [] end)
    |> Enum.map(fn entry ->
      mneme_name = resolve_mneme_name(entry)
      {mneme_name, %{data_paths: entry.cache_dirs}}
    end)
    |> Enum.reject(fn {name, _} -> is_nil(name) end)
    |> Map.new()
  end

  @doc """
  Return enriched agent info for all agents that have learnable cache dirs.

  Each entry: `%{agent: atom, display: String.t(), data_paths: [String.t()], available: boolean}`.
  """
  def learnable_agents do
    AgentEx.Protocol.ACP.Discovery.known_agents()
    |> Enum.filter(fn entry -> Map.get(entry, :cache_dirs, []) != [] end)
    |> Enum.map(fn entry ->
      %{
        agent: resolve_mneme_name(entry) || entry.name,
        display: entry.display,
        data_paths: entry.cache_dirs,
        available: cache_dir_exists?(entry.cache_dirs)
      }
    end)
  end

  @doc """
  Build `[{provider_module, config}]` tuples ready for Mneme calls.

  Delegates to `Mneme.Learner.CodingAgent.provider_configs/1` with
  overrides from the agent_ex registry.
  """
  def provider_configs_for_mneme do
    Mneme.Learner.CodingAgent.provider_configs(build_provider_configs())
  end

  # Map agent_ex canonical names to mneme provider names.
  # Uses the entry's aliases to find matches.
  defp resolve_mneme_name(entry) do
    mneme_providers = Mneme.Learner.CodingAgent.providers()
    mneme_names = Enum.map(mneme_providers, & &1.agent_name())
    all_names = [entry.name | Map.get(entry, :aliases, [])]

    Enum.find(mneme_names, fn mneme_name ->
      mneme_name in all_names
    end)
  end

  defp cache_dir_exists?(dirs) do
    Enum.any?(dirs, fn dir ->
      dir |> Path.expand() |> File.dir?()
    end)
  end
end
