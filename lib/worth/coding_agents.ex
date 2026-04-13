defmodule Worth.CodingAgents do
  @moduledoc """
  Service for discovering and managing local coding agent CLIs.

  Supports auto-discovery of installed coding agents (Claude Code, OpenCode, etc.)
  and integrates them with AgentEx's pluggable protocol infrastructure.
  """

  require Logger

  @known_agents [
    %{cli_name: "claude", protocol: :claude_code, display_name: "Claude Code"},
    %{cli_name: "opencode", protocol: :opencode, display_name: "OpenCode"}
  ]

  @doc "Discover all available coding agents on the system."
  def discover do
    @known_agents
    |> Enum.filter(fn agent ->
      System.find_executable(agent.cli_name) != nil
    end)
    |> Enum.map(fn agent ->
      Map.put(agent, :available, true)
    end)
  end

  @doc "Check if a specific coding agent is available."
  def available?(protocol) do
    case protocol_config(protocol) do
      nil -> false
      config -> System.find_executable(config.cli_name) != nil
    end
  end

  @doc "Get the protocol config for a given protocol atom."
  def protocol_config(:claude_code), do: Enum.find(@known_agents, &(&1.protocol == :claude_code))
  def protocol_config(:opencode), do: Enum.find(@known_agents, &(&1.protocol == :opencode))
  def protocol_config(_), do: nil

  @doc "Get the AgentEx profile atom for a coding agent."
  def profile_for(:claude_code), do: :claude_code
  def profile_for(:opencode), do: :opencode
  def profile_for(_), do: nil

  @doc "List all registered protocol names (from AgentEx Registry)."
  def list_registered do
    AgentEx.Protocol.Registry.for_transport(:local_agent)
  end

  @doc "Check if a protocol is both registered and available."
  def active?(protocol) do
    AgentEx.Protocol.Registry.available?(protocol)
  end

  @doc "Register a protocol with AgentEx.Registry."
  def register_protocol(protocol_module, protocol_atom) do
    case AgentEx.Protocol.Registry.lookup(protocol_atom) do
      {:ok, _} ->
        Logger.info("Protocol #{protocol_atom} already registered")
        :ok

      :error ->
        AgentEx.Protocol.Registry.register(protocol_atom, protocol_module)
        Logger.info("Registered coding agent protocol: #{protocol_atom}")
    end
  end

  @doc "Auto-discover and register all available coding agents, adding them to config."
  def auto_register do
    discovered = discover()

    for agent <- discovered do
      case agent.protocol do
        :claude_code ->
          register_protocol(AgentEx.Protocol.ClaudeCode, :claude_code)
          add_to_config(:claude_code, "Claude Code")

        :opencode ->
          register_protocol(AgentEx.Protocol.OpenCode, :opencode)
          add_to_config(:opencode, "OpenCode")

        _ ->
          Logger.warning("Unknown coding agent protocol: #{inspect(agent.protocol)}")
      end
    end

    {:ok, discovered}
  end

  @doc "Add a coding agent to the local config if not already present."
  def add_to_config(protocol, display_name) do
    config = Worth.Config.get_all()
    existing = config[:coding_agents] || []

    if Enum.any?(existing, &(&1[:protocol] == protocol)) do
      Logger.info("Coding agent #{display_name} already in config")
      :ok
    else
      new_agent = %{
        protocol: protocol,
        name: display_name,
        enabled: true
      }

      Worth.Config.put_setting([:coding_agents], existing ++ [new_agent], persist: false)
      Logger.info("Added coding agent to config: #{display_name}")
    end
  end

  @doc "Convert a protocol atom to a display-friendly name."
  def display_name(:claude_code), do: "Claude Code"
  def display_name(:opencode), do: "OpenCode"
  def display_name(atom) when is_atom(atom), do: Atom.to_string(atom)
  def display_name(other), do: inspect(other)
end
